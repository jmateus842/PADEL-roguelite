# Padel Roguelite progress

Log of ongoing work and decisions, so a new session can pick up where the last one stopped. Format: `rules/template-session.md`.

## Project status (as of 2026-10-19)

* **Current priority:** playtest 1 against the opponent (F5 opens the match now), then the volley protocol from Session 8. Run `run_tests.bat` after every change to the ball, player, rally or opponent. Run `run_tests.bat` after every change to the ball, player or rally.
* **Playcentric step:** 5. Playtest 1, first pass done on the practice court. Match build ready for the real pass.
* **Known blockers:** None.
* **Active known issues:**
    * Padel origin and Balatro release date in the goals doc came from memory and still need checking (from Session 1).
    * Sim tuning (glass and mesh restitution, ball bounce) is guessed and unchecked against real footage (from Session 2).
    * The "ball died" rule never fired in 60,000 random launches. It may be dead code (from Session 4).
    * **Ready to test: volley vs. bounce.** The opponent now lobs when you stand within 3.5 m of the net, and the match HUD counts your volleys, bounce hits and glass hits. Run the Session 8 protocol in the match (from Session 7, opponent in Session 10).
    * Match rules are simplified: the serve changes sides every point, serves are auto-aimed into the box (no service faults), and the score is a plain point count (from Session 10).
* **Technical debt:**
    * The `SHOTS` table lives in both `sim/wall_shots.py` and `scripts/shots.gd`. `tests/test_sim.py` now fails if they differ, so drift gets caught, but you still edit both (from Session 3).
    * `shot_planner.gd` (moved out of `rally.gd`, now shared by you, the opponent and the practice court) plans shots with its own light copy of the ball's flight (drag, gravity, net). Change the model's tuning and the planner drifts. The return and lob grid tests catch it (from Session 7, moved in Session 10).
    * The practice court and the match reuse the `lab_*` actions (Space, T, R, arrows). The match uses `lab_speed` for slow motion, so a second scene needs them now. Rename to shared names soon (from Session 7).
    * `tests/golden_random.json` is tracked but rewritten on every test run. Runs on different machines change the last digit of some floats, so git shows it as modified. Harmless (the Godot check allows 1e-9 m), but decide whether to gitignore it (from Session 9).

---

## 2026-10-19 (Session 10) – Basic opponent on the far half, real points [Opponent] [Prototype]

### Handoff

* **Result:** a new main scene, `scenes/match.tscn`. You play points against a basic opponent on the far half: serve, rally, score.
* **Why it matters:** this is the "plain padel vs. basic AI" build that playtest 1 called for. Standing at the net now costs something, because the opponent lobs you, so the parked volley question can finally get an answer.
* **Next recommended action:** reload the project, run `run_tests.bat`, press F5 and play 10 minutes. Then run the Session 8 volley protocol, reading the hit counts from the HUD.

### Accomplished

* `scripts/opponent.gd`: a brain that drives a player body. It waits `REACTION` (0.25 s) after your shot, steps a copy of the ball ahead, and picks the first spot where the ball is in its band and it gets there without a scramble. If none exists, it picks the spot with the least pressure, which often means waiting for the bounce or the glass. It swings the moment the ball is in reach, then walks back home, 2.5 m from its back glass.
* Misses: once per ball it rolls a whiff, 3% on an easy ball, up to 53% when it barely got there. Rushed shots also spray wider.
* Shot choice: a drive (15 m/s) to the side you're not on, ±0.8 m error. A lob when you stand within 3.5 m of the net.
* Knobs at the top of `opponent.gd`: `REACTION`, `RUN_SPEED` (5.0, you run 5.5), `DRIVE_SPEED`, `AIM_ERROR`, `LOB_WHEN`, `MISS_BASE`, `MISS_PRESSURE`, `COMFORT`.
* `scripts/match_rules.gd`: serve, receiver rules, scoring. The ball model already judges from the hitter's side, so a result starting with "winner" goes to the hitter and anything else goes to the other side. Serves come from the right on even points and the left on odd ones, diagonally into the box (lands 5 m past the net).
* `scripts/match.gd` + `scenes/match.tscn`: HUD with score, rally length, last point, your hits by type (volley, after the bounce, off the glass), average contact height, and opponent lobs and whiffs. You hold still until the serve, and swing serves when it's yours. `-- --demo` puts a second opponent on your side.
* `scripts/shot_planner.gd`: the return planner moved out of `rally.gd`, plus a new `plan_lob()` (52°, lands 2 m from the back wall). The serve has `plan()` take depth and pace.
* `scripts/player.gd`: `far` flag for the far half, `drive()` in court axes, `top_speed` and `color` vars. Your controls work the same.
* `scripts/ball_model.gd`: `clone()` copies the ball's state for the opponent's look-ahead. `step()` is untouched, and the sim checks still match.
* `project.godot`: main scene is the match. The practice court and the ball lab still open from the editor.

