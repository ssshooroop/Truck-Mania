"""Economy model runner for Truck Mania / Cargo Yard.

    python level-design/economy/run_economy.py                  # exact model report
    python level-design/economy/run_economy.py --validate       # exact model vs agent simulation
    python level-design/economy/run_economy.py --optimize       # revenue / engagement frontier
    python level-design/economy/run_economy.py --sensitivity    # effect of each lever

Add --levels bus-bloom/generated_levels/levels.json to use generated levels;
without it a synthetic campaign is built from level_pipeline.json.
Results go to level-design/economy/out/.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import campaign_data  # noqa: E402
import economy_model as em  # noqa: E402
import exact_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / 'bus-bloom' / 'config'
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out'


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


# --- Parameters ---------------------------------------------------------------

def get_param(cfg: dict, name: str) -> float:
    if name == 'rescue.cost':
        return cfg['rescue']['costs'][0]
    if name == 'rescue.escalation':
        costs = cfg['rescue']['costs']
        return costs[1] / costs[0] if len(costs) > 1 else 1.0
    if name == 'difficulty_shift':
        return cfg.get('difficulty_shift', 0.0)
    if name == 'rescue.shuffle_strength_log2':
        return round(math.log2(cfg['rescue'].get('shuffle_strength', 1)))
    node = cfg
    *path, last = name.split('.')
    for key in path:
        node = node[key]
    return node[last]


def set_param(cfg: dict, name: str, value: float) -> None:
    if name == 'rescue.cost':
        esc = get_param(cfg, 'rescue.escalation')
        cfg['rescue']['costs'] = [value, round(value * esc / 10) * 10]
        return
    if name == 'rescue.escalation':
        base = cfg['rescue']['costs'][0]
        cfg['rescue']['costs'] = [base, round(base * value / 10) * 10]
        return
    if name == 'difficulty_shift':
        cfg['difficulty_shift'] = value
        return
    if name == 'rescue.shuffle_strength_log2':
        cfg['rescue']['shuffle_strength'] = int(2 ** round(value))
        return
    node = cfg
    *path, last = name.split('.')
    for key in path:
        node = node[key]
    node[last] = int(value) if isinstance(node[last], int) and float(value).is_integer() else value


class Evaluator:
    """Caches difficulty-shifted campaigns and counts model evaluations."""

    def __init__(self, levels: list, achievements: list):
        self.levels = levels
        self.achievements = achievements
        self.shifted: dict = {}
        self.calls = 0

    def campaign(self, cfg: dict) -> list:
        delta = round(cfg.get('difficulty_shift', 0.0), 6)
        strength = int(cfg['rescue'].get('shuffle_strength', 1))
        key = (delta, strength)
        if key not in self.shifted:
            levels = campaign_data.select_shuffle_strength(self.levels, strength)
            self.shifted[key] = campaign_data.shift_difficulty(levels, delta) if delta else levels
        return self.shifted[key]

    def __call__(self, cfg: dict) -> dict:
        self.calls += 1
        return exact_model.evaluate(self.campaign(cfg), cfg, self.achievements)['summary']


def objective(s: dict, lam: float, constraints: dict) -> float:
    """J = LTV + lambda * E[levels completed] - penalties for violated constraints:`n    retention to level 10 below its floor, or too many deadlocks the player cannot afford."""
    value = s['ltv_usd'] + lam * s['levels_completed']
    floor = constraints.get('retention_level_10_min')
    if floor is not None:
        value -= 10.0 * max(0.0, floor - s['retention'].get(10, 0.0))
    walls = constraints.get('wall_share_max')
    if walls is not None:
        value -= 10.0 * max(0.0, s['wall_share'] - walls)
    return value


_worker_evaluator = None


def _init_worker(levels: list, achievements: list) -> None:
    global _worker_evaluator
    _worker_evaluator = Evaluator(levels, achievements)


def _evaluate_in_worker(cfg: dict) -> dict:
    return _worker_evaluator(cfg)


class ParallelSearch:
    """Steepest ascent over the parameter grid. All neighbours of the current
    point are evaluated in parallel; summaries are cached by parameter values
    because they do not depend on lambda."""

    def __init__(self, levels: list, achievements: list, space: dict, workers: int):
        from concurrent.futures import ProcessPoolExecutor
        self.space = space
        self.cache: dict = {}
        self.pool = ProcessPoolExecutor(max_workers=workers, initializer=_init_worker,
                                        initargs=(levels, achievements))

    def key(self, cfg: dict) -> tuple:
        return tuple(round(float(get_param(cfg, name)), 6) for name in self.space)

    def evaluate_many(self, cfgs: list) -> list:
        missing = [c for c in cfgs if self.key(c) not in self.cache]
        unique = {self.key(c): c for c in missing}
        for k, summary in zip(unique, self.pool.map(_evaluate_in_worker, unique.values())):
            self.cache[k] = summary
        return [self.cache[self.key(c)] for c in cfgs]

    def neighbours(self, cfg: dict) -> list:
        result = []
        for name, rng in self.space.items():
            current = get_param(cfg, name)
            for direction in (1, -1):
                value = round(current + direction * rng['step'], 6)
                if rng['min'] - 1e-9 <= value <= rng['max'] + 1e-9:
                    trial = copy.deepcopy(cfg)
                    set_param(trial, name, value)
                    result.append(trial)
        return result

    def run(self, cfg: dict, lam: float, constraints: dict, max_steps: int = 60) -> tuple:
        best_cfg = copy.deepcopy(cfg)
        best_summary = self.evaluate_many([best_cfg])[0]
        best = objective(best_summary, lam, constraints)
        for _ in range(max_steps):
            trials = self.neighbours(best_cfg)
            summaries = self.evaluate_many(trials)
            scores = [objective(s, lam, constraints) for s in summaries]
            index = max(range(len(scores)), key=scores.__getitem__)
            if scores[index] <= best + 1e-7:
                break
            best, best_cfg, best_summary = scores[index], trials[index], summaries[index]
        return best_cfg, best_summary, best


# --- Reports ------------------------------------------------------------------

def headline(s: dict) -> dict:
    medians = [m for m in s['balance_median'][14:50] if not math.isnan(m)]
    return {
        'ltv_usd': round(s['ltv_usd'], 4),
        'ltv_rv': round(s['ltv_rewarded_usd'], 4),
        'ltv_int': round(s['ltv_interstitial_usd'], 4),
        'ltv_iap': round(s['ltv_iap_usd'], 4),
        'levels': round(s['levels_completed'], 2),
        'ret_10': round(s['retention'].get(10, 0), 3),
        'ret_30': round(s['retention'].get(30, 0), 3),
        'ret_100': round(s['retention'].get(100, 0), 3),
        'D1': round(s['retention_days'][1], 3),
        'D7': round(s['retention_days'][7], 3),
        'days': round(s['days_played'], 2),
        'rv_views': round(s['rv_views'], 2),
        'interstitials': round(s['interstitials'], 2),
        'slots_paid': round(s['rescues_paid'], 2),
        'shuffles_paid': round(s['shuffles_paid'], 2),
        'swaps_paid': round(s['swaps_paid'], 2),
        'cranes_paid': round(s['cranes_paid'], 2),
        'extra_slot_boosters': round(s['boosters'], 2),
        'balance_med_15_50': round(statistics.fmean(medians), 0) if medians else None,
        'wall_share': round(s['wall_share'], 3),
        'sink_faucet': round(s['sink_faucet'], 3),
    }


def params_row(cfg: dict, space: dict) -> dict:
    return {name: get_param(cfg, name) for name in space}


def markdown_table(rows: list) -> str:
    keys = list(rows[0].keys())
    lines = ['| ' + ' | '.join(keys) + ' |', '|' + '---|' * len(keys)]
    for row in rows:
        lines.append('| ' + ' | '.join(f'{row[k]:.4g}' if isinstance(row[k], float) else str(row[k])
                                       for k in keys) + ' |')
    return '\n'.join(lines)


def validate(levels: list, cfg: dict, achievements: list, players: int, seed: int) -> list:
    """Exact model vs agent simulation on the same rules."""
    exact = exact_model.evaluate(levels, cfg, achievements)
    series, hist, bal = exact['series'], exact['histograms'], exact['balance']
    results = em.simulate(levels, cfg, achievements, players, seed)
    rows = []
    for L in (1, 5, 10, 20, 30, 50, 100):
        if L > len(levels):
            continue
        done = [r.balance[L - 1] for r in results if len(r.balance) >= L]
        row = hist[L - 1]
        rows.append({'level': L,
                     'completed_exact': round(float(series['completed'][L - 1]), 4),
                     'completed_sim': round(len(done) / players, 4),
                     'balance_exact': round(float((row * bal).sum() / row.sum()), 1) if row.sum() else None,
                     'balance_sim': round(statistics.fmean(done), 1) if done else None})
    totals = {
        'levels': (float(series['completed'].sum()), sum(len(r.balance) for r in results) / players),
        'rv_views': (float((series['rv_double'] + series['rv_rescue']).sum()),
                     sum(r.rv_double + r.rescues_rv for r in results) / players),
        'rescues_paid': (float(series['rescues_paid'].sum()), sum(r.rescues_paid for r in results) / players),
        'interstitials': (float(series['interstitial'].sum()), sum(r.interstitials for r in results) / players),
        'shuffles_paid': (float(series['shuffles'].sum()), sum(r.shuffles_paid for r in results) / players),
        'swaps_paid': (float(series['swaps'].sum()), sum(r.swaps_paid for r in results) / players),
        'cranes_paid': (float(series['cranes'].sum()), sum(r.cranes_paid for r in results) / players),
        'extra_slot_boosters': (float(series['boosters'].sum()), sum(r.boosters for r in results) / players),
        'iap_usd': (float(series['iap_usd'].sum()), sum(r.iap_usd for r in results) / players),
    }
    for name, (e, s) in totals.items():
        rows.append({'level': name, 'completed_exact': round(e, 4), 'completed_sim': round(s, 4),
                     'balance_exact': '', 'balance_sim': ''})
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--levels', type=Path)
    parser.add_argument('--economy', type=Path, default=CONFIG_DIR / 'economy_config.json')
    parser.add_argument('--search', type=Path, default=HERE / 'economy_search.json')
    parser.add_argument('--validate', action='store_true')
    parser.add_argument('--optimize', action='store_true')
    parser.add_argument('--sensitivity', action='store_true')
    parser.add_argument('--lambda', dest='lam', type=float, default=0.0,
                        help='engagement weight for --sensitivity')
    parser.add_argument('--players', type=int, default=20000)
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()

    cfg = load_json(args.economy)
    achievements = load_json(CONFIG_DIR / 'achievements.json')['achievements']
    if args.levels:
        levels = campaign_data.load_levels(args.levels)
        source = str(args.levels)
    else:
        levels = campaign_data.synthesize(load_json(CONFIG_DIR / 'level_pipeline.json'))
        source = 'synthetic campaign (level_pipeline.json)'
    OUT.mkdir(exist_ok=True)
    search = load_json(args.search)
    space = search['parameters']
    constraints = search['objective']['constraints']
    evaluate = Evaluator(levels, achievements)
    print(f'Levels: {source}, {len(levels)} levels')

    if args.validate:
        started = time.time()
        rows = validate(evaluate.campaign(cfg), cfg, achievements, args.players, args.seed)
        print(markdown_table(rows))
        print(f'{args.players} simulated players, {time.time() - started:.1f} s')
        return 0

    if args.optimize:
        import os
        started = time.time()
        searcher = ParallelSearch(levels, achievements, space, max(1, (os.cpu_count() or 2) - 1))
        frontier = []
        start_cfg = cfg
        for lam in search['objective']['lambdas']:
            best_cfg, summary, score = searcher.run(start_cfg, lam, constraints)
            frontier.append({'lambda': lam, **headline(summary), **params_row(best_cfg, space)})
            (OUT / f'optimum_lambda_{lam:g}.json').write_text(
                json.dumps(best_cfg, indent=2, ensure_ascii=False), encoding='utf-8')
            print(f'lambda={lam:g}: J={score:.4f}  ({len(searcher.cache)} evaluations, '
                  f'{time.time() - started:.0f} s)', flush=True)
        baseline = {'lambda': 'start', **headline(searcher.evaluate_many([cfg])[0]), **params_row(cfg, space)}
        table = markdown_table([baseline] + frontier)
        (OUT / 'frontier.md').write_text(table + '\n', encoding='utf-8')
        print(table)
        return 0

    if args.sensitivity:
        base = evaluate(cfg)
        rows = []
        for name, rng in space.items():
            value = get_param(cfg, name)
            up = min(rng['max'], value + rng['step'])
            if up == value:
                continue
            trial = copy.deepcopy(cfg)
            set_param(trial, name, up)
            s = evaluate(trial)
            rows.append({'parameter': name, 'from': value, 'to': up,
                         'd_ltv_usd': round(s['ltv_usd'] - base['ltv_usd'], 5),
                         'd_ltv_pct': round(100 * (s['ltv_usd'] / base['ltv_usd'] - 1), 2),
                         'd_levels': round(s['levels_completed'] - base['levels_completed'], 3),
                         'd_ret_30_pp': round(100 * (s['retention'][30] - base['retention'][30]), 2),
                         'd_objective': round(objective(s, args.lam, constraints)
                                              - objective(base, args.lam, constraints), 5)})
        table = markdown_table(rows)
        (OUT / 'sensitivity.md').write_text(table + '\n', encoding='utf-8')
        print(json.dumps(headline(base), ensure_ascii=False))
        print(table)
        return 0

    started = time.time()
    s = exact_model.evaluate(evaluate.campaign(cfg), cfg, achievements)['summary']
    print(json.dumps(headline(s), indent=2, ensure_ascii=False))
    print(f'exact model: {time.time() - started:.2f} s')
    segments = [{'segment': name, **headline(seg)} for name, seg in s['segments'].items()]
    print(markdown_table(segments))
    (OUT / 'report.json').write_text(json.dumps({'headline': headline(s), 'segments': segments,
                                                 'balance_median': s['balance_median']},
                                                indent=2, ensure_ascii=False), encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
