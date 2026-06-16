---
description: Update Skyline, restart the daemon, and print plugin refresh steps.
---

Run the skyline upgrade script to update the binary to the latest release and restart the daemon:

```
skyline_run(["bash", "${CLAUDE_PLUGIN_ROOT}/scripts/upgrade.sh"])
```

After the script completes, show the user the plugin-update steps printed by the script and remind them to restart the session.