#### Decisions
* One body script for both sides, and the opponent works on either side. Tests and demo mode put one on yours.
* The opponent plays the same ball model and planner as you, so it can't cheat on physics.
* Server alternates every point for now, with no service faults and a plain point count. Real padel scoring waits until the rally feels right.

### Verified

* Full suite on Godot 4.5.stable (Linux, cloud): Python all good, Godot all good (4,243 checks, up from 3,728). New suite 8:
    * The far body stays on its half.
    * 216 lobs from a grid over the half land in and stay above 1.9 m wherever a net player stands.
    * The opponent lobs only when you're close to the net and always aims away from you.
    * Points go to the right side: a serve you don't return, your ball out, their ball in, your swing out of reach.
    * Both serves land in the correct diagonal box.
    * The opponent returns 77% of drives from a grid over your half to every aim. The test needs at least 60% and less than 100%.
    * Opponent vs. opponent, 150 points: every point ends, nobody leaves their half, the same seeds play the same match. Median rally 4 hits, longest 25.
* Planted six bugs one at a time and restored each: lob at 30° (33 failures), scoring swapped (5), aims at you (5), far body can cross the net (3), 1.5 s reaction (3), serve never changes side (2). Clean run passes after restoring.
* Opened all three scenes headless with no errors. Rendered the match in demo mode under Xvfb: serve, rallies and scoring show, HUD hit counts update, opponent drawn in orange.
* Not played by hand yet. Not run on Windows yet. Test run went from about 3 s to about 16 s, mostly the 150 point match.

### Deferred / Follow-up

1. Reload the project in the editor (files changed from outside), run `run_tests.bat`, press F5 and play.
2. Volley protocol from Session 8, in the match.
3. Tune from the playtest: opponent knobs in `opponent.gd`, `SERVE_SPEED` and `SERVE_DEPTH` in `match_rules.gd`.
4. Later: real padel scoring, service faults, a lob for you.

### Files Touched

* `scripts/opponent.gd`, `scripts/match_rules.gd`, `scripts/match.gd`, `scripts/shot_planner.gd` (plus `.uid` files) — **New** — opponent brain, match rules, match scene script, shared shot planner
* `scenes/match.tscn` — **New** — match scene
* `scripts/player.gd` — **Edit** — far side, `drive()`, speed and color vars
* `scripts/rally.gd` — **Edit** — planner moved to `shot_planner.gd`
* `scripts/ball_model.gd` — **Edit** — `clone()`
* `project.godot` — **Edit** — main scene is the match
* `tests/godot_tests.gd` — **Edit** — suite 8, suite 7 uses the planner
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority moved to playtest 1 in the match. The volley known issue is now ready to test. Added the simplified match rules as a known issue. Updated the planner and `lab_*` items in technical debt.

---

## 2026-10-19 (Session 9) – Project under git, old shot check removed [Tooling]

### Handoff

* **Result:** the folder is a git repo on `main` with two commits. `scripts/check_shots.gd` is gone.
* **Why it matters:** the opponent is the next big change, and now there's a clean point to roll back to.
* **Next recommended action:** build the basic opponent on the far half.

### Accomplished

* `git init -b main`. Author set in the repo config (Juan Diego Mateus Garibaldi). `core.autocrlf` is false so Windows line endings stay as they are.
* First commit: everything from Sessions 1 to 8. `__pycache__/` added to `.gitignore` and left out.
* Second commit: deleted `scripts/check_shots.gd` and its `.uid`. Nothing else referenced it. `tests/godot_tests.gd` suite 1 covers the same check.

### Verified

* Python half of the tests passes after the delete. Godot half not run (no Godot on the machine that made the change). Run `run_tests.bat` on Windows to confirm.

### Deferred / Follow-up

1. Run `run_tests.bat` on Windows.
2. Basic opponent: far-half player, predicts the ball with `run_to_end()`, lobs when you stand near the net, simple point scoring.
3. Decide on gitignoring `tests/golden_random.json`.

### Files Touched

* `.gitignore` — **Edit** — ignore `__pycache__/`
* `scripts/check_shots.gd`, `scripts/check_shots.gd.uid` — **Delete** — replaced by the test suite
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Removed the `check_shots.gd` item from technical debt. Added the `golden_random.json` churn. Priority moves to the basic opponent.

---

## 2026-10-19 (Session 8) – First practice session feels good, volley question parked [Playtest]

### Handoff

* **Result:** JD played the practice court for a while. It feels good to play. He couldn't tell yet whether volleys and glass balls feel different, so the question is parked here with a ready protocol.
* **Why it matters:** the "walls feel like a tool" goal depends on the glass ball being worth waiting for. Today nothing makes the choice matter: the return is auto-aimed the same way either way, and there's no opponent to punish standing at the net.
* **Next recommended action:** decide the next build step. A basic opponent is the natural one, since it gives court position and the volley choice real consequences.

