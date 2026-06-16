---
description: Fully uninstall Skyline wiring, daemon services, plugins, and package files.
---

Run the skyline uninstall script to remove MCP wiring, hooks, instructions, daemon autostart, installed plugins, helper processes, dispatchers, and the global skyline package:

```
skyline_run(["bash", "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh"])
```

After the script completes, report the verification lines it printed. Do not report manual cleanup unless the verification output shows a concrete remaining artifact.
