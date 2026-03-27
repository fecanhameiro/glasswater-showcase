# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GlassWater is an iOS/watchOS SwiftUI app for water intake tracking. **iOS 26+ deployment target.**

**IMPORTANTE:** Sempre implemente usando as APIs mais recentes do iOS 26 sem fallbacks para versões anteriores. Não é necessário usar `@available` checks.

**Integrations:** SwiftData, HealthKit, UserNotifications, WidgetKit, App Intents (Siri), Firebase Crashlytics

## Build Commands

Open `GlassWater.xcodeproj` in Xcode. No tests in the repository.

## Architecture

**MVVM-lite pattern:**
- `GlassWater/Views` - SwiftUI views
- `GlassWater/ViewModels` - `@Observable` view models
- `GlassWater/Services` - Business logic services (protocol-based)
- `GlassWater/Domain` - Domain models
- `Shared/` - SwiftData models, stores, and helpers shared with widgets

**Dependency Injection:**
- `AppServices` struct holds all service protocols
- `PreviewServices` provides mock implementations for Xcode previews

**Data Flow:**
1. `GlassWaterApp.swift` creates `ModelContainer` and `AppServices`, injects into `RootView`
2. Views instantiate ViewModels with `@Observable`, call services via `AppServices`
3. `SwiftDataWaterStore` and `SwiftDataSettingsStore` are the persistence layer
4. `HomeViewModel.add` saves locally, triggers haptics, writes to HealthKit if authorized
5. `NotificationService` schedules reminders respecting minimum interval
6. `HydrationUpdateBroadcaster` shares state with widgets via app groups

**App Group:** `group.com.glasswater.app` - used for sharing data between app, widgets, and watch

## Key Files

| Area | Files |
|------|-------|
| Entry point | `GlassWater/App/GlassWaterApp.swift` |
| DI container | `GlassWater/Services/AppServices.swift`, `PreviewServices.swift` |
| SwiftData models | `Shared/WaterEntry.swift`, `Shared/UserSettings.swift` |
| Persistence | `Shared/SwiftDataWaterStore.swift`, `SwiftDataSettingsStore.swift` |
| Schema setup | `Shared/ModelContainerFactory.swift` |
| Main screens | `Views/Home/HomeView.swift`, `Views/History/HistoryView.swift`, `Views/Settings/SettingsView.swift` |
| Widget | `GlassWaterWidgetExtension/GlassWaterWidget.swift` |
| App Intent | `Shared/AddWaterIntent.swift` |
| Constants | `Shared/AppConstants.swift` |

## Adding New Code

**New SwiftData models:** Update schema in `Shared/ModelContainerFactory.swift`

**New services:** Add to `GlassWater/Services/AppServices.swift` and `PreviewServices.swift`

**Localization:** Use `LocalizedStringKey` or `String(localized:)`. Base English strings in `GlassWater/Resources/en.lproj/Localizable.strings`. HealthKit descriptions in `InfoPlist.strings`.

## UI Guidelines

> **For detailed Liquid Glass API, code examples, and checklists, see the `ios26-dev` and `ios26-review` skills.**

### Core Liquid Glass Rules

- **Use `.glassEffect()`** (iOS 26) — NEVER use `.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`
- Glass variants: `.regular` (controls, buttons), `.clear` (over photos/media), `.identity` (conditional toggle)
- Interactive buttons MUST use `.glassEffect(.regular.interactive())` for shimmer/bounce
- Multiple glass elements nearby MUST be wrapped in `GlassEffectContainer`
- Glass is **only for navigation layer** (toolbars, action bars, floating controls) — NEVER on content cards/list cells

### Color Rules — Two Contexts