### Accomplished

* Playtest 1, first pass, by JD on Windows. Movement, swing and returns feel good. No bugs reported.
* No clear read on volley vs. bounce timing.

#### Parked: volley vs. bounce

**The risk.** Hittable time per feed, standing in the right spot (Session 7): drive 0.50 s volley / 0.46 s after the bounce, double wall 0.47 / 0.48, cross to side glass 0.52 / 0.44. Only lob, corner kill and contrapared favor the bounce. If volleying is as easy and as rewarding, players camp at the net and the walls become decoration ("tennis with decorative walls" in the goals doc).

**Why it didn't show up.** A volley and a glass ball end the same way today. Same auto-aimed return, no opponent reply, no cost to standing at the net.

**Protocol when we come back to it (about 10 minutes):**
1. Repeat `drive_to_back_glass` (Left/Right). 5 tries volleying from about 2 m off the net, count returns.
2. Same feed, 5 tries from the back letting it come off the glass, count returns. T for slow motion if needed.
3. Repeat 1 and 2 with `double_wall`.
4. Mix mode (R), 5 minutes at normal speed, notice where you stand by default.
5. After each part write: returns out of 5, whether you knew when to swing or mashed the button, whether you read height from the shadow or the gauge.

**How to read it:**
* Volleys come back more and free play pulls you to the net: the risk is real. Fix before the opponent.
* Glass balls come back as often and you sometimes wait for them unprompted: the core holds, move on.
* You mash the button on glass balls: a readability problem (0.3 m band, shadow), not a volley problem.

**Fixes on the table if the risk is real:** smaller reach or a weaker, less accurate return on volleys. A stronger return off the glass. Optional instrumentation first: HUD counts of volleys / off the bounce / off the glass, contact height per hit, and a log file per session.

**Triggers to reopen:** the opponent lands, a playtester camps at the net, or playtest 2 players never mention the walls.

### Verified

* Played by hand on Windows by JD. Not measured: hit types and contact heights are not recorded yet.

### Deferred / Follow-up

1. Choose the next step (basic opponent likely).
2. Reopen the volley question on any trigger above.
3. `git init` and a first commit.

### Files Touched

* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority moved from playtest 1 to choosing the next step. The volley known issue now points to this entry.

---

## 2026-10-19 (Session 7) – Player returns fed balls on a practice court [Player] [Prototype]

### Handoff

* **Result:** a new main scene, `scenes/practice.tscn`. A feeder on the far half sends the sim's shots, and you move with WASD or the stick and return them with J or A.
* **Why it matters:** this is everything playtest 1 needs. Plain padel, walls in play, no powerups. The hitting band and reach are tunable constants, and the HUD counts returns, misses and good leaves.
* **Next recommended action:** press F5 and play 10 minutes in mix mode. Then write down if you aim for the glass, whether low balls off the glass feel fair, and whether you volley everything.

### Accomplished

* `scripts/player.gd`: moves at up to 5.5 m/s (45 m/s² acceleration), stays on the near half (0.3 m from walls, 0.4 m from the net). Reach 1.1 m, band 0.3 to 1.9 m, swing live 0.18 s then 0.25 s cooldown. The reach ring turns green when the ball is playable right now.
* `scripts/rally.gd`: feeds, receiver rules, return planner and tally. The ball counts as playable once the feed has crossed to our side and is still alive, so volleys are legal. One hit per swing.
* Feeds: the model still only plays near to far. A feed is the sim shot played with `flipped = true` in `ball.gd`, drawn turned around (x to 10 - x, y to 20 - y). The court is symmetric, so every rule holds without touching the tested model. Feeds = the 11 sim shots minus the two smashes that leave the court.
* Return shot: aimed at 16.5 m deep, stick left/right at contact moves the aim ±4 m. The planner takes the lowest angle that clears the net by 0.15 m, raises it to land on the target, and drops pace (down to 7 m/s) when that would fly long or wide. It runs a light copy of the flight at 10 ms steps, worst case 3.5 ms per hit.
* `scripts/practice.gd` + `scenes/practice.tscn`: HUD with tally and return rate, a height gauge with the green band, a feeder marker. Controls: Space next feed, Left/Right repeat one feed, R back to mix, T slow motion (1x, 0.5x, 0.25x). `-- --feed=lob` starts on one feed.
* `scripts/ball.gd`: `flipped`, `world()`, and a `hit_check` callable run after each model step. `play()` takes `from_far`. Lab behavior unchanged.
* `scripts/ball_model.gd`: added `crossed()`. Nothing else changed, the sim checks still match.
* `scripts/controls.gd`: `swing` on J and A (cross).
* `project.godot`: main scene is now the practice court. The ball lab still runs with F6 on `scenes/ball_lab.tscn`.
* `tests/godot_tests.gd`: suite 6 (player) and suite 7 (rally). Suite 5 now also checks every gamepad button triggers one action only.

