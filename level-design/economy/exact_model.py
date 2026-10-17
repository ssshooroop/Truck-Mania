"""Exact distributional model of the coin economy.

Instead of sampling players, the probability distribution of a segment over
the state (fails on this level f, clean streak S, coin balance b) is pushed
through every level. Expectations (revenue, retention, coins) are therefore
deterministic, which makes the model suitable for optimisation and for exact
sensitivities. The rules mirror economy_model.Player; run_economy.py --validate
compares both.

Balance is kept in buckets of `quantum` coins; a fractional coin amount is
split between the two neighbouring buckets so that the mean moves exactly.
Balances above `balance_cap` are accumulated in the top bucket.
"""
from __future__ import annotations

import math

import numpy as np

import economy_model as em

EPS = 1e-9
MAX_ATTEMPTS = 80
SERIES = ('reached', 'completed', 'churn_win', 'churn_fail', 'attempts', 'seconds',
          'coins_in', 'coins_out', 'rv_double', 'rv_rescue', 'interstitial', 'iap_usd',
          'rescues_paid', 'shuffles', 'swaps', 'cranes', 'boosters', 'rescues_free', 'tutorial_shuffles',
          'deadlocks', 'walls')


def _roll(arr: np.ndarray, k: int) -> np.ndarray:
    """Shifts mass by k buckets along the last axis, clamping at both ends."""
    n = arr.shape[-1]
    if k == 0:
        return arr.copy()
    out = np.zeros_like(arr)
    if k > 0:
        if k >= n:
            out[..., -1] = arr.sum(axis=-1)
            return out
        out[..., k:] = arr[..., :n - k]
        out[..., -1] += arr[..., n - k:].sum(axis=-1)
    else:
        k = -k
        if k >= n:
            out[..., 0] = arr.sum(axis=-1)
            return out
        out[..., :n - k] = arr[..., k:]
        out[..., 0] += arr[..., :k].sum(axis=-1)
    return out


def shift(arr: np.ndarray, coins: float, quantum: float) -> np.ndarray:
    if coins == 0:
        return arr.copy()
    steps = coins / quantum
    k = math.floor(steps)
    frac = steps - k
    out = _roll(arr, k)
    if frac > 1e-12:
        out = out * (1.0 - frac) + _roll(arr, k + 1) * frac
    return out


