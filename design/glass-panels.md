# Glass panels and shot types brainstorm

Ideas from the Session 14 playtest log. Nothing here is built yet. It records the direction, the reasons and what to test first.

## Stance: padel is the base, not the target

The game doesn't try to be a faithful padel sim. Plain padel (walls, bounces, the receiver rules) is the base that has to feel good first. Powerups, the roguelite structure and systems like the glass panels are where the game becomes its own thing. Realism is a tool, not a rule.

## What the playtest log showed

First match with the overlay, 32 points, 14 to 18 (`logs/match_2026-10-19T23-03-53.csv`, kept local).

* You volleyed 68 of your 110 shots. Only 4 came off the glass. The walls are decoration, which is the risk Session 8 parked.
* Your volleys averaged 4.4 m from the net, just outside the opponent's 3.5 m lob trigger. It never lobbed you.
* Nobody missed a shot. All 32 points ended on two bounces, and all 14 of your points came from opponent whiffs (8 working, 6 stretched, 0 easy).
* Crosscourt is no longer free: 30 hit, 4 won. Down the line won more, 65 hit, 8 won.
* You lost 4 points straight off its serve.

**The shared cause:** every swing that touches the ball produces a perfect, legal shot. A low volley in mid-court is as good as a comfortable ball off the glass. So there's no reason to wait for the wall, nobody ever misses, and the only way to lose a ball is a whiff roll.

## Shot types on different buttons

### Shots worth having

| Shot | What it is | Sweet spot |
|---|---|---|
| Drive | The flat shot we have now. Pace and placement | Waist height, time on the ball |
| Lob (globo) | High and deep, over a player at the net, toward the glass | Works from low contacts |
| Chiquita | Slow, low ball to the feet of a player at the net | Low contact, close to the net to work well |
| Overhead | Bandeja (controlled, keeps you at the net) or smash (por 3, por 4 from the sim) | Above the current band (1.9 m) |
| Drop shot (dejada) | Later, if needed | |

### Mapping options

1. **One button per shot:** A drive, Y lob, X chiquita, B overhead (keyboard J, K, L, I). Clear and deliberate, but a lot of buttons for a fast game.
2. **One button plus stick:** push up for deep or lob, neutral for drive, pull back for soft. Overhead is automatic on high balls. Fewer buttons, but it mixes aim with shot type.
3. **Contextual:** one button and the game picks the shot. Easy, but barely a choice, which is today's problem.

**Leaning:** start with two buttons, drive and lob, plus an automatic overhead on the drive button when the ball is above the band. Add the chiquita only if mid-court still feels flat. Keep the option 1 layout in mind so later shots don't force a remap.

### Contact quality has to come with it

Buttons only create choice if the shots differ in outcome. Each shot gets a sweet spot (height, time on the ball, distance to the ball). Off the sweet spot, the shot loses pace and gains aim, depth and net error, so some shots go into the net or out. Aiming at the lines and corners adds error, aiming middle is safe. A low volley in mid-court can't produce a good drive, so you lob from there or wait for the glass.

Show it in the overlay ("CLEAN", "RUSHED") so players learn why a shot went wrong. Part of the opponent's whiffs should become visible net and out errors, which read as earned instead of random.

## Glass panels

### The core rule

The back glass is split into panels. Each panel shows a symbol for a powerup or an event. When a legal ball (after its bounce) hits a panel, that panel triggers. Every ball heading for the glass then asks both players a question:

* **Defender:** cut it off before the glass, or let it reach the panel?
* **Attacker:** aim at a panel that hurts them, or one they'll want to avoid?

A panel isn't always good for the hitter or the defender. The same panel can be worth letting through on one ball and worth stopping on the next. That's the decision the walls are missing today.

### How many panels

* **2 (left, right):** easiest to read, few choices.
* **3 (left, center, right):** lines up with the shot kinds. Cross and line go to the sides, mid to the center. Start here.
* **6 (3 columns × 2 rows):** adds height. A drive hits the bottom row, a lob the top. The ball model already knows where and how high the ball hits the glass. Natural later step.

### Effect ideas

Good for whoever lets it hit (rewards waiting):

* **Charge:** your next shot gets extra pace.
* **Slow:** the rebound comes off slower, time for a clean shot.
* **Reach:** a bigger hitting zone for your next contact.

Bad for whoever lets it hit (rewards cutting it off):

* **Boost:** the rebound comes off much faster.
* **Shrink:** smaller reach for the next contact.
* **Fog:** the ball's shadow disappears for a moment, height is hard to read.

Chaos (either way):

* **Double:** the point is worth two.
* **Mirror:** the rebound angle flips.
* **Steal:** whoever wins the point takes a charge or currency.

### Rules to keep it fair and readable

* **Telegraph the target.** The overlay already predicts the landing spot. Extend it to show which panel the ball will hit, early enough to decide.
* **One trigger per point**, or points turn into noise.
* **No panel is pure upside.** If one is, everyone aims there and the choice disappears. The extra error from aiming at the sides (contact quality) helps here.
* **Readable in half a second:** icon plus color, and the same effect always looks the same.

### Roguelite hooks

* Panels give each court or match its own glass layout. Between matches you pick a panel to install, on your glass or theirs.
* Bosses with rigged glass, for example a back wall of Boost panels that forces you to volley.
* Panels level up, or combine with shot powerups: "your lobs trigger panels twice", "your contrapared steals the panel's effect".
* Shots decide how the ball gets to the glass, panels decide what the glass does. Lob to the top row, drive to the bottom, chiquita to keep it short of the glass.

## Opponent changes that support this

* **Shots by your zone:** at the net it lobs you, in mid-court it hits at your feet, at the back it drives deep or angled. Quick test first: widen the lob trigger from 3.5 m to about 6 m.
* **Lobs push you onto the glass.** Your band tops out at 1.9 m, so a good lob forces you back to play it off the back glass. Lobs are the cheapest way to make the walls matter.
* **Lob quality from strain:** a good lob when comfortable, a short floater when stretched (a smash chance for you).

## Serve

* Check before tuning: log your failed swings and your position on the serve, since the log can't tell yet whether you missed, stood wrong or never reached it.
* Real padel serves are weak (underhand, below the waist). Try `SERVE_SPEED` 10 to 11 m/s instead of 14.
* Let the receiver move during the serve.

## Order to build and test

One change per playtest, compared against the log.

1. **Zone-based opponent shots**, starting with the wider lob trigger. Cheap, and it tests whether lobs push you to the glass.
2. **Shot buttons and contact quality** together: drive, lob, automatic overhead. The big one.
3. **Glass panel prototype:** three panels on the opponent's glass only, one effect (Charge in the center). Check whether glass hits go up from 4 out of 110 and whether you let balls through on purpose. Then add one bad panel and see if you start cutting balls off.
4. **Serve tune and swing logging**, any time.

Possible shortcut: test one panel before step 2, as a quick probe of whether it changes behavior at all. The risk is that a Charge panel just strengthens a shot that's already perfect.

## Open questions

* Do panels live on both back glasses from the start, or only the opponent's?
* Do side glass panels make sense, or does it get too busy?
* Does a panel trigger on any glass hit, or only after a legal bounce? (Current leaning: only after a legal bounce, so it never rewards a fault.)
* How does the opponent AI read panels? It needs to choose to let a ball through or cut it off, or the panels only work one way.
* Currency or charges: is there a meter, or do effects fire and vanish?