#### Decisions
* Feeds reuse the model mirrored instead of teaching it a second direction. The opponent AI can hit the same way later.
* Hit rule reads the ball's true position (shadow) plus height, not the drawn ball.
* The return is auto-aimed for now: one swing button, stick picks left, center or right. Shot types (drive, lob, smash) wait for playtest 1.

#### Findings
* Hittable time per feed, standing in the right spot: volley window and after-bounce window are about the same for most feeds (drive 0.50 s volley / 0.46 s after bounce, double wall 0.47 / 0.48). Only lob, corner kill and contrapared favor the bounce. If players volley everything, that's the "tennis with decorative walls" risk from the goals doc. Possible fixes: a smaller reach for volleys, or a later rule like the volley needing a set position.

### Verified

* Full suite on Godot 4.5.stable (Linux, cloud): Python all good, Godot all good (3,728 checks, up from 2,718).
* Suite 7 plays every feed through `ball.gd` at 60 fps with the player standing at the first hittable spot and swinging on time, both as a volley and after the bounce. All 9 feeds come back in. 900 returns from a grid over the near half at three heights and three aims all land in.
* Planted six bugs one at a time and restored each: receiver plays before the net (9 failures), player can cross the net (3), planner aims into the net (102), feed not mirrored in x (9), tally swapped (3), reach 5x too big (2). Clean run passes after restoring.
* Rendered the scene under Xvfb with a scripted player: feed comes in, ring turns green, the hit sends the return off with its trail, feeder marker and height gauge show.
* Not played by hand yet. Not run on Windows yet.
* `project.godot` was rewritten by the editor during this session, so only the main scene and description lines were changed in place.

### Deferred / Follow-up

1. Reload the project, run `run_tests.bat`, then press F5 and play playtest 1.
2. Tune from the playtest: `BAND_LOW`, `REACH`, `SPEED` in `player.gd`, `RETURN_SPEED` and `TARGET_DEPTH` in `rally.gd`.
3. Decide on the volley question after playtest 1.
4. `git init` and a first commit before the next big change.

### Files Touched

* `scripts/player.gd`, `scripts/rally.gd`, `scripts/practice.gd` (plus `.uid` files) — **New** — player, rally rules and return planner, practice court
* `scenes/practice.tscn` — **New** — practice court scene
* `scripts/ball.gd` — **Edit** — mirrored feeds, hit check hook
* `scripts/ball_model.gd` — **Edit** — `crossed()`
* `scripts/controls.gd` — **Edit** — `swing` action
* `project.godot` — **Edit** — main scene is the practice court
* `tests/godot_tests.gd` — **Edit** — suites 6 and 7, button check across all actions
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority moved to playtest 1. Added the volley finding as a known issue. Added the planner's flight copy and the shared `lab_*` actions as technical debt.

---

## 2026-10-19 (Session 6) – WASD moves the player, lab keys moved to T and R [Input]

### Handoff

* **Result:** WASD is bound to the four movement actions next to the left stick. The lab's speed key moved from S to T, and auto replay moved from A to R.
* **Why it matters:** the player can now move on keyboard or pad from its first build, and a test fails if any key ends up on two actions.
* **Next recommended action:** build the player on the near half. Read `Controls.move_vector()` for movement and use a face button for the swing.

### Accomplished

* `scripts/controls.gd`: `move_left/right/up/down` get A, D, W, S. `lab_speed` is T, `lab_auto` is R. Header comment now says the lab stays off WASD too.
* `scripts/ball_lab.gd`: header table and keyboard hint line show T speed and R auto.
* `tests/godot_tests.gd` suite 5: every key in the table triggers exactly one action across the whole table (lab and movement), and WASD is bound to the right movement action.

#### Decisions
* T (tempo) and R (repeat) sit above WASD and stay clear of keys the player is likely to take next (Space, J/K/L, Shift).
* Arrow keys stay on the lab's shot picker for now. They aren't movement keys.

### Verified

* Full suite on Godot 4.5.stable (Linux, cloud): Python all good, Godot all good (2,718 checks, up from 2,704).
* Planted the old clash (`lab_auto` back on A): 2 failures naming A on both `lab_auto` and `move_left`. Clean run passes after restoring.
* Not run on Windows yet. Reload the project in the editor before pressing F5, since `controls.gd` changed from outside.

### Deferred / Follow-up

1. Run `run_tests.bat` on Windows and press T and R in the lab.
2. Player on the near half: movement from `Controls.move_vector()`, hitting zone, 0.3 to 1.9 m band as tunable constants, one face button to swing.

### Files Touched

* `scripts/controls.gd` — **Edit** — WASD movement, lab keys to T and R
* `scripts/ball_lab.gd` — **Edit** — header and hint line
* `tests/godot_tests.gd` — **Edit** — key clash check across all actions, WASD check
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Removed the S/A versus WASD clash from technical debt. Priority stays on the first player.

