//
//  ContentView.swift
//  CAT Inspect
//
//  Created by Sujal Bhakare on 2/27/26.
//

import SwiftUI

// MARK: - Caterpillar Dark Theme

private enum CATTheme {
    // Core brand
    static let catYellow      = Color(red: 1.0,  green: 0.804, blue: 0.067)   // #FFCD11
    static let catYellowDark  = Color(red: 0.85, green: 0.68,  blue: 0.0)     // darker gold
    static let catBlack       = Color(red: 0.07, green: 0.07,  blue: 0.09)    // #121217
    static let catCharcoal    = Color(red: 0.11, green: 0.11,  blue: 0.14)    // #1C1C23

    // Surfaces
    static let background     = Color(red: 0.06, green: 0.06,  blue: 0.08)    // deep black
    static let card           = Color(red: 0.11, green: 0.11,  blue: 0.14)
    static let cardElevated   = Color(red: 0.14, green: 0.14,  blue: 0.18)
    static let cardBorder     = Color.white.opacity(0.06)

    // Text
    static let heading        = Color.white
    static let body           = Color(red: 0.72, green: 0.72, blue: 0.76)
    static let muted          = Color(red: 0.45, green: 0.45, blue: 0.50)

    // Semantic
    static let critical       = Color(red: 1.0,  green: 0.30, blue: 0.30)
    static let warning        = Color(red: 1.0,  green: 0.76, blue: 0.20)
    static let success        = Color(red: 0.30, green: 0.86, blue: 0.56)
    static let info           = Color(red: 0.40, green: 0.70, blue: 1.0)

