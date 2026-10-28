# Settings

Read this before adding or changing a preference.

- Keys and defaults live in ShotCore `Preferences`.
- `SettingsStore` is an `@Observable` cache, and views use its `@Setting(key)` wrapper (never `@AppStorage`).