**Over `TimeOfDayBackgroundView`** (always colorful/dark gradient):
- Use `Color.onTimeOfDayText` (.white), `Color.onTimeOfDaySecondaryText` (.white.opacity(0.85)), `Color.onTimeOfDayTertiaryText` (.white.opacity(0.6))
- Cards: `Color.onTimeOfDayCardBackground` + `Color.onTimeOfDayCardStroke`
- NEVER use `.primary`, `.secondary`, `Color.textPrimary` — they break on colorful gradients
- Views: `OnboardingView`, `HistoryView` (WeeklyChart, Insights, DailyHistory), `HistoryRowView`

**Over system backgrounds** (sheets, modals, grouped backgrounds):
- Use normal adaptive colors: `.primary`, `.secondary`, etc.
- Views: `DayEntriesSheetView`, Settings, Widgets

**Over Glass elements** — use adaptive colors:
- Dark mode: `.white` / `.white.opacity(0.8)` — Light mode: `.primary` / `.secondary`
- Use `.weight(.bold)` or `.weight(.semibold)` for legibility

### Glass Tints for Brand Identity

```swift
.glassEffect(.regular.tint(Color.cyan.opacity(0.15)).interactive())  // water theme
.glassEffect(.regular.tint(Color.blue.opacity(0.2)).interactive())   // primary action
.glassEffect(.regular.tint(Color.green.opacity(0.15)).interactive()) // success
```

### Animations (Spring Only)

```swift
withAnimation(.spring(.smooth)) { }  // standard transitions
withAnimation(.spring(.bouncy)) { }  // touch feedback
withAnimation(.spring(.snappy)) { }  // quick actions
// FORBIDDEN: .linear, .easeInOut
```

### Haptics (Mandatory)

```swift
.sensoryFeedback(.impact(weight: .medium), trigger: actionTrigger)
.sensoryFeedback(.selection, trigger: selectionTrigger)
.sensoryFeedback(.success, trigger: successTrigger)
```

### Shape & Corner Rules

- ALWAYS: `RoundedRectangle(cornerRadius: 20, style: .continuous)`
- NEVER: `RoundedRectangle(cornerRadius: 20)` (missing style) or `Rectangle()`

### Consolidated Anti-Patterns

- Old materials (`.ultraThinMaterial`, etc.) — use `.glassEffect()`
- Glass elements outside `GlassEffectContainer`
- Glass on content (list cells, cards) — glass is navigation-layer only
- Buttons without `.interactive()` — loses shimmer/bounce
- `.linear` / `.easeInOut` animations — use spring
- Missing haptic feedback on interactions
- Corners without `.continuous` style
- `.foregroundStyle(.primary)` over glass or TimeOfDay backgrounds

## Widget Design

> **`.glassEffect()` does NOT work in WidgetKit** — buttons disappear. Use traditional gradients and semi-transparent colors instead.

