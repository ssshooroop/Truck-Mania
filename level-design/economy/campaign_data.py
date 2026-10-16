"""Level data for the economy model.

load_levels() reads bus-bloom/generated_levels/levels.json written by
res://tools/build_levels.gd. synthesize() builds a stand-in campaign with the
same schedule (bus-bloom/config/level_pipeline.json) and target difficulty
bands, so the economy can be calibrated before real levels exist.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

REFERENCE_SKILL = 0.7
SKILL_GRID = (0.0, 0.35, 0.7, 0.95)


def slot_type(number: int, seq: dict) -> str:
    """Same schedule as LevelSequencer.slot_type."""
    if number in seq.get('booster_tutorial_levels', []):
        return 'booster_tutorial'
    if number in seq.get('shuffle_tutorial_levels', []):
        return 'shuffle_tutorial'
    onboarding = seq['onboarding']
    if number <= len(onboarding):
        return onboarding[number - 1]
    every = seq['gate_every']
    if every > 0 and number % every == 0:
        if number < seq['first_gate_level'] or not seq['gate_pattern']:
            return 'hard'
        index = (number - seq['first_gate_level']) // every
        return seq['gate_pattern'][index % len(seq['gate_pattern'])]
    rhythm = seq['rhythm']
    return rhythm[((number - 1) % max(1, every)) % len(rhythm)]


def _logit(p: float) -> float:
    p = min(0.999, max(0.001, p))
    return math.log(p / (1 - p))


def _sigmoid(x: float) -> float:
    return 1 / (1 + math.exp(-x))




def _shift_p(p: float, delta: float) -> float:
    """Moves a probability by `delta` in logit space; 0 and 1 stay put."""
    if p <= 0.0 or p >= 1.0 or delta == 0:
        return p
    return _sigmoid(_logit(p) + delta)


def _normalise(entry: dict) -> dict:
    """Derived fields used by the simulation.

    Booster utility comes from LevelSolver.booster_profile. Older level files
    without it fall back to post_rescue_fail and generic shuffle values.
    """
    fail = entry['fail_rate']
    if not entry.get('slot_again'):
        post = entry['post_rescue_fail'] if entry['type'] == 'slot_gate' else \
            (entry['post_rescue_fail'] / fail if fail > 0 else 0.0)
        entry['slot_again'] = [min(1.0, post), min(1.0, post * 0.5)]
    if not entry.get('shuffle_again'):
        entry['shuffle_again'] = [0.7, 0.5]
    if not entry.get('swap_again'):
        entry['swap_again'] = [min(1.0, v * 1.3) for v in entry['slot_again']]
    if not entry.get('fail_by_slots'):
        entry['fail_by_slots'] = {'3': fail, '4': fail * entry['slot_again'][0], '5': fail * entry['slot_again'][0] * 0.5}
    entry['fail_by_slots'] = {int(k): float(v) for k, v in entry['fail_by_slots'].items()}
    entry['slot_again'] = [float(v) for v in entry['slot_again']]
    entry['shuffle_again'] = [float(v) for v in entry['shuffle_again']]
    entry['swap_again'] = [float(v) for v in entry['swap_again']]
    if not entry.get('crane_again'):
        entry['crane_again'] = [v * 0.85 for v in entry['slot_again']]
    entry['crane_again'] = [float(v) for v in entry['crane_again']]
    entry['shuffle_by_strength'] = {int(k): [float(x) for x in v['again']]
                                   for k, v in (entry.get('shuffle_by_strength') or {}).items()}
    entry['tutorial_again'] = 1.0 - float(entry.get('tutorial_post_win') or 0.0)
    entry.setdefault('tutorial_booster', 'slot' if entry['type'] == 'booster_tutorial' else None)
    curve = {float(s): float(p) for s, p in entry['fail_by_skill'].items()}
    if 0.9 in curve:
        # Planning players define 0.9 (ordinary) and 1.0 (strong); the greedy
        # 0.95 point would break the order of the scale.
        curve.pop(0.95, None)
    entry['fail_by_skill'] = sorted(curve.items())
    return entry


def synthesize(pipeline_cfg: dict, count: int | None = None, seed: int = 7) -> list:
    seq = pipeline_cfg['sequence']
    count = count or seq['level_count']
    rng = random.Random(seed)
    levels = []
    for number in range(1, count + 1):
        kind = slot_type(number, seq)
        progress = min(1.0, (number - 1) / max(1, seq['ramp_levels'] - 1))
        low, high = seq['targets'][kind]
        target = min(0.95, max(0.0, low + (high - low) * progress + rng.gauss(0, 0.02)))
        v_low = seq['vehicles_start'][0] + (seq['vehicles_end'][0] - seq['vehicles_start'][0]) * progress
        v_high = seq['vehicles_start'][1] + (seq['vehicles_end'][1] - seq['vehicles_start'][1]) * progress
        vehicles = round(rng.uniform(v_low, v_high))
        tutorial = None
        if kind == 'booster_tutorial':
            target = 0.35
        if kind == 'shuffle_tutorial':
            kind, tutorial = 'shuffle_tutorial', 0.88
            target = 0.3
        if kind in ('slot_gate', 'shuffle_tutorial'):
            fail_grid = {str(s): 1.0 for s in SKILL_GRID}
            fail, post = 1.0, target
            near_miss, interest = 0.85, 0.6
            by_slots = {'3': 1.0, '4': post, '5': post * 0.4}
            slot_again, shuffle_again = [post, 0.4], [0.9, 0.5]
        else:
            # Skill moves the fail rate along a logistic curve around the reference.
            fail_grid = {str(s): _sigmoid(_logit(target) + 5.0 * (REFERENCE_SKILL - s)) for s in SKILL_GRID}
            fail = target
            again = min(0.6, 0.15 + fail * 0.6)
            post = fail * again
            near_miss = 0.45 + 0.4 * fail
            # Interest peaks for mid difficulty: trivial and brutal levels bore or annoy.
            interest = 0.3 + 0.6 * math.exp(-((fail - 0.35) / 0.3) ** 2)
            by_slots = {'3': fail, '4': fail * 0.45, '5': fail * 0.2}
            slot_again, shuffle_again = [again, again * 0.5], [0.6 + 0.3 * fail, 0.5]
        levels.append(_normalise({
            'level': number, 'type': kind, 'fail_rate': fail, 'post_rescue_fail': post,
            'fail_by_skill': fail_grid, 'near_miss': near_miss, 'interest': interest,
            'fail_by_slots': by_slots, 'slot_again': slot_again, 'shuffle_again': shuffle_again,
            'shuffle_by_strength': {k: {'again': [min(1.0, a * (0.85 ** math.log2(k))) for a in shuffle_again]}
                                    for k in (1, 2, 4, 8, 16)},
            'tutorial_post_win': tutorial,
            'moves': vehicles, 'cargo': vehicles * 4, 'synthetic': True,
        }))
    return levels


def shift_difficulty(levels: list, delta: float) -> list:
    """What-if copy with every deadlock probability moved by `delta` in logit space.

    delta = ln(2) doubles the odds of a deadlock. Certain outcomes (0 or 1,
    such as a slot gate at three slots) stay certain.
    """
    shifted = []
    for level in levels:
        copy = dict(level)
        copy['fail_by_skill'] = [(s, _shift_p(p, delta)) for s, p in level['fail_by_skill']]
        copy['fail_rate'] = _shift_p(level['fail_rate'], delta)
        copy['fail_by_slots'] = {k: _shift_p(v, delta) for k, v in level['fail_by_slots'].items()}
        copy['slot_again'] = [_shift_p(v, delta) for v in level['slot_again']]
        copy['shuffle_again'] = [_shift_p(v, delta) for v in level['shuffle_again']]
        copy['swap_again'] = [_shift_p(v, delta) for v in level['swap_again']]
        copy['crane_again'] = [_shift_p(v, delta) for v in level['crane_again']]
        copy['shuffle_by_strength'] = {k: [_shift_p(v, delta) for v in again]
                                       for k, again in level['shuffle_by_strength'].items()}
        shifted.append(copy)
    return shifted


def load_levels(path: Path) -> list:
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    levels = []
    for level in data['levels']:
        c = level['campaign']
        levels.append(_normalise({
            'level': c['level'], 'type': c['type'], 'fail_rate': c['fail_rate'],
            'post_rescue_fail': c['post_rescue_fail'], 'fail_by_skill': c['fail_by_skill'],
            'near_miss': c['near_miss'], 'interest': c['interest'],
            'fail_by_slots': c.get('fail_by_slots'), 'slot_again': c.get('slot_again'),
            'shuffle_again': c.get('shuffle_again'), 'shuffle_by_strength': c.get('shuffle_by_strength'),
            'swap_again': c.get('swap_again'), 'crane_again': c.get('crane_again'),
            'tutorial_post_win': c.get('tutorial_post_win') if c['type'] == 'shuffle_tutorial' else None,
            'tutorial_booster': (level.get('tutorial') or {}).get('booster') if c['type'] == 'booster_tutorial' else None,
            'shuffle_hopeless': c.get('shuffle_hopeless', 0.0), 'shuffle_spread': c.get('shuffle_spread', 0.0),
            'moves': c['vehicle_count'], 'cargo': len(level['queue']), 'synthetic': False,
        }))
    return levels


def select_shuffle_strength(levels: list, strength: int) -> list:
    """Copies with shuffle_again taken from the measured smart shuffle of the
    nearest available strength (best of `strength` random permutations)."""
    result = []
    for level in levels:
        table = level['shuffle_by_strength']
        if not table:
            result.append(level)
            continue
        k = min(table, key=lambda s: (abs(math.log2(s) - math.log2(max(1, strength))), s))
        copy = dict(level)
        copy['shuffle_again'] = table[k]
        result.append(copy)
    return result