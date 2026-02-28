# CAT Inspect Integration Guide

## Where to put image assets

Place each part image in its matching imageset under:

`CAT Inspect/CAT Inspect/Assets.xcassets/`

Current inspection card image assets:

- `hydraulic_pump_a17.imageset` -> add `hydraulic_pump_a17.png`
- `fuel_injector_b9.imageset` -> add `fuel_injector_b9.png`
- `cooling_fan_c3.imageset` -> add `cooling_fan_c3.png`

You can also add new imagesets and reference them through `partImageAssetName` in `InspectionItem`.

## API integration section

API scaffold files:

- `CAT Inspect/CAT Inspect/Services/InspectionAPI.swift`
- `CAT Inspect/CAT Inspect/Views/DashboardViewModel.swift`

What to wire:

1. Set real base URLs in `APIEnvironment`.
2. Implement network calls inside `LiveInspectionAPIClient`.
3. Replace `loadMockData()` usage in `DashboardViewModel` with async API fetches.
4. In `startInspection(_:)`, call `apiClient.startInspection(...)` and update local state on success/failure.

Suggested response DTO mapping:

- Dashboard summary -> `[KPIItem]` and `[DashboardAlert]`
- Today's inspections -> `[InspectionItem]`
- Sync status -> `SyncState` (`synced`, `pending`, `failed`)
