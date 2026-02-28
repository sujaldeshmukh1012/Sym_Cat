//
//  DashboardViewModel.swift
//  CAT Inspect
//

import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var inspectorName: String = "Inspector"
    @Published var inspectorRegion: String = ""
    @Published var connectionOffline = false
    @Published var isLoading = true
    @Published var kpis: [KPIItem] = []
    @Published var alerts: [DashboardAlert] = []
    @Published var todaysInspections: [InspectionItem] = []

    private let backend = SupabaseInspectionBackend.shared
    private var hasLoadedOnce = false

    init() {}

    func setInspectorProfile(name: String, region: String) {
        inspectorName = name
        inspectorRegion = region
    }

    func loadIfNeeded() async {
        if hasLoadedOnce { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        do {
            let payload = try await backend.fetchDashboardPayload()
            kpis = payload.kpis
            alerts = payload.alerts
            todaysInspections = payload.todaysInspections
            connectionOffline = false
            hasLoadedOnce = true
        } catch {
            connectionOffline = true
        }
        isLoading = false
    }
}
