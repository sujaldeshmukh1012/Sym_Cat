//
//  ContentView.swift
//  CAT Inspect
//
//  Created by Sujal Bhakare on 2/27/26.
//

import SwiftUI
import CoreLocation
import VisionKit
import AVFoundation
import PDFKit
import PhotosUI

// MARK: - Caterpillar Dark Theme

private enum CATTheme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Core brand
    static let catYellow      = Color(red: 1.0,  green: 0.804, blue: 0.067)   // #FFCD11
    static let catYellowDark  = Color(red: 0.85, green: 0.68,  blue: 0.0)     // darker gold
    static let catBlack       = dynamic(light: .init(red: 0.11, green: 0.11, blue: 0.14, alpha: 1),
                                        dark: .init(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
    static let catCharcoal    = dynamic(light: .init(red: 0.98, green: 0.98, blue: 0.99, alpha: 1),
                                        dark: .init(red: 0.11, green: 0.11, blue: 0.14, alpha: 1))

    // Surfaces
    static let background     = dynamic(light: .init(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),
                                        dark: .init(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
    static let card           = dynamic(light: .white,
                                        dark: .init(red: 0.11, green: 0.11, blue: 0.14, alpha: 1))
    static let cardElevated   = dynamic(light: .init(red: 0.94, green: 0.95, blue: 0.97, alpha: 1),
                                        dark: .init(red: 0.14, green: 0.14, blue: 0.18, alpha: 1))
    static let cardBorder     = dynamic(light: .init(red: 0.86, green: 0.88, blue: 0.92, alpha: 1),
                                        dark: UIColor.white.withAlphaComponent(0.06))

    // Text
    static let heading        = dynamic(light: .init(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
                                        dark: .white)
    static let body           = dynamic(light: .init(red: 0.26, green: 0.29, blue: 0.35, alpha: 1),
                                        dark: .init(red: 0.72, green: 0.72, blue: 0.76, alpha: 1))
    static let muted          = dynamic(light: .init(red: 0.44, green: 0.47, blue: 0.53, alpha: 1),
                                        dark: .init(red: 0.45, green: 0.45, blue: 0.50, alpha: 1))

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

private enum RootTab: Hashable {
    case fleet
    case inspections
    case reports
    case profile
}

private enum FleetReportStatus: String, Codable {
    case draft = "Draft"
    case submitted = "Submitted"
}

private struct FleetReportRecord: Identifiable, Hashable {
    let id: UUID
    let sourceInspectionID: UUID?
    let title: String
    let fleetID: String
    let inspectionDate: String
    var status: FleetReportStatus
    let pdfFileName: String
    var inspectorFeedback: String
    var legalSummary: String
    var legalWitnessName: String
    var legalCorrectiveActions: String

    static let dummy: [FleetReportRecord] = [
        FleetReportRecord(
            id: UUID(),
            sourceInspectionID: nil,
            title: "Inspection Report W8210127",
            fleetID: "W8210127",
            inspectionDate: "2025-06-28",
            status: .submitted,
            pdfFileName: "inspection_report_W8210127_20250628 (7) (1).pdf",
            inspectorFeedback: "",
            legalSummary: "All mandatory safety checks completed.",
            legalWitnessName: "Jordan Miles",
            legalCorrectiveActions: "No corrective action required."
        ),
        FleetReportRecord(
            id: UUID(),
            sourceInspectionID: nil,
            title: "Inspection Report X0199334",
            fleetID: "X0199334",
            inspectionDate: "2025-06-17",
            status: .submitted,
            pdfFileName: "inspection_report_W8210127_20250628 (7) (1).pdf",
            inspectorFeedback: "",
            legalSummary: "Routine maintenance findings documented.",
            legalWitnessName: "Anika Ford",
            legalCorrectiveActions: "Hydraulic seal replacement scheduled."
        ),
        FleetReportRecord(
            id: UUID(),
            sourceInspectionID: nil,
            title: "Inspection Report D4401190",
            fleetID: "D4401190",
            inspectionDate: "2025-05-31",
            status: .submitted,
            pdfFileName: "inspection_report_W8210127_20250628 (7) (1).pdf",
            inspectorFeedback: "",
            legalSummary: "Inspection complete and archived.",
            legalWitnessName: "Sam Ortega",
            legalCorrectiveActions: "Cooling fan torque recalibration."
        )
    ]
}

private struct LegalReportFormData {
    var legalSummary: String
    var witnessName: String
    var siteConditions: String
    var correctiveActions: String
    var recommendation: String
    var complianceAcknowledged: Bool
}

@MainActor
private final class ReportStore: ObservableObject {
    @Published var reports: [FleetReportRecord] = []
    private let backend = SupabaseInspectionBackend.shared

    func addDraft(from inspection: FleetInspectionRecord) {
        if reports.contains(where: { $0.sourceInspectionID == inspection.id && $0.status == .draft }) {
            return
        }
        let draft = FleetReportRecord(
            id: UUID(),
            sourceInspectionID: inspection.id,
            title: "Draft Report \(inspection.assetName)",
            fleetID: inspection.assetID.isEmpty ? inspection.serialNumber : inspection.assetID,
            inspectionDate: Self.formatDate(inspection.updatedAt),
            status: .draft,
            pdfFileName: "inspection_report_W8210127_20250628 (7) (1).pdf",
            inspectorFeedback: "",
            legalSummary: "",
            legalWitnessName: "",
            legalCorrectiveActions: ""
        )
        reports.insert(draft, at: 0)
    }

    func createSubmittedReport(from inspection: FleetInspectionRecord, legal: LegalReportFormData) {
        reports.removeAll(where: { $0.sourceInspectionID == inspection.id && $0.status == .draft })
        let report = FleetReportRecord(
            id: UUID(),
            sourceInspectionID: inspection.id,
            title: "Inspection Report \(inspection.assetName)",
            fleetID: inspection.assetID.isEmpty ? inspection.serialNumber : inspection.assetID,
            inspectionDate: Self.formatDate(Date()),
            status: .submitted,
            pdfFileName: "inspection_report_W8210127_20250628 (7) (1).pdf",
            inspectorFeedback: legal.recommendation,
            legalSummary: legal.legalSummary,
            legalWitnessName: legal.witnessName,
            legalCorrectiveActions: legal.correctiveActions
        )
        reports.insert(report, at: 0)
    }

    func createSubmittedReport(
        from inspection: FleetInspectionRecord,
        reportURL: String,
        summary: String
    ) {
        reports.removeAll(where: { $0.sourceInspectionID == inspection.id && $0.status == .draft })
        let report = FleetReportRecord(
            id: UUID(),
            sourceInspectionID: inspection.id,
            title: "Inspection Report \(inspection.assetName)",
            fleetID: inspection.backendFleetID.map(String.init) ?? inspection.serialNumber,
            inspectionDate: Self.formatDate(Date()),
            status: .submitted,
            pdfFileName: reportURL,
            inspectorFeedback: summary,
            legalSummary: inspection.generalInfo,
            legalWitnessName: inspection.inspectorName,
            legalCorrectiveActions: inspection.comments
        )
        reports.insert(report, at: 0)
    }

    func updateInspectorFeedback(reportID: UUID, feedback: String) {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return }
        reports[index].inspectorFeedback = feedback
    }

    func submitDraft(reportID: UUID, legal: LegalReportFormData) {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return }
        reports[index].status = .submitted
        reports[index].legalSummary = legal.legalSummary
        reports[index].legalWitnessName = legal.witnessName
        reports[index].legalCorrectiveActions = legal.correctiveActions
        reports[index].inspectorFeedback = legal.recommendation
    }

    func loadFromBackend() async {
        do {
            let backendReports = try await backend.fetchReportsList().map { item in
                FleetReportRecord(
                    id: UUID(),
                    sourceInspectionID: nil,
                    title: "Inspection Report \(item.fleetSerial)",
                    fleetID: item.fleetSerial,
                    inspectionDate: item.inspectionDate,
                    status: .submitted,
                    pdfFileName: item.reportURL,
                    inspectorFeedback: "",
                    legalSummary: "",
                    legalWitnessName: "",
                    legalCorrectiveActions: ""
                )
            }
            let drafts = reports.filter { $0.status == .draft }
            reports = drafts + backendReports
        } catch {
            // Keep local data if backend load fails.
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct InspectorProfile: Codable {
    var fullName: String
    var employeeID: String
    var roleTitle: String
    var region: String
    var phone: String
    var email: String
    var certificationLevel: String
    var yearsExperience: String
    var shift: String
    var baseLocation: String
    var emergencyContactName: String
    var emergencyContactPhone: String
    var profileImageData: Data?

    static let `default` = InspectorProfile(
        fullName: "Bhanu Reddy",
        employeeID: "CAT-84721",
        roleTitle: "Senior AI Inspection Officer",
        region: "Region C - South Yard",
        phone: "+1 (312) 555-0187",
        email: "bhanu.reddy@catinspect.com",
        certificationLevel: "Level III - Heavy Fleet",
        yearsExperience: "8",
        shift: "Day Shift",
        baseLocation: "Chicago Service Hub",
        emergencyContactName: "Jordan Rivera",
        emergencyContactPhone: "+1 (312) 555-0135",
        profileImageData: nil
    )
}

@MainActor
private final class InspectorProfileStore: ObservableObject {
    @Published var profile: InspectorProfile = .default

    private let storageKey = "catinspect.inspector.profile"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    func save() {
        guard let data = try? encoder.encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode(InspectorProfile.self, from: data) else {
            profile = .default
            return
        }
        profile = decoded
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var inspectionDB = InspectionDatabase()
    @StateObject private var reportStore = ReportStore()
    @StateObject private var profileStore = InspectorProfileStore()
    @StateObject private var connectionManager = BackendConnectionManager.shared
    @AppStorage("catinspect.darkmode.enabled") private var isDarkModeEnabled = false
    @State private var selectedTab: RootTab = .fleet
    @State private var showGlobalSearch = false
    @State private var activeWorkflowInspectionID: UUID?
    @State private var appLoadingMessage: String?
    @State private var appErrorMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FleetHomeView(
                    viewModel: viewModel,
                    profileStore: profileStore,
                    connectionManager: connectionManager,
                    onOpenSearch: { showGlobalSearch = true },
                    onGoToInspections: { selectedTab = .inspections },
                    onInspectFleet: { formData in
                        appLoadingMessage = "Creating inspection..."
                        defer { appLoadingMessage = nil }
                        do {
                            let record = try await inspectionDB.createInspectionFromBackend(from: formData)
                            activeWorkflowInspectionID = record.id
                        } catch {
                            appErrorMessage = error.localizedDescription
                            // For QR/backend flow, do not silently fallback to local default tasks.
                            // This keeps task source strictly tied to fleet todo rows.
                            if formData.backendFleetID == nil {
                                let record = inspectionDB.createInspection(from: formData)
                                activeWorkflowInspectionID = record.id
                            }
                        }
                    },
                    onStartTodayInspection: { inspection in
                        let seed = FleetInspectionFormData(
                            backendFleetID: nil,
                            inspectorName: profileStore.profile.fullName,
                            assetName: inspection.itemName,
                            serialNumber: "",
                            model: "",
                            serviceMeterValue: "",
                            productFamily: "",
                            make: "Caterpillar",
                            assetID: "",
                            location: inspection.location,
                            customerUCID: "",
                            customerName: "",
                            customerPhone: "",
                            customerEmail: "",
                            workOrderNumber: "",
                            additionalEmails: [],
                            generalInfo: "",
                            comments: ""
                        )
                        let record = inspectionDB.createInspection(from: seed)
                        activeWorkflowInspectionID = record.id
                    }
                )
            }
            .tag(RootTab.fleet)
            .tabItem {
                Label("Fleet", systemImage: "car.2.fill")
            }

            NavigationStack {
                InspectionsQueueScreen(
                    viewModel: viewModel,
                    inspectionDB: inspectionDB,
                    onOpenSearch: { showGlobalSearch = true },
                    onStartInspection: { inspectionID in
                        activeWorkflowInspectionID = inspectionID
                    },
                    onStartTodayInspection: { inspection in
                        let seed = FleetInspectionFormData(
                            backendFleetID: nil,
                            inspectorName: profileStore.profile.fullName,
                            assetName: inspection.itemName,
                            serialNumber: "",
                            model: "",
                            serviceMeterValue: "",
                            productFamily: "",
                            make: "Caterpillar",
                            assetID: "",
                            location: inspection.location,
                            customerUCID: "",
                            customerName: "",
                            customerPhone: "",
                            customerEmail: "",
                            workOrderNumber: "",
                            additionalEmails: [],
                            generalInfo: "",
                            comments: ""
                        )
                        let record = inspectionDB.createInspection(from: seed)
                        activeWorkflowInspectionID = record.id
                    }
                )
            }
            .tag(RootTab.inspections)
            .tabItem {
                Label("Inspections", systemImage: "checklist")
            }

            NavigationStack {
                ReportsScreen(
                    reportStore: reportStore,
                    onOpenSearch: { showGlobalSearch = true }
                )
            }
            .tag(RootTab.reports)
            .tabItem {
                Label("Reports", systemImage: "doc.richtext")
            }

            NavigationStack {
                ProfileScreen(
                    isDarkModeEnabled: $isDarkModeEnabled,
                    profileStore: profileStore,
                    connectionManager: connectionManager
                )
            }
            .tag(RootTab.profile)
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
        .tint(CATTheme.catYellow)
        .preferredColorScheme(isDarkModeEnabled ? .dark : .light)
        .overlay {
            if let appLoadingMessage {
                CATBlockingLoadingOverlay(message: appLoadingMessage)
            }
        }
        .alert(
            "Backend Notice",
            isPresented: Binding(
                get: { appErrorMessage != nil },
                set: { if !$0 { appErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appErrorMessage = nil }
        } message: {
            Text(appErrorMessage ?? "")
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { activeWorkflowInspectionID != nil },
                set: { if !$0 { activeWorkflowInspectionID = nil } }
            )
        ) {
            if let inspectionID = activeWorkflowInspectionID {
                FleetInspectionWorkflowView(
                    inspectionID: inspectionID,
                    inspectionDB: inspectionDB,
                    reportStore: reportStore,
                    appLoadingMessage: $appLoadingMessage,
                    appErrorMessage: $appErrorMessage
                ) {
                    activeWorkflowInspectionID = nil
                }
            }
        }
        .sheet(isPresented: $showGlobalSearch) {
            NavigationStack {
                GlobalSearchScreen(
                    viewModel: viewModel,
                    inspectionDB: inspectionDB,
                    reportStore: reportStore
                )
            }
        }
        .task(id: profileStore.profile.fullName + profileStore.profile.region) {
            viewModel.setInspectorProfile(name: profileStore.profile.fullName, region: profileStore.profile.region)
            await viewModel.loadIfNeeded()
            await reportStore.loadFromBackend()
            // Connect WebSocket to local FastAPI
            connectionManager.connect()
        }
    }
}

// MARK: - Fleet Home

private struct FleetHomeView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var profileStore: InspectorProfileStore
    @ObservedObject var connectionManager: BackendConnectionManager
    let onOpenSearch: () -> Void
    let onGoToInspections: () -> Void
    let onInspectFleet: (FleetInspectionFormData) async -> Void
    let onStartTodayInspection: (InspectionItem) -> Void
    @StateObject private var locationService = LocationPrefillService()
    @State private var showingFleetScanner = false
    @State private var scannedFleetCode = ""
    @State private var showingCreateInspection = false
    @State private var showLocationChoice = false
    @State private var prefilledLocation = ""
    @State private var prefilledLocationMode: InspectionLocationMode = .input
    @State private var showConnectionFailureAlert = false
    @State private var connectionFailureAcknowledged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView().tint(CATTheme.catYellow)
                        Text("Loading dashboard...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CATTheme.body)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CATTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(CATTheme.cardBorder, lineWidth: 1)
                            )
                    )
                }

                if !connectionManager.state.isConnected {
                    OfflineBanner()
                }

                HeaderCard(
                    profile: profileStore.profile,
                    isBackendConnected: connectionManager.state.isConnected
                )

                SectionHeader(title: "Fleet Actions", icon: "square.grid.2x2.fill")
                VStack(spacing: 12) {
                    ActionCardButton(title: "Create Inspection", icon: "plus.circle.fill", foreground: CATTheme.catBlack, background: AnyShapeStyle(CATTheme.headerGradient)) {
                        showLocationChoice = true
                    }
                    HStack(spacing: 10) {
                        ActionCardButton(title: "Search Fleet", icon: "magnifyingglass", foreground: CATTheme.heading, background: AnyShapeStyle(CATTheme.cardElevated)) {
                            onOpenSearch()
                        }
                        ActionCardButton(title: "Scan Fleet QR", icon: "qrcode.viewfinder", foreground: CATTheme.heading, background: AnyShapeStyle(CATTheme.cardElevated)) {
                            showingFleetScanner = true
                        }
                    }
                }

                SectionHeader(title: "Today's Inspections", icon: "wrench.and.screwdriver.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.todaysInspections) { inspection in
                            TodayInspectionTile(inspection: inspection) {
                                onStartTodayInspection(inspection)
                            }
                        }
                    }
                }
                if !viewModel.isLoading && viewModel.todaysInspections.isEmpty {
                    Text("No backend inspections available right now.")
                        .font(.caption)
                        .foregroundStyle(CATTheme.muted)
                }

                ActionCardButton(title: "Open Inspections Screen", icon: "arrow.right.circle.fill", foreground: CATTheme.catBlack, background: AnyShapeStyle(CATTheme.headerGradient)) {
                    onGoToInspections()
                }

                if !scannedFleetCode.isEmpty {
                    Text("Scanned Fleet: \(scannedFleetCode)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CATTheme.success)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .refreshable {
            await viewModel.refresh()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CATNavTitle()
            }
        }
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("Location For New Inspection", isPresented: $showLocationChoice, titleVisibility: .visible) {
            Button("Use Current Location") {
                locationService.requestCurrentLocation { locationValue in
                    prefilledLocation = locationValue
                    prefilledLocationMode = .live
                    showingCreateInspection = true
                }
            }
            Button("Enter Manually") {
                prefilledLocation = ""
                prefilledLocationMode = .input
                showingCreateInspection = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how you want to fill location for this inspection.")
        }
        .sheet(isPresented: $showingCreateInspection) {
            NavigationStack {
                CreateInspectionView(
                    initialLocation: prefilledLocation,
                    initialLocationMode: prefilledLocationMode,
                    inspectorName: profileStore.profile.fullName,
                    onInspectFleet: onInspectFleet
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFleetScanner) {
            NavigationStack {
                InspectionScannerView(mode: .assetQR) { value in
                    scannedFleetCode = value
                }
            }
        }
        .onChange(of: connectionManager.state) { oldState, newState in
            if newState.isConnected {
                viewModel.connectionOffline = false
                connectionFailureAcknowledged = false
                showConnectionFailureAlert = false
                return
            }

            let isFailureState: Bool
            switch newState {
            case .reconnecting, .disconnected:
                isFailureState = true
                viewModel.connectionOffline = true
            case .connecting, .connected:
                isFailureState = false
            }

            if isFailureState && !connectionFailureAcknowledged {
                showConnectionFailureAlert = true
            }
        }
        .alert("Backend Connection Failed", isPresented: $showConnectionFailureAlert) {
            Button("Retry") {
                connectionFailureAcknowledged = false
                connectionManager.connect()
            }
            Button("OK", role: .cancel) {
                connectionFailureAcknowledged = true
            }
        } message: {
            Text("Unable to reach the backend right now.")
        }
    }
}

private struct CATNavTitle: View {
    var body: some View {
        Group {
            if UIImage(named: "cat_logo") != nil {
                Image("cat_logo")
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
        .frame(width: 50, height: 50)
        
    }
}

// MARK: - Header Card

private struct HeaderCard: View {
    let profile: InspectorProfile
    let isBackendConnected: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("INSPECTOR")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(CATTheme.catYellow)
                Text(profile.fullName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(profile.region)
                        .font(.subheadline)
                }
                .foregroundStyle(CATTheme.muted)
                Text("\(profile.roleTitle) • \(profile.employeeID)")
                    .font(.caption2)
                    .foregroundStyle(CATTheme.body)
            }

            Spacer()

            InspectorAvatarSquare(
                imageData: profile.profileImageData,
                initials: profile.fullName.initials,
                isBackendConnected: isBackendConnected
            )
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

private struct InspectorAvatarSquare: View {
    let imageData: Data?
    let initials: String
    let isBackendConnected: Bool
    var size: CGFloat = 62

    init(
        imageData: Data?,
        initials: String = "",
        isBackendConnected: Bool = false,
        size: CGFloat = 62
    ) {
        self.imageData = imageData
        self.initials = initials
        self.isBackendConnected = isBackendConnected
        self.size = size
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        CATTheme.headerGradient
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CATTheme.catBlack)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CATTheme.catYellow.opacity(0.35), lineWidth: 1.2)
            )

            Circle()
                .fill(isBackendConnected ? CATTheme.success : CATTheme.critical)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(CATTheme.card, lineWidth: 1)
                )
        }
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

private struct CATBlockingLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(CATTheme.catYellow)
                    .scaleEffect(1.1)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CATTheme.heading)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: 260)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(CATTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(CATTheme.cardBorder, lineWidth: 1)
                    )
            )
        }
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

