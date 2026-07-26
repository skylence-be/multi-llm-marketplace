# laravel-livewire-filament-claude

Laravel / Livewire / Filament development plugin for Claude Code.

**Status: foundations only.** The plugin manifest and marketplace registration
exist; no skills, commands, agents, or hooks ship yet.

## Planned layout

- `skills/` — stack skills: Eloquent and Laravel app patterns, Livewire 3
  components, Filament resources, schemas, and actions
- `commands/` — scaffold and review slash commands
- `agents/` — stack reviewer / architect subagents
- `hooks/` — session discipline for stack work

Directories are created when their first content lands, so an installed
foundations build contains only this README and the manifest.

## Install

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install laravel-livewire-filament-claude@multi-llm-marketplace
```

Installing at this stage gives you the empty shell; it is only useful for
pinning the plugin name ahead of the first content release.
