# Tetris and Breakout ideas brainstorm

Ideas borrowed from Tetris (hold, Zone, garbage lines) and Breakout (bricks, multiball, paddle expand, fireball, catch). Nothing here is built yet. It records what fits, the reasons and when to test it. Builds on `design/glass-panels.md`.

## Stance: run layer, not core

These are powerup and run ideas. The core comes first: stop the opponent camping on deep center, then contact timing bands (step 3 of the aim design). One change per playtest still applies.

Breakout is the closer cousin: a ball, a paddle and a structure that breaks when hit. Tetris gives resource and pressure systems more than physics.

## Ideas that fit, ranked

### 1. Zone on the slow-mo meter (best fit)

L2 slow-mo exists (`scripts/focus.gd`, 3 s, 10 s refill). Today it only buys time.

* While slow-mo runs, every clean contact or glass hit adds one to a stack.
* When the meter empties, the stack releases on your next shot: extra pace, a guaranteed panel trigger, or a point worth more.
* Slow-mo becomes a gamble. Burn it to survive, or save it for a rally where you can bank three glass hits.
* It gives a direct reason to play off the glass, which playtests 1 to 4 say is missing.

Cheapest probe of the set, since the meter exists. Test it after the camping fix so it doesn't muddy that playtest.

### 2. Breakable glass panels (Breakout's bricks)

`glass-panels.md` treats glass as a trigger. Breakout treats it as a structure that wears down.

* Each panel takes 2 or 3 hits. Each legal glass hit cracks it.
* Breaking it fires a bigger effect.
* A broken panel changes the court for the rest of the match. Options: it opens a gap the ball can leave through (like the por 3 exit in the sim), or it goes dead and plays like the mesh.
* The match gets a visible arc.
* Answers the open question "meter, or fire and vanish?" with a third option: progress you can see on the wall.

**Piercing ball (fireball):** a powerup ball that shatters a panel in one hit instead of bouncing off it.

### 3. Garbage lines for PvP

Your best moments make the other player's world worse.

* Winning a point off the glass, or breaking a panel, puts a bad panel (Boost, Shrink, Fog) on the opponent's back glass.
* This is the "install on your glass or theirs" hook from `glass-panels.md`, earned mid-match instead of picked between matches.
* Solo version: a boss does it to you.

### 4. Catch and Hold

**Catch (on the ball):** hold RT to cradle the ball for about half a second, aim with the right stick, release. Strong and readable, but it skips the contact timing bands. Make it a powerup with limited charges, never the base swing.

**Hold (on effects):** one slot that stores a panel effect instead of firing it, so the player picks the moment. Works better than holding the ball.

### 5. Multiball, with a guard

"Splits on wall hit" is already in the powerup categories (Session 1). The risk is the "must not feel like" goal: an unreadable ball once powerups stack.

* Only the real ball can score.
* Splits are ghosts. They only trigger or crack panels.
* Ghosts look different and have no shadow, so the true ball stays readable.

That makes multiball a panel tool, not a test of who can track five balls.

### Already covered

Paddle expand is the Reach panel effect in `glass-panels.md`.

## New ideas they spark

* **Clearing the glass.** Trigger all three panels on the opponent's glass within one point and the glass clears: a big reward, panels reset. Rewards hitting in different directions, which fits the crosscourt vs. down-the-line numbers from playtest 1.
* **The monument.** Tetris makes failure pile up where you can see it. Here, points lost on your own errors crack your glass, and cracked panels start working against you. Depends on step 3, since nobody makes errors until contact quality exists.
* **A ball the opponent can't volley.** A shot that must bounce before anyone can hit it. Good as a boss counter or powerup. Not the fix for camping, because the core has to solve that without powerups.

## Order to test

After the camping fix and contact timing:

1. **Zone stacking** on the existing meter. Check whether glass hits per match go up and whether you save slow-mo on purpose.
2. **Breakable panels**, once the panel prototype (step 3 in `glass-panels.md`) exists. Start with 2 hits per panel and one break effect.
3. **Garbage panels** when PvP exists.
4. Catch, Hold and multiball as draft powerups once the run layer exists.

## Open questions

* Does a Zone stack carry across points, or reset each point?
* Do broken panels repair between matches, or does damage carry through the run?
* If a broken panel opens an exit, who wins the point when the ball leaves through it?
* How does the opponent AI read stacked Zone or cracked panels?
* Is Hold one slot for the whole run, or per match?
