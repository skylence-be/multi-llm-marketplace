---
name: laravel-blueprint-skill
description: Force-invoked by feature-loop-skill at PLAN time when composer.json names laravel. Conduct addendum for Laravel app-structure work, data model, routing, auth, query ownership. Reference docs (API signatures, config keys) route to Boost-generated skills or search-docs, never duplicated here. Not for Livewire component conduct (livewire-blueprint-skill) or Filament (filament-blueprint-skill).
---

Addendum to feature-loop-skill's SLICE CYCLE for laravel stack, loaded at PLAN time per that loop's ORIENT step. feature-loop-skill absent ⇒ this file does not apply, stop.

REFERENCE: API signature / config key / artisan flag question ⇒ project's Boost-generated skill or `search-docs` tool. NEVER hardcode Laravel API reference here; conduct only, docs live elsewhere.

RUN: php generation/artisan commands ⇒ Herd php.bat, never bare php.exe (crashes -1073741515 this stack).

PLAN order (laravel-specific confirmation of feature-loop PLAN): data model → auth/first user-facing surface → behaviors → polish. Do not reorder for laravel features.

SLICE CYCLE ADDENDA:
  ├─ query touching user/tenant-owned rows ⇒ scope through relation, never raw id: `auth()->user()->rel()->findOrFail()` (or tenant equivalent); same slice adds test proving second user/tenant sees nothing
  ├─ template edit (.blade.php) ⇒ `edit verify:true` = syntax reparse only, catches nothing at runtime; re-read edited range IMMEDIATELY after edit, then pair with route-level render test (assertOk + content assertion) same slice; diagnostics reports non-analyzed blade as clean, not proof; field cost of skipping: full file recreation after multiple-root render error
  └─ commit checkpoint ⇒ unchanged from feature-loop-skill, no laravel-specific override

FINAL ATTESTATION: feature-loop-skill's FINAL enumerates each SLICE CYCLE ADDENDA line above as applied|n/a(<reason>). An addendum untouched by FINAL is a declared deviation, not a silent pass; do not let "Deviations: None" stand while one of these went unreported.

RULE SKIPS: same discipline as feature-loop-skill, declare before proceeding, never drop silently.

Not for Livewire component-action conduct (Livewire::test coverage, assertion strength, wire:click discipline) ⇒ livewire-blueprint-skill. Not for Filament resource/schema/action conduct ⇒ filament-blueprint-skill.
