//
//  InspectionAPI.swift
//  CAT Inspect
//

import Foundation

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
}


enum BackendError: LocalizedError {
    case invalidURL
    case missingFleet(serial: String)
    case missingInspection
    case missingTask
    case invalidResponse
    case server(statusCode: Int, message: String)
    case rowLevelSecurityBlocked(table: String, operation: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Backend URL is invalid."
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
        case .rowLevelSecurityBlocked(let table, let operation):
            return "Supabase RLS blocked \(operation) on table '\(table)'. Add RLS policy for your app role."
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

final class SupabaseInspectionBackend {
    static let shared = SupabaseInspectionBackend()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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
        reportDocument: String
    ) async throws -> BackendReportResult {
        log("submitFinalReport inspectionID=\(inspectionID) taskIDs=\(taskIDs.count)")
        let reportURL = try await uploadReportDocumentToS3(inspectionID: inspectionID, reportDocument: reportDocument)
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let reportRows: [SupabaseReportRow] = try await post(
            table: "report",
            payload: [
                ReportInsertPayload(
                    inspectionID: inspectionID,
                    tasks: taskIDs,
                    reportPDF: reportURL,
                    pdfCreated: timestamp
                )
            ]
        )
        guard let first = reportRows.first else { throw BackendError.invalidResponse }
        return BackendReportResult(reportID: first.id, reportPDF: first.reportPDF ?? reportURL)
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

    private func uploadReportDocumentToS3(
        inspectionID: Int64,
        reportDocument: String
    ) async throws -> String {
        // TODO: replace with real S3 upload call when credentials and endpoint are available.
        log("uploadReportDocumentToS3 inspectionID=\(inspectionID) payloadChars=\(reportDocument.count)")
        let timestamp = Int(Date().timeIntervalSince1970)
        return "s3://cat-inspect-reports/inspection_\(inspectionID)_\(timestamp).pdf"
    }
}

private struct EmptyResponse: Decodable {}

private struct SupabaseErrorBody: Decodable {
    let code: String?
    let message: String?
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

private struct SupabaseTaskRow: Decodable {
    let id: Int64
    let title: String?
    let description: String?
    let index: Int?
}

private struct SupabaseReportRow: Decodable {
    let id: Int64
    let reportPDF: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportPDF = "report_pdf"
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