---

## 2026-10-19 (Session 5) – Ball lab works with a gamepad, input lives in one table [Input] [Godot]

### Handoff

* **Result:** every input now goes through named actions in `scripts/controls.gd` (autoload `Controls`), with keyboard and gamepad bindings side by side. The ball lab runs fully on a controller, and left stick movement actions are ready for the player.
* **Why it matters:** the player can read `Controls.move_vector()` and named actions from day one, so controller support doesn't need retrofitting later. The test suite fails if a binding goes missing or one button triggers two lab actions.
* **Next recommended action:** plug in a controller, press F5, and check the D-pad, LB/RB, Start, Back and the stick readout. Then build the player on the face buttons and left stick.

### Accomplished

* `scripts/controls.gd`: one `ACTIONS` table, registered at startup. Gamepad bindings use device -1, so any pad works, not just the first one. `move_vector()` gives the left stick with a 0.25 circular deadzone. `using_gamepad` follows whatever you touched last.
* Lab on a gamepad: D-pad left/right or LB/RB change the shot, Start replays, D-pad up changes speed, D-pad down toggles auto, Back runs check all. Keys 1-9 stay keyboard only.
* The lab HUD shows the connected controller's name, live left stick values, and the hint line for the device you're using.
* `tests/godot_tests.gd` suite 5 (72 checks): every action exists with exactly its table bindings, registering twice doesn't stack them, each key and button triggers exactly one lab action on pad 0 and pad 3, the lab stays off the face buttons, and the stick respects the deadzone.

#### Decisions
* Bindings live in code, not in project.godot, so tests can read them and the table is the single place to change them.
* Lab controls stay off the face buttons and the left stick. Those are reserved for the player, so the lab and the player can share a scene later.
* Movement has no keyboard keys yet, because WASD clashes with the lab's S and A. Pick them with the player.

### Verified

* Full suite on Godot 4.5.stable (Linux, cloud): Python all good, Godot all good (2,704 checks).
* Planted two bugs and restored each: lab_auto bound to the same D-pad button as lab_speed (4 failures), bindings tied to pad 0 only (pad 3 failures). Clean run passes after restoring.
* Loaded the real lab scene headless and fed it fake controller presses: D-pad right and RB moved the shot from 1 to 3, D-pad up changed the speed, Back gave "11/11 match", and pressing a key switched the hint line back to the keyboard.
* Not tried with a physical controller. Not run on Windows yet.
* First Windows run failed: "Identifier Controls not declared" plus "Unrecognized UID". Cause: the editor was open while `project.godot` changed, so it never loaded the new autoload. Fix: the lab now preloads `controls.gd` and registers the bindings itself if the autoload is missing. Checked headless with the autoload and without it.
* JD ran the lab on Windows with a real controller after reloading the project: it works.
* JD ran `run_tests.bat` on Windows (Godot 4.5 console exe set in `GODOT`): ALL TESTS PASSED, 2,704 Godot checks plus the Python half.
* `run_tests.bat` now saves its output to `tests/last_run.txt` (gitignored) and waits for a key at the end, so a double-click doesn't close the window before you can read it. `--no-pause` skips the wait.
* Lesson: close or reload the Godot project (Project → Reload Current Project) before files change on disk from outside the editor. Saving from a stale editor can overwrite `project.godot`.

### Deferred / Follow-up

1. Try a real controller in the lab (Xbox, and a PlayStation pad if you have one).
2. Player: face buttons for shots, left stick to move, keyboard keys picked to avoid the lab's S and A.
3. Optional later: a short rumble on glass hits, if playtests say the walls need more feel.

### Files Touched

* `scripts/controls.gd`, `scripts/controls.gd.uid` — **New** — input table, registration, stick helper, device tracking
* `project.godot` — **Edit** — `Controls` autoload
* `scripts/ball_lab.gd` — **Edit** — named actions instead of raw keys, controller info and hints in the HUD
* `tests/godot_tests.gd` — **Edit** — suite 5, controls
* `run_tests.bat` — **Edit** — log to `tests/last_run.txt`, pause at the end
* `.gitignore` — **Edit** — ignore `tests/last_run.txt`
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Tests confirmed on Windows, so `check_shots.gd` can go now.
* Added the S/A versus WASD clash as technical debt. The real controller check passed the same session, so it isn't a known issue.

---

## 2026-10-19 (Session 4) – Ball confirmed on Windows and guarded by an automated test suite [Testing] [Godot]

### Handoff

* **Result:** the ball lab passes 11/11 on JD's Windows machine (Godot 4.5), and `run_tests.bat` now checks the ball model against the Python sim on 414 shots, plus rules and frame-rate playback.
* **Why it matters:** the player, AI and powerups all build on the ball model. Any change that breaks it now fails a test, and the random shots cover what the player will actually hit, not just the 11 tuned shots.
* **Next recommended action:** run `run_tests.bat` once on Windows, then add one player on the near half who can return the ball.

