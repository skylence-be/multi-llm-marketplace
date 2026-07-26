---
name: livewire-blueprint-skill
description: Force-invoked by feature-loop-skill at PLAN time when composer.json names livewire. Conduct addendum for Livewire component work, test coverage, assertion strength, event discipline. Reference docs (component API, directive syntax) route to Boost-generated skills or search-docs, never duplicated here. Not for Laravel app-structure conduct (laravel-blueprint-skill) or Filament (filament-blueprint-skill).
---

Addendum to feature-loop-skill's SLICE CYCLE for livewire stack, loaded at PLAN time per that loop's ORIENT step. Pairs with laravel-blueprint-skill on same composer.json; both apply when both stacks present.

REFERENCE: component API / directive / lifecycle-hook question ⇒ project's Boost-generated skill or `search-docs` tool. NEVER hardcode Livewire API reference here; conduct only.

SLICE CYCLE ADDENDA:
  ├─ component action (public method a user can trigger) ⇒ `Livewire::test()` covering it same slice, no exceptions: validation path, scoping, filters all count as actions; field-observed failure: 23 green model-level tests + zero component coverage self-reported as "full coverage"
  ├─ test assertion ⇒ bare `assertOk()` / status-200 alone = failure mode; assert on rendered content or component state, not just HTTP status
  ├─ user/tenant-owned data inside a component action ⇒ same query-scoping rule as laravel-blueprint-skill (`auth()->user()->rel()->findOrFail()`), test proving cross-user isolation same slice
  ├─ inter-component communication ⇒ direct `wire:click` / public method call over `$wire.dispatch` + `#[On]` global events; global events = last resort, not default
  └─ component template edit (.blade.php) ⇒ same verify-gap as laravel-blueprint-skill (`verify:true` is syntax-only), field-observed break is a multiple-root render error; re-read edited range immediately after edit, pair with route-level render test same slice

FINAL ATTESTATION: feature-loop-skill's FINAL enumerates each SLICE CYCLE ADDENDA line above as applied|n/a(<reason>). An addendum untouched by FINAL is a declared deviation, not a silent pass; do not let "Deviations: None" stand while one of these went unreported.

RULE SKIPS: same discipline as feature-loop-skill, declare before proceeding, never drop silently.

Not for Laravel data-model/query/auth conduct ⇒ laravel-blueprint-skill. Not for Filament resource/schema/action conduct ⇒ filament-blueprint-skill.
