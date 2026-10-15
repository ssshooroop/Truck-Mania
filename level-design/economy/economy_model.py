"""Coin economy of Truck Mania / Cargo Yard: formulas and an agent simulation.

The exact distributional model (exact_model.py) is the one used for
optimisation; this agent simulation follows the same rules player by player
and is used to cross-check it.

Level data (campaign_data.py) drives player behaviour:
- fail_by_skill -> probability of a deadlock for the player's current skill;
- fail_by_slots -> deadlock rate when starting with 3 / 4 / 5 slots (Extra Slot booster);
- slot_again    -> chance of another deadlock after the 1st / 2nd +1 slot at a deadlock;
- shuffle_again -> chance of another deadlock after shuffling the queue at a deadlock
                   (with 0 / 1 extra slots), measured with the real shuffle;
- near_miss     -> share of cargo cleared at the deadlock, raises willingness to pay;
- interest      -> 0..1, boring levels raise churn after a win.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

HARD_TYPES = ('hard', 'very_hard', 'soft_gate', 'slot_gate')
BASE_SLOTS = 3
MAX_SLOTS = 5


# --- Formulas ---------------------------------------------------------------

def base_reward(level: int, cfg: dict) -> float:
    """R_base(L) = min(cap, a + floor(b * sqrt(L)))."""
    r = cfg['reward']['base']
    return min(r['cap'], r['a'] + math.floor(r['b'] * math.sqrt(level)))


def streak_bonus(streak: int, cfg: dict) -> float:
    """B_clean(S) = step * min(cap, S); S counts clean wins in a row including this one."""
    s = cfg['reward']['clean_streak']
    return s['step'] * min(s['cap'], streak)


def rescue_cost(index: int, cfg: dict) -> float:
    """Price of the (index+1)-th slot bought at deadlocks within one attempt."""
    costs = cfg['rescue']['costs']
    return costs[min(index, len(costs) - 1)]


def after_rescue_streak(streak: int, cfg: dict) -> int:
    """Clean streak after a win that needed a rescue."""
    policy = cfg['reward']['rescue_streak_policy']
    if policy == 'keep':
        return streak + 1
    if policy == 'reset':
        return 0
    return streak  # freeze: no bonus, no reset


def login_per_second(cfg: dict) -> float:
    """Daily login coins spread over the daily play time (mean of the 7-day cycle)."""
    s = cfg['session']
    day = s['minutes'] * 60 * s['sessions_per_day']
    rewards = cfg['daily_login']
    return cfg.get('daily_login_scale', 1.0) * sum(rewards) / len(rewards) / day


def skill_at(completed: int, segment: dict) -> float:
    """Learning curve s(n) = s0 + (s1 - s0) * (1 - exp(-n / tau))."""
    s0, s1 = segment['skill_start'], segment['skill_end']
    return s0 + (s1 - s0) * (1.0 - math.exp(-completed / segment['learning_levels']))


def fail_at(level: dict, skill: float) -> float:
    """Base-slot deadlock probability, linear in skill between measured points."""
    points = level['fail_by_skill']
    if skill <= points[0][0]:
        return points[0][1]
    for (s0, p0), (s1, p1) in zip(points, points[1:]):
        if skill <= s1:
            return p0 + (p1 - p0) * (skill - s0) / (s1 - s0)
    return points[-1][1]


def start_fail(level: dict, skill: float, extra_slots: int) -> float:
    """Deadlock probability of an attempt that starts with 3 + extra_slots slots.

    The measured ratio f(3+e)/f(3) at the reference skill scales the
    skill-specific base rate; a slot gate uses the measured rate directly.
    """
    if level['type'] in ('slot_gate', 'shuffle_tutorial'):
        return level['fail_by_slots'][BASE_SLOTS + extra_slots]
    base = fail_at(level, skill)
    if extra_slots == 0:
        return base
    f3 = level['fail_by_slots'][BASE_SLOTS]
    return base * level['fail_by_slots'][BASE_SLOTS + extra_slots] / f3 if f3 > 0 else 0.0


def again_after(level: dict, tool: str, added: int) -> float:
    """Chance of another deadlock right after using `tool` with `added` extra slots before it."""
    table = {'slot': level['slot_again'], 'shuffle': level['shuffle_again'], 'swap': level['swap_again'],
             'crane': level['crane_again']}[tool]
    return table[min(added, len(table) - 1)]


TOOLS = ('slot', 'shuffle', 'swap', 'crane')


def tool_prices(cfg: dict, slot_cost: float) -> dict:
    r = cfg['rescue']
    return {'slot': slot_cost, 'shuffle': r['shuffle_cost'], 'swap': r['swap_cost'], 'crane': r['crane_cost']}


def offered_tools(cfg: dict, slot_ok: bool, affordable: dict) -> list:
    """Tools the player can pay for at a deadlock.

    Slot and crane need a free slot place (at most 5). With shuffle_menu 'fallback'
    the shuffle is offered only when a slot cannot be bought (too poor or all
    five slots open); with 'equal' it is always offered.
    """
    slot = slot_ok and affordable['slot']
    result = ['slot'] if slot else []
    if affordable['shuffle'] and (cfg['rescue'].get('shuffle_menu', 'equal') == 'equal' or not slot):
        result.append('shuffle')
    if cfg['rescue'].get('swap_enabled', True) and affordable['swap']:
        result.append('swap')
    if cfg['rescue'].get('crane_enabled', True) and slot_ok and affordable['crane']:
        result.append('crane')
    return result

def willingness(level: dict, streak: int, segment: dict, cfg: dict) -> float:
    """P(pay | affordable) = w0 + w_near*(near_miss - 0.5) + w_streak*min(S, 5)/5, clipped."""
    b = cfg['behaviour']
    value = segment['buy_rescue_base'] + b['near_miss_weight'] * (level['near_miss'] - 0.5) \
        + b['streak_weight'] * min(streak, 5) / 5.0
    return min(1.0, max(0.0, value))


def attempt_seconds(level: dict, cfg: dict) -> float:
    s = cfg['session']
    return s['seconds_per_attempt'] + s['seconds_per_move'] * level['moves']


def interstitial_schedule(levels: list, cfg: dict) -> dict:
    """{level number: extra churn hazard} for the levels followed by an interstitial.

    Shown only after a win (a lost attempt never shows one), from start_level
    on, once `every_levels` wins and at least `min_seconds` of play (one attempt
    per level) have passed since the previous show. Fatigue: with Δ seconds
    between shows a session holds T/Δ shows, and each show costs
    h_int * (1 + phi * max(0, T/Δ - 1)).
    """
    i = cfg['interstitial']
    if not i['enabled']:
        return {}
    b = cfg['behaviour']
    session = cfg['session']['minutes'] * 60
    every = max(1, int(i['every_levels']))
    shows: dict = {}
    since = 0.0
    wins = 0
    for number, level in enumerate(levels, start=1):
        since += attempt_seconds(level, cfg)
        wins += 1
        if number >= i['start_level'] and wins >= every and since >= i.get('min_seconds', 0):
            per_session = session / max(since, 1.0)
            shows[number] = b['interstitial_churn'] * (1 + b.get('interstitial_fatigue', 0.0)
                                                      * max(0.0, per_session - 1))
            since = 0.0
            wins = 0
    return shows

def level_achievements(achievements: list) -> dict:
    """{levels_completed: coins} for the achievements both models handle exactly."""
    result: dict = {}
    for a in achievements:
        t = a['trigger']
        if t['counter'] == 'levels_completed':
            result[t['at_least']] = result.get(t['at_least'], 0) + a['reward'].get('coins', 0)
    return result


def fixed_completion_coins(number: int, cfg: dict, by_level: dict) -> float:
    """Chest plus level-count achievements paid on completing level `number`."""
    chest = cfg['chest']
    coins = chest['coins'] if number % chest['every_levels'] == 0 else 0
    return coins + by_level.get(number, 0)


def booster_applies(level: dict, number: int, fails_here: int, cfg: dict) -> bool:
    """Extra Slot for the whole level is considered on hard levels and after a fail."""
    b = cfg['booster']
    return level['type'] not in ('shuffle_tutorial', 'booster_tutorial') and number >= b['unlock_level'] \
        and (level['type'] in HARD_TYPES or fails_here > 0)


# --- Agent simulation -------------------------------------------------------

@dataclass
class PlayerResult:
    segment: str
    balance: list = field(default_factory=list)
    earned: list = field(default_factory=list)
    spent: list = field(default_factory=list)
    attempts: list = field(default_factory=list)
    churned_at: int | None = None
    rescues_paid: int = 0
    shuffles_paid: int = 0
    swaps_paid: int = 0
    cranes_paid: int = 0
    rescues_rv: int = 0
    rescues_free: int = 0
    tutorial_shuffles: int = 0
    boosters: int = 0
    rv_double: int = 0
    interstitials: int = 0
    iap_usd: float = 0.0
    seconds: float = 0.0


class Player:
    def __init__(self, cfg: dict, segment: dict, by_level: dict, shows: dict, rng: random.Random):
        self.cfg, self.segment, self.rng, self.by_level, self.shows = cfg, segment, rng, by_level, shows
        self.balance = float(cfg['start_balance'])
        self.streak = 0
        self.completed = 0
        self.purchases = 0
        self.result = PlayerResult(segment['name'])
        self.login_rate = login_per_second(cfg)
        self._earned = self._spent = 0.0

    def _gain(self, amount: float) -> None:
        self.balance += amount
        self._earned += amount

    def _spend(self, amount: float) -> None:
        self.balance -= amount
        self._spent += amount

    def _rescue(self, level: dict, added: int, bought: int, fails_here: int) -> str | None:
        """Resolves one deadlock: returns 'slot', 'shuffle', 'swap' or None (gives up)."""
        cfg, rng, seg = self.cfg, self.rng, self.segment
        slot_ok = BASE_SLOTS + added < MAX_SLOTS
        slot_cost = rescue_cost(bought, cfg)
        prices = tool_prices(cfg, slot_cost)
        affordable = offered_tools(cfg, slot_ok, {t: self.balance >= c for t, c in prices.items()})
        if affordable and rng.random() < willingness(level, self.streak, seg, cfg):
            weights = seg['tool_weights']
            tool = rng.choices(affordable, [weights[t] for t in affordable])[0]
            self._spend(prices[tool])
            if tool == 'slot':
                self.result.rescues_paid += 1
            elif tool == 'shuffle':
                self.result.shuffles_paid += 1
            elif tool == 'swap':
                self.result.swaps_paid += 1
            else:
                self.result.cranes_paid += 1
            return tool
        if not slot_ok:
            return None
        if cfg['rewarded_video']['rescue'] and rng.random() < seg['rv_rescue_rate']:
            self.result.rescues_rv += 1
            return 'slot'
        decay = cfg['iap_pack'].get('repeat_decay', 1.0) ** min(self.purchases, 3)
        if self.balance < slot_cost and rng.random() < seg['iap_rate'] * decay:
            self.purchases += 1
            pack = cfg['iap_pack']
            self._gain(pack['coins'])
            self.result.iap_usd += pack['usd']
            self._spend(slot_cost)
            self.result.rescues_paid += 1
            return 'slot'
        pity = cfg['rescue']['pity']
        if fails_here >= pity['after_fails'] and (level['type'] == 'slot_gate' or not pity['only_slot_gates']):
            self.result.rescues_free += 1
            return 'slot'
        return None
    def play(self, level: dict, number: int) -> bool:
        """Plays until the level is won or the player churns. Returns False on churn."""
        cfg, rng, seg, b = self.cfg, self.rng, self.segment, self.cfg['behaviour']
        self._earned = self._spent = 0.0
        fails_here = attempts = 0
        while True:
            attempts += 1
            seconds = attempt_seconds(level, cfg)
            self.result.seconds += seconds
            self._gain(self.login_rate * seconds)
            booster = cfg['booster']
            added = 0
            if booster_applies(level, number, fails_here, cfg) \
                    and self.balance >= booster['price'] * booster['rich_multiplier'] \
                    and rng.random() < seg['booster_rate']:
                self._spend(booster['price'])
                self.result.boosters += 1
                added = 1
            p = start_fail(level, skill_at(self.completed, seg), added)
            bought = tools = 0
            gave_up = False
            if level['type'] == 'shuffle_tutorial':
                # Onboarding: the level deadlocks, a hint gives a free verified
                # shuffle, and the player may still misplay afterwards.
                self.result.tutorial_shuffles += 1
                p = level['tutorial_again']
                tools = 1
            tutorial = level.get('tutorial_booster') if level['type'] == 'booster_tutorial' else None
            while rng.random() < p:
                tool = None
                if tutorial and tools == 0:
                    # Onboarding hint: the first deadlock gets this booster for free.
                    tool = tutorial
                    self.result.tutorial_shuffles += 1
                elif tools < cfg['rescue']['max_tools']:
                    tool = self._rescue(level, added, bought, fails_here)
                if tool is None:
                    gave_up = True
                    break
                tools += 1
                p = again_after(level, tool, added)
                if tool == 'slot':
                    added += 1
                    bought += 0 if tutorial and tools == 1 else 1
                elif tool == 'crane':
                    added += 1      # the crane also opens a slot place
            if gave_up:
                wall = self.balance < min(tool_prices(cfg, rescue_cost(0, cfg)).values())
                fails_here += 1
                self.streak = 0
                hazard = seg['churn_fail'] * (1 + b['frustration_weight'] * (fails_here - 1))
                if wall:
                    hazard *= b['wall_churn_multiplier']
                if rng.random() < hazard:
                    self.result.churned_at = number
                    return False
                continue
            self._win(level, number, tools)
            self.result.attempts.append(attempts)
            self.result.balance.append(self.balance)
            self.result.earned.append(self._earned)
            self.result.spent.append(self._spent)
            hazard = seg['churn_win'] * (1 + b['boredom_weight'] * (1 - level['interest']))
            if number in self.shows:
                self.result.interstitials += 1
                hazard += self.shows[number]
            if rng.random() < hazard:
                self.result.churned_at = number + 1
                return False
            return True

    def _win(self, level: dict, number: int, tools: int) -> None:
        cfg, rng = self.cfg, self.rng
        if tools == 0:
            self.streak += 1
            reward = base_reward(number, cfg) + streak_bonus(self.streak, cfg)
        else:
            self.streak = after_rescue_streak(self.streak, cfg)
            reward = base_reward(number, cfg) \
                + (streak_bonus(self.streak, cfg) if cfg['reward']['rescue_streak_policy'] == 'keep' else 0)
        rv = cfg['rewarded_video']
        if rv['double_reward'] and number >= rv['double_unlock_level'] and rng.random() < self.segment['rv_double_rate']:
            self.result.rv_double += 1
            reward *= 2
        self._gain(reward + fixed_completion_coins(number, cfg, self.by_level))
        self.completed += 1
        c = cfg['cosmetic']
        if self.balance >= c['price'] + c['reserve'] and rng.random() < self.segment['cosmetic_rate']:
            self._spend(c['price'])


def simulate(levels: list, cfg: dict, achievements: list, players: int, seed: int = 1) -> list:
    rng = random.Random(seed)
    by_level = level_achievements(achievements)
    shows = interstitial_schedule(levels, cfg)
    segments = cfg['segments']
    weights = [s['share'] for s in segments]
    results = []
    for _ in range(players):
        player = Player(cfg, rng.choices(segments, weights)[0], by_level, shows, rng)
        for number, level in enumerate(levels, start=1):
            if not player.play(level, number):
                break
        results.append(player.result)
    return results