    // Gradients
    static let headerGradient = LinearGradient(
        colors: [catYellow, Color(red: 0.95, green: 0.65, blue: 0.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let cardGlow       = catYellow.opacity(0.06)
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        TabView {
            NavigationStack {
                DashboardHomeView(viewModel: viewModel)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }

            PlaceholderScreen(title: "Inspections", icon: "checklist.checked",
                              subtitle: "Inspection queue and filters.")
                .tabItem {
                    Label("Inspections", systemImage: "checklist")
                }

            PlaceholderScreen(title: "Alerts", icon: "bell.badge.fill",
                              subtitle: "Operational notifications and escalations.")
                .tabItem {
                    Label("Alerts", systemImage: "bell.fill")
                }

            PlaceholderScreen(title: "History", icon: "chart.bar.xaxis",
                              subtitle: "Completed inspections and trends.")
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            PlaceholderScreen(title: "Profile", icon: "person.crop.circle.fill",
                              subtitle: "Inspector settings and account.")
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(CATTheme.catYellow)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Dashboard Home

private struct DashboardHomeView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showingCreateInspection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.connectionOffline {
                    OfflineBanner()
                }

                HeaderCard(name: viewModel.inspectorName, region: viewModel.inspectorRegion)

                SectionHeader(title: "KPI Summary", icon: "chart.bar.fill")
                KPIStrip(kpis: viewModel.kpis)

                SectionHeader(title: "Active Alerts", icon: "exclamationmark.triangle.fill")
                VStack(spacing: 12) {
                    ForEach(viewModel.alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }

                SectionHeader(title: "Operational Overview", icon: "gearshape.2.fill")
                OperationalSummaryCard()

                SectionHeader(title: "Today's Inspections", icon: "wrench.and.screwdriver.fill")
                VStack(spacing: 16) {
                    ForEach(viewModel.todaysInspections) { inspection in
                        InspectionCard(inspection: inspection) {
                            viewModel.startInspection(inspection)
                        }
                    }
                }

                SectionHeader(title: "Historical Insights", icon: "chart.line.uptrend.xyaxis")
                HistoryCard()

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("CAT Inspect")
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateInspection = true
                } label: {
                    Text("Create Inspection")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(CATTheme.headerGradient)
                        )
                        .foregroundStyle(CATTheme.catBlack)
                }
            }
        }
        .sheet(isPresented: $showingCreateInspection) {
            NavigationStack {
                CreateInspectionView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Header Card

private struct HeaderCard: View {
    let name: String
    let region: String

    var body: some View {
        HStack(spacing: 16) {
            // Avatar circle with CAT branding
            ZStack {
                Circle()
                    .fill(CATTheme.headerGradient)
                    .frame(width: 56, height: 56)
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CATTheme.catBlack)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("INSPECTOR")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(CATTheme.catYellow)
                Text(name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(region)
                        .font(.subheadline)
                }
                .foregroundStyle(CATTheme.muted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(CATTheme.muted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(CATTheme.catYellow.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: CATTheme.catYellow.opacity(0.08), radius: 12, y: 4)
        )
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(CATTheme.catYellow)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(CATTheme.heading)
        }
        .padding(.top, 4)
    }
}

// MARK: - KPI Strip

private struct KPIStrip: View {
    let kpis: [KPIItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(kpis) { kpi in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kpi.title.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(CATTheme.muted)

                        Text(kpi.value)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(CATTheme.heading)

                        HStack(spacing: 4) {
                            Image(systemName: kpi.trendUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2.weight(.heavy))
                            Text(kpi.trendText)
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(kpi.trendUp
                                      ? CATTheme.success.opacity(0.15)
                                      : CATTheme.critical.opacity(0.15))
                        )
                        .foregroundStyle(kpi.trendUp ? CATTheme.success : CATTheme.critical)

                        Text(kpi.lastUpdated)
                            .font(.caption2)
                            .foregroundStyle(CATTheme.muted)
                    }
                    .frame(width: 180, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(CATTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(CATTheme.cardBorder, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Alert Card

private struct AlertCard: View {
    let alert: DashboardAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: alertIcon)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(alert.severity.rawValue.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                Spacer()
                Circle()
                    .fill(alertColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .fill(alertColor.opacity(0.4))
                            .frame(width: 16, height: 16)
                    )
            }
            .foregroundStyle(alertColor)

            Text(alert.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(CATTheme.heading)
            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(CATTheme.body)
                .lineSpacing(2)

            Button(action: {}) {
                Text(alert.actionTitle)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(alertButtonForeground)
            .background(alertColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [alertColor.opacity(0.5), alertColor.opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1
                        )
                )
                .shadow(color: alertColor.opacity(0.1), radius: 10, y: 4)
        )
    }

    private var alertColor: Color {
        switch alert.severity {
        case .critical: return CATTheme.critical
        case .warning:  return CATTheme.warning
        case .info:     return CATTheme.info
        }
    }

    private var alertButtonForeground: Color {
        switch alert.severity {
        case .critical: return .white
        case .warning:  return CATTheme.catBlack
        case .info:     return .white
        }
    }

    private var alertIcon: String {
        switch alert.severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning:  return "exclamationmark.circle.fill"
        case .info:     return "info.circle.fill"
        }
    }
}

// MARK: - Operational Summary Card

private struct OperationalSummaryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CATTheme.catYellow.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bolt.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CATTheme.catYellow)
                }
                Text("Live Operations")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                Spacer()
                Text("LIVE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(CATTheme.success)
                    .background(
                        Capsule().fill(CATTheme.success.opacity(0.15))
                    )
            }

            HStack(spacing: 0) {
                StatPill(value: "12", label: "Online", color: CATTheme.success)
                StatPill(value: "2", label: "Maintenance", color: CATTheme.warning)
                StatPill(value: "0", label: "Offline", color: CATTheme.critical)
            }

            Divider().overlay(CATTheme.cardBorder)

            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text("Next sync window: 10:30 AM")
                    .font(.caption)
            }
            .foregroundStyle(CATTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
    }
}

private struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.heavy))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(CATTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.06))
        )
    }
}

// MARK: - Inspection Card

private struct InspectionCard: View {
    let inspection: InspectionItem
    let onStartTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(inspection.itemName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(CATTheme.heading)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption)
                        Text(inspection.location)
                            .font(.subheadline)
                    }
                    .foregroundStyle(CATTheme.body)
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)
                        Text("Scheduled: \(inspection.scheduledTime)")
                            .font(.caption)
                    }
                    .foregroundStyle(CATTheme.muted)
                }
                Spacer()
                PriorityBadge(priority: inspection.priority)
            }

            Divider().overlay(CATTheme.cardBorder)

            // Content row
            HStack(alignment: .top, spacing: 14) {
                PartImageView(assetName: inspection.partImageAssetName)

                VStack(alignment: .leading, spacing: 10) {
                    // Sync badge
                    HStack(spacing: 6) {
                        Image(systemName: syncIcon)
                        Text(inspection.syncState.rawValue)
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(syncColor)
                    .background(
                        Capsule().fill(syncColor.opacity(0.12))
                    )

                    Link(destination: inspection.documentationURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                            Text("Part Documentation")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CATTheme.info)
                    }

                    Link(destination: inspection.blueprintURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "ruler.fill")
                            Text("Blueprint Reference")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CATTheme.info)
                    }

                    Spacer()

                    Button(action: onStartTapped) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("Start Inspection")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: CATTheme.catYellow.opacity(0.3), radius: 8, y: 3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        )
    }

    private var syncColor: Color {
        switch inspection.syncState {
        case .synced:  return CATTheme.success
        case .pending: return CATTheme.warning
        case .failed:  return CATTheme.critical
        }
    }

    private var syncIcon: String {
        switch inspection.syncState {
        case .synced:  return "checkmark.circle.fill"
        case .pending: return "clock.badge.exclamationmark"
        case .failed:  return "xmark.octagon.fill"
        }
    }
}

