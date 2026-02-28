//
//  DashboardViewModel.swift
//  CAT Inspect
//

import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var inspectorName: String = "Alex Rivera"
    @Published var inspectorRegion: String = "Region C - South Yard"
    @Published var connectionOffline = false
    @Published var kpis: [KPIItem] = []
    @Published var alerts: [DashboardAlert] = []
    @Published var todaysInspections: [InspectionItem] = []

    private let apiClient: InspectionAPIClient

    init(apiClient: InspectionAPIClient = LiveInspectionAPIClient()) {
        self.apiClient = apiClient
        loadMockData()
    }

    func startInspection(_ inspection: InspectionItem) {
        // API call hook:
        // Task { try await apiClient.startInspection(inspectionID: inspection.id) }
        print("Start inspection tapped for \(inspection.itemName)")
    }

    private func loadMockData() {
        kpis = [
            KPIItem(title: "Open Inspections", value: "14", trendText: "+8%", trendUp: false, lastUpdated: "Updated 08:12"),
            KPIItem(title: "Completed Today", value: "9", trendText: "+12%", trendUp: true, lastUpdated: "Updated 08:12"),
            KPIItem(title: "Critical Findings", value: "2", trendText: "-18%", trendUp: true, lastUpdated: "Updated 08:12")
        ]

        alerts = [
            DashboardAlert(
                severity: .critical,
                title: "Hydraulic Press Line 3",
                message: "Temperature variance exceeded operating threshold.",
                actionTitle: "Review Now"
            ),
            DashboardAlert(
                severity: .warning,
                title: "Network Intermittent",
                message: "Recent sync retries detected in Bay 2.",
                actionTitle: "View Queue"
            )
        ]

        todaysInspections = [
            InspectionItem(
                id: UUID(),
                itemName: "Hydraulic Pump A17",
                location: "Plant 1 - Bay 4",
                priority: .critical,
                partImageAssetName: "hydraulic_pump_a17",
                documentationURL: URL(string: "https://www.caterpillar.com/en/support/maintenance")!,
                blueprintURL: URL(string: "https://www.caterpillar.com/en/company/brand")!,
                scheduledTime: "09:00 AM",
                syncState: .synced
            ),
            InspectionItem(
                id: UUID(),
                itemName: "Fuel Injector B9",
                location: "Plant 2 - Rack 1",
                priority: .high,
                partImageAssetName: "fuel_injector_b9",
                documentationURL: URL(string: "https://www.caterpillar.com/en/support/parts")!,
                blueprintURL: URL(string: "https://www.caterpillar.com/en/company/suppliers")!,
                scheduledTime: "11:30 AM",
                syncState: .pending
            ),
            InspectionItem(
                id: UUID(),
                itemName: "Cooling Fan C3",
                location: "Plant 1 - Line 2",
                priority: .medium,
                partImageAssetName: "cooling_fan_c3",
                documentationURL: URL(string: "https://www.caterpillar.com/en/support/safety-services")!,
                blueprintURL: URL(string: "https://www.caterpillar.com/en/support/operations")!,
                scheduledTime: "03:45 PM",
                syncState: .failed
            )
        ]
    }
}
