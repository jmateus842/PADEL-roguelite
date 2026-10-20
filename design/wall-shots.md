# Wall shots brainstorm

Playcentric step 2. A catalog of padel shots that use the walls, what each one asks of both players, and what the simulator (`sim/wall_shots.py`) says about them. No powerups here except where the sim showed a shot can't exist without one.

## Rules that shape wall play

* Your shot has to bounce on their floor before it touches their glass or mesh. If it hits their wall first, it's out.
* After that bounce, their glass and mesh are in play until the second bounce. The defender can let the ball come off the wall and hit it then.
* You can play the ball into your own glass (never your own mesh) so it rebounds over the net. That's the contrapared.
* A ball that leaves the court after a valid bounce is a winner, unless the defender runs outside to chase it (salida). The sim treats it as a winner.
* A ball that bounces on their side, hits their glass and flies back over the net is also your point.

## Enclosure used in the sim

* Court 20 x 10 m. Net 0.88 m. Service lines 6.95 m from the net.
* Back walls: 3 m glass plus 1 m mesh, 4 m total.
* Side walls: glass in the corners, mesh on the rest. The sim uses the common build: 2 m of glass at 3 m high (4 m total), then 2 m of glass at 2 m high (3 m total), then mesh 3 m high to the net. The rules only say glass in the corners, so this split is an assumption.

## Shot catalog

| Shot | What it is | Hitter decides | Defender has to read |
|---|---|---|---|
| Drive to the back glass | Fast, flat, deep ball | Depth and pace. Too deep and it hits the glass first (fault) | Where it comes off the glass and how low |
| Lob (globo) | High ball over the opponent | Height and depth | Run back and wait for it off the glass, or smash it early |
| Cross to the side glass | Diagonal ball that bounces and runs into the side glass | Angle | The direction change off the side glass |
| Double wall (doble pared) | Side glass then back glass, or the reverse | Aim at the corner | Two direction changes in under a second |
| Corner kill (al rincón) | Slow, angled overhead (bandeja or víbora style) into the corner | Placement over pace | Where the ball dies in the corner |
| Into the mesh (a la malla) | Ball that bounces and hits the side mesh | Aim at the mesh section | A dead, low ball with an unreliable bounce |
| Smash por 3 | Smash that bounces and leaves over the back wall | Position (near the net) and a steep angle | Whether to run outside to chase it |
| Smash por 4 | Smash that leaves over the side wall | Position and angle toward the side | Same, toward the side |
| Flat smash back over the net | Smash that comes off their glass high and flies back to you | Hard and not steep | Whether to cut it off before it reaches the glass |
| Contrapared | You hit into your own back glass to get it over the net | Desperation choice when the ball is behind you | A high ball arriving late |
| Bajada de pared | The defender's counter: wait for the ball off the glass and attack it | (defender's shot) | This is what the "hittable time" in the sim measures |

## What the simulator showed

Run all shots with `python sim/wall_shots.py`, or pick some: `python sim/wall_shots.py lob contrapared`. Plots land in `sim/shots/`, with a table in `sim/shots/summary.md`. "Hittable time" is how long the ball sits between 0.3 m and 1.9 m high inside the defender's half, after the first bounce and before the second.

| Shot | Result | Defender's hittable time |
|---|---|---|
| drive_to_back_glass | comes off the glass at 0.4 m | 0.46 s |
| lob | comes off the glass at 2.0 m | 0.78 s |
| cross_to_side_glass | side glass, then back glass | 0.44 s |
| double_wall | side then back glass, both at 0.6 m | 0.48 s |
| corner_kill | side then back glass at 0.9 m | 0.81 s |
| into_the_mesh | mesh kills it at 0.2 m | 0.42 s |
| smash_flat | off their glass at 2.5 m, back over the net | 0.20 s |
| smash_por_3 | out over the back wall | 0.12 s |
| smash_por_4_kick | out over the side wall, only with a 1.6x kick | 0.07 s |
| contrapared | lands deep, comes off their glass at 1.3 m | 0.72 s |
| too_long | hits their glass before bouncing, out | none |

### Findings

1. **Pace against arc is the main decision.** Flat drives give the defender under half a second and come off the glass low. Lobs and slow corner balls give about 0.8 s. That trade makes a good core choice: pressure with pace, or buy time with height.
2. **Power has a ceiling.** At 27 m/s flat, the drive hits their glass before bouncing. The walls punish overhitting on their own, with no extra rule needed.
3. **Side and double wall shots don't buy extra time.** They sit at 0.44 to 0.48 s, the same as a plain drive. Their value is position: they pull the defender into the corner and change where the ball comes out. In a top-down view that direction change has to be easy to read, so the shadow carries a lot of weight.
4. **Por 3 works only from near the net with a steep smash.** It needed −40° from 2.7 m, bouncing at 11.6 m. At −25° the ball hits their glass at 2.5 m and flies back over the net. Both are winners, so the smash decision is about position and angle.
5. **Por 4 isn't possible without spin.** The ball reaches the side mesh while still low. It needed a 1.6x kick on the first bounce, which puts more energy out than in. That makes por 4 (and a charged smash) a natural powerup, not a base shot.
6. **The contrapared is fair.** With the base numbers (22 m/s at 32°) it clears the net by a lot and gives the defender 0.72 s. It saves a point without being a free winner.
7. **Mesh is a dead zone and glass is lively.** Mesh at 0.25 restitution kills the ball. Aiming at the mesh becomes its own tactic, which supports "walls are a tool, not a hazard".

### Design takeaways for the core

* The defender's skill is reading the rebound and being there in a 0.4 to 0.8 s window. That's the timing budget for movement speed and the hit window in Godot.
* The 0.3 to 1.9 m hitting band is realistic. Flat drives come off the glass below it, so the game may need a wider band or a small lift off the glass. Playtest 1 should decide that, not the sim.
* Spin-like effects (kick, curve) are where the powerups live. The base game can stay spin-free.

## Limits of the sim

* No spin, so topspin, slice and side curve are missing. The kick value fakes topspin on the first bounce only.
* No players. Hittable time is when the ball could be hit, not whether someone could get there.
* The tuning numbers are starting guesses. Floor bounce follows the FIP-style drop test as I remember it (2.54 m drop, about 1.4 m rebound). Glass and mesh restitution are guesses. Check them against video before trusting them.
* The side view flattens x, so side walls don't show there. Use the top view for them.

## Tuning to carry into Godot

The constants at the top of `sim/wall_shots.py` (`G`, `DRAG`, `FLOOR_E`, `FLOOR_GRIP`, `GLASS_E`, `MESH_E`, `WALL_GRIP`) are the starting values for the Godot ball. Godot should match the sim's plots for the same launch values. If it doesn't, one of the two has a bug.