### Accomplished

* Opened the project on Windows. Godot 4.5.stable, RTX 4060 laptop. Ball lab runs, C shows 11/11, shots look right by eye.
* `sim/wall_shots.py`: plotting moved into `main()` behind `if __name__ == "__main__"`, plus a `shot_row()` helper. Importing the sim now runs nothing. Output is byte-for-byte the same.
* `tests/test_sim.py` (Python half):
    * `SHOTS` in `scripts/shots.gd` matches `sim/wall_shots.py` (reads the GDScript dict as a Python literal).
    * `sim/shots/summary.md` is current with the sim.
    * Writes `tests/golden_random.json`: 400 seeded random launches (seed 1969, max 60 per outcome) plus 3 hand-found edge cases (came back over the net, net from behind, timeout). 13 different outcomes covered.
* `tests/godot_tests.gd` (Godot half, about 2,600 checks in under 3 s):
    1. Named shots match `summary.md`.
    2. Random shots match the Python sim: same row, same step count, same event count, final position within 1e-9 m (actual gap about 1e-14 m).
    3. Rules always hold: never under the floor, inside the court until the last step, fixed DT, events in order, no energy gain without kick, deterministic.
    4. `ball.gd` playback at 30, 60, 144 and 240 fps plus random stutter, at 1x, 0.25x and 0.1x: ball clock stays within one DT of game time, path equals `run_to_end()`, `point_over` fires once.
* `run_tests.bat`: runs both halves. Uses the `GODOT` environment variable for the console exe, falls back to `godot` on PATH.

#### Findings
* The model runs one step past `MAX_T` on timeout because `t` lands a hair under 5.0 after 2,500 additions of DT. Python does the same, so it isn't a mismatch.
* "ball died" never fired in a 60,000 launch search. Check whether that branch can happen before the player starts relying on it.

### Verified