// MARK: - Part Image View

private struct PartImageView: View {
    let assetName: String

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [CATTheme.catCharcoal, CATTheme.card],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    VStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.title3)
                            .foregroundStyle(CATTheme.catYellow.opacity(0.6))
                        Text("Part Image")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(CATTheme.muted)
                    }
                }
            }
        }
        .frame(width: 130, height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CATTheme.catYellow.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Priority Badge

private struct PriorityBadge: View {
    let priority: InspectionPriority

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.caption2)
            Text(priority.rawValue.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(foregroundColor)
        .background(
            Capsule()
                .fill(backgroundColor)
                .overlay(
                    Capsule().stroke(foregroundColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var backgroundColor: Color {
        switch priority {
        case .critical: return CATTheme.critical.opacity(0.15)
        case .high:     return CATTheme.warning.opacity(0.15)
        case .medium:   return CATTheme.success.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch priority {
        case .critical: return CATTheme.critical
        case .high:     return CATTheme.warning
        case .medium:   return CATTheme.success
        }
    }
}

// MARK: - History Card

private struct HistoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CATTheme.success.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(CATTheme.success)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-Day Compliance Trend")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(CATTheme.heading)
                    Text("Last report generated at 07:30 AM")
                        .font(.caption2)
                        .foregroundStyle(CATTheme.muted)
                }
            }

            // Faux mini chart bar visualization
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(["M","T","W","T","F","S","S"], id: \.self) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [CATTheme.catYellow, CATTheme.catYellow.opacity(0.5)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(height: barHeight(for: day))
                        Text(day)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(CATTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 4)

            HStack {
                Text("98.2% pass rate")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CATTheme.success)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.heavy))
                    Text("+1.3% vs prev")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(CATTheme.success)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(CATTheme.success.opacity(0.12)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
    }

    private func barHeight(for day: String) -> CGFloat {
        let heights: [String: CGFloat] = [
            "M": 32, "T": 38, "W": 28, "F": 42, "S": 35
        ]
        return heights[day] ?? 36
    }
}

// MARK: - Offline Banner

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CATTheme.warning.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "wifi.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(CATTheme.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline Mode")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CATTheme.warning)
                Text("Actions will be queued and synced automatically.")
                    .font(.caption)
                    .foregroundStyle(CATTheme.body)
            }
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CATTheme.warning)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CATTheme.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CATTheme.warning.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Placeholder Screen

private struct PlaceholderScreen: View {
    let title: String
    let icon: String
    let subtitle: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(CATTheme.catYellow.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundStyle(CATTheme.catYellow)
                }
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CATTheme.body)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CATTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Create Inspection

