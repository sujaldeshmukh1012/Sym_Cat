//
//  InspectionAPI.swift
//  CAT Inspect
//

import Foundation
import UIKit

enum APIEnvironment: String {
    case development = "https://api-dev.example.com"
    case staging = "https://api-staging.example.com"
    case production = "https://api.example.com"

    var baseURL: URL {
        guard let url = URL(string: rawValue) else {
            preconditionFailure("Invalid base URL")
        }
        return url
    }
}

protocol InspectionAPIClient {
    func fetchDashboardSummary(userID: String) async throws
    func fetchTodaysInspections(userID: String) async throws -> [InspectionItem]
    func startInspection(inspectionID: UUID) async throws
}

struct LiveInspectionAPIClient: InspectionAPIClient {
    let environment: APIEnvironment
    let urlSession: URLSession

    init(environment: APIEnvironment = .development, urlSession: URLSession = .shared) {
        self.environment = environment
        self.urlSession = urlSession
    }

    func fetchDashboardSummary(userID: String) async throws {
        // TODO: Hook your dashboard API.
    }

    func fetchTodaysInspections(userID: String) async throws -> [InspectionItem] {
        // TODO: Hook your inspection list API.
        return []
    }

    func startInspection(inspectionID: UUID) async throws {
        // TODO: Hook your start inspection API.
    }
}

enum SupabaseConfig {
    static let baseURL = URL(string: "https://axxxkhxsuigimqragicw.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4eHhraHhzdWlnaW1xcmFnaWN3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjI1NzYyMywiZXhwIjoyMDg3ODMzNjIzfQ.8xTJC_hCRGdpv3J58UgzDe7BQiWaL5YR-jM7twPvsIQ"
    static let publishableKey = "sb_publishable_ZuuKxEPK62lNDHVIvRgLMg8aV8BXF"
    static let bucketName = "inspection_key"
    static let storageObjectBaseURL: URL = {
        baseURL.appendingPathComponent("storage/v1/object")
    }()
}

enum BackendServiceConfig {
    static let apiBaseURL = URL(string: "http://127.0.0.1:8000")!
}


enum BackendError: LocalizedError {
    case invalidURL
    case missingConfig(key: String)
    case missingFleet(serial: String)
    case missingInspection
    case missingTask
    case invalidResponse
    case server(statusCode: Int, message: String)
    case duplicatePrimaryKey(table: String, message: String)
    case rowLevelSecurityBlocked(table: String, operation: String)
    case uploadFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Backend URL is invalid."
        case .missingConfig(let key):
            return "Missing config key: \(key)"
        case .missingFleet(let serial):
            return "Fleet not found for serial \(serial)."
        case .missingInspection:
            return "Inspection not found."
        case .missingTask:
            return "Task not found."
        case .invalidResponse:
            return "Backend returned invalid data."
        case .server(let statusCode, let message):
            return "Backend error (\(statusCode)): \(message)"
        case .duplicatePrimaryKey(let table, let message):
            return "Duplicate primary key on '\(table)': \(message)"
        case .rowLevelSecurityBlocked(let table, let operation):
            return "Supabase RLS blocked \(operation) on table '\(table)'. Add RLS policy for your app role."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        }
    }
}

struct BackendTaskSeed {
    let taskID: Int64
    let order: Int
    let title: String
    let detail: String
}

struct BackendCreateInspectionResult {
    let inspectionID: Int64
    let fleetID: Int64
    let fleetName: String
    let serialNumber: String
    let model: String
    let make: String
    let family: String
    let tasks: [BackendTaskSeed]
}

struct BackendReportResult {
    let reportID: Int64
    let reportPDF: String
}

struct BackendDashboardPayload {
    let kpis: [KPIItem]
    let alerts: [DashboardAlert]
    let todaysInspections: [InspectionItem]
}

struct BackendReportListItem {
    let reportID: Int64
    let inspectionID: Int64?
    let fleetSerial: String
    let inspectionDate: String
    let reportURL: String
}

struct BackendReportPayload {
    let componentIdentified: String
    let overallStatus: String
    let operationalImpact: String
    let anomalies: [[String: String]]
    let inspectorName: String
}

