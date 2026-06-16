Run the skyline uninstall script to remove all MCP wiring, hooks, instructions, and the daemon autostart service:

```
skyline_run(["bash", "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh"])
```

After the script completes, show the user the remaining manual steps printed by the script.