private struct InspectionsQueueScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var inspectionDB: InspectionDatabase
    let onOpenSearch: () -> Void
    let onStartInspection: (UUID) -> Void
    let onStartTodayInspection: (InspectionItem) -> Void
    @State private var showPrevious = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().tint(CATTheme.catYellow)
                        Text("Loading inspections...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CATTheme.body)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(CATTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(CATTheme.cardBorder, lineWidth: 1)
                            )
                    )
                }
                SearchBarButton(title: "Search Fleet / Inspection / Report") {
                    onOpenSearch()
                }

                SectionHeader(title: "Inspections To Do", icon: "list.clipboard.fill")
                ForEach(viewModel.todaysInspections) { inspection in
                    InspectionQueueRow(
                        title: inspection.itemName,
                        subtitle: "\(inspection.location) • \(inspection.priority.rawValue)",
                        buttonTitle: "Start Workflow"
                    ) {
                        onStartTodayInspection(inspection)
                    }
                }

                DisclosureGroup(isExpanded: $showPrevious) {
                    if inspectionDB.inspections.isEmpty {
                        Text("No previous inspections yet.")
                            .font(.subheadline)
                            .foregroundStyle(CATTheme.muted)
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(inspectionDB.inspections) { record in
                                InspectionQueueRow(
                                    title: record.assetName,
                                    subtitle: "\(record.location) • \(record.tasks.filter { $0.completed }.count)/\(record.tasks.count) tasks",
                                    buttonTitle: "Open"
                                ) {
                                    onStartInspection(record.id)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                } label: {
                    HStack {
                        Text("Previous Inspections")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CATTheme.heading)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CATTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(CATTheme.cardBorder, lineWidth: 1)
                            )
                    )
                }
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Inspections")
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct InspectionQueueRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(CATTheme.body)
            }
            Spacer()
            Button(action: action) {
                Text(buttonTitle)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(Capsule().fill(CATTheme.headerGradient))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct ReportsScreen: View {
    @ObservedObject var reportStore: ReportStore
    let onOpenSearch: () -> Void
    @State private var selectedReport: FleetReportRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SearchBarButton(title: "Search Fleet / Inspection / Report") {
                    onOpenSearch()
                }
                SectionHeader(title: "Fleet Reports (PDF)", icon: "doc.text.fill")
                ForEach(reportStore.reports) { report in
                    Button {
                        selectedReport = report
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.richtext.fill")
                                .foregroundStyle(CATTheme.catYellow)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(CATTheme.heading)
                                Text("Fleet \(report.fleetID) • \(report.inspectionDate) • \(report.status.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(CATTheme.body)
                            }
                            Spacer()
                            Circle()
                                .fill(report.status == .draft ? CATTheme.warning : CATTheme.success)
                                .frame(width: 9, height: 9)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(CATTheme.muted)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CATTheme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Reports")
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await reportStore.loadFromBackend()
        }
        .sheet(item: $selectedReport) { report in
            NavigationStack {
                ReportDetailScreen(
                    report: report,
                    feedback: report.inspectorFeedback,
                    onSubmitDraft: { form in
                        reportStore.submitDraft(reportID: report.id, legal: form)
                    },
                    onSend: { feedback in
                        reportStore.updateInspectorFeedback(reportID: report.id, feedback: feedback)
                    }
                )
            }
        }
    }
}

private struct ReportDetailScreen: View {
    let report: FleetReportRecord
    @State var feedback: String
    let onSubmitDraft: (LegalReportFormData) -> Void
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sent = false
    @State private var legalSummary = ""
    @State private var witnessName = ""
    @State private var siteConditions = ""
    @State private var correctiveActions = ""
    @State private var recommendation = ""
    @State private var complianceAcknowledged = false

    var body: some View {
        VStack(spacing: 12) {
            if report.status == .draft {
                Text("Draft report is not submitted yet. Complete required legal details.")
                    .font(.subheadline)
                    .foregroundStyle(CATTheme.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CATTextEditorField(title: "Incident / Condition Summary", text: $legalSummary, minHeight: 72)
                CATInputField(title: "Witness / Approver Name", text: $witnessName)
                CATTextEditorField(title: "Site Conditions", text: $siteConditions, minHeight: 60)
                CATTextEditorField(title: "Corrective Actions", text: $correctiveActions, minHeight: 72)
                CATTextEditorField(title: "Final Recommendation", text: $recommendation, minHeight: 72)
                Toggle(isOn: $complianceAcknowledged) {
                    Text("I confirm legal/compliance data is complete.")
                        .font(.subheadline)
                        .foregroundStyle(CATTheme.body)
                }
                .toggleStyle(SwitchToggleStyle(tint: CATTheme.catYellow))

                Button {
                    let form = LegalReportFormData(
                        legalSummary: legalSummary,
                        witnessName: witnessName,
                        siteConditions: siteConditions,
                        correctiveActions: correctiveActions,
                        recommendation: recommendation,
                        complianceAcknowledged: complianceAcknowledged
                    )
                    onSubmitDraft(form)
                    dismiss()
                } label: {
                    Label("Submit Draft", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!complianceAcknowledged || legalSummary.isEmpty || witnessName.isEmpty)
                .opacity((!complianceAcknowledged || legalSummary.isEmpty || witnessName.isEmpty) ? 0.5 : 1.0)
            } else {
                Group {
                    if let pdfURL = reportPDFURL(fileName: report.pdfFileName) {
                        PDFDocumentView(url: pdfURL)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(CATTheme.catYellow)
                            Text(report.pdfFileName)
                                .font(.caption)
                                .foregroundStyle(CATTheme.body)
                            Text("PDF preview placeholder")
                                .font(.caption2)
                                .foregroundStyle(CATTheme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CATTheme.cardElevated)
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                CATTextEditorField(title: "Inspector Feedback", text: $feedback, minHeight: 70)
                Button {
                    onSend(feedback)
                    sent = true
                } label: {
                    Label("Send Feedback", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if sent {
                    Text("Report feedback sent.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CATTheme.success)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
    }
}

private struct LegalReportFormView: View {
    let inspection: FleetInspectionRecord
    let onSubmit: (LegalReportFormData) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var legalSummary = ""
    @State private var witnessName = ""
    @State private var siteConditions = ""
    @State private var correctiveActions = ""
    @State private var recommendation = ""
    @State private var complianceAcknowledged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Legal Report Details")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(CATTheme.heading)
                Text("Fleet: \(inspection.assetName) • \(inspection.location)")
                    .font(.caption)
                    .foregroundStyle(CATTheme.body)

                CATTextEditorField(title: "Incident / Condition Summary", text: $legalSummary, minHeight: 72)
                CATInputField(title: "Witness / Approver Name", text: $witnessName)
                CATTextEditorField(title: "Site Conditions", text: $siteConditions, minHeight: 60)
                CATTextEditorField(title: "Corrective Actions", text: $correctiveActions, minHeight: 72)
                CATTextEditorField(title: "Final Recommendation", text: $recommendation, minHeight: 72)

                Toggle(isOn: $complianceAcknowledged) {
                    Text("I confirm this report follows legal/compliance requirements.")
                        .font(.subheadline)
                        .foregroundStyle(CATTheme.body)
                }
                .toggleStyle(SwitchToggleStyle(tint: CATTheme.catYellow))

                Button {
                    let form = LegalReportFormData(
                        legalSummary: legalSummary,
                        witnessName: witnessName,
                        siteConditions: siteConditions,
                        correctiveActions: correctiveActions,
                        recommendation: recommendation,
                        complianceAcknowledged: complianceAcknowledged
                    )
                    onSubmit(form)
                    dismiss()
                } label: {
                    Label("Create Legal Report", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!complianceAcknowledged || legalSummary.isEmpty || witnessName.isEmpty)
                .opacity((!complianceAcknowledged || legalSummary.isEmpty || witnessName.isEmpty) ? 0.5 : 1.0)
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Create Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
    }
}

private struct StructuredReportComposerView: View {
    let inspection: FleetInspectionRecord
    let onSubmit: (StructuredInspectionReportFormData) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var generalInfo: String
    @State private var comments: String
    @State private var taskInputs: [StructuredTaskReportInput]
    @State private var signatureStrokes: [[CGPoint]] = []
    @State private var isSubmitting = false

    init(
        inspection: FleetInspectionRecord,
        onSubmit: @escaping (StructuredInspectionReportFormData) async -> Void
    ) {
        self.inspection = inspection
        self.onSubmit = onSubmit
        _generalInfo = State(initialValue: inspection.generalInfo)
        _comments = State(initialValue: inspection.comments)
        let seededTasks = inspection.tasks
            .sorted(by: { $0.taskNumber < $1.taskNumber })
            .map { task in
                StructuredTaskReportInput(
                    id: task.id,
                    backendTaskID: task.backendTaskID,
                    taskNumber: task.taskNumber,
                    sourceTitle: task.title,
                    summaryTitle: Self.prepopulateSummary(title: task.title, detail: task.detail),
                    status: task.walkthroughStatus,
                    taskFeedback: task.feedbackText
                )
            }
        _taskInputs = State(initialValue: seededTasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                CreateSectionCard(title: "Inspection Snapshot", icon: "lock.shield.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        nonEditableRow("Inspection Number", inspection.backendInspectionID.map(String.init) ?? inspection.id.uuidString)
                        nonEditableRow("Serial Number (fleet_serial)", inspection.backendFleetID.map(String.init) ?? inspection.serialNumber)
                        nonEditableRow("Inspector", inspection.inspectorName)
                        nonEditableRow("Location", inspection.location.isEmpty ? "N/A" : inspection.location)
                    }
                }

                CreateSectionCard(title: "General Info & Comments", icon: "text.alignleft") {
                    VStack(spacing: 10) {
                        CATTextEditorField(title: "General Info", text: $generalInfo, minHeight: 90)
                        CATTextEditorField(title: "Comments", text: $comments, minHeight: 90)
                    }
                }

                CreateSectionCard(title: "Task Status Matrix", icon: "list.bullet.clipboard.fill") {
                    VStack(spacing: 10) {
                        ForEach(taskInputs.indices, id: \.self) { index in
                            let matchingTask = inspection.tasks.first(where: { $0.id == taskInputs[index].id })
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Task \(taskInputs[index].taskNumber)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CATTheme.muted)
                                if let matchingTask, !matchingTask.photoFileNames.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(matchingTask.photoFileNames, id: \.self) { photo in
                                                TaskPhotoThumb(fileName: photo)
                                            }
                                        }
                                    }
                                    .frame(height: 56)
                                }
                                CATInputField(
                                    title: "Summarized Title",
                                    text: Binding(
                                        get: { taskInputs[index].summaryTitle },
                                        set: { taskInputs[index].summaryTitle = $0 }
                                    )
                                )
                                Picker(
                                    "Status",
                                    selection: Binding(
                                        get: { taskInputs[index].status },
                                        set: { taskInputs[index].status = $0 }
                                    )
                                ) {
                                    ForEach(TaskReportStatus.allCases, id: \.self) { state in
                                        Text(state.rawValue).tag(state)
                                    }
                                }
                                .pickerStyle(.segmented)
                                CATTextEditorField(
                                    title: "Task Feedback",
                                    text: Binding(
                                        get: { taskInputs[index].taskFeedback },
                                        set: { taskInputs[index].taskFeedback = $0 }
                                    ),
                                    minHeight: 54
                                )
                            }
                            .padding(10)
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
                }

                CreateSectionCard(title: "Digital Signature", icon: "signature") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign in the area below.")
                            .font(.caption)
                            .foregroundStyle(CATTheme.body)
                        SignaturePadView(strokes: $signatureStrokes)
                            .frame(height: 160)
                        HStack {
                            Spacer()
                            Button("Clear Signature") {
                                signatureStrokes.removeAll()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CATTheme.warning)
                        }
                    }
                }

                Button {
                    let signatureVector = SignatureVectorEncoder.encode(strokes: signatureStrokes)
                    let payload = StructuredInspectionReportFormData(
                        generalInfo: generalInfo,
                        comments: comments,
                        taskInputs: taskInputs,
                        signatureVector: signatureVector
                    )
                    isSubmitting = true
                    Task {
                        await onSubmit(payload)
                        isSubmitting = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(CATTheme.catBlack)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSubmitting ? "Submitting..." : "Submit Report")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(signatureStrokes.isEmpty || isSubmitting)
                .opacity(signatureStrokes.isEmpty || isSubmitting ? 0.55 : 1.0)
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Generate Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
    }

    private func nonEditableRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(CATTheme.muted)
            Text(value.isEmpty ? "N/A" : value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CATTheme.heading)
        }
    }

    private static func prepopulateSummary(title: String, detail: String) -> String {
        // LLM prepopulate hook: replace with AI summary endpoint when available.
        let seed = title.isEmpty ? detail : title
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 56 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 56)
        return String(trimmed[..<end]) + "..."
    }
}

private struct SignaturePadView: View {
    @Binding var strokes: [[CGPoint]]
    @State private var activeStroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(CATTheme.cardElevated)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CATTheme.cardBorder, lineWidth: 1)

                Path { path in
                    for stroke in strokes {
                        guard let first = stroke.first else { continue }
                        path.move(to: first)
                        for point in stroke.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    if let first = activeStroke.first {
                        path.move(to: first)
                        for point in activeStroke.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(CATTheme.heading, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = CGPoint(
                            x: min(max(0, value.location.x), geo.size.width),
                            y: min(max(0, value.location.y), geo.size.height)
                        )
                        activeStroke.append(point)
                    }
                    .onEnded { _ in
                        if !activeStroke.isEmpty {
                            strokes.append(activeStroke)
                        }
                        activeStroke = []
                    }
            )
        }
    }
}

private enum SignatureVectorEncoder {
    static func encode(strokes: [[CGPoint]]) -> String {
        let rows = strokes.map { stroke in
            stroke.map { point in "\(Int(point.x)),\(Int(point.y))" }.joined(separator: ";")
        }
        return rows.joined(separator: "|")
    }
}

private struct GlobalSearchScreen: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var inspectionDB: InspectionDatabase
    @ObservedObject var reportStore: ReportStore
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Fleet") {
                ForEach(filteredFleet, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(CATTheme.heading)
                        Text(item.subtitle).font(.caption).foregroundStyle(CATTheme.body)
                    }
                }
            }
            Section("Inspections") {
                ForEach(filteredInspections, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(CATTheme.heading)
                        Text(item.subtitle).font(.caption).foregroundStyle(CATTheme.body)
                    }
                }
            }
            Section("Reports") {
                ForEach(filteredReports, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).foregroundStyle(CATTheme.heading)
                        Text(item.subtitle).font(.caption).foregroundStyle(CATTheme.body)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search fleet, inspections, reports")
        .scrollContentBackground(.hidden)
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Global Search")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
    }

    private var filteredFleet: [SearchRowItem] {
        let items = inspectionDB.inspections.map {
            SearchRowItem(title: $0.assetName, subtitle: "Fleet • \($0.location)")
        }
        return filter(items)
    }

    private var filteredInspections: [SearchRowItem] {
        let items = viewModel.todaysInspections.map {
            SearchRowItem(title: $0.itemName, subtitle: "Inspection • \($0.location)")
        }
        return filter(items)
    }

    private var filteredReports: [SearchRowItem] {
        let items = reportStore.reports.map {
            SearchRowItem(title: $0.title, subtitle: "Report • Fleet \($0.fleetID)")
        }
        return filter(items)
    }

    private func filter(_ items: [SearchRowItem]) -> [SearchRowItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }
}

