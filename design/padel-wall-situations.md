# Padel wall situations: reference for the wall decision mechanic

Purpose: reference data for designing how the player chooses to play the ball off the walls ("take it now" vs. "let it come off the glass"). Not a spec. Nothing here is built.

## Trust and status

* Source: a text written by a friend of JD, from how padel is coached and how commentators break down points. Written from the player's point of view. Not checked against footage or the rules. Treat numbers (heights, distances, speeds) as rough.
* Court dimensions in the Court section match `scripts/ball_model.gd`. The wall heights, the glass/mesh split along the side wall and the rebound numbers below are from the source only and are not modeled or verified.
* The base game has no spin (`design/wall-shots.md`: spin effects are powerups, `kick` fakes topspin on the first bounce only). Cases that need spin are marked `needs_spin`.
* Related: `design/glass-panels.md` (shot buttons, contact quality, glass panels), `design/wall-shots.md` (named wall shots), `sim/wall_shots.py`.

## Court (for reading the cases)

* 20 m long by 10 m wide. Net 0.88 m high at y = 10. Service line 6.95 m from the net, so about 3 m from the back glass.
* Source claims: back glass 4 m high; side glass covers only the last 4 m at each end; closer to the net the side wall is metal mesh. Unchecked.
* Model: `GLASS_E` 0.65, `MESH_E` 0.25, `FLOOR_E` 0.74, `WALL_GRIP` 0.9, `FLOOR_GRIP` 0.85, `REACH_LOW` 0.3 m, `REACH_HIGH` 1.9 m.
* "Back" means near your own back glass. "Net" means near the net. "You" is the player on the near half.

## Rules that matter for the decision

* A ball that hits the glass **before** bouncing on the receiving side is **out**. So a ball heading for your glass without a bounce is a point for you if you let it go. Volleying it gives the point back.
* A ball must bounce on the receiving side before it touches the glass or mesh. After the bounce, glass is live and the ball stays in play.
* Hitting the mesh after the bounce is a fault in the serve; in a rally the mesh rebound is dead or random.
* Serve: underhand, at or below the waist, must bounce in the diagonal box. After that bounce it may hit the glass and stay in play. The receiver cannot volley it.
* Contrapared: hitting your own back or side glass to send the ball over the net is legal.

## Decision factors (what makes "wait for the wall" right or wrong)

1. Ball height if taken now, relative to the player's reach band.
2. Time the glass buys (a fast ball comes off slower, so waiting gives time).
3. Position: at the net (waiting gives up the net) or at the back (waiting costs nothing).
4. Spin (`needs_spin`): topspin comes off faster and further, backspin dies at the glass.
5. Whether the rebound will leave the court or cross the net on its own.
6. Whether the rebound is predictable (single glass: yes; double wall, corner joint, mesh: no).

## Physics rules of thumb (source, unverified)

* Every glass hit removes pace. The ball leaves the glass at about the height it arrived.
* Flat and hard: comes off far, low to medium height. Soft and high: comes off short, slow, easy.
* Topspin (`needs_spin`): skids on the floor, rises off the glass, leaves faster and further.
* Backspin or slice (`needs_spin`): checks on the floor, drops off the glass, dies low against it.
* Side glass sends the ball toward the middle. Slice makes it hug the wall.
* Double wall: slower, but the exit angle is hard to predict.
* Mesh and corner joints: the ball dies or leaves at a random angle.

## Cases

Each case: trigger, where players stand, the decision, what the ball does, how the player moves, the shot played, what goes wrong, and whether the game can show it today. `game` values: `possible` (works with the current ball model), `needs_spin`, `needs_feature` (names it), `skip`.

### C1. Deep lob over you at the net

* trigger: opponent at the back hits a high, slow lob that clears you and lands 1 to 2 m from your back glass.
* positions: you and partner at the net (you right, about 2 m back). Opponents deep, moving forward once the lob is over you.
* decision: too high and too far back for a smash or bandeja. Let it bounce and come off the glass. If it crosses diagonally over your partner, you swap sides and the closer one chases.
* ball: soft lob, little spin: bounces high, meets the glass at about 1.5 to 2 m, floats out 1 to 2 m slowly. Easier. Topspin lob (`needs_spin`): bounces fast and low, hits hard, shoots out far. Harder.
* movement: turn sideways and run back along the side wall, do not backpedal. Stand beside the ball's path facing the side wall, let it pass, hit when it drops to waist height. Partner drops back to cover the middle.
* shot: lob back over opponents who moved up. If they stayed back, a low ball at their feet.
* fails: lands at the foot of the glass and dies (then contrapared, C12). Catches the corner and comes out sideways. Player loses sight of it while running.
* game: possible (soft lob). Topspin version needs_spin.

### C2. Bajada de pared: attack a high rebound

