//
//  InspectionModels.swift
//  CAT Inspect
//

import Foundation

enum InspectionPriority: String, CaseIterable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
}

enum SyncState: String {
    case synced = "Synced"
    case pending = "Pending"
    case failed = "Failed"
}

struct InspectionItem: Identifiable, Hashable {
    let id: UUID
    let itemName: String
    let location: String
    let priority: InspectionPriority
    let partImageAssetName: String
    let documentationURL: URL
    let blueprintURL: URL
    let scheduledTime: String
    let syncState: SyncState
}

enum AlertSeverity: String {
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"
}

struct DashboardAlert: Identifiable {
    let id = UUID()
    let severity: AlertSeverity
    let title: String
    let message: String
    let actionTitle: String
}

struct KPIItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let trendText: String
    let trendUp: Bool
    let lastUpdated: String
}