private struct SearchRowItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private struct SearchBarButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(title)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .foregroundStyle(CATTheme.body)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(CATTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(CATTheme.cardBorder, lineWidth: 1)
                    )
            )
        }
    }
}

private struct ActionCardButton: View {
    let title: String
    let icon: String
    let foreground: Color
    let background: AnyShapeStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).fontWeight(.bold)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CATTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

private struct TodayInspectionTile: View {
    let inspection: InspectionItem
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(inspection.itemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CATTheme.heading)
            Text(inspection.location)
                .font(.caption)
                .foregroundStyle(CATTheme.body)
            Text(inspection.priority.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CATTheme.warning)
            Button("Start") { onStart() }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(CATTheme.catBlack)
                .background(CATTheme.headerGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CATTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        var lastURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        loadPDF(into: pdfView, context: context)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if context.coordinator.lastURL != url {
            loadPDF(into: uiView, context: context)
        }
    }

    private func loadPDF(into view: PDFView, context: Context) {
        context.coordinator.lastURL = url
        if url.isFileURL {
            view.document = PDFDocument(url: url)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard context.coordinator.lastURL == url, let data else { return }
            let document = PDFDocument(data: data)
            DispatchQueue.main.async {
                if context.coordinator.lastURL == url {
                    view.document = document
                }
            }
        }.resume()
    }
}