* trigger: medium-deep lob or weak high ball bounces, then hits your back glass high and leaves above shoulder height.
* positions: you at the back or just retreated. Opponents at the net or moving up.
* decision: do not lift it defensively. Let it come off the glass and attack it in the air before it drops.
* ball: leaves at 2 m or more, drifting toward the net slowly. Easy to hit hard.
* movement: turn sideways early with your back to the glass, step forward with the ball as it leaves. Hit 1 to 2 m out from the glass at head or shoulder height.
* shot: flat or sliced overhead driven down at the feet, at the gap between opponents, or into their side glass at an angle.
* fails: ball is lower than read, so it goes into the net. Too hard from deep gives a net player an easy volley. High reward, medium risk.
* game: possible. This is the main reward for waiting.

### C3. Hard ball deep, the standard defense

* trigger: opponents at the net hit a hard flat volley or bandeja deep. It bounces about 2 m from your glass at waist or chest height and runs into the glass.
* positions: you and partner both back, 1 to 2 m in front of the glass. Opponents at the net.
* decision: wait for the glass. Before the wall the ball is fast and at your body. The glass takes pace off and gives space.
* ball: leaves slower than it arrived, at about the height it hit, travels 2 to 4 m out, low to medium height.
* movement: step back toward the glass first for room, then move forward with the ball and hit it beside the body, not in front.
* shot: mostly cross-court (net is lower in the middle, diagonal is longer). Low to the net players' feet, or a lob to regain the net.
* fails: standing too close to the glass jams you. A flat ball can come off farther than expected and rush you.
* game: possible. This is the case that should make waiting pay when a hard ball arrives.

### C4. Topspin smash off the back glass flies out

* trigger: opponent smashes hard with topspin or kick. It bounces mid-backcourt and hits your glass high.
* positions: you at the back. Smasher at the net, partner close behind.
* decision: read whether it leaves the court (over the side wall "por 3", or back over the net). If it will, chase it. If not, play it on the way down after the glass.
* ball (`needs_spin`): topspin makes it rise off the glass, fast and high, toward the net or angled to the side. If it crosses back over the net before you touch it, the opponents win the point.
* movement: turn and sprint toward your own net, following the ball. On courts with doors you may leave the court and play it from outside.
* shot: any lift that gets it back, usually a soft lob. From outside the court, whatever works.
* fails: start too late. Read "out" when it will drop behind you. Second bounce before you arrive.
* game: needs_spin (the model fakes it with `kick`; `wall-shots.md` covers por 3 and por 4). Leaving the court: skip.

### C5. Rebound drops short near your own net

* trigger: hard smash or flat ball bounces deep, hits the glass with a lot of pace, rebounds all the way out and drops 1 to 3 m from your net.
* positions: you were waiting near the glass for a normal rebound. Opponents at the net, close to where it lands.
* decision: no choice, chase it forward and hit before the second bounce.
* ball: loses height as it travels, lands soft and short. Reachable if read early.
* movement: sprint forward, hit while moving, low and stretched.
* shot: soft lob over the net players, or soft ball at their feet. Hitting hard feeds a volley.
* fails: arrive late. Arrive with no time to set up, so you pop it up.
* game: possible. It shows the downside of waiting for a fast rebound.

### C6. Side wall then back wall

* trigger: angled cross-court ball bounces in your backcourt near the side, hits the side glass, then the back glass.
* positions: you back right, partner back left, opponents at the net.
* decision: wait for both walls. Hitting between the two is cramped.
* ball: each wall removes pace. After side then back it exits toward the middle, slower and lower. Easier if you are patient.
* movement: stay out of the corner, about 1.5 m from both walls, facing the side wall. Let it come to you and move toward the middle with it. Call it so partners do not both go.
* shot: usually a lob, since the ball is slow and low. Or a soft cross-court.
* fails: misread which wall is second. Ball hits the wall joint and dies or shoots off at a strange angle. Crowding the corner jams you.
* game: possible (double wall exists in `wall-shots.md`). Partner calling: skip, there is no partner.

### C7. Back wall then side wall (doble pared)

* trigger: deep ball into the corner hits the back glass first, then the side glass.
* positions: same as C6.
* decision: wait for the second wall. Hardest rebound to read.
* ball: leaves the back glass angled toward the side, hits the side, then shoots back toward the middle and the net. Sometimes with more pace than expected.
* movement: wait a little out from the corner toward the middle. Turn the body to follow it off the side glass.
* shot: mostly a lob, since the player is rarely set up.
* fails: rush in and get caught between walls. The side angle surprises. Ball hits the glass frame.
* game: possible.

### C8. Side glass only

* trigger: cross-court ball or a víbora (sliced bandeja) aimed at your side glass bounces in your backcourt and hits the side glass.
* positions: you at the back on that side. Opponents at the net; the one who hit it is diagonal from you.
* decision: depends on height. High ball: let it come off the side and hit it. Low sliced víbora: take it before the side glass, since after the glass it stays low and hugs the wall.
* ball: leaves toward the middle. Slice (`needs_spin`) keeps it low and skidding along the wall. Harder.
* movement: stand facing the side glass, a racket's length away, and let it come off before swinging.
* shot: down the line, or a lob.
* fails: ball sticks to the glass, racket hits the frame or wall. It dies at the bottom of the wall.
* game: possible for the high ball. The sliced version is needs_spin.

