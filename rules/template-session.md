# Template for `progress.md`

`progress.md` has two parts: a **status block** at the top, then **session entries**, newest first. The goal is to make the next handoff obvious without forcing future agents to read the whole log.

---

## Part 1: Status block (top of the file, update every session)

```markdown
# Padel Roguelite progress

## Project status (as of YYYY-MM-DD)

* **Current priority:** [Main goal for the next session.]
* **Playcentric step:** [Which step of the loop the project is on, e.g. "4. Digital prototype".]
* **Known blockers:** [Issues preventing progress, or "None".]
* **Active known issues:**
    * [Issue (from Session XX).]
* **Technical debt:**
    * [Refactor or cleanup needed (from Session YY).]

---
```

---

## Part 2: Session entry (add a new one below the status block)

## YYYY-MM-DD (Session XX) – [Short Outcome-Oriented Title] [Tag1] [Tag2]

### Handoff

* **Result:** [What changed in one sentence.]
* **Why it matters:** [The design decision, blocker, playtest finding, or risk this addressed.]
* **Next recommended action:** [The single best next step.]

### Accomplished

* [Concrete change: mechanic, scene, script, design decision, playtest.]
* [Important implementation detail only if it helps future work.]
* [Avoid repeating project history unless it changes the next decision.]

### Verified

* [How it was checked: ran the scene in Godot, playtest with notes, paper prototype.]
* [If not verified, write: `Not run (reason)`.]

### Deferred / Follow-up

* [Only items that should survive into the next session.]
* [Include blocker or dependency when known.]

### Files Touched

* `path/to/file` — **New/Edit/Delete** — [short reason]
* `progress.md` — **Edit** — this entry and status block

### Status Update

* [What changed in the top status block.]

---

## Rules for future entries

* Newest session goes first, right under the status block.
* Start each session with `### Handoff` so the next agent can quickly understand result, importance, and next action.
* Always include `### Verified`, even when the answer is `Not run`.
* Use `### Deferred / Follow-up` only for work that should actually carry into the next session.
* Make the session title outcome-based, not activity-based.
* Prefer short factual bullets over long paragraphs.
* Use exact paths in `Files Touched` (`res://` paths or repo paths). Skip large code snippets unless essential.
* Record playtest findings against the experience goals: which goal held and which didn't.
* Durable design decisions (camera, ball model, mode, roguelite structure) stay in the session that made them. When one changes, log the change in the new session and say which earlier decision it replaces.
* Update the status block only with durable state: priority, playcentric step, blockers, issues, technical debt.