private func reportPDFURL(fileName: String) -> URL? {
    if let directURL = URL(string: fileName),
       let scheme = directURL.scheme?.lowercased(),
       scheme == "http" || scheme == "https" || scheme == "file" {
        return directURL
    }
    if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
        return bundleURL
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    let docURL = (docs ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(fileName)
    if FileManager.default.fileExists(atPath: docURL.path) {
        return docURL
    }
    return nil
}

// MARK: - Create Inspection

private struct CreateInspectionView: View {
    @Environment(\.dismiss) private var dismiss
    let inspectorName: String
    let onInspectFleet: (FleetInspectionFormData) async -> Void
    @State private var showingScanner = false
    @State private var scanMode: ScanMode = .assetQR
    @State private var isSubmitting = false

    @State private var backendFleetID: Int64?
    @State private var fleetName = ""
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

    init(
        initialLocation: String = "",
        initialLocationMode: InspectionLocationMode = .input,
        inspectorName: String,
        onInspectFleet: @escaping (FleetInspectionFormData) async -> Void
    ) {
        self.inspectorName = inspectorName
        self.onInspectFleet = onInspectFleet
        _locationText = State(initialValue: initialLocation)
        _locationMode = State(initialValue: initialLocationMode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CreateSectionCard(title: "Scan Asset", icon: "viewfinder") {
                    HStack(spacing: 10) {
                        Button {
                            scanMode = .assetQR
                            showingScanner = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                Text("Asset QR")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .foregroundStyle(CATTheme.catBlack)
                            .background(CATTheme.headerGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            scanMode = .catPIN
                            showingScanner = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                Text("CAT PIN")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity, minHeight: 46)
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

                CreateSectionCard(title: "Customer & Asset Info", icon: "shippingbox.fill") {
                    VStack(spacing: 10) {
                        CATInputField(title: "Fleet Name", text: $fleetName)
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

                Button {
                    isSubmitting = true
                    Task {
                        await onInspectFleet(
                            FleetInspectionFormData(
                                backendFleetID: backendFleetID,
                                inspectorName: inspectorName,
                                assetName: fleetName.isEmpty ? (model.isEmpty ? "Fleet Asset" : model) : fleetName,
                                serialNumber: serialNumber,
                                model: model,
                                serviceMeterValue: serviceMeterValue,
                                productFamily: productFamily,
                                make: make,
                                assetID: assetID,
                                location: locationText,
                                customerUCID: ucid,
                                customerName: customerName,
                                customerPhone: customerPhone,
                                customerEmail: customerEmail,
                                workOrderNumber: workOrderNumber,
                                additionalEmails: additionalEmails,
                                generalInfo: generalInfo,
                                comments: comments
                            )
                        )
                        isSubmitting = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(CATTheme.catBlack)
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                        }
                        Text(isSubmitting ? "Creating..." : "Inspect Fleet")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.7 : 1.0)
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
        .sheet(isPresented: $showingScanner) {
            InspectionScannerView(mode: scanMode) { scannedValue in
                applyScannedValue(scannedValue)
            }
        }
    }

    private func applyScannedValue(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        switch scanMode {
        case .catPIN:
            assetID = value
            if serialNumber.isEmpty {
                serialNumber = value
            }
        case .assetQR:
            let parsed = parseScannedFleetJSON(value) ?? parseScannedPairs(value)
            if let idValue = parsed["ID"], let id = Int64(idValue) {
                backendFleetID = id
            }
            if backendFleetID == nil, let serialID = parsed["FLEETSERIAL"], let id = Int64(serialID) {
                backendFleetID = id
            }
            if let val = parsed["NAME"], model.isEmpty { model = val }
            if let val = parsed["NAME"] { fleetName = val }
            if let val = parsed["SN"] ?? parsed["SERIAL"] ?? parsed["SERIALNUMBER"] { serialNumber = val }
            if let val = parsed["MODEL"] { model = val }
            if let val = parsed["SMU"] ?? parsed["SERVICEMETER"] { serviceMeterValue = val }
            if let val = parsed["FAMILY"] ?? parsed["PRODUCTFAMILY"] ?? parsed["TYPE"] { productFamily = val }
            if let val = parsed["MAKE"] { make = val }
            if let val = parsed["ASSET"] ?? parsed["ASSETID"] { assetID = val }
            if let val = parsed["LOCATION"] {
                locationText = val
                locationMode = .input
            }
            if let val = parsed["CUSTOMERNAME"] { customerName = val }
            if let val = parsed["CUSTOMERID"] ?? parsed["UCID"] { ucid = val }
            if let val = parsed["WORKORDER"] ?? parsed["WORKORDERNUMBER"] { workOrderNumber = val }
            if let val = parsed["CUSTOMEREMAIL"] { customerEmail = val }
            if let val = parsed["CUSTOMERPHONE"] { customerPhone = val }
            if parsed.isEmpty {
                if serialNumber.isEmpty {
                    serialNumber = value
                } else {
                    assetID = value
                }
            }
        }
    }

    private func parseScannedPairs(_ value: String) -> [String: String] {
        let components = value.split(separator: ";")
        var map: [String: String] = [:]
        for component in components {
            let pair = component.split(separator: ":", maxSplits: 1).map { String($0) }
            guard pair.count == 2 else { continue }
            map[pair[0].uppercased().replacingOccurrences(of: " ", with: "")] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    private func parseScannedFleetJSON(_ value: String) -> [String: String]? {
        let normalized = normalizeScannedJSONPayload(value)
        guard let data = normalized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let dictionary: [String: Any]
        if let map = object as? [String: Any] {
            dictionary = map
        } else if let array = object as? [[String: Any]], let first = array.first {
            dictionary = first
        } else {
            return nil
        }

        var output: [String: String] = [:]
        for (key, raw) in dictionary {
            let normalized = key.uppercased().replacingOccurrences(of: "_", with: "")
            if let stringValue = raw as? String {
                output[normalized] = stringValue
            } else if let numberValue = raw as? NSNumber {
                output[normalized] = numberValue.stringValue
            } else if let dictValue = raw as? [String: Any] {
                for (nestedKey, nestedRaw) in dictValue {
                    let nestedNorm = "\(normalized)\(nestedKey.uppercased().replacingOccurrences(of: "_", with: ""))"
                    if let nestedString = nestedRaw as? String {
                        output[nestedNorm] = nestedString
                    } else if let nestedNumber = nestedRaw as? NSNumber {
                        output[nestedNorm] = nestedNumber.stringValue
                    }
                }
            }
        }
        return output
    }

    private func normalizeScannedJSONPayload(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            let start = trimmed.index(after: trimmed.startIndex)
            let end = trimmed.index(before: trimmed.endIndex)
            let inner = String(trimmed[start..<end])
            return inner.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return trimmed
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

private extension String {
    var initials: String {
        let comps = split(separator: " ")
        let letters = comps.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "IN" : String(letters).uppercased()
    }
}

private extension Binding where Value == InspectorProfile {
    var fullName: Binding<String> { .init(get: { wrappedValue.fullName }, set: { wrappedValue.fullName = $0 }) }
    var employeeID: Binding<String> { .init(get: { wrappedValue.employeeID }, set: { wrappedValue.employeeID = $0 }) }
    var roleTitle: Binding<String> { .init(get: { wrappedValue.roleTitle }, set: { wrappedValue.roleTitle = $0 }) }
    var region: Binding<String> { .init(get: { wrappedValue.region }, set: { wrappedValue.region = $0 }) }
    var phone: Binding<String> { .init(get: { wrappedValue.phone }, set: { wrappedValue.phone = $0 }) }
    var email: Binding<String> { .init(get: { wrappedValue.email }, set: { wrappedValue.email = $0 }) }
    var certificationLevel: Binding<String> { .init(get: { wrappedValue.certificationLevel }, set: { wrappedValue.certificationLevel = $0 }) }
    var yearsExperience: Binding<String> { .init(get: { wrappedValue.yearsExperience }, set: { wrappedValue.yearsExperience = $0 }) }
    var shift: Binding<String> { .init(get: { wrappedValue.shift }, set: { wrappedValue.shift = $0 }) }
    var baseLocation: Binding<String> { .init(get: { wrappedValue.baseLocation }, set: { wrappedValue.baseLocation = $0 }) }
    var emergencyContactName: Binding<String> { .init(get: { wrappedValue.emergencyContactName }, set: { wrappedValue.emergencyContactName = $0 }) }
    var emergencyContactPhone: Binding<String> { .init(get: { wrappedValue.emergencyContactPhone }, set: { wrappedValue.emergencyContactPhone = $0 }) }
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

private struct FleetInspectionWorkflowView: View {
    let inspectionID: UUID
    @ObservedObject var inspectionDB: InspectionDatabase
    @ObservedObject var reportStore: ReportStore
    @Binding var appLoadingMessage: String?
    @Binding var appErrorMessage: String?
    let onClose: () -> Void

    @StateObject private var cameraService = FleetCameraService()
    @StateObject private var voiceService = VoiceFeedbackService()
    @State private var walkAroundActive = false
    @State private var selectedTaskID: UUID?
    @State private var feedbackText = ""
    @State private var selectedWalkthroughStatus: TaskReportStatus = .normal
    @State private var capturedPhotoFileNames: [String] = []
    @State private var selectedPreviewPhotoFileName: String?
    @State private var sendStatusText = ""
    @State private var isTaskSyncing = false
    @State private var showReportComposer = false

    private var record: FleetInspectionRecord? {
        inspectionDB.record(for: inspectionID)
    }

    private var currentTask: FleetTaskRecord? {
        guard let record else { return nil }
        if let selectedTaskID,
           let task = record.tasks.first(where: { $0.id == selectedTaskID }) {
            return task
        }
        return record.tasks.first
    }

    private var allTasksCompleted: Bool {
        guard let record else { return false }
        return !record.tasks.isEmpty && record.tasks.allSatisfy(\.completed)
    }

    var body: some View {
        ZStack {
            FleetCameraPreview(session: cameraService.session)
                .ignoresSafeArea()

            Color.black.opacity(0.12).ignoresSafeArea()

            VStack(spacing: 0) {
                topOverlay
                Spacer()
                bottomOverlay
            }
        }
        .onAppear {
            cameraService.start()
            if selectedTaskID == nil {
                selectedTaskID = record?.tasks.first?.id
            }
            syncInputsWithCurrentTask()
        }
        .onDisappear {
            cameraService.stop()
        }
        .onChange(of: record?.tasks.count) { _, _ in
            if selectedTaskID == nil {
                selectedTaskID = record?.tasks.first?.id
            }
        }
        .onChange(of: selectedTaskID) { _, _ in
            syncInputsWithCurrentTask()
        }
        .sheet(item: Binding(
            get: {
                selectedPreviewPhotoFileName.map { SelectedPhoto(fileName: $0) }
            },
            set: { selectedPreviewPhotoFileName = $0?.fileName }
        )) { item in
            PhotoPreviewSheet(fileName: item.fileName)
        }
        .sheet(isPresented: $showReportComposer) {
            if let record {
                NavigationStack {
                    StructuredReportComposerView(inspection: record) { form in
                        appLoadingMessage = "Submitting report..."
                        do {
                            let result = try await inspectionDB.submitStructuredReport(for: inspectionID, form: form)
                            let summary = "Submitted report #\(result.reportID)"
                            reportStore.createSubmittedReport(from: record, reportURL: result.reportURL, summary: summary)
                            sendStatusText = "Report submitted."
                            appLoadingMessage = nil
                            showReportComposer = false
                            onClose()
                        } catch {
                            appLoadingMessage = nil
                            appErrorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var topOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(CATTheme.catYellow)
                }
                Spacer()
                Text("Inspect Fleet")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(CATTheme.success)
                    .frame(width: 10, height: 10)
            }

            if let record {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.assetName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(record.location.isEmpty ? "Location pending" : record.location)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Tasks")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("\(record.tasks.filter { $0.completed }.count)/\(record.tasks.count)")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(CATTheme.catYellow)
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !sendStatusText.isEmpty {
                Text(sendStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CATTheme.success)
            }

            if !walkAroundActive {
                Button {
                    walkAroundActive = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk.motion")
                        Text("Activate Walk Around")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 8) {
                    if allTasksCompleted {
                        completionActionsCard
                    } else {
                        tasksTabStrip
                        ScrollView(.vertical, showsIndicators: false) {
                            if let task = currentTask {
                                taskControlCard(task)
                            }
                        }
                        .frame(maxHeight: 230)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(CATTheme.card.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var completionActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All tasks completed")
                .font(.headline.weight(.bold))
                .foregroundStyle(CATTheme.success)
            Text("Choose next action for this completed inspection.")
                .font(.caption)
                .foregroundStyle(CATTheme.body)
            HStack(spacing: 8) {
                Button {
                    if let record {
                        reportStore.addDraft(from: record)
                        onClose()
                    }
                } label: {
                    Label("Save Draft", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                Button {
                    showReportComposer = true
                } label: {
                    Label("Generate Report", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CATTheme.cardElevated.opacity(0.85))
        )
    }

    private var tasksTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(record?.tasks ?? []) { task in
                    Button {
                        selectedTaskID = task.id
                    } label: {
                        Text("Task \(task.taskNumber)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(tabTextColor(for: task))
                            .background(
                                Capsule()
                                    .fill(selectedTaskID == task.id ? AnyShapeStyle(CATTheme.headerGradient) : AnyShapeStyle(CATTheme.cardElevated))
                            )
                    }
                    .disabled(voiceService.isRecording || isTaskSyncing)
                    .opacity((voiceService.isRecording || isTaskSyncing) ? 0.5 : 1.0)
                }
            }
        }
    }

    private func taskControlCard(_ task: FleetTaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task \(task.taskNumber) of \(record?.tasks.count ?? 6)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(task.completed ? CATTheme.success : CATTheme.catYellow)
                Spacer()
                if task.completed {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CATTheme.success)
                }
            }

            Text(task.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(task.completed ? CATTheme.success : CATTheme.heading)
            Text(task.detail)
                .font(.caption)
                .foregroundStyle(CATTheme.body)
            if task.backendSyncStatus == "failed" {
                Text("Backend sync failed: \(task.backendError)")
                    .font(.caption2)
                    .foregroundStyle(CATTheme.warning)
                    .lineLimit(2)
            } else if task.backendSyncStatus == "synced" {
                Text("Synced to backend")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CATTheme.success)
            }

            if !task.started {
                Button {
                    inspectionDB.markTaskStarted(inspectionID: inspectionID, taskID: task.id)
                } label: {
                    Text("Start Task")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isTaskSyncing)
            } else {
                HStack(spacing: 8) {
                    Button {
                        guard capturedPhotoFileNames.count < 5 else { return }
                        cameraService.capturePhoto { filename in
                            guard let filename else { return }
                            capturedPhotoFileNames.append(filename)
                        }
                    } label: {
                        Label("Capture Photo (\(capturedPhotoFileNames.count)/5)", systemImage: "camera.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(capturedPhotoFileNames.count >= 5 || isTaskSyncing)
                    .opacity((capturedPhotoFileNames.count >= 5 || isTaskSyncing) ? 0.5 : 1.0)

                    Button {
                        if voiceService.isRecording {
                            voiceService.stopRecording()
                        } else {
                            voiceService.startRecording(inspectionID: inspectionID, taskID: task.id)
                        }
                    } label: {
                        Label(
                            voiceService.isRecording ? "Stop Capture Voice" : "Capture Voice",
                            systemImage: voiceService.isRecording ? "stop.circle.fill" : "mic.fill"
                        )
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .foregroundStyle(CATTheme.heading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(CATTheme.cardElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(CATTheme.cardBorder, lineWidth: 1)
                    )
                    .disabled(isTaskSyncing)
                    .opacity(isTaskSyncing ? 0.5 : 1.0)
                }

                if !capturedPhotoFileNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(capturedPhotoFileNames, id: \.self) { fileName in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        selectedPreviewPhotoFileName = fileName
                                    } label: {
                                        TaskPhotoThumb(fileName: fileName)
                                    }
                                    Button {
                                        capturedPhotoFileNames.removeAll { $0 == fileName }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(CATTheme.critical)
                                            .background(Circle().fill(CATTheme.card))
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }
                    .frame(height: 56)
                }

                CATTextEditorField(title: "Task Feedback", text: $feedbackText, minHeight: 50)
                Picker("Task Status", selection: $selectedWalkthroughStatus) {
                    ForEach(TaskReportStatus.allCases, id: \.self) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    isTaskSyncing = true
                    Task {
                        let audioFileName = await voiceService.stopAndStream(
                            inspectionID: inspectionID,
                            taskID: task.id,
                            feedbackText: feedbackText,
                            photoFileName: capturedPhotoFileNames.last
                        )
                        appLoadingMessage = "Submitting task \(task.taskNumber)..."
                        let syncStatus = await inspectionDB.saveTaskFeedbackAndSync(
                            inspectionID: inspectionID,
                            taskID: task.id,
                            feedbackText: feedbackText,
                            photoFileNames: capturedPhotoFileNames,
                            audioFileName: audioFileName,
                            walkthroughStatus: selectedWalkthroughStatus
                        )
                        appLoadingMessage = nil
                        isTaskSyncing = false
                        sendStatusText = "Task \(task.taskNumber): \(syncStatus)"
                        if let nextTaskID = nextTaskID(after: task.id) {
                            selectedTaskID = nextTaskID
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isTaskSyncing {
                            ProgressView().tint(CATTheme.catBlack)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isTaskSyncing ? "Uploading..." : "Send Feedback")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(CATTheme.catBlack)
                    .background(CATTheme.headerGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isTaskSyncing)
                .opacity(isTaskSyncing ? 0.55 : 1.0)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CATTheme.cardElevated.opacity(0.85))
        )
    }

    private func syncInputsWithCurrentTask() {
        guard let task = currentTask else { return }
        feedbackText = task.feedbackText
        selectedWalkthroughStatus = task.walkthroughStatus
        capturedPhotoFileNames = task.photoFileNames
        selectedPreviewPhotoFileName = nil
    }

    private func nextTaskID(after taskID: UUID) -> UUID? {
        guard let tasks = record?.tasks,
              let index = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let nextIndex = index + 1
        guard nextIndex < tasks.count else { return nil }
        return tasks[nextIndex].id
    }

    private func tabTextColor(for task: FleetTaskRecord) -> Color {
        if selectedTaskID == task.id {
            return CATTheme.catBlack
        }
        if task.completed {
            return CATTheme.success
        }
        return CATTheme.heading
    }
}

private struct SelectedPhoto: Identifiable {
    let fileName: String
    var id: String { fileName }
}

private struct TaskPhotoThumb: View {
    let fileName: String

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: localMediaURL(fileName: fileName).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.black.opacity(0.15)
                    Image(systemName: "photo")
                        .foregroundStyle(CATTheme.muted)
                }
            }
        }
        .frame(width: 72, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CATTheme.cardBorder, lineWidth: 1)
        )
    }
}

private struct PhotoPreviewSheet: View {
    let fileName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = UIImage(contentsOfFile: localMediaURL(fileName: fileName).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                Text("Photo unavailable")
                    .foregroundStyle(.white)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
    }
}

private func localMediaURL(fileName: String) -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    return (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(fileName)
}

private struct FleetCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

@MainActor
private final class FleetCameraService: NSObject, ObservableObject, @preconcurrency AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var completion: ((String?) -> Void)?

    override init() {
        super.init()
        configure()
    }

    func start() {
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    func capturePhoto(completion: @escaping (String?) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion?(nil)
            completion = nil
            return
        }
        let fileName = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = Self.storageDirectory().appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
            completion?(fileName)
        } catch {
            completion?(nil)
        }
        completion = nil
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    private static func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return base ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

@MainActor
private final class VoiceFeedbackService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var currentFileName: String?

    func startRecording(inspectionID: UUID, taskID: UUID) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted, let self else { return }
            Task { @MainActor in
                self.beginRecording(inspectionID: inspectionID, taskID: taskID)
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
    }

    func stopAndStream(
        inspectionID: UUID,
        taskID: UUID,
        feedbackText: String,
        photoFileName: String?
    ) async -> String? {
        if isRecording {
            stopRecording()
        }
        guard let audioFile = currentFileName else { return nil }
        _ = await submitToBackend(
            inspectionID: inspectionID,
            taskID: taskID,
            feedbackText: feedbackText,
            photoFileName: photoFileName,
            audioFileName: audioFile
        )
        return audioFile
    }

    private func beginRecording(inspectionID: UUID, taskID: UUID) {
        let name = "audio_\(inspectionID.uuidString.prefix(6))_\(taskID.uuidString.prefix(6))_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = storageDirectory().appendingPathComponent(name)
        currentFileName = name

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        isRecording = true
    }

    private func submitToBackend(
        inspectionID: UUID,
        taskID: UUID,
        feedbackText: String,
        photoFileName: String?,
        audioFileName: String
    ) async -> Bool {
        // Backend submission hook: replace with your inspection feedback API call.
        // Send inspectionID, taskID, feedbackText, photo file, and audio file.
        try? await Task.sleep(nanoseconds: 350_000_000)
        return true
    }

    private func storageDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return base ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

private enum ScanMode {
    case assetQR
    case catPIN

    var title: String {
        switch self {
        case .assetQR: return "Asset QR Scanner"
        case .catPIN: return "CAT PIN Scanner"
        }
    }
}

private struct InspectionScannerView: View {
    let mode: ScanMode
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var didHandleScan = false

    private var supportedTypes: Set<DataScannerViewController.RecognizedDataType> {
        switch mode {
        case .assetQR:
            return [.barcode(symbologies: [.qr])]
        case .catPIN:
            return [.barcode(symbologies: [.code128, .code39, .ean13, .ean8, .upce])]
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable(recognizedDataTypes: supportedTypes) { value in
                    handleScannedValue(value)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CATTheme.cardBorder, lineWidth: 1)
                )

                Text("Point the camera at the \(mode == .assetQR ? "asset QR code" : "CAT PIN barcode").")
                    .font(.subheadline)
                    .foregroundStyle(CATTheme.body)
            } else {
                Text("Scanner unavailable on this device. Enter code manually.")
                    .font(.subheadline)
                    .foregroundStyle(CATTheme.body)
            }

            CATInputField(title: mode == .assetQR ? "Asset QR Value" : "CAT PIN Value", text: $manualCode)
            Button {
                handleScannedValue(manualCode)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Use This Value")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(CATTheme.catBlack)
                .background(CATTheme.headerGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(16)
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(CATTheme.catYellow)
            }
        }
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func handleScannedValue(_ value: String) {
        guard !didHandleScan else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        didHandleScan = true
        onScanned(trimmed)
        // Delay dismiss very slightly so scanner can settle and avoid camera pipeline asserts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            dismiss()
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType>
    let onScan: (String) -> Void

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var didEmitScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                emitIfNeeded(payload, scanner: dataScanner)
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let first = addedItems.first else { return }
            if case .barcode(let barcode) = first, let payload = barcode.payloadStringValue {
                emitIfNeeded(payload, scanner: dataScanner)
            }
        }

        private func emitIfNeeded(_ payload: String, scanner: DataScannerViewController) {
            guard !didEmitScan else { return }
            didEmitScan = true
            scanner.stopScanning()
            onScan(payload)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }
}

@MainActor
private final class LocationPrefillService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation(completion: @escaping (String) -> Void) {
        self.completion = completion

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            completion("")
        @unknown default:
            completion("")
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            completion?("")
            completion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            completion?("")
            completion = nil
            return
        }
        let value = String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
        completion?(value)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?("")
        completion = nil
    }
}

private struct ProfileScreen: View {
    @Binding var isDarkModeEnabled: Bool
    @ObservedObject var profileStore: InspectorProfileStore
    @ObservedObject var connectionManager: BackendConnectionManager
    @State private var selectedPhoto: PhotosPickerItem?

    private var binding: Binding<InspectorProfile> {
        Binding(
            get: { profileStore.profile },
            set: {
                profileStore.profile = $0
                profileStore.save()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    InspectorAvatarSquare(
                        imageData: profileStore.profile.profileImageData,
                        initials: profileStore.profile.fullName.initials,
                        isBackendConnected: connectionManager.state.isConnected,
                        size: 84
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profileStore.profile.fullName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(CATTheme.heading)
                        Text(profileStore.profile.roleTitle)
                            .font(.subheadline)
                            .foregroundStyle(CATTheme.body)
                        Text(profileStore.profile.employeeID)
                            .font(.caption)
                            .foregroundStyle(CATTheme.muted)
                    }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Set Profile Photo", systemImage: "photo.fill.on.rectangle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(CATTheme.catBlack)
                        .background(CATTheme.headerGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                CreateSectionCard(title: "General Details", icon: "person.text.rectangle.fill") {
                    VStack(spacing: 10) {
                        CATInputField(title: "Full Name", text: binding.fullName)
                        CATInputField(title: "Employee ID", text: binding.employeeID)
                        CATInputField(title: "Role / Title", text: binding.roleTitle)
                        CATInputField(title: "Region", text: binding.region)
                        CATInputField(title: "Base Location", text: binding.baseLocation)
                        CATInputField(title: "Shift", text: binding.shift)
                        CATInputField(title: "Years of Experience", text: binding.yearsExperience, keyboardType: .numberPad)
                        CATInputField(title: "Certification Level", text: binding.certificationLevel)
                    }
                }

                CreateSectionCard(title: "Contact Information", icon: "phone.fill") {
                    VStack(spacing: 10) {
                        CATInputField(title: "Work Phone", text: binding.phone, keyboardType: .phonePad)
                        CATInputField(title: "Work Email", text: binding.email, keyboardType: .emailAddress)
                        CATInputField(title: "Emergency Contact Name", text: binding.emergencyContactName)
                        CATInputField(title: "Emergency Contact Phone", text: binding.emergencyContactPhone, keyboardType: .phonePad)
                    }
                }

                CreateSectionCard(title: "Preferences", icon: "gearshape.fill") {
                    Toggle(isOn: $isDarkModeEnabled) {
                        Label("Dark Mode", systemImage: "moon.fill")
                            .foregroundStyle(CATTheme.heading)
                    }
                    .tint(CATTheme.catYellow)
                }
            }
            .padding(16)
        }
        .background(CATTheme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .toolbarBackground(CATTheme.catCharcoal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    profileStore.profile.profileImageData = data
                    profileStore.save()
                }
            }
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
