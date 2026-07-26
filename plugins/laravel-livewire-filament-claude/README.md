# laravel-livewire-filament-claude

Laravel / Livewire / Filament development plugin for Claude Code.

**Status: conduct layer shipped.** Three blueprint skills are in; reference
skills, scaffold commands, agents, and hooks land in later versions.

## Skills

- `laravel-blueprint-skill` - force-invoked by feature-loop-skill at plan
  time when `composer.json` names laravel. Data model, routing, auth, and
  query-ownership conduct.
- `livewire-blueprint-skill` - force-invoked at plan time when
  `composer.json` names livewire. Component test coverage, assertion
  strength, and event discipline conduct.
- `filament-blueprint-skill` - force-invoked at plan time when
  `composer.json` names filament. Skeleton addendum; inherits the laravel
  and livewire canon until filament-specific failure modes are field-proven.

None of these duplicate Laravel Boost's generated reference skills or
`search-docs`; they are conduct only and route lookups back to those.

## Planned layout

- `commands/` - scaffold and review slash commands
- `agents/` - stack reviewer / architect subagents
- `hooks/` - session discipline for stack work

## Install

```
/plugin marketplace add skylence-be/multi-llm-marketplace
/plugin install laravel-livewire-filament-claude@multi-llm-marketplace
```

Installing now gives you the three blueprint skills; feature-loop-skill
force-invokes the matching one at plan time once your project's
`composer.json` names laravel, livewire, or filament.