private struct CreateInspectionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var serialNumber = ""
    @State private var model = ""
    @State private var serviceMeterValue = ""
    @State private var productFamily = ""
    @State private var make = ""
    @State private var assetID = ""
    @State private var locationMode: InspectionLocationMode = .input
    @State private var locationText = ""

    @State private var ucid = ""
    @State private var customerName = ""
    @State private var customerPhone = ""
    @State private var customerEmail = ""
    @State private var workOrderNumber = ""
    @State private var additionalEmails: [String] = [""]

    @State private var generalInfo = ""
    @State private var comments = ""

    @State private var walkaroundSafetyDecals = false
    @State private var walkaroundLeaks = false
    @State private var walkaroundTiresTracks = false
    @State private var walkaroundAttachments = false
    @State private var walkaroundLights = false
    @State private var walkaroundNotes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CreateSectionCard(title: "Customer & Asset Info", icon: "shippingbox.fill") {
                    VStack(spacing: 10) {
                        CATInputField(title: "Serial Number", text: $serialNumber)
                        CATInputField(title: "Model", text: $model)
                        CATInputField(title: "Service Meter Value", text: $serviceMeterValue, keyboardType: .decimalPad)
                        CATInputField(title: "Product Family", text: $productFamily)
                        CATInputField(title: "Make", text: $make)
                        CATInputField(title: "Asset ID", text: $assetID)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.caption.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(CATTheme.muted)

                            Picker("Location Mode", selection: $locationMode) {
                                Text("Live").tag(InspectionLocationMode.live)
                                Text("Input & Select").tag(InspectionLocationMode.input)
                            }
                            .pickerStyle(.segmented)

                            if locationMode == .live {
                                Button {
                                    locationText = "Using current device location"
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "location.fill")
                                        Text("Use Current Location")
                                            .fontWeight(.semibold)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 46)
                                    .foregroundStyle(CATTheme.catBlack)
                                    .background(CATTheme.headerGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            CATInputField(title: "Location Value", text: $locationText)
                        }

                        Divider().overlay(CATTheme.cardBorder)
                            .padding(.vertical, 4)

                        CATInputField(title: "Customer UCID", text: $ucid)
                        CATInputField(title: "Customer Name", text: $customerName)
                        CATInputField(title: "Phone", text: $customerPhone, keyboardType: .phonePad)
                        CATInputField(title: "Primary Email", text: $customerEmail, keyboardType: .emailAddress)
                        CATInputField(title: "Work Order Number", text: $workOrderNumber)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Additional Emails")
                                    .font(.caption.weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(CATTheme.muted)
                                Spacer()
                                Button {
                                    additionalEmails.append("")
                                } label: {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(CATTheme.catYellow)
                            }

                            ForEach(additionalEmails.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    CATInputField(
                                        title: "Additional Email \(index + 1)",
                                        text: Binding(
                                            get: { additionalEmails[index] },
                                            set: { additionalEmails[index] = $0 }
                                        ),
                                        keyboardType: .emailAddress
                                    )

                                    if additionalEmails.count > 1 {
                                        Button {
                                            additionalEmails.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(CATTheme.critical)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                CreateSectionCard(title: "General Info & Comments", icon: "text.bubble.fill") {
                    VStack(spacing: 10) {
                        CATTextEditorField(title: "General Info", text: $generalInfo, minHeight: 88)
                        CATTextEditorField(title: "Comments", text: $comments, minHeight: 88)
                    }
                }

                CreateSectionCard(title: "Walk Arounds", icon: "figure.walk") {
                    VStack(alignment: .leading, spacing: 8) {
                        CATChecklistRow(title: "Safety Decals / Labels", isOn: $walkaroundSafetyDecals)
                        CATChecklistRow(title: "Leaks / Hoses / Connections", isOn: $walkaroundLeaks)
                        CATChecklistRow(title: "Tires / Tracks Condition", isOn: $walkaroundTiresTracks)
                        CATChecklistRow(title: "Attachments / Couplers", isOn: $walkaroundAttachments)
                        CATChecklistRow(title: "Lights / Signals", isOn: $walkaroundLights)
                        CATTextEditorField(title: "Walk Around Notes", text: $walkaroundNotes, minHeight: 72)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save Inspection Draft")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Create Inspection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private enum InspectionLocationMode: String, CaseIterable {
    case live
    case input
}

private struct CreateSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CATTheme.catYellow)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        )
    }
}

private struct CATInputField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CATTheme.muted)
            TextField("", text: $text)
                .textInputAutocapitalization(.never)
                .keyboardType(keyboardType)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .foregroundStyle(CATTheme.heading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CATTheme.cardElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
        }
    }
}

private struct CATTextEditorField: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(CATTheme.muted)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Enter \(title.lowercased())...")
                        .font(.subheadline)
                        .foregroundStyle(CATTheme.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CATTheme.heading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .frame(minHeight: minHeight)
                    .background(Color.clear)
            }
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CATTheme.cardElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CATTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

private struct CATChecklistRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CATTheme.body)
        }
        .toggleStyle(SwitchToggleStyle(tint: CATTheme.catYellow))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(CATTheme.cardElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
