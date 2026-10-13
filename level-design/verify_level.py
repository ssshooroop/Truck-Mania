"""Exhaustive, cell-based FIFO/holding-area verification; no game-code imports."""
from collections import Counter, deque
from fractions import Fraction
from functools import lru_cache
from pathlib import Path
import json
import sys

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name('level-001-easy.json')
config = json.loads(path.read_text(encoding='utf-8'))
vehicles = config['vehicles']
by_id = {v['id']: v for v in vehicles}
assert len(by_id) == len(vehicles), 'Duplicate vehicle IDs'
width, height = config['grid']['width'], config['grid']['height']
k = config['metadata']['buffer_slots']
queue = tuple(config['passenger_queue'])
directions = {'N': (0, -1), 'S': (0, 1), 'W': (-1, 0), 'E': (1, 0)}
occupied = {}
bodies = {}
sweeps = {}
for v in vehicles:
    x, y = v['position']
    dx, dy = directions[v['direction']]
    cells = {(x - dx * i, y - dy * i) for i in range(v['length'])}
    assert all(0 <= a < width and 0 <= b < height for a, b in cells), 'Body outside grid'
    assert not (cells & set(occupied)), 'Overlapping vehicle bodies'
    bodies[v['id']] = cells
    for cell in cells:
        occupied[cell] = v['id']
    ray = set()
    x, y = x + dx, y + dy
    while 0 <= x < width and 0 <= y < height:
        ray.add((x, y))
        x, y = x + dx, y + dy
    sweeps[v['id']] = ray
assert not config['grid']['walls'] and not config['grid']['obstacles']
capacity = Counter()
for v in vehicles:
    capacity[v['color']] += v['capacity']
assert capacity == Counter(queue), 'Color-capacity imbalance'
dependencies = {i: {j for j in by_id if i != j and sweeps[i] & bodies[j]} for i in by_id}
remaining = set(by_id)
while remaining:
    roots = {i for i in remaining if not (dependencies[i] & remaining)}
    assert roots, 'Cyclic blocking graph'
    remaining -= roots

def physical_moves(yard):
    return tuple(i for i in yard if not (dependencies[i] & set(yard)))

def advance(state, vehicle_id):
    yard, waiting, cursor = state
    assert vehicle_id in physical_moves(yard) and len(waiting) < k
    loads = dict(waiting)
    loads[vehicle_id] = 0
    deliveries = []
    while cursor < len(queue):
        choices = [i for i in loads if by_id[i]['color'] == queue[cursor]]
        if not choices:
            break
        selected = min(choices, key=lambda i: (-loads[i], i))
        loads[selected] += 1
        deliveries.append(selected)
        cursor += 1
        if loads[selected] == by_id[selected]['capacity']:
            del loads[selected]
    return (tuple(i for i in yard if i != vehicle_id), tuple(sorted(loads.items())), cursor), deliveries

start = (tuple(sorted(by_id)), (), 0)
seen, deadlocks, lookahead_failures = set(), [], []
pending = deque([start])
window = k * min(v['capacity'] for v in vehicles)
edges = 0
while pending:
    state = pending.popleft()
    if state in seen:
        continue
    seen.add(state)
    yard, waiting, cursor = state
    assert len(waiting) <= k
    conservation = Counter(queue[cursor:])
    expected = Counter()
    for vid in yard:
        expected[by_id[vid]['color']] += by_id[vid]['capacity']
    for vid, loaded in waiting:
        expected[by_id[vid]['color']] += by_id[vid]['capacity'] - loaded
    assert conservation == expected, 'Cargo conservation failed'
    if cursor == len(queue):
        assert not yard and not waiting
        continue
    physical = physical_moves(yard)
    if not any(by_id[i]['color'] in queue[cursor:cursor + window] for i in physical):
        lookahead_failures.append(state)
    legal = physical if len(waiting) < k else ()
    if not legal:
        deadlocks.append(state)
    for vid in legal:
        next_state, _ = advance(state, vid)
        pending.append(next_state)
        edges += 1

@lru_cache(None)
def outcome(state):
    if state[2] == len(queue):
        return Fraction(1), 1, 0
    moves = physical_moves(state[0]) if len(state[1]) < k else ()
    if not moves:
        return Fraction(0), 0, 1
    children = [outcome(advance(state, vid)[0]) for vid in moves]
    return (sum((c[0] for c in children), Fraction()) / len(moves),
            sum(c[1] for c in children), sum(c[2] for c in children))

state, path_log = start, []
for vid in config['golden_path']:
    before = state
    state, loads = advance(state, vid)
    path_log.append({'vehicle': vid, 'available_before': list(physical_moves(before[0])),
                     'waiting_after': list(state[1]), 'delivered_this_move': len(loads),
                     'delivery_order': list(dict.fromkeys(loads)), 'queue_consumed': state[2]})
assert state == ((), (), len(queue)), 'Golden path does not win'

# Check reverse insertion paths and reconstruct FIFO by undoing actual loading events.
reverse_path = path.with_name('level-001-reverse-construction.json')
reverse = json.loads(reverse_path.read_text(encoding='utf-8'))
inserted, restored_queue = set(), []
for step in reverse['undo_steps']:
    vid = step['return_vehicle']
    assert vid not in inserted
    assert not any(sweeps[vid] & bodies[j] for j in inserted), 'Reverse entry is blocked'
    forward_step = next(p for p in path_log if p['vehicle'] == vid)
    assert [b['vehicle_id'] for b in step['prepend_unloaded_batches']] == list(reversed(forward_step['delivery_order']))
    for batch in step['prepend_unloaded_batches']:
        assert batch['color'] == by_id[batch['vehicle_id']]['color']
        assert batch['count'] == by_id[batch['vehicle_id']]['capacity']
        restored_queue[0:0] = [batch['color']] * batch['count']
    inserted.add(vid)
assert inserted == set(by_id) and restored_queue == list(queue)
assert not deadlocks and not lookahead_failures
probability, winning, losing = outcome(start)
report = {'level_id': config['metadata']['id'], 'vehicles': len(vehicles), 'cargo_units': len(queue),
          'color_capacity': dict(capacity), 'buffer_slots': k, 'lookahead_window': window,
          'reachable_states': len(seen), 'legal_transitions': edges,
          'winning_sequences': winning, 'losing_sequences': losing,
          'random_legal_choice_win_probability': str(probability),
          'human_win_rate': None, 'deadlocks': len(deadlocks),
          'lookahead_failures': len(lookahead_failures), 'dependencies': {i: sorted(v) for i, v in dependencies.items()},
          'golden_path': path_log, 'reverse_generation_verified': True,
          'scope': 'Settled discrete states after automatic FIFO loading, before the next dispatch.'}
path.with_name('level-001-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
