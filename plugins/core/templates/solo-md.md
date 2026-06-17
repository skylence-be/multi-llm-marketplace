<!-- BEGIN core:solo -->
This machine runs SoloTerm; use the Solo MCP tools for any state that must outlive the current conversation (cross-session notes, shared task lists, agent coordination), and TaskCreate only for in-conversation tracking that dies with the turn.
End a session or hand work to another agent with the solo-session-handoff-skill: it calls whoami() to confirm the Solo MCP server is reachable, writes a scratchpad with session state, open todos, suggested next skills, and pick-up notes when online, and falls back to session-handoff-skill (a chat-only summary for /clear) when offline.
Persist plans and notes with scratchpad_write / scratchpad_append; name a plan with a `PRD:` prefix and a standing backlog of deferred work with a `DEFERRED:` prefix, keep a `## Handoff` and a `## Suggested skills` section in pick-up notes, reference plans and diffs by absolute path instead of pasting them, and redact secrets and PII as `[REDACTED]`.
Coordinate work through shared todos: todo_create one per delegatable unit, todo_list to read the queue, todo_complete to mark done, and annotate each todo in the PRD with its delegation target (which model, own agent or batched, parallel or sequential).
Serialize writers that would otherwise race with lock_acquire / lock_release (and lock_status to inspect), holding a lock only across the critical section.
Move work across project boundaries with the transfer tools (todo_transfer, scratchpad_transfer) rather than copying by hand, so a single source of truth follows the work to the project that now owns it.
<!-- END core:solo -->