### C9. Serve off the glass

* trigger: medium-pace serve bounces near the service line and runs into the back glass or side glass.
* positions: server behind their service line, partner at the net. You receive about 1 m in front of your glass. Your partner near your service line.
* decision: deep fast serve: let it come off the glass for more time. Short or sliced serve that will die at the glass: take it right after the bounce, before the wall.
* ball: usually leaves the glass around waist height and 1 to 2 m out. A slice serve (`needs_spin`) off the side glass stays low and can jam you against the side.
* movement: wait close to the glass, slightly to one side, step with the ball as it leaves.
* shot: cross-court and low to the server's feet as they come forward, or a lob over the net player.
* fails: sliced serve dies at the foot of the glass. Serve aimed at the side jams you between the glass and the ball.
* game: possible. Serves are auto-aimed into the box now (no faults). See `glass-panels.md` serve notes.

### C10. When waiting is a mistake

* short or medium lob at the net: you can bandeja it, but you hesitate and run back to play it off the glass. You give up the net and end up lobbing from deep.
* heavy backspin toward the glass (`needs_spin`): it dies low against the glass. Take it early.
* ball heading for the mesh or corner joint: rebound is unpredictable. Play it before it gets there.
* chest-high ball while you stand on the service line: volley it. Waiting gives the opponents time to close the net.
* reverse mistake: if the ball will hit your glass without bouncing first, it is out and the point is yours. Volleying it hands them a second chance.
* game: possible, and it supplies the cost side of the wall decision. The "out before bouncing" rule already exists in the match rules.

### C11. How attackers force you onto the wall

* deep víbora or bandeja into the back corner: forces a double-wall rebound (C6, C7).
* hard flat ball deep at the body: no time before the wall, so you must use it (C3).
* topspin lob over a net player (`needs_spin`): forces a run back and a play off the glass (C1).
* kick smash (`needs_spin`): forces a chase or watching it leave the court (C4, C5).
* low sliced ball at the side glass (`needs_spin`): forces a low rebound (C8).
* ball at the mesh near the net: forces a play before the mesh or a gamble on a dead rebound (C13).
* game: this is the opponent-side counterpart. Use it for zone-based opponent shot choice (`glass-panels.md`).

### C12. Contrapared

* trigger: a lob has passed you or the ball is dying at your glass, and you face the wrong way to hit forward.
* decision: hit the ball backward into your own back glass, sometimes the side glass, so it bounces off and goes over the net. Legal.
* ball: leaves your glass high and slow, a weak lob. Often drops short near the opponents' net.
* movement: face your own glass, often sideways, and swing up into it.
* fails: it does not clear the net. It is so short and slow that the opponents put it away.
* game: needs_feature (a shot that targets your own glass). Best fit for the glass-panel idea and for the "change the direction of the hit" mechanic.

### C13. Ball into the mesh

* trigger: the ball bounces where the side wall is mesh, or a smash bounces and hits the mesh.
* decision: play it before the mesh if you can.
* ball: dies and drops nearly straight down, or leaves at a random angle. Much harder.
* fails: you wait for a glass-like rebound that never comes. It hits a metal post and goes anywhere.
* game: possible (`MESH_E` 0.25). Random angle: needs_feature.

### C14. Sliced ball dies low at the glass

* trigger: opponent hits a deep ball with heavy backspin. It bounces low and meets your glass at ankle or knee height.
* decision: take it before the glass if possible. Otherwise get very low and scoop it as it trickles off.
* ball (`needs_spin`): backspin drags it down against the glass. It leaves barely, low and slow. Very hard.
* movement: bend the knees deep, get the racket head under the ball.
* shot: a lob is about the only option.
* fails: it does not leave the glass at all. You hit the glass instead of the ball.
* game: needs_spin.

## Summary for the design

* Core pattern across C1 to C3 and C6 to C9: **a fast or high ball is better played after the glass, a slow short ball or a net position is better played now.** The cost of waiting is lost net position (C1, C10) or a rebound that comes off farther than expected (C5).
* Cases buildable with the current spin-free model: C1 (soft lob), C2, C3, C5, C6, C7, C8 (high ball), C9, C10, C13.
* Cases that need spin: C4, C8 (slice), C14, and the topspin variants of C1 and C9.
* Cases that need a new feature: C12 (hit your own glass on purpose), C13's random angle.
* Skipped: leaving the court through a door (C4), partner calling (C6), swapping sides with a partner (C1). The game has one player per side.

## Open questions for the design

* Is the direction choice made before the swing (aim input) or by choosing which shot to play (button)?
* What does the player gain from waiting, in game terms: more time, a higher-quality contact, or a bigger effect when the ball hits a glass panel?
* Does waiting cost net position, and is net position something the game tracks?
* Should the contrapared be a shot of its own?
