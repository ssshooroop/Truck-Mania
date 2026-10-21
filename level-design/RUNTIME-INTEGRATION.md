# Runtime integration, 2026-10-15

Imported source: `origin/level-pipeline-economy`, commit `8f0b912`.

- `bus-bloom/config/campaign.json` is the shipping copy of generated `levels.json` (100 levels). Refresh it whenever the offline campaign is rebuilt. The ignored `generated_levels` directory remains analysis output.
- `game_model.gd` reads the campaign positions, capacities, cargo queues and order certificates. Every attempt starts with three bays. Purchased bays last for that attempt only.
- `runtime_economy.gd` reads `economy_config.json` and `achievements.json`: initial wallet 50; base reward `min(cap,a+floor(b*sqrt(level)))`; clean streak; chest every ten distinct completions; achievement counters and inventory; daily login cycle. Existing wallets and completion claims are preserved. Replays do not grant completion rewards again.
- The first eligible deadlock at level 3 or later teaches one free bay. Completion is persisted. Players who skip the level-3 deadlock remain eligible later.
- Paid slots cost 100/200 in an attempt. The pre-start extra-slot offer from level 12 costs 150. Crane, swap and smart shuffle are available at deadlocks, using configured prices and the two-tool limit. Crane opens a bay and lifts a matching yard truck. Swap returns the least-loaded docked truck and its cargo, replacing it with the largest yard truck matching the queue head. Shuffle uses the configured 16-candidate policy. Paid tool actions clear Undo history to prevent duplicate benefits.
- Ads, IAP and cosmetic catalogue require production integrations/content. Their economic assumptions are retained in configuration; the preview never simulates a completed ad or purchase. Player-skill probabilities, churn and LTV are offline simulation parameters, not gameplay gates.
- M PLUS Rounded 1c Medium/Bold/ExtraBold/Black are bundled with their OFL license. Unused weights are excluded from exports.

Verification: 100 certificates pass in the runtime and exported PCK (10,417 checks); 28 campaign/UI checks; 9 reward/save checks; 52 road-menu checks; 84 concurrent loading checks; native smooth-motion checks. All 100 levels pass swept motion verification (994,983 samples, zero collisions or invisible vehicles). Native screenshots inspected; no claim of mobile-device or browser rendering QA.

The service road is at y=516; bay fronts at y=227. Forward exits stop before the loading area, bottom exits reach the bottom lane before travelling up the side, and trucks align before entering bays. These clearances accommodate the new campaign's longer trucks and different docking orders.

## Variety pass after playtesting

The player found levels 1–11 too easy and repetitive. Revision `variety-2026-10-15` preserves every vehicle's geometry and capacity, while rebuilding colours and cargo queues. Levels 1–5 have four actual colours, 6–10 have five, and subsequent levels alternate five/six. A colour occupies at most 40% of trucks and 45% of cargo capacity. Palettes are permuted across all six materials. Generator reports now count actual colours instead of the requested upper limit; configured evaluation rejects colour imbalances.

`tools/tune_variety.gd` selects against the previous campaign saved in `artifacts/campaign-before-variety.json` (the imported 8f0b912 campaign), then remeasures the complete evaluation including booster effects. Its nominal fail-rate increase is six percentage points, bounded at twelve points; it keeps the novice cap for the first ten levels and a stricter first-level welcome. Level 3 remains a free-slot tutorial. Offline reports and the shipping campaign are synchronized. Prices, wallet and saved progression are unchanged. All difficulty estimates are simulated, pending another human playtest.


### Compact parking and tap handling (2026-10-15)

Campaign revision `compact-2026-10-15` moves vehicle centers closer together while preserving every directed blocking relationship, cargo, colors, capacities, and solution certificates. Vehicle dimensions remain unchanged. The offline `tools/compact_campaign.gd` uses the preserved pre-compaction campaign and checks clearance for every accepted move. Runtime tests solve all 100 levels with three slots.

Input uses event coordinates in canvas space. During road movement, the most recently selected yard truck remains highlighted and starts when the road is free; level changes clear this pending choice. Hit testing follows the same visual pose as rendering.


### Short smooth truck routes (2026-10-16)

`truck_route.gd` connects oriented poses with tangent circular arcs and straight segments. It first checks a direct connection; when obstructed it searches optional forward-clearance and perimeter poses by travel length. Both sides are available. It checks the complete rotated vehicle footprint against yard and docked trucks, including intermediate animation poses. A small turn radius is a constrained-space fallback; normal connections prefer wider arcs. Routing is a finite candidate search, not a proof of the global continuous-space optimum.

Arrival follows one distance-parameterized tween with heading tangent to the route. The chosen path uses screen coordinates directly, avoiding the former edge projection and sideways motion. Departure backs out along the bay axis as necessary, then changes to forward travel toward the nearest reachable screen edge, easing speed to zero at the direction switch. Locked exits still use the contact-and-bounce feedback and existing puzzle rules. The previous perimeter controller remains an emergency fallback if no candidate can be found.

Validation includes the full campaign motion probe, actual native animation/capture, tap queue regression, and all three vehicle sizes at all five bays with occupied neighbours.

Final route validation: all 100 campaign levels passed the motion probe without intersections or completely invisible poses. Levels 9 and 83 were retested after adding a fine-search approach alignment for long trucks beside occupied bays; both now use smooth routes. All 15 vehicle-size/bay combinations passed arrival/departure tests. Swept oriented envelopes conservatively contain each interpolated body between route samples.

Worker idle performance: after 4.5 seconds without input or loading/road activity, runs right–left–right then jumps three times. Input, overlays, work and level changes cancel it. Reduced motion disables this performance.

## Ten-level playtest, 2026-10-17

Shipping campaign is the first ten levels from c3a0f1cc52436f704863cb50b4bf89fc476704f5, revision playtest10-c3a0f1c. Layouts, colours and queues are unchanged for evaluation of the new difficulty model. The previous 100-level campaign is backed up in bus-bloom/artifacts/campaign-before-test10.json. Runtime economy prices remain unchanged. A separate user://cargo_yard_playtest10_c3a0f1c.cfg keeps the old wallet/progress intact and restarts onboarding. Generator and offline economy changes are not imported in this bounded playtest. All ten levels pass the motion probe (119235 samples, zero intersections or invisible poses).
