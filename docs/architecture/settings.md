# Settings

Read this before adding or changing a preference.

- Keys and defaults live in ShotCore `Preferences`.
- `SettingsStore` is an `@Observable` cache, and views use its `@Setting(key)` wrapper (never `@AppStorage`).
- The Settings window (`SettingsView.swift`) has a sidebar of `SettingsSection`s, each with its icon tint (`Brutal.SidebarTint`), and the open section's rows on the right. `SettingsNavigation` holds the section, the search and the keyboard state, and `shot://settings?section=` opens a section.
- A preference's row goes in its section's view as a `SettingRow` or `ToggleRow` inside a `SettingsCard`. The search at the top of the sidebar finds it with no extra work: ShotCore's `SettingsSearch.matches` looks for every typed word in the row's name and description and in its group's and section's names, so a clear name and description are what make it findable. While a search holds a word, the window lists the matching rows from every section, and a card hides when none of its rows match.