final class SupabaseInspectionBackend {
    static let shared = SupabaseInspectionBackend()
    private static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var verifiedStorageBuckets: Set<String> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func createInspection(from form: FleetInspectionFormData) async throws -> BackendCreateInspectionResult {
        log("createInspection.start serial=\(form.serialNumber) asset=\(form.assetName) backendFleetID=\(String(describing: form.backendFleetID))")
        let fleet = try await resolveFleet(from: form)
        log("createInspection.fleetResolved fleetID=\(fleet.id) serial=\(fleet.serialNumber ?? "nil")")
        let inspection = try await insertInspection(fleetID: fleet.id, form: form)
        log("createInspection.inspectionInserted inspectionID=\(inspection.id)")
        let todos = try await fetchTodos(fleetID: fleet.id)
        log("createInspection.todoFetched count=\(todos.count)")

        let taskRows: [SupabaseTaskRow]
        if todos.isEmpty {
            let defaultTasks = Self.defaultTaskTemplate().map {
                TaskInsertPayload(
                    title: $0.title,
                    state: "pending",
                    images: [],
                    anomolies: [],
                    index: $0.index,
                    fleetSerial: fleet.id,
                    inspectionID: inspection.id,
                    description: $0.detail,
                    feedback: ""
                )
            }
            taskRows = try await insertTasks(defaultTasks)
        } else {
            let fromTodo = todos.enumerated().map { offset, todo in
                TaskInsertPayload(
                    title: todo.title ?? "Task \(offset + 1)",
                    state: "pending",
                    images: [],
                    anomolies: [],
                    index: todo.index ?? (offset + 1),
                    fleetSerial: fleet.id,
                    inspectionID: inspection.id,
                    description: todo.description ?? "",
                    feedback: ""
                )
            }
            taskRows = try await insertTasks(fromTodo)
        }

        try await updateInspectionTaskIDs(inspectionID: inspection.id, taskIDs: taskRows.map(\.id))
        log("createInspection.tasksLinked inspectionID=\(inspection.id) taskIDs=\(taskRows.map(\.id))")

        return BackendCreateInspectionResult(
            inspectionID: inspection.id,
            fleetID: fleet.id,
            fleetName: fleet.name ?? "",
            serialNumber: fleet.serialNumber ?? form.serialNumber,
            model: fleet.model.map(String.init) ?? form.model,
            make: fleet.make ?? form.make,
            family: fleet.family ?? form.productFamily,
            tasks: taskRows.map {
                BackendTaskSeed(
                    taskID: $0.id,
                    order: $0.index ?? 0,
                    title: $0.title ?? "Task",
                    detail: $0.description ?? ""
                )
            }
            .sorted(by: { $0.order < $1.order })
        )
    }

    func markTaskStarted(taskID: Int64) async throws {
        log("markTaskStarted taskID=\(taskID)")
        _ = try await patch(
            table: "task",
            filters: [URLQueryItem(name: "id", value: "eq.\(taskID)")],
            payload: ["state": "in_progress"]
        ) as [SupabaseTaskRow]
    }

    func submitTaskFeedback(
        taskID: Int64,
        feedbackText: String,
        imageURLs: [String],
        anomalies: [String]
    ) async throws {
        log("submitTaskFeedback taskID=\(taskID) images=\(imageURLs.count) anomalies=\(anomalies.count)")
        _ = try await patch(
            table: "task",
            filters: [URLQueryItem(name: "id", value: "eq.\(taskID)")],
            payload: [
                "state": "completed",
                "feedback": feedbackText,
                "images": imageURLs,
                "anomolies": anomalies
            ]
        ) as [SupabaseTaskRow]
    }

    func uploadTaskImages(
        inspectionID: Int64,
        taskID: Int64,
        localPhotos: [(fileName: String, data: Data, mimeType: String)]
    ) async throws -> [String] {
        if localPhotos.isEmpty { return [] }
        log("uploadTaskImages inspectionID=\(inspectionID) taskID=\(taskID) count=\(localPhotos.count)")
        var urls: [String] = []
        for photo in localPhotos {
            let remoteName = "inspections/\(inspectionID)/tasks/\(taskID)/\(UUID().uuidString)_\(photo.fileName)"
            let url = try await uploadObject(
                objectKey: remoteName,
                data: photo.data,
                contentType: photo.mimeType
            )
            urls.append(url)
        }
        return urls
    }