**Existing components** (reuse, don't recreate):
- `WidgetSharedComponents.swift` — `WidgetStatCard`, `WidgetQuickAddButtonLabel`, shared helpers
- `WidgetSmallView.swift`, `WidgetMediumView.swift`, `WidgetLargeView.swift` — per-family layouts

**Widget colors:** `.primary`, `.secondary`, `.tertiary` for text hierarchy; `Color.cyan`, `Color.blue` for accents; `Color.primary.opacity(0.05)` for card backgrounds

**Sizing by family:**

| Family | Ring | Font | Spacing | Padding |
|--------|------|------|---------|---------|
| Small | 80pt | 15-18pt | 6pt | 8-12pt |
| Medium | 68pt | 13-16pt | 8-10pt | 12-14pt |
| Large | 100pt | 22-34pt | 10-16pt | 16pt |

## Dynamic Island & Live Activity

### Key Files

| File | Role |
|------|------|
| `LiveActivityService.swift` | Creation, update, end lifecycle |
| `HydrationUpdateBroadcaster.swift` | Throttle (0.35s) + broadcast to LA + Widgets |
| `AppServices+Broadcast.swift` | `broadcastCurrentSnapshot()` for scenePhase transitions |
| `GlassWaterLiveActivityAttributes.swift` | ActivityAttributes + ContentState |
| `LiveActivityContentStateFactory.swift` | Factory for ContentState |
| `GlassWaterWidget.swift` | Dynamic Island + Lock Screen UI |

### User Settings

- `liveActivitiesEnabled` — toggles Dynamic Island on/off
- `liveActivitySensitiveModeEnabled` — hides numeric values (privacy), does NOT control visibility

### Lifecycle Rules

**Starts when:** foreground + `allowStartWhenNeeded = true` + `!goalReached` + `areActivitiesEnabled` + toggle on

**Ends automatically:**
- Goal reached → celebration state → dismiss after 30 min
- Outside reminder window → dismiss after 20 min buffer
- User disables in Settings → immediate `end()`

**Background:** `LiveActivityService(allowStartWhenNeeded: false)` in `BackgroundRefreshService` — updates/ends existing LAs only, NEVER starts new ones

### Goal-Reached Behavior

1. Compact trailing → green checkmark instead of percentage
2. Expanded bottom + Lock Screen → celebration message instead of quick-add buttons
3. Progress bar → changes from cyan to green
4. Auto-dismiss after 30 min via `dismissalPolicy: .after()`

## Cross-Surface Hydration Sync

### Architecture: Darwin Notifications

All surfaces (app, widget, LA/DI, watch) must stay in sync. When water is added from **any source**, all other surfaces update.

**Mechanism:** Darwin notifications (`CFNotificationCenter`) for cross-process IPC on the same device.

**Key Files:**

| File | Role |
|------|------|
| `Shared/HydrationChangeNotifier.swift` | Posts Darwin notification `"com.glasswater.hydrationChanged"` — used by all targets |
| `GlassWater/Services/HydrationChangeObserver.swift` | Listens for Darwin notifications in the main app process |
| `GlassWater/App/GlassWaterApp.swift` | Wires observer → `broadcastCurrentSnapshot()` + posts `.hydrationDidChangeExternally` |

### How It Works

```
Widget/LA button tap → AddWaterIntent.perform():
  1. Save to SwiftData
  2. Save snapshot to App Group
  3. Update LA directly (only works from app process via LiveActivityIntent)
  4. WidgetCenter.reloadTimelines()
  5. HydrationChangeNotifier.post() ← Darwin notification
  6. Main app receives → broadcastCurrentSnapshot() → updates LA/DI
  7. → posts .hydrationDidChangeExternally → HomeViewModel.refreshFromExternalChange()
```

### Important Rules

- **Always call `HydrationChangeNotifier.post()`** after saving hydration data from any external source (widget, LA, watch)
- **`AddWaterIntent` uses `LiveActivityIntent`** on iOS (runs in app process, can access `Activity<>.activities`) and `AppIntent` on watchOS (no Live Activities on watch)
- Darwin notifications are **signal-only** — no data payload. The receiver reads fresh data from SwiftData/App Group
- Darwin notifications are **same-device only** — watch ↔ phone sync uses HealthKit observer queries
- **`HomeViewModel.refreshFromExternalChange()`** is a lightweight refresh (re-reads SwiftData entries only, no HealthKit sync)

### Watch ↔ Phone Sync

Watch and phone are different devices — Darwin notifications don't cross devices. Sync works via:
1. **Watch → Phone:** Watch saves to HealthKit → Phone's `HKObserverQuery` fires → `handleHealthUpdate()` → `broadcastCurrentSnapshot()` (~2-5s delay)
2. **Phone → Watch:** Phone saves to App Group snapshot. Watch reads snapshot on next `load()` or `applySnapshotIfAvailable()`

### Update Propagation Matrix

| Source → | Widget | LA/DI | Main App | Watch |
|----------|--------|-------|----------|-------|
| **Main App** | ✅ broadcaster | ✅ broadcaster | ✅ direct | ⏳ HK observer |
| **Widget Button** | ✅ WidgetCenter | ✅ Darwin→broadcaster | ✅ Darwin→refresh | ⏳ HK observer |
| **LA Button** | ✅ WidgetCenter | ✅ direct (LiveActivityIntent) | ✅ Darwin→refresh | ⏳ HK observer |
| **Watch** | ✅ watch WidgetCenter | ⏳ HK observer | ⏳ HK observer | ✅ direct |

## Quick-Add Buttons (MANDATORY — All Surfaces)

### Button Rules

Every surface that shows quick-add buttons MUST follow the **same 2-button pattern** (except the main app which has its own 3+1 layout):

| Button | ID | Icon | Amount | Logic |
|--------|----|------|--------|-------|
| **Button 1** | `"quick"` | `plus` | 10% of daily goal | `QuickAddOptions.amount(forPercent: 10, goalMl:)` — computed, never stored |
| **Button 2** | `"custom"` | `slider.horizontal.3` | User's custom amount | `UserSettings.lastCustomAmountMl` — persisted, synced everywhere |

**Critical rules:**
- Custom amount is clamped to **[50ml, 1500ml]** via `QuickAddOptions.clampCustomAmount()`
- If user **never set** a custom amount, fallback = **25% of goal** (`resolvedCustomAmount`)
- Changing custom amount on **any surface** must propagate to **all surfaces**

### Surface Implementation Matrix

| Surface | Buttons | Amount Source | Key File |
|---------|---------|-------------|----------|
| **Main app ActionBar** | 3 percent (10/15/25%) + 1 custom | `HomeViewModel.customAmountMl` | `ActionBarView.swift` |
| **Widget small** | 2 (quick + custom) | `HydrationSnapshot.customAmountMl` | `WidgetSmallView.swift` |
| **Widget medium** | 2 (quick + custom) | `HydrationSnapshot.customAmountMl` | `WidgetMediumView.swift` |
| **Widget large** | 2 (quick + custom) | `HydrationSnapshot.customAmountMl` | `WidgetLargeView.swift` |
| **Live Activity (lock screen)** | 2 (quick + custom) | `ContentState.customAmountMl` | `GlassWaterLiveActivityView.swift` |
| **Dynamic Island (expanded)** | 2 (quick + custom) | `ContentState.customAmountMl` | `GlassWaterWidget.swift` |
| **Watch** | 2 (quick + custom) | `WatchState.customAmountMl` | `WatchQuickAddGridView.swift` |

### Custom Amount — Single Source of Truth

**Source of truth:** `UserSettings.lastCustomAmountMl: Int?` in SwiftData (phone).

**Write paths (custom amount changes from any surface):**
1. **Phone app** → `HomeViewModel.addCustom()` → `storeCustomAmount()` → `SwiftDataSettingsStore.save()` → `syncAppGroupDefaults()` → broadcast → all surfaces
2. **Phone settings** → `SettingsViewModel.persistChanges()` → `sendSettings()` → WatchState push (sentinel `totalMl=-1`)
3. **Watch** → `WatchHomeViewModel.addCustom()` → sends `WatchCommand.setCustomAmount` → phone persists to SwiftData → broadcasts to all surfaces

**Propagation:**
```
Phone SwiftData → syncAppGroupDefaults() → App Group UserDefaults
                → HydrationSnapshotProvider → HydrationSnapshot → App Group JSON → Widgets
                → LiveActivityContentStateFactory → ContentState → LA/DI
                → buildWatchState() → WatchState → WatchConnectivity → Watch

Watch → WatchCommand.setCustomAmount → Phone onCommandReceived
     → settingsStore.save() → syncAppGroupDefaults() + broadcast → all surfaces
```

### Key Files

| File | Role |
|------|------|
| `Shared/QuickAddOptions.swift` | Core algorithm: `liveActivityOptions()`, `resolvedCustomAmount()`, `clampCustomAmount()` |
| `Shared/AppConstants.swift` | `quickAddPercents`, `customAmountMinMl/MaxMl/StepMl`, `appGroupCustomAmountKey` |
| `Shared/WatchCommand.swift` | `.setCustomAmount` action — watch→phone custom amount sync |
| `Shared/WatchState.swift` | `customAmountMl: Int` — phone→watch transport |
| `Shared/HydrationSnapshot.swift` | `customAmountMl: Int` — widget/LA data carrier |
| `Shared/UserSettings.swift` | `lastCustomAmountMl: Int?` — single source of truth |
| `GlassWater/Services/AppServices+WatchState.swift` | Builds `WatchState.customAmountMl` from settings |

### Anti-Patterns

- NEVER hardcode button amounts — always derive from `QuickAddOptions`
- NEVER show only 1 button on surfaces that should have 2
- NEVER save custom amount only locally — always sync back to phone's SwiftData
- NEVER use different button logic per surface (except main app's 3+1 layout)
- NEVER forget to propagate custom amount changes to all surfaces via broadcast

## Day Rollover Architecture (Midnight Reset)

At midnight, all surfaces must reset to 0ml. Uses **5 independent mechanisms** (defense-in-depth):

| # | Mechanism | File | Covers |
|---|-----------|------|--------|
| 1 | `UIApplication.significantTimeChangeNotification` observer | `GlassWaterApp.swift` | App in foreground at midnight, timezone changes |
| 2 | Midnight-aligned `BGAppRefreshTask` (separate identifier `com.glasswater.app.midnight`) | `BackgroundRefreshService.scheduleMidnightRefresh()` | App in background overnight |
| 3 | Widget midnight timeline entry | `GlassWaterWidget.swift` timeline() | Widget displays — always resets at midnight |
| 4 | `LiveActivityService` day-change detection + cold-launch stale cleanup | `LiveActivityService.swift` update() | Any `update()` call after midnight ends old LA + starts fresh |
| 5 | `AddWaterIntent` staleDate + activityState check | `AddWaterIntent.swift` updateLiveActivityIfPossible() | LA/widget button tap after midnight ends stale activity |

### `latestEntry()` vs `latestTodayEntry(for:)` — CRITICAL

| Method | Scope | Usage |
|--------|-------|-------|
| `latestEntry()` | All-time (no date filter) | **Only** for global queries (e.g., notification scheduling across days) |
| `latestTodayEntry(for:)` | Single day | **Always use** for snapshots, widgets, LA, background refresh |

### Key Files

| File | Day Rollover Role |
|------|------------------|
| `GlassWaterApp.swift` | `significantTimeChangeNotification` observer + `scheduleMidnightRefresh()` call |
| `LiveActivityService.swift` | `currentDayStart` comparison + `dayChanged` flag to force clean restart |
| `BackgroundRefreshService.swift` | `scheduleMidnightRefresh()` + `latestTodayEntry(for:)` (day-scoped) |
| `GlassWaterWidget.swift` | Midnight timeline entry + `latestTodayEntry(for:)` in SwiftData fallback |
| `AddWaterIntent.swift` | `staleDate` check in `updateLiveActivityIfPossible()` |
| `SwiftDataWaterStore.swift` | `latestTodayEntry(for:)` — day-scoped version of `latestEntry()` |

### Anti-Patterns

- NEVER use `latestEntry()` for building snapshots or widget data — use `latestTodayEntry(for:)`
- NEVER assume ActivityKit removes activities instantly after `end()` — check for lingering activities
- NEVER rely on `staleDate` alone to dismiss a Live Activity — it only marks it visually stale
- NEVER remove any of the 5 day-rollover mechanisms — they are defense-in-depth
- NEVER skip `HydrationChangeNotifier.post()` after saving data in intents
- NEVER use `existingSnapshot.lastIntakeMl` as fallback without checking `isDate(dayStart, inSameDayAs: .now)`
