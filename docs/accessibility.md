# Accessibility

RepoHub follows WCAG 2.2 AA where it applies to a macOS app, using the platform's own accessibility APIs (#58).

## Automated audits

[`AccessibilityTests`](../App/Tests/RepoHubUITests/AccessibilityTests.swift) runs Xcode's `performAccessibilityAudit()` on every main screen in CI (the **App UI tests (macOS)** job, a required check). The screens are the dashboard, a repository's details, all four Settings tabs, the Activity window, and the Clean Up Branches sheet. Any issue fails the build, except the framework-owned ones below, which an app can't change:

| Skipped | Why |
| --- | --- |
| "No description" on unlabeled `Group` containers and the Touch Bar | SwiftUI's layout containers. VoiceOver doesn't stop on them. |
| "Action is missing" on pop-up and menu buttons | SwiftUI `Picker` and `Menu` are native `NSPopUpButton`s, which open with VoiceOver's press action. The audit doesn't see it. |
| Contrast outside the frontmost window or sheet, and of toolbar tab titles | macOS dims inactive windows on purpose, and AppKit draws the Settings tab titles. |
| Contrast inside the selected row of the dashboard table | SwiftUI `Table` cells aren't told they're selected (`backgroundProminence`), so they keep their colors on the highlight, as AppKit tables do. |

`testKeyboardShortcuts` checks that the menu shortcuts open and close the cleanup sheet (⌥⌘B, Escape) and the Activity window (⇧⌘A). Moving through the table with the arrow keys is the standard AppKit table behavior.

## Findings and fixes (2026-10-22)

The first audit reported 189 issues. After the skips above, these were real and are fixed:

| Finding | Fix |
| --- | --- |
| The repository table, details, and stale branch lists had no labels | `accessibilityLabel` on each ("Repositories", "Details of *name*", "Branches to delete") |
| Change counts and the details header were elements with no role | The counts are static text; the header is a heading |
| Secondary text was ~3.9:1, below 4.5:1 | `.secondaryText`: an opaque gray (~8:1 light, ~10:1 dark), the full label color with Increase Contrast, and primary on selected rows |
| Green, orange, and red status text (Clean, Unavailable, Unmerged, review requests, errors) was ~2.5:1 | `StatusLabel`: the icon carries the color and the text stays readable |
| `ContentUnavailableView`'s gray text failed contrast | `EmptyStateView`, the same layout in readable colors, with a heading |
| The "Current" branch badge's tinted capsule | An outlined capsule |

## Practices

- **VoiceOver:** controls have labels. Icon-only buttons use `Label` with `.iconOnly`, so VoiceOver reads the title. Row details combine into one element that reads naturally ("dirty, main, No upstream"). Charts have labels.
- **Never color alone:** every status has text or a distinct icon shape: CI passed, failed, and running use a checkmark, an octagon, and a clock; changes use a count per kind.
- **Keyboard:** every action is in a menu with a shortcut:

  | Shortcut | Action |
  | --- | --- |
  | ⌘O / ⌘R | Add Folder / Refresh |
  | ⌥⌘F / ⌥⌘P | Fetch / Pull the selected repositories |
  | ⇧⌥⌘F | Fetch All |
  | ⌥⌘B | Clean Up Branches |
  | ⌥⌘E / ⌥⌘T / ⌥⌘R | Open in Editor / Terminal / Show in Finder |
  | ⌥⌘C / ⌥⌘G | Copy Remote URL / Open on GitHub |
  | ⇧⌘A / ⌘, | Activity / Settings |

  Return confirms and Escape cancels the cleanup sheet.
- **Reduce Motion:** RepoHub has no custom animations. System transitions follow the setting.
- **Increase Contrast and Dark Mode:** only semantic and dynamic colors are used, so both are followed automatically.

## Manual check

Before a release, with VoiceOver on (⌘F5) and Accessibility Inspector, check that:

1. VoiceOver reads each dashboard row's name, branch, changes, and CI.
2. The Clean Up Branches sheet can be completed with VoiceOver alone.
3. Text stays readable at Increase Contrast, in Dark Mode, and with Reduce Transparency.

Record any finding as an issue labeled `area: ux`.