    func fetchDashboardPayload() async throws -> BackendDashboardPayload {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayISO = ISO8601DateFormatter().string(from: todayStart)
        var inspectionRows: [SupabaseInspectionListRow] = try await get(
            table: "inspection",
            query: [
                URLQueryItem(name: "select", value: "id,created_at,location,fleet_serial,completed_on,tasks"),
                URLQueryItem(name: "created_at", value: "gte.\(todayISO)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")
            ]
        )
        if inspectionRows.isEmpty {
            inspectionRows = try await get(
                table: "inspection",
                query: [
                    URLQueryItem(name: "select", value: "id,created_at,location,fleet_serial,completed_on,tasks"),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                    URLQueryItem(name: "limit", value: "50")
                ]
            )
        }

        let fleetIDs = Array(Set(inspectionRows.compactMap(\.fleetSerial))).sorted()
        let fleetByID = try await fetchFleetDictionary(ids: fleetIDs)

        let inspections: [InspectionItem] = inspectionRows.enumerated().map { offset, row in
            let fleet = row.fleetSerial.flatMap { fleetByID[$0] }
            let unresolvedName = fleet?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let itemName = unresolvedName.isEmpty ? "Fleet \(row.fleetSerial.map(String.init) ?? "Unknown")" : unresolvedName
            let priority: InspectionPriority
            let taskCount = row.tasks?.count ?? 0
            if taskCount >= 6 {
                priority = .high
            } else if taskCount == 0 {
                priority = .medium
            } else {
                priority = .medium
            }
            let scheduledTime = formatTime(row.createdAt)
            let location = (row.location ?? "").isEmpty ? "Location pending" : (row.location ?? "")
            return InspectionItem(
                id: UUID(),
                itemName: itemName,
                location: location,
                priority: priority,
                partImageAssetName: "hydraulic_pump_a17",
                documentationURL: URL(string: "https://www.caterpillar.com/en/support/maintenance")!,
                blueprintURL: URL(string: "https://www.caterpillar.com/en/company/brand")!,
                scheduledTime: scheduledTime,
                syncState: row.completedOn == nil ? .pending : .synced
            )
        }

        let openCount = inspectionRows.filter { $0.completedOn == nil }.count
        let completedToday = inspectionRows.filter { $0.completedOn != nil }.count
        let failedTaskRows: [SupabaseTaskStateRow] = (try? await get(
            table: "task",
            query: [
                URLQueryItem(name: "select", value: "id,state"),
                URLQueryItem(name: "state", value: "eq.failed"),
                URLQueryItem(name: "limit", value: "100")
            ]
        )) ?? []

        let inProgressTaskRows: [SupabaseTaskStateRow] = (try? await get(
            table: "task",
            query: [
                URLQueryItem(name: "select", value: "id,state"),
                URLQueryItem(name: "state", value: "eq.in_progress"),
                URLQueryItem(name: "limit", value: "100")
            ]
        )) ?? []

        let kpis: [KPIItem] = [
            KPIItem(title: "Open Inspections", value: "\(openCount)", trendText: "--", trendUp: false, lastUpdated: "Live"),
            KPIItem(title: "Completed Today", value: "\(completedToday)", trendText: "--", trendUp: true, lastUpdated: "Live"),
            KPIItem(title: "Failed Tasks", value: "\(failedTaskRows.count)", trendText: "--", trendUp: failedTaskRows.isEmpty, lastUpdated: "Live")
        ]

        var alerts: [DashboardAlert] = []
        if !failedTaskRows.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .critical,
                    title: "Task Sync Failures",
                    message: "\(failedTaskRows.count) task(s) are in failed state.",
                    actionTitle: "Review"
                )
            )
        }
        if !inProgressTaskRows.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .warning,
                    title: "Walkthroughs In Progress",
                    message: "\(inProgressTaskRows.count) task(s) are currently in progress.",
                    actionTitle: "Open"
                )
            )
        }
        if alerts.isEmpty {
            alerts.append(
                DashboardAlert(
                    severity: .info,
                    title: "System Healthy",
                    message: "No critical task failures detected.",
                    actionTitle: "Refresh"
                )
            )
        }

        return BackendDashboardPayload(kpis: kpis, alerts: alerts, todaysInspections: inspections)
    }

    func fetchReportsList() async throws -> [BackendReportListItem] {
        let reportRows: [SupabaseReportListRow] = try await get(
            table: "report",
            query: [
                URLQueryItem(name: "select", value: "id,inspection_id,report_pdf,pdf_created,created_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )

        if reportRows.isEmpty { return [] }

        let inspectionIDs = Array(Set(reportRows.compactMap(\.inspectionID))).sorted()
        let inspectionByID = try await fetchInspectionDictionary(ids: inspectionIDs)
        let fleetIDs = Array(Set(inspectionByID.values.compactMap(\.fleetSerial))).sorted()
        let fleetByID = try await fetchFleetDictionary(ids: fleetIDs)

        return reportRows.compactMap { row in
            guard let pdf = row.reportPDF, !pdf.isEmpty else { return nil }
            let inspection = row.inspectionID.flatMap { inspectionByID[$0] }
            let fleet = inspection?.fleetSerial.flatMap { fleetByID[$0] }
            let fleetSerial = fleet?.serialNumber ?? inspection?.fleetSerial.map(String.init) ?? "Unknown"
            return BackendReportListItem(
                reportID: row.id,
                inspectionID: row.inspectionID,
                fleetSerial: fleetSerial,
                inspectionDate: formatDate(row.pdfCreated ?? row.createdAt),
                reportURL: pdf
            )
        }
    }

    func requestReportGeneration(inspectionID: Int64, taskIDs: [Int64]) async throws -> BackendReportResult {
        log("requestReportGeneration inspectionID=\(inspectionID) taskIDs=\(taskIDs)")
        let reportRows: [SupabaseReportRow] = try await post(
            table: "report",
            payload: [
                ReportInsertPayload(
                    inspectionID: inspectionID,
                    tasks: taskIDs,
                    reportPDF: nil,
                    pdfCreated: nil
                )
            ]
        )
        guard let first = reportRows.first else { throw BackendError.invalidResponse }
        return BackendReportResult(reportID: first.id, reportPDF: first.reportPDF ?? "")
    }

    func submitFinalReport(
        inspectionID: Int64,
        taskIDs: [Int64],
        reportPayload: BackendReportPayload
    ) async throws -> BackendReportResult {
        log("submitFinalReport inspectionID=\(inspectionID) taskIDs=\(taskIDs.count) mode=in_app_pdf")
        let context = try await loadInspectionReportContext(inspectionID: inspectionID)
        let reportData = LocalReportRenderData(
            customerName: context.customerName,
            serialNumber: context.serialNumber,
            model: context.model,
            inspector: reportPayload.inspectorName.nilIfBlank ?? context.inspector,
            date: context.date,
            inspectionID: inspectionID,
            componentIdentified: reportPayload.componentIdentified,
            overallStatus: reportPayload.overallStatus,
            operationalImpact: reportPayload.operationalImpact,
            anomalies: reportPayload.anomalies
        )

        let pdfData = try await makeInspectionPDF(reportData: reportData)
        let objectKey = "reports/inspection_\(inspectionID)_\(Int(Date().timeIntervalSince1970)).pdf"
        let reportURL = try await uploadObject(
            objectKey: objectKey,
            data: pdfData,
            contentType: "application/pdf"
        )

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let reportPayloadInsert = ReportInsertPayload(
            inspectionID: inspectionID,
            tasks: taskIDs,
            reportPDF: reportURL,
            pdfCreated: timestamp
        )
        let created = try await insertReportWithRetry(payload: reportPayloadInsert)
        return BackendReportResult(reportID: created.id, reportPDF: created.reportPDF ?? reportURL)
    }

    private func insertReportWithRetry(payload: ReportInsertPayload, maxAttempts: Int = 6) async throws -> SupabaseReportRow {
        var attempt = 1
        while true {
            do {
                let rows: [SupabaseReportRow] = try await post(
                    table: "report",
                    payload: [payload]
                )
                guard let first = rows.first else { throw BackendError.invalidResponse }
                return first
            } catch BackendError.duplicatePrimaryKey(let table, let message) where table == "report" && attempt < maxAttempts {
                log("insertReportWithRetry.duplicate attempt=\(attempt) max=\(maxAttempts) detail=\(message)")
                attempt += 1
                try? await Task.sleep(nanoseconds: 120_000_000)
                continue
            }
        }
    }

    private func loadInspectionReportContext(inspectionID: Int64) async throws -> LocalInspectionReportContext {
        let rows: [SupabaseInspectionDetailsRow] = try await get(
            table: "inspection",
            query: [
                URLQueryItem(name: "select", value: "id,created_at,customer_name,inspector,fleet_serial"),
                URLQueryItem(name: "id", value: "eq.\(inspectionID)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        guard let inspection = rows.first else {
            throw BackendError.missingInspection
        }

        var fleet: SupabaseFleetRow?
        if let fleetID = inspection.fleetSerial {
            let fleetRows: [SupabaseFleetRow] = try await get(
                table: "fleet",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "id", value: "eq.\(fleetID)"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            fleet = fleetRows.first
        }

        return LocalInspectionReportContext(
            customerName: inspection.customerName ?? "Unknown Customer",
            serialNumber: fleet?.serialNumber ?? inspection.fleetSerial.map(String.init) ?? "Unknown",
            model: fleet?.model.map(String.init) ?? "Unknown",
            inspector: inspection.inspector ?? "Inspector",
            date: formatReportDate(inspection.createdAt)
        )
    }

    private func formatReportDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Self.reportDateFormatter.string(from: Date()) }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: raw) {
            return Self.reportDateFormatter.string(from: date)
        }
        return Self.reportDateFormatter.string(from: Date())
    }

    private func makeInspectionPDF(reportData: LocalReportRenderData) async throws -> Data {
        let html = renderReportHTML(reportData: reportData)
        return try await renderPDFData(from: html)
    }

    private func renderReportHTML(reportData: LocalReportRenderData) -> String {
        let logoHTML: String = {
            if let image = UIImage(named: "Alter_CAT"), let data = image.pngData() {
                let b64 = data.base64EncodedString()
                return "<img src=\"data:image/png;base64,\(b64)\" style=\"height:52px; width:auto;\" />"
            }
            if let image = UIImage(named: "cat_logo"), let data = image.pngData() {
                let b64 = data.base64EncodedString()
                return "<img src=\"data:image/png;base64,\(b64)\" style=\"height:52px; width:auto;\" />"
            }
            return "&nbsp;"
        }()

        let statusSummary = reportData.anomalies.reduce(into: (critical: 0, monitor: 0, ok: 0, na: 0)) { acc, anomaly in
            let severity = (anomaly["severity"] ?? "").lowercased()
            if severity == "critical" || severity == "fail" {
                acc.critical += 1
            } else if severity == "moderate" || severity == "monitor" {
                acc.monitor += 1
            } else if severity == "normal" || severity == "pass" {
                acc.ok += 1
            } else {
                acc.na += 1
            }
        }

        let anomalyRows = reportData.anomalies.map { anomaly -> String in
            let component = htmlEscape(anomaly["component"] ?? "Component")
            let issue = htmlEscape(anomaly["issue"] ?? "Issue")
            let description = htmlEscape(anomaly["description"] ?? "")
            let recommendedAction = htmlEscape(anomaly["recommended_action"] ?? "")
            let severityRaw = (anomaly["severity"] ?? "NORMAL")
            let severityUpper = htmlEscape(severityRaw.uppercased())
            let dotColor: String
            let statusClass: String
            switch severityRaw.lowercased() {
            case "critical", "fail":
                dotColor = "#cc0000"
                statusClass = "FAIL"
            case "moderate", "monitor":
                dotColor = "#e87722"
                statusClass = "MONITOR"
            default:
                dotColor = "#3a9e3a"
                statusClass = "NORMAL"
            }
            return """
            <tr class="item-row">
                <td class="item-name">
                    <span class="row-dot" style="background:\(dotColor);"></span>
                    <strong>\(component)</strong> &mdash; \(issue)
                </td>
                <td class="item-status status-\(statusClass)">\(severityUpper)</td>
            </tr>
            <tr class="comment-row"><td colspan="2">Comments: \(description)</td></tr>
            <tr class="action-row"><td colspan="2">Action: \(recommendedAction)</td></tr>
            """
        }.joined(separator: "\n")

        let headerTitle = htmlEscape(
            reportData.componentIdentified.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Wheel Loader: Safety & Maintenance"
            : reportData.componentIdentified
        )

        let findingsSection: String = {
            guard !reportData.anomalies.isEmpty else { return "" }
            return """
            <div class="section-header" style="margin-top:16px;">Detailed Findings</div>
            <table class="findings-table">
                \(anomalyRows)
            </table>
            """
        }()

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,Arial,sans-serif;font-size:7.5pt;color:#000}
        .page{padding:10px}
        .header{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:6px}
        .title{font-size:13pt;font-weight:600}
        .sub{font-size:7pt;color:#444;margin-top:2px}
        .info{width:100%;border-collapse:collapse;margin-top:6px}
        .info td{font-size:7pt;padding:2px 4px;vertical-align:top}
        .lbl{color:#666;width:120px}
        .val{color:#000}
        .section{background:#cfcfcf;font-weight:600;font-size:8pt;padding:3px 5px;margin-top:8px}
        .findings{width:100%;border-collapse:collapse}
        .findings td{padding:4px 5px;font-size:7.5pt;border-bottom:1px solid #e5e5e5}
        .item-name{width:75%}
        .item-status{text-align:right;font-weight:600}
        .comment td{padding-left:14px;font-size:7pt;background:#ffffcc}
        .status-PASS,.status-NORMAL{color:#2f9e44}
        .status-MONITOR{color:#e87722}
        .status-FAIL{color:#cc0000}
        .footer{margin-top:10px;font-size:7pt;display:flex;justify-content:space-between;border-top:1px solid #ddd;padding-top:4px}
        </style>
        </head>
        <body>
        <div class="page">
        <div class="header">
        <div>
        <div class="title">\(headerTitle)</div>
        <div class="sub">
        Daily
        <span style="color:#cc0000">●</span> \(statusSummary.critical)
        <span style="color:#e87722">●</span> \(statusSummary.monitor)
        <span style="color:#2f9e44">●</span> \(statusSummary.ok)
        <span style="color:#777">●</span> \(statusSummary.na)
        </div>
        </div>
        <div>\(logoHTML)</div>
        </div>
        <table class="info">
        <tr><td class="lbl">Inspection #</td><td class="val">\(reportData.inspectionID)</td><td class="lbl">Customer #</td><td class="val">&nbsp;</td></tr>
        <tr><td class="lbl">Serial</td><td class="val">\(htmlEscape(reportData.serialNumber))</td><td class="lbl">Customer</td><td class="val">\(htmlEscape(reportData.customerName))</td></tr>
        <tr><td class="lbl">Make</td><td class="val">CATERPILLAR</td><td class="lbl">Work Order</td><td class="val">&nbsp;</td></tr>
        <tr><td class="lbl">Model</td><td class="val">\(htmlEscape(reportData.model))</td><td class="lbl">Completed</td><td class="val">\(htmlEscape(reportData.date))</td></tr>
        <tr><td class="lbl">Family</td><td class="val">Medium Wheel Loader</td><td class="lbl">Inspector</td><td class="val">\(htmlEscape(reportData.inspector))</td></tr>
        <tr><td class="lbl">Location</td><td class="val" colspan="3">601 Richland St, East Peoria, IL 61611</td></tr>
        </table>
        \(findingsSection)
        <div class="footer">
        <span>SN: \(htmlEscape(reportData.serialNumber))</span>
        <span>Executive Summary</span>
        <span>Page 1</span>
        </div>
        </div>
        </body>
        </html>
        """
    }

    private func renderPDFData(from html: String) async throws -> Data {
        try await MainActor.run {
            let renderer = HTMLPrintPageRenderer()
            let formatter = UIMarkupTextPrintFormatter(markupText: html)
            renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

            // A4 @ 72dpi
            let paperRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
            let printableRect = paperRect.insetBy(dx: 20, dy: 22)
            renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
            renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")

            return renderer.pdfData()
        }
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func resolveFleet(from form: FleetInspectionFormData) async throws -> SupabaseFleetRow {
        if let fleetID = form.backendFleetID {
            log("resolveFleet.byBackendFleetID fleetID=\(fleetID)")
            let rows: [SupabaseFleetRow] = try await get(
                table: "fleet",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "id", value: "eq.\(fleetID)"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            if let first = rows.first {
                return first
            }
            throw BackendError.missingFleet(serial: "fleet.id=\(fleetID)")
        }

        let serial = form.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serial.isEmpty {
            log("resolveFleet.bySerial serial=\(serial)")
            let rows: [SupabaseFleetRow] = try await get(
                table: "fleet",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "serial_number", value: "eq.\(serial)"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            if let first = rows.first {
                return first
            }
        }

        let payload = FleetInsertPayload(
            name: form.assetName.isEmpty ? form.model : form.assetName,
            serialNumber: serial.isEmpty ? nil : serial,
            type: form.productFamily.isEmpty ? nil : form.productFamily,
            make: form.make.isEmpty ? nil : form.make,
            family: form.productFamily.isEmpty ? nil : form.productFamily,
            model: Int64(form.model.trimmingCharacters(in: .whitespacesAndNewlines))
        )

        let rows: [SupabaseFleetRow] = try await post(
            table: "fleet",
            payload: [payload],
            extraQuery: [URLQueryItem(name: "on_conflict", value: "serial_number")],
            prefer: "resolution=merge-duplicates,return=representation"
        )
        if let first = rows.first {
            return first
        }
        throw BackendError.missingFleet(serial: serial)
    }

    private func fetchFleetDictionary(ids: [Int64]) async throws -> [Int64: SupabaseFleetRow] {
        guard !ids.isEmpty else { return [:] }
        let idList = ids.map(String.init).joined(separator: ",")
        let rows: [SupabaseFleetRow] = try await get(
            table: "fleet",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "in.(\(idList))")
            ]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    private func fetchInspectionDictionary(ids: [Int64]) async throws -> [Int64: SupabaseInspectionLookupRow] {
        guard !ids.isEmpty else { return [:] }
        let idList = ids.map(String.init).joined(separator: ",")
        let rows: [SupabaseInspectionLookupRow] = try await get(
            table: "inspection",
            query: [
                URLQueryItem(name: "select", value: "id,fleet_serial,created_at"),
                URLQueryItem(name: "id", value: "in.(\(idList))")
            ]
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    private func formatDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "N/A" }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
        return raw
    }

    private func formatTime(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "N/A" }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
        return "N/A"
    }

    private func fetchTodos(fleetID: Int64) async throws -> [SupabaseTodoRow] {
        log("fetchTodos fleetID=\(fleetID)")
        return try await get(
            table: "todo",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "fleet_serial", value: "eq.\(fleetID)"),
                URLQueryItem(name: "order", value: "index.asc")
            ]
        )
    }

    private func insertInspection(fleetID: Int64, form: FleetInspectionFormData) async throws -> SupabaseInspectionRow {
        log("insertInspection fleetID=\(fleetID) location=\(form.location) customer=\(form.customerName)")
        let inspectionPayload = InspectionInsertPayload(
            fleetSerial: fleetID,
            report: [],
            tasks: [],
            customerID: Int64(form.customerUCID.trimmingCharacters(in: .whitespacesAndNewlines)),
            customerName: form.customerName.nilIfBlank,
            workOrder: form.workOrderNumber.nilIfBlank,
            inspector: nil,
            location: form.location.nilIfBlank,
            assetID: form.assetID.nilIfBlank
        )
        let rows: [SupabaseInspectionRow] = try await post(table: "inspection", payload: [inspectionPayload])
        guard let first = rows.first else { throw BackendError.missingInspection }
        return first
    }

    private func insertTasks(_ payload: [TaskInsertPayload]) async throws -> [SupabaseTaskRow] {
        log("insertTasks count=\(payload.count)")
        return try await post(table: "task", payload: payload)
    }

    private func updateInspectionTaskIDs(inspectionID: Int64, taskIDs: [Int64]) async throws {
        log("updateInspectionTaskIDs inspectionID=\(inspectionID) taskIDs=\(taskIDs)")
        _ = try await patch(
            table: "inspection",
            filters: [URLQueryItem(name: "id", value: "eq.\(inspectionID)")],
            payload: ["tasks": taskIDs]
        ) as [SupabaseInspectionRow]
    }

    private func get<T: Decodable>(table: String, query: [URLQueryItem]) async throws -> T {
        try await request(
            table: table,
            method: "GET",
            query: query,
            body: nil,
            prefer: nil
        )
    }

    private func post<T: Decodable, P: Encodable>(
        table: String,
        payload: P,
        extraQuery: [URLQueryItem] = [],
        prefer: String = "return=representation"
    ) async throws -> T {
        let body = try encoder.encode(payload)
        return try await request(
            table: table,
            method: "POST",
            query: extraQuery,
            body: body,
            prefer: prefer
        )
    }

    private func patch<T: Decodable>(
        table: String,
        filters: [URLQueryItem],
        payload: [String: Any]
    ) async throws -> T {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw BackendError.invalidResponse
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try await request(
            table: table,
            method: "PATCH",
            query: filters,
            body: body,
            prefer: "return=representation"
        )
    }

    private func request<T: Decodable>(
        table: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        prefer: String?
    ) async throws -> T {
        if SupabaseConfig.anonKey.isEmpty {
            throw BackendError.missingConfig(key: "SUPABASE_KEY")
        }
        guard var components = URLComponents(url: SupabaseConfig.baseURL, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidURL
        }
        components.path = "/rest/v1/\(table)"
        components.queryItems = query

        guard let url = components.url else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        request.httpBody = body

        let queryLog = components.percentEncodedQuery ?? "(none)"
        let payloadLog = body.flatMap { String(data: $0, encoding: .utf8) } ?? "(none)"
        log("HTTP.REQUEST method=\(method) table=\(table)")
        log("HTTP.URL \(url.absoluteString)")
        log("HTTP.QUERY \(queryLog)")
        log("HTTP.PREFER \(prefer ?? "(none)")")
        log("HTTP.BODY \(truncate(payloadLog, limit: 1500))")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            log("HTTP.ERROR invalid response object")
            throw BackendError.invalidResponse
        }
        let responseLog = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        log("HTTP.RESPONSE status=\(http.statusCode) table=\(table)")
        log("HTTP.RESPONSE.BODY \(truncate(responseLog, limit: 2000))")
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown backend error"
            if let supabaseError = try? decoder.decode(SupabaseErrorBody.self, from: data),
               supabaseError.code == "42501" {
                throw BackendError.rowLevelSecurityBlocked(table: table, operation: method)
            }
            if let supabaseError = try? decoder.decode(SupabaseErrorBody.self, from: data),
               supabaseError.code == "23505" {
                let detail = supabaseError.details ?? supabaseError.message ?? message
                throw BackendError.duplicatePrimaryKey(table: table, message: detail)
            }
            throw BackendError.server(statusCode: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            throw error
        }
    }

    private static func defaultTaskTemplate() -> [(index: Int, title: String, detail: String)] {
        [
            (1, "Exterior Walkaround", "Check visible frame and body condition for damage or wear."),
            (2, "Fluid Leakage Check", "Inspect hydraulic lines, joints, and undercarriage for leaks."),
            (3, "Engine Bay Condition", "Validate hoses, belts, and fasteners around engine components."),
            (4, "Safety Components", "Verify alarms, lights, emergency shutoff and warning labels."),
            (5, "Attachment Interface", "Inspect couplers, pins, and locking mechanisms."),
            (6, "Operator Feedback", "Capture operator comments for performance and unusual behavior.")
        ]
    }

    private func log(_ message: String) {
        print("[SupabaseAPI] \(message)")
    }

    private func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return "\(value[..<end])… [truncated]"
    }

    private func uploadObject(
        objectKey: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        let bucket = SupabaseConfig.bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        if bucket.isEmpty {
            throw BackendError.missingConfig(key: "SUPABASE_BUCKET_NAME")
        }
        try await ensureStorageBucketExists(bucket)
        guard var components = URLComponents(url: SupabaseConfig.storageObjectBaseURL, resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidURL
        }
        components.path += "/\(bucket)/\(objectKey)"
        guard let url = components.url else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        log("HTTP.REQUEST method=POST storage_upload")
        log("HTTP.URL \(url.absoluteString)")
        log("HTTP.BODY bytes=\(data.count)")

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        let responseText = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
        log("HTTP.RESPONSE status=\(http.statusCode) storage_upload")
        log("HTTP.RESPONSE.BODY \(truncate(responseText, limit: 1200))")
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.uploadFailed(message: responseText)
        }

        return "\(SupabaseConfig.baseURL.absoluteString)/storage/v1/object/public/\(bucket)/\(objectKey)"
    }

    private func ensureStorageBucketExists(_ bucket: String) async throws {
        if verifiedStorageBuckets.contains(bucket) { return }

        guard let getURL = URL(string: "\(SupabaseConfig.baseURL.absoluteString)/storage/v1/bucket/\(bucket)") else {
            throw BackendError.invalidURL
        }
        var getRequest = URLRequest(url: getURL)
        getRequest.httpMethod = "GET"
        getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        getRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        getRequest.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        log("HTTP.REQUEST method=GET storage_bucket_check")
        log("HTTP.URL \(getURL.absoluteString)")

        let (checkData, checkResponse) = try await session.data(for: getRequest)
        guard let checkHTTP = checkResponse as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        let checkText = String(data: checkData, encoding: .utf8) ?? "<non-utf8>"
        log("HTTP.RESPONSE status=\(checkHTTP.statusCode) storage_bucket_check")
        log("HTTP.RESPONSE.BODY \(truncate(checkText, limit: 1200))")

        if checkHTTP.statusCode == 200 {
            verifiedStorageBuckets.insert(bucket)
            return
        }
        if !isStorageBucketMissing(statusCode: checkHTTP.statusCode, responseText: checkText) {
            throw BackendError.uploadFailed(message: "Bucket check failed: \(checkText)")
        }

        guard let createURL = URL(string: "\(SupabaseConfig.baseURL.absoluteString)/storage/v1/bucket") else {
            throw BackendError.invalidURL
        }
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        createRequest.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["id": bucket, "name": bucket, "public": true]
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        log("HTTP.REQUEST method=POST storage_bucket_create")
        log("HTTP.URL \(createURL.absoluteString)")
        log("HTTP.BODY \(payload)")

        let (createData, createResponse) = try await session.data(for: createRequest)
        guard let createHTTP = createResponse as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        let createText = String(data: createData, encoding: .utf8) ?? "<non-utf8>"
        log("HTTP.RESPONSE status=\(createHTTP.statusCode) storage_bucket_create")
        log("HTTP.RESPONSE.BODY \(truncate(createText, limit: 1200))")

        guard (200..<300).contains(createHTTP.statusCode) || createHTTP.statusCode == 409 else {
            throw BackendError.uploadFailed(message: "Bucket create failed: \(createText)")
        }
        verifiedStorageBuckets.insert(bucket)
    }

    private func isStorageBucketMissing(statusCode: Int, responseText: String) -> Bool {
        if statusCode == 404 { return true }
        if statusCode != 400 { return false }
        if responseText.contains("\"statusCode\":\"404\"") { return true }
        if let data = responseText.data(using: .utf8),
           let body = try? decoder.decode(StorageErrorBody.self, from: data),
           body.statusCode == "404" {
            return true
        }
        return false
    }
}

private struct EmptyResponse: Decodable {}

private final class HTMLPrintPageRenderer: UIPrintPageRenderer {
    func pdfData() -> Data {
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        for page in 0..<numberOfPages {
            UIGraphicsBeginPDFPage()
            drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }
}

private struct SupabaseErrorBody: Decodable {
    let code: String?
    let details: String?
    let message: String?
}

private struct StorageErrorBody: Decodable {
    let statusCode: String?
    let error: String?
    let message: String?
}

private struct ReportGenerateRequestDTO: Encodable {
    let componentIdentified: String
    let overallStatus: String
    let operationalImpact: String
    let anomalies: [[String: String]]
    let tasks: [Int64]

    enum CodingKeys: String, CodingKey {
        case componentIdentified = "component_identified"
        case overallStatus = "overall_status"
        case operationalImpact = "operational_impact"
        case anomalies
        case tasks
    }
}

private struct ReportGenerateResponseDTO: Decodable {
    let message: String?
    let status: String?
    let data: ReportGenerateRowDTO
}

private struct ReportGenerateRowDTO: Decodable {
    let id: Int64?
    let reportPDF: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportPDF = "report_pdf"
    }
}

private struct SupabaseFleetRow: Decodable {
    let id: Int64
    let name: String?
    let serialNumber: String?
    let type: String?
    let make: String?
    let family: String?
    let model: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case serialNumber = "serial_number"
        case type
        case make
        case family
        case model
    }
}

private struct SupabaseTodoRow: Decodable {
    let id: Int64
    let title: String?
    let index: Int?
    let fleetSerial: Int64?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case index
        case fleetSerial = "fleet_serial"
        case description
    }
}

private struct SupabaseInspectionRow: Decodable {
    let id: Int64
    let tasks: [Int64]?
}

private struct SupabaseInspectionListRow: Decodable {
    let id: Int64
    let createdAt: String?
    let location: String?
    let fleetSerial: Int64?
    let completedOn: String?
    let tasks: [Int64]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case location
        case fleetSerial = "fleet_serial"
        case completedOn = "completed_on"
        case tasks
    }
}

private struct SupabaseInspectionLookupRow: Decodable {
    let id: Int64
    let fleetSerial: Int64?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fleetSerial = "fleet_serial"
        case createdAt = "created_at"
    }
}

private struct SupabaseInspectionDetailsRow: Decodable {
    let id: Int64
    let createdAt: String?
    let customerName: String?
    let inspector: String?
    let fleetSerial: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case customerName = "customer_name"
        case inspector
        case fleetSerial = "fleet_serial"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
        fleetSerial = try container.decodeIfPresent(Int64.self, forKey: .fleetSerial)
        if let inspectorString = try? container.decode(String.self, forKey: .inspector) {
            inspector = inspectorString
        } else if let inspectorID = try? container.decode(Int64.self, forKey: .inspector) {
            inspector = String(inspectorID)
        } else {
            inspector = nil
        }
    }
}

private struct SupabaseTaskRow: Decodable {
    let id: Int64
    let title: String?
    let description: String?
    let index: Int?
}

private struct SupabaseTaskStateRow: Decodable {
    let id: Int64
    let state: String?
}

private struct SupabaseReportRow: Decodable {
    let id: Int64
    let reportPDF: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportPDF = "report_pdf"
    }
}

private struct SupabaseReportListRow: Decodable {
    let id: Int64
    let inspectionID: Int64?
    let reportPDF: String?
    let pdfCreated: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case inspectionID = "inspection_id"
        case reportPDF = "report_pdf"
        case pdfCreated = "pdf_created"
        case createdAt = "created_at"
    }
}

private struct FleetInsertPayload: Encodable {
    let name: String?
    let serialNumber: String?
    let type: String?
    let make: String?
    let family: String?
    let model: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case serialNumber = "serial_number"
        case type
        case make
        case family
        case model
    }
}

private struct InspectionInsertPayload: Encodable {
    let fleetSerial: Int64
    let report: [Int64]
    let tasks: [Int64]
    let customerID: Int64?
    let customerName: String?
    let workOrder: String?
    let inspector: Int64?
    let location: String?
    let assetID: String?

    enum CodingKeys: String, CodingKey {
        case fleetSerial = "fleet_serial"
        case report
        case tasks
        case customerID = "customer_id"
        case customerName = "customer_name"
        case workOrder = "work_order"
        case inspector
        case location
        case assetID = "asset_id"
    }
}

private struct TaskInsertPayload: Encodable {
    let title: String
    let state: String
    let images: [String]
    let anomolies: [String]
    let index: Int
    let fleetSerial: Int64
    let inspectionID: Int64
    let description: String
    let feedback: String

    enum CodingKeys: String, CodingKey {
        case title
        case state
        case images
        case anomolies
        case index
        case fleetSerial = "fleet_serial"
        case inspectionID = "inspection_id"
        case description
        case feedback
    }
}

private struct ReportInsertPayload: Encodable {
    let inspectionID: Int64
    let tasks: [Int64]
    let reportPDF: String?
    let pdfCreated: String?

    enum CodingKeys: String, CodingKey {
        case inspectionID = "inspection_id"
        case tasks
        case reportPDF = "report_pdf"
        case pdfCreated = "pdf_created"
    }
}

private struct LocalInspectionReportContext {
    let customerName: String
    let serialNumber: String
    let model: String
    let inspector: String
    let date: String
}

private struct LocalReportRenderData {
    let customerName: String
    let serialNumber: String
    let model: String
    let inspector: String
    let date: String
    let inspectionID: Int64
    let componentIdentified: String
    let overallStatus: String
    let operationalImpact: String
    let anomalies: [[String: String]]

    var normalizedStatus: String {
        switch overallStatus.uppercased() {
        case "RED":
            return "Critical"
        case "AMBER":
            return "Moderate"
        case "GREEN":
            return "Normal"
        default:
            return overallStatus
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
