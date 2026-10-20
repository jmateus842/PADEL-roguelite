# Progress-driven next steps

**Executable entry rule.** When this rule is attached or invoked (`@rules/next-steps.md`), run the session-start ritual now. Do not summarize this file instead of doing the work.

---

## Execute immediately

1. **Read the top status block** of `progress.md` (repo root, everything above the first `---`).
2. **Read the last 3 `### Handoff` sections** in `progress.md`. If there are fewer, read all of them.
3. **Follow references only when needed.** If a Handoff cites unresolved earlier work, read only those sections.
4. **Check the project folder** for state the log may not mention (for example, whether the Godot project exists yet: `project.godot`).
5. **Infer current state:** what's done, in progress, blocked, and what remains. Mention contradictions only if they change the next action.
6. **Produce the recommendation** using the output format below.

Do not ask the user to attach another rule. Do the reading and respond in one turn.

---

## Output format (required)

Concise recommendation, not a full project audit:

- **Where we are:** 2–4 bullets
- **Do next:** 1–3 ordered actions, one clear recommended path
- **Open/check:** exact files, scenes or commands only if immediately useful
- **Watch out:** 1–2 risks, unknowns, or contradictions only if relevant

Only add timelines, detailed risks, citations, or longer priority lists when the user asks for a plan or that detail changes the recommendation.

---

## Priority order

1. Follow the playcentric loop in `progress.md`: prove the core (plain padel, walls) before adding powerups or content
2. Unblock dependencies and reduce risk early
3. Get something playable quickly, so it can be playtested
4. Minimize rework (align with decisions already logged)
5. Tight feedback loops (run the scene, playtest, check against the experience goals)

Cite section names only when they support a decision or resolve ambiguity.

---

## After the recommendation

| Need | Use |
|------|-----|
| Step-by-step plan without code | `@rules/nocode.md` |
| Writing the session entry at the end | `rules/template-session.md` |