* JD ran the ball lab on Windows: C shows 11/11.
* Full suite on Godot 4.5.stable (Linux, same build as JD's): Python all good, Godot all good (2,632 checks).
* Planted four bugs one at a time and restored each: glass bounce 0.65 to 0.66 (406 failures), lob speed changed in `shots.gd` only (Python table check and named shots fail), one step per frame instead of substeps (40 playback failures), floor bounce not lifting z (660 failures). Clean run passes after restoring.
* `run_tests.bat` not run on Windows yet.

### Deferred / Follow-up

1. Set `GODOT` to the console exe and run `run_tests.bat` on Windows.
2. Player on the near half: movement, a hitting zone and the 0.3 to 1.9 m height band.
3. Playtest 1 prep: feed balls from the far side.
4. Look into the "ball died" branch.

### Files Touched

* `sim/wall_shots.py` — **Edit** — importable, `shot_row()` helper, same output
* `tests/test_sim.py` — **New** — Python half of the tests
* `tests/golden_random.json` — **New** — generated, rewritten on every test run
* `tests/godot_tests.gd` — **New** — Godot half of the tests
* `run_tests.bat` — **New** — one command for both halves
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority stays on the first player, with `run_tests.bat` after every ball change. Added the "ball died" question as a known issue. The `SHOTS` duplication is now guarded by a test. Added `check_shots.gd` cleanup as technical debt.

---

## 2026-10-19 (Session 3) – Godot ball lab matches the sim on all 11 shots [Prototype] [Godot]

### Handoff

* **Result:** the Godot project exists, and a ball lab scene plays the sim's 11 shots with the same ball model. Every result, hittable time and event matches `sim/shots/summary.md`.
* **Why it matters:** the ball model is proven in Godot before anything gets built on top of it. The sim and the game now share one set of numbers, and a headless check catches drift.
* **Next recommended action:** add one player the user moves on the near half who can hit the ball back, then playtest 1 with a wall-only practice partner (ball fed from the far side) to test the 0.3 m hitting band.

### Accomplished

* Godot 4.4 project at the repo root, GL Compatibility renderer, 1280x720, main scene `res://scenes/ball_lab.tscn`.
* `scripts/ball_model.gd`: line-for-line port of `simulate()`, `playable_windows()` and `describe()` from `sim/wall_shots.py`. Same constants, plain 64-bit floats (Godot's `Vector3` is 32-bit).
* `scripts/ball.gd`: steps the model at the sim's fixed `DT = 0.002` with an accumulator inside `_physics_process` (about 8 substeps per 60 Hz tick). Draws the shadow at the true `(x, y)`, the ball lifted by `z`, a height-colored trail and event markers.
* `scripts/court.gd`: grey box top-down court. Glass thick and blue, mesh thin and grey, same split as the sim.
* `scripts/ball_lab.gd`: shot picker, side view panel that mirrors the plots, live info and a "same as the sim" line. Keys: Left/Right, 1-9, Space, S (1x/0.25x/0.1x), A (auto replay), C (check all).
* `scripts/shots.gd`: the sim's `SHOTS` table, plus a loader for the expected rows in `sim/shots/summary.md`.
* `scripts/check_shots.gd`: headless check, exits 1 if any shot differs from the sim.
* `sim/.gdignore` keeps Godot from importing the sim's plots.

#### Decisions
* The ball model lives in a plain `RefCounted` script, separate from the node that draws it. Players, AI and powerups talk to the model, so the check keeps working as the game grows.
* Fixed `DT` substepping replaces "one step per frame". Game time and sim time stay identical.
* `SHOTS` exists twice (Python and `shots.gd`). Change both together, then rerun the check.

### Verified

* `godot --headless --path . --script res://scripts/check_shots.gd` on Godot 4.4.1 (Linux, cloud): 11/11 shots match the sim row for row.
* Rendered the scene under Xvfb and checked frames by eye: drive_to_back_glass and double_wall show the same bounce points and wall heights as their plots.
* Not run yet on JD's Windows machine.

### Deferred / Follow-up

1. Open the project in Godot on Windows, press F5, then C, and confirm 11/11.
2. Player on the near half: movement, a hitting zone and the 0.3 to 1.9 m height band. Shot choice can be a key per shot type for now.
3. Playtest 1 prep: feed balls from the far side (reverse the sim's shots) so the player returns wall balls.
4. Still open: glass/mesh restitution against real footage, and the Session 1 fact checks in the goals doc.

### Files Touched

* `project.godot` — **New** — Godot 4.4 project
* `.gitignore` — **New** — ignores `.godot/`
* `scenes/ball_lab.tscn` — **New** — ball lab scene
* `scripts/ball_model.gd`, `scripts/ball.gd`, `scripts/court.gd`, `scripts/ball_lab.gd`, `scripts/shots.gd`, `scripts/check_shots.gd` (plus `.uid` files) — **New**
* `sim/.gdignore` — **New** — keep plots out of the Godot import
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority moved to the first player and playtest 1 prep. Playcentric step stays 4, with the ball part done. Added the duplicated `SHOTS` table as technical debt.

---

## 2026-10-19 (Session 2) – Wall shots cataloged and simulated, por 4 needs a powerup [Design] [Prototype]

### Handoff

* **Result:** wall shot brainstorm written and a Python sim of the planned ball model plots 11 shots with the defender's hittable time.
* **Why it matters:** the sim gives deterministic numbers for wall play before Godot. Pace against arc is the core decision, the defender's window is 0.4 to 0.8 s, and por 4 can't exist without spin, so it belongs in the powerup pool.
* **Next recommended action:** create the Godot project and build the ball alone with the sim's constants. Fire the same launch values and compare against `sim/shots/*.png`.

### Accomplished

* `design/wall-shots.md`: rules that shape wall play, enclosure model, 11-shot catalog, sim findings and design takeaways.
* `sim/wall_shots.py`: same model as the Godot plan (x, y plus fake z, quadratic drag, floor and wall reflection, glass vs mesh, padel rule checks). One PNG per shot (top view plus side view) and `sim/shots/summary.md`.
* Launch values for each shot came out of a parameter sweep, so every shot lands as intended.
* Added `kick` (extra bounce on the first floor hit) as a stand-in for topspin to test smashes.

#### Decisions
* Paper coin test for physics replaced by the sim. A paper test of decisions (turn-based shot and position picks) stays optional.
* Por 4 and charged smash go to the powerup pool, not the base shot set.
* Base game stays spin-free. Spin-like effects (kick, curve) are powerup territory.

#### Findings against the experience goals
* "Walls feel like a tool": holds in the sim. Glass is lively, mesh kills the ball, overhitting into their glass is a fault.
* "Every rally can outsmart with the walls": side and double wall shots don't add time, they move the defender. Needs a readable direction change off the glass (shadow).
* Risk: flat drives come off the glass at 0.2 to 0.6 m, under the 0.3 m hitting band. Playtest 1 decides if the game needs a wider band or a small lift off the glass.

### Verified

* Ran `python3 sim/wall_shots.py` on this machine. 11 plots plus summary generated, results match the cloud run.
* Checked the double_wall, contrapared and smash_por_4_kick plots by eye: events, windows and rule outcomes are correct.
* Court specs checked against Wikipedia (Padel) and padelbrowser.com. The side glass 2 m / 2 m split is the common build, not a rule.

### Deferred / Follow-up

1. Create the Godot project and port the ball model with the sim's constants.
2. Check glass/mesh restitution and the ball drop spec against real footage or FIP rules.
3. Optional: paper test of decisions (shot type and aim vs. defender position) using the sim plots as reference.
4. Still open from Session 1: verify padel origin and Balatro release date in the goals doc.

### Files Touched

* `design/wall-shots.md` — **New** — brainstorm and sim findings
* `sim/wall_shots.py` — **New** — wall shot simulator
* `sim/shots/` — **New** — generated plots and summary (regenerate any time)
* `progress.md` — **Edit** — this entry and status block

### Status Update

* Priority moved to the Godot ball prototype. Playcentric step moved to 4. Added the unchecked sim tuning as a known issue.

---

## 2026-10-19 (Session 1) – Concept, methodology and experience goals defined [Design] [Planning]

### Handoff

* **Result:** the concept, core technical decisions, methodology and player experience goals are set. No code and no Godot project yet.
* **Why it matters:** the goals give every later prototype and playtest something to measure against, and the "prove plain padel first" rule keeps powerups from hiding a weak core.
* **Next recommended action:** brainstorm mechanics and paper-prototype wall shots, then create the Godot project and build the ball alone.

### Accomplished

* Experience goals doc written as a Claude Doc: [Padel Roguelite: Player Experience Goals](https://claude.ai/code/artifact/dbdbad5a-a465-4f72-a606-6ebc0d0a1415).

#### Concept
- 2D padel game in **Godot**.
- **Powerup** version of padel with a **roguelite** structure.
- Pitch: the glass walls stay in play, and that's what separates padel from every tennis game. If the walls feel good, there's a game.

#### Technical decisions
- **Camera:** top-down with fake height. The ball has `x, y` on the court plus a simulated `z`. Draw the ball offset by `z` and a shadow at the real position.
- **Ball:** plain `Node2D` with its own velocity, gravity on `z` and reflection rules for floor and walls. **No `RigidBody2D`** (Godot physics fights bounces, spin and rebounds).
- **Mode:** start **1v1**. 2v2 means teammate AI plus two opponents, the biggest scope trap. 1v1 also fits "your build vs. their build".

#### Methodology: playcentric design (Fullerton, *Game Design Workshop*)
1. Set player experience goals.
2. Brainstorm mechanics.
3. Physical prototype (paper court, coin for the ball).
4. Digital prototype with placeholder shapes.
5. Playtest.
6. Evaluate and revise, back to 5 until the core hits the goals.
7. Design document (only what's proven).
8. Production (AI, modes, art, sound).
9. QA and polish.

Related terms: iterative design, rapid prototyping, greyboxing, vertical slice. Useful lenses: MDA (Hunicke, LeBlanc, Zubek 2004) and game feel / juice (Swink, *Game Feel*).

#### Roguelite structure (proposal)
- **A run is a tournament.** Each match is a floor. Lose a match and the run ends.
- **Between matches,** draft 1 powerup out of 2 or 3.
- **Opponents** get harder and stranger (wall specialist, smash-heavy, boss with a gimmick).
- **Meta progression:** unlock powerups, characters or courts between runs.
- **Run length:** 5 to 7 matches, short sets, about 30 minutes per run.

Powerup categories: ball (splits on wall hit, speeds up per bounce, curves), walls (extra spin on your glass, opponent's rebounds slower), racket/player (bigger sweet spot, charged smash, dash), rule bending (wall-won point counts double). Synergies are the goal: combos that feel broken in a fun way.

#### Experience goals (step 1, done)
- **Core:** every run gives at least one rally where the player outsmarts the opponent with the walls, and at least one moment where the build feels absurdly powerful.
- **Supporting:** walls feel like a tool, not a hazard · every draft is a real decision (Balatro as reference) · a run is short enough to restart without hesitation.
- **Must not feel like:** chaos hiding a weak core · tennis with decorative walls · random losses · an unreadable ball once powerups stack (every ball effect needs a visual signal, and the shadow always shows the true position).

#### Playtest plan
1. Plain padel vs. basic AI, **zero powerups**. Signal: players aim for the glass on purpose by the end of a session.
2. Around 5 powerups + a 3 match run. Signal: players hesitate in the draft and talk about their build afterward.
3. Full loop. Signals: players restart without being prompted, and loss-of-ball moments don't cluster around specific powerup combos.

#### Risks
- Powerups can hide a weak core. Prototype plain padel first.
- Roguelites eat content: 30 to 50 powerups for varied runs, plus balancing.
- AI has to handle weird ball behavior.

### Verified

* Not run (design-only session, nothing to test).

### Deferred / Follow-up

1. Steps 2 and 3: brainstorm mechanics and do a paper prototype of wall shots.
2. Create the Godot project in this folder.
3. Digital prototype of the ball alone: fake `z`, shadow, floor bounce, wall reflection. Grey boxes, no score, no menus.
4. Verify padel origin (Enrique Corcuera, Acapulco, 1969) and Balatro's release date (February 2024) before handing the goals doc to a professor.

### Files Touched

* `progress.md` — **New** — first entry
* `rules/` — **New** — session rules adapted from another project

### Status Update

* Status block created. Priority set to brainstorm, paper prototype and ball prototype.