def evaluate_segment(levels: list, cfg: dict, seg: dict, by_level: dict,
                     quantum: float = 10.0, balance_cap: float = 3000.0) -> dict:
    """State (purchases p, clean streak S, balance b). Inside a level every
    pending player has failed the same number of times, so the fail counter
    is the attempt index and needs no dimension of its own."""
    n_levels = len(levels)
    nb = int(balance_cap // quantum) + 1
    bal = np.arange(nb) * quantum
    s_cap = cfg['reward']['clean_streak']['cap']
    n_s = max(s_cap, 5) + 1
    pity = cfg['rescue']['pity']
    costs = cfg['rescue']['costs']
    shuffle_cost = cfg['rescue']['shuffle_cost']
    max_tools = cfg['rescue']['max_tools']
    beh = cfg['behaviour']
    booster = cfg['booster']
    rv_cfg = cfg['rewarded_video']
    pack = cfg['iap_pack']
    cosmetic = cfg['cosmetic']
    login = em.login_per_second(cfg)
    policy = cfg['reward']['rescue_streak_policy']
    shows = em.interstitial_schedule(levels, cfg)
    out = {key: np.zeros(n_levels) for key in SERIES}
    histograms = np.zeros((n_levels, nb))
    swap_cost = cfg['rescue']['swap_cost']
    crane_cost = cfg['rescue']['crane_cost']
    crane_on = bool(cfg['rescue'].get('crane_enabled', True))
    poor = bal < min(em.tool_prices(cfg, costs[0]).values())
    wall = np.where(poor, beh['wall_churn_multiplier'], 1.0)
    booster_rich = bal >= booster['price'] * booster['rich_multiplier']
    cosmetic_rich = bal >= cosmetic['price'] + cosmetic['reserve']
    can_shuffle = bal >= shuffle_cost
    can_swap = (bal >= swap_cost) & bool(cfg['rescue'].get('swap_enabled', True))
    shuffle_equal = cfg['rescue'].get('shuffle_menu', 'equal') == 'equal'
    weights = seg['tool_weights']

    # Purchases so far (0..3+): each pack lowers the chance of the next one.
    n_p = 4 if seg['iap_rate'] > 0 else 1
    iap_p = (seg['iap_rate'] * pack.get('repeat_decay', 1.0) ** np.arange(n_p))[:, None, None]
    state = np.zeros((n_p, n_s, nb))
    state[0, 0, 0] = 1.0
    state = shift(state, cfg['start_balance'], quantum)

    for i, level in enumerate(levels):
        number = i + 1
        seconds = em.attempt_seconds(level, cfg)
        skill = em.skill_at(i, seg)
        willing = np.array([em.willingness(level, s, seg, cfg) for s in range(n_s)])[None, :, None]
        hazard_easy, hazard_effort = em.win_hazards(level, number, seg, cfg, shows,
                                                    em.start_fail(level, skill, 0))
        double = seg['rv_double_rate'] if rv_cfg['double_reward'] and number >= rv_cfg['double_unlock_level'] else 0.0
        fixed = em.fixed_completion_coins(number, cfg, by_level)
        base = em.base_reward(number, cfg)
        # Per streak value: (next streak, reward) after a clean win and after a rescued win.
        clean_move = [(min(n_s - 1, s + 1), base + em.streak_bonus(s + 1, cfg)) for s in range(n_s)]
        rescue_move = [(min(n_s - 1, em.after_rescue_streak(s, cfg)),
                        base + (em.streak_bonus(s + 1, cfg) if policy == 'keep' else 0)) for s in range(n_s)]
        out['reached'][i] = state.sum()
        # After the reward, before churn: first-attempt clean wins vs wins after effort.
        winners_easy = np.zeros((n_p, n_s, nb))
        winners_effort = np.zeros((n_p, n_s, nb))
        pending = state

        for fails in range(MAX_ATTEMPTS):
            mass = pending.sum()
            if mass < EPS:
                break
            out['attempts'][i] += mass
            out['seconds'][i] += mass * seconds
            out['coins_in'][i] += mass * login * seconds
            pending = shift(pending, login * seconds, quantum)
            free_rescue = fails >= pity['after_fails'] and (level['type'] == 'slot_gate' or not pity['only_slot_gates'])

            clean = np.zeros_like(pending)
            rescued_win = np.zeros_like(pending)
            gave_up = np.zeros_like(pending)

            def resolve(dead: np.ndarray, added: int, bought: int, tools: int) -> None:
                """Deadlock mass with `added` extra slots and `tools` helps used this attempt."""
                nonlocal gave_up, rescued_win
                if dead.sum() < EPS:
                    return
                if tools >= max_tools:
                    gave_up += dead
                    return
                slot_ok = em.BASE_SLOTS + added < em.MAX_SLOTS
                slot_cost = em.rescue_cost(bought, cfg)
                can_slot = (bal >= slot_cost) if slot_ok else np.zeros(nb, dtype=bool)
                # Same menu as economy_model.offered_tools; choice by segment weights.
                offer_shuffle = can_shuffle if shuffle_equal else (can_shuffle & ~can_slot)
                w_slot = weights['slot'] * can_slot
                w_shuffle = weights['shuffle'] * offer_shuffle
                w_swap = weights['swap'] * can_swap
                w_crane = weights['crane'] * ((bal >= crane_cost) & (slot_ok and crane_on))
                total = w_slot + w_shuffle + w_swap + w_crane
                offered = total > 0
                payers = dead * offered * willing
                norm = np.where(offered, total, 1.0)
                to_slot = payers * (w_slot / norm)
                to_shuffle = payers * (w_shuffle / norm)
                to_swap = payers * (w_swap / norm)
                to_crane = payers * (w_crane / norm)
                rest = dead - payers
                slot_mass = shift(to_slot, -slot_cost, quantum)
                out['coins_out'][i] += slot_cost * to_slot.sum() + shuffle_cost * to_shuffle.sum() \
                    + swap_cost * to_swap.sum() + crane_cost * to_crane.sum()
                out['rescues_paid'][i] += to_slot.sum()
                out['shuffles'][i] += to_shuffle.sum()
                out['swaps'][i] += to_swap.sum()
                out['cranes'][i] += to_crane.sum()
                if slot_ok:
                    if rv_cfg['rescue']:
                        rv = rest * seg['rv_rescue_rate']
                        rest = rest - rv
                        out['rv_rescue'][i] += rv.sum()
                        slot_mass = slot_mass + rv
                    iap = rest * iap_p * (bal < slot_cost)
                    iap_mass = iap.sum()
                    if iap_mass > EPS:
                        rest = rest - iap
                        bought_up = np.zeros_like(iap)       # the purchase counter moves up
                        bought_up[1:] += iap[:-1]
                        bought_up[-1] += iap[-1]
                        slot_mass = slot_mass + shift(bought_up, pack['coins'] - slot_cost, quantum)
                        out['coins_in'][i] += pack['coins'] * iap_mass
                        out['coins_out'][i] += slot_cost * iap_mass
                        out['iap_usd'][i] += pack['usd'] * iap_mass
                        out['rescues_paid'][i] += iap_mass
                    if free_rescue:
                        out['rescues_free'][i] += rest.sum()
                        slot_mass = slot_mass + rest
                        rest = np.zeros_like(rest)
                gave_up += rest
                q = em.again_after(level, 'slot', added)
                rescued_win += slot_mass * (1 - q)
                resolve(slot_mass * q, added + 1, bought + 1, tools + 1)
                shuffled = shift(to_shuffle, -shuffle_cost, quantum)
                q = em.again_after(level, 'shuffle', added)
                rescued_win += shuffled * (1 - q)
                resolve(shuffled * q, added, bought, tools + 1)
                swapped = shift(to_swap, -swap_cost, quantum)
                q = em.again_after(level, 'swap', added)
                rescued_win += swapped * (1 - q)
                resolve(swapped * q, added, bought, tools + 1)
                craned = shift(to_crane, -crane_cost, quantum)
                q = em.again_after(level, 'crane', added)
                rescued_win += craned * (1 - q)
                resolve(craned * q, added + 1, bought, tools + 1)

            if em.booster_applies(level, number, fails, cfg):
                buy = pending * booster_rich * seg['booster_rate']
                out['coins_out'][i] += booster['price'] * buy.sum()
                out['boosters'][i] += buy.sum()
                groups = ((pending - buy, 0), (shift(buy, -booster['price'], quantum), 1))
            else:
                groups = ((pending, 0),)
            for group, added in groups:
                p = em.start_fail(level, skill, added)
                clean += group * (1 - p)
                dead = group * p
                out['deadlocks'][i] += dead.sum()
                if level['type'] == 'booster_tutorial' and level.get('tutorial_booster'):
                    # Onboarding hint: the first deadlock gets this booster for free.
                    tool = level['tutorial_booster']
                    out['tutorial_shuffles'][i] += dead.sum()
                    q = em.again_after(level, tool, added)
                    rescued_win += dead * (1 - q)
                    resolve(dead * q, added + (1 if tool in ('slot', 'crane') else 0), 0, 1)
                    continue
                if level['type'] == 'shuffle_tutorial':
                    # Onboarding: free verified shuffle at the deadlock, then a possible misplay.
                    out['tutorial_shuffles'][i] += dead.sum()
                    q = level['tutorial_again']
                    rescued_win += dead * (1 - q)
                    resolve(dead * q, added, 0, 1)
                    continue
                out['walls'][i] += (dead * poor).sum()
                resolve(dead, added, 0, 0)

            # Wins: the streak moves and the reward is paid.
            for source, moves, easy in ((clean, clean_move, fails == 0), (rescued_win, rescue_move, False)):
                target = winners_easy if easy else winners_effort
                for s in range(n_s):
                    slab = source[:, s, :]
                    m = slab.sum()
                    if m < EPS:
                        continue
                    s_next, reward = moves[s]
                    out['completed'][i] += m
                    out['rv_double'][i] += m * double
                    out['coins_in'][i] += m * ((1 + double) * reward + fixed)
                    paid_out = shift(slab, reward + fixed, quantum) * (1 - double)
                    if double > 0:
                        paid_out += shift(slab, 2 * reward + fixed, quantum) * double
                    target[:, s_next] += paid_out

            # Give-ups: streak lost, one more fail on this level, possible churn.
            lost = gave_up.sum(axis=1)                    # (n_p, nb), streak -> 0
            hazard = np.minimum(1.0, seg['churn_fail'] * (1 + beh['frustration_weight'] * fails) * wall)
            out['churn_fail'][i] += (lost * hazard).sum()
            pending = np.zeros_like(pending)
            pending[:, 0] = lost * (1 - hazard)
        else:
            out['churn_fail'][i] += pending.sum()       # attempt budget exhausted

        # Cosmetic purchases by rich winners, then churn after the win.
        winners = np.zeros((n_p, n_s, nb))
        for group, hazard_win in ((winners_easy, hazard_easy), (winners_effort, hazard_effort)):
            buy = group * cosmetic_rich * seg['cosmetic_rate']
            out['coins_out'][i] += cosmetic['price'] * buy.sum()
            group = group - buy + shift(buy, -cosmetic['price'], quantum)
            if number in shows:
                out['interstitial'][i] += group.sum()
            out['churn_win'][i] += group.sum() * hazard_win
            winners += group * (1 - hazard_win)
        histograms[i] = winners.sum(axis=(0, 1))
        state = winners

    return {'series': out, 'histograms': histograms, 'balance': bal}


def evaluate(levels: list, cfg: dict, achievements: list, **grid) -> dict:
    """Share-weighted mixture of all segments plus campaign-level KPIs."""
    by_level = em.level_achievements(achievements)
    total = None
    hist = None
    per_segment = {}
    for seg in cfg['segments']:
        result = evaluate_segment(levels, cfg, seg, by_level, **grid)
        per_segment[seg['name']] = summarise(result['series'], result['histograms'], result['balance'], cfg)
        w = seg['share']
        if total is None:
            total = {k: v * w for k, v in result['series'].items()}
            hist = result['histograms'] * w
            bal = result['balance']
        else:
            for k, v in result['series'].items():
                total[k] += v * w
            hist += result['histograms'] * w
    summary = summarise(total, hist, bal, cfg)
    summary['segments'] = per_segment
    return {'series': total, 'histograms': hist, 'balance': bal, 'summary': summary}


def _quantile(hist_row: np.ndarray, bal: np.ndarray, q: float) -> float:
    mass = hist_row.sum()
    if mass <= 0:
        return float('nan')
    cdf = np.cumsum(hist_row) / mass
    return float(bal[min(len(bal) - 1, int(np.searchsorted(cdf, q)))])


def summarise(series: dict, hist: np.ndarray, bal: np.ndarray, cfg: dict) -> dict:
    m = cfg['monetization']
    n = len(series['reached'])
    alive_after = np.append(series['reached'][1:], hist[-1].sum())
    rv = series['rv_double'] + series['rv_rescue']
    ad_rv = rv.sum() * m['ecpm_rewarded_usd'] / 1000
    ad_int = series['interstitial'].sum() * m['ecpm_interstitial_usd'] / 1000
    iap = series['iap_usd'].sum() * (1 - m['store_fee'])
    s = cfg['session']
    day = s['minutes'] * 60 * s['sessions_per_day']
    medians = [_quantile(hist[i], bal, 0.5) for i in range(n)]
    cost = cfg['rescue']['costs'][0]
    below = [float((hist[i] * (bal < cost)).sum() / hist[i].sum()) if hist[i].sum() > 0 else 0.0
             for i in range(n)]
    reach_days = np.cumsum(series['seconds']) / np.maximum(series['reached'], 1e-12) / day

    def retention_day(d: int) -> float:
        # Share still playing when the average survivor has played d days.
        idx = int(np.searchsorted(reach_days, d))
        return float(series['reached'][idx]) if idx < n else float(alive_after[-1])

    return {
        'ltv_usd': ad_rv + ad_int + iap,
        'ltv_rewarded_usd': ad_rv,
        'ltv_interstitial_usd': ad_int,
        'ltv_iap_usd': iap,
        'levels_completed': float(series['completed'].sum()),
        'retention': {L: float(alive_after[L - 1]) for L in (10, 20, 30, 50, 100) if L <= n},
        'retention_days': {d: retention_day(d) for d in (1, 3, 7)},
        'days_played': float(series['seconds'].sum() / day),
        'rv_views': float(rv.sum()),
        'interstitials': float(series['interstitial'].sum()),
        'rescues_paid': float(series['rescues_paid'].sum()),
        'rescues_free': float(series['rescues_free'].sum()),
        'shuffles_paid': float(series['shuffles'].sum()),
        'swaps_paid': float(series['swaps'].sum()),
        'cranes_paid': float(series['cranes'].sum()),
        'boosters': float(series['boosters'].sum()),
        'wall_share': float(series['walls'].sum() / max(series['deadlocks'].sum(), 1e-12)),
        'sink_faucet': float(series['coins_out'].sum() / max(series['coins_in'].sum(), 1e-12)),
        'balance_median': medians,
        'below_rescue': below,
    }
