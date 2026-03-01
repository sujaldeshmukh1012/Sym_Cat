import Foundation
import UIKit

// MARK: - Configuration

enum InspectionConfig {
    /// Modal endpoint — AI vision analysis only (no DB writes)
    static let modalBaseURL = AppRuntimeConfig.string(
        "INSPEX_MODAL_BASE_URL",
        default: "https://your-modal-endpoint.modal.run"
    )
    /// Backend API — DB operations (report anomalies, order parts)
    /// For physical devices: set CAT_BACKEND_API_URL to your Mac's LAN IP
    /// e.g. "http://192.168.1.XXX:8000" — find via: ifconfig | grep "inet "
    /// For Simulator: http://127.0.0.1:8000 works fine
    static let apiBaseURL: String = {
        let configured = AppRuntimeConfig.string("CAT_BACKEND_API_URL", default: "")
        if !configured.isEmpty { return configured }
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        // On a real device, try to discover the Mac's Bonjour name
        // Fallback: user must set CAT_BACKEND_API_URL in Info.plist or env
        let fallback = "http://127.0.0.1:8000"
        print("[InspectionConfig] WARNING: Using localhost for API — this won't work on a physical device. Set CAT_BACKEND_API_URL to your Mac's LAN IP (e.g. http://192.168.1.X:8000)")
        return fallback
        #endif
    }()
}

// MARK: - Response models

struct InspectResponse: Codable {
    var componentIdentified: String?
    var componentRoute: String?
    var overallStatus: String?
    var operationalImpact: String?
    var anomalies: [[String: AnyCodableValue]]?
    var parts: [[String: AnyCodableValue]]?
    var inspectionId: Int?
    var taskId: Int?
    var machine: String?
    var baselineText: String?
    var flaggedForReview: Bool?
    
    enum CodingKeys: String, CodingKey {
        case componentIdentified = "component_identified"
        case componentRoute = "component_route"
        case overallStatus = "overall_status"
        case operationalImpact = "operational_impact"
        case anomalies, parts
        case inspectionId = "inspection_id"
        case taskId = "task_id"
        case machine
        case baselineText = "baseline_text"
        case flaggedForReview = "flagged_for_review"
    }
}

struct ReportAnomaliesRequest: Codable {
    let taskId: Int
    let inspectionId: Int?
    let overallStatus: String
    let operationalImpact: String
    let anomalies: [[String: AnyCodableValue]]
    
    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case inspectionId = "inspection_id"
        case overallStatus = "overall_status"
        case operationalImpact = "operational_impact"
        case anomalies
    }
}

struct ReportAnomaliesResponse: Codable {
    let taskUpdated: Bool
    let anomaliesCount: Int
    let error: String
    
    enum CodingKeys: String, CodingKey {
        case taskUpdated = "task_updated"
        case anomaliesCount = "anomalies_count"
        case error
    }
}

struct OrderPartsRequest: Codable {
    let inspectionId: Int?
    let parts: [[String: AnyCodableValue]]
    
    enum CodingKeys: String, CodingKey {
        case inspectionId = "inspection_id"
        case parts
    }
}

struct OrderPartsResponse: Codable {
    let ordersCreated: Int
    let details: [String]
    let errors: [String]
    
    enum CodingKeys: String, CodingKey {
        case ordersCreated = "orders_created"
        case details, errors
    }
}

// MARK: - AnyCodableValue (handles mixed JSON)

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else { self = .null }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v):   try container.encode(v)
        case .null:          try container.encodeNil()
        }
    }
    
    var stringValue: String {
        switch self {
        case .string(let v): return v
        case .int(let v):    return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v):   return v ? "true" : "false"
        case .null:          return ""
        }
    }
}

// MARK: - Network Service

actor InspectionNetworkService {
    static let shared = InspectionNetworkService()
    private let session = URLSession.shared
    
    /// Call Modal /inspect — sends image + voice text, returns AI analysis
    func runInspection(
        imageData: Data,
        voiceText: String,
        equipmentId: String = "CAT-320-002",
        equipmentModel: String = "CAT 320 Excavator"
    ) async throws -> InspectResponse {
        let url = URL(string: "\(InspectionConfig.modalBaseURL)/inspect")!
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180  // GPU cold start can be slow
        
        var body = Data()
        
        // Image field
        body.appendMultipart(boundary: boundary, name: "image", filename: "inspection.jpg", mimeType: "image/jpeg", data: imageData)
        // Text fields
        body.appendMultipartField(boundary: boundary, name: "voice_text", value: voiceText)
        body.appendMultipartField(boundary: boundary, name: "equipment_id", value: equipmentId)
        body.appendMultipartField(boundary: boundary, name: "equipment_model", value: equipmentModel)
        // Close
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InspectionError.serverError(status, String(data: data, encoding: .utf8) ?? "")
        }
        
        return try JSONDecoder().decode(InspectResponse.self, from: data)
    }
    
    /// Call API /report-anomalies — save findings to task table
    func reportAnomalies(
        taskId: Int,
        inspectionId: Int?,
        overallStatus: String,
        operationalImpact: String,
        anomalies: [[String: AnyCodableValue]]
    ) async throws -> ReportAnomaliesResponse {
        let payload = ReportAnomaliesRequest(
            taskId: taskId,
            inspectionId: inspectionId,
            overallStatus: overallStatus,
            operationalImpact: operationalImpact,
            anomalies: anomalies
        )
        return try await postJSON(
            url: "\(InspectionConfig.apiBaseURL)/report-anomalies",
            body: payload
        )
    }
    
    /// Call API /order-parts — check inventory and create orders
    func orderParts(
        inspectionId: Int?,
        parts: [[String: AnyCodableValue]]
    ) async throws -> OrderPartsResponse {
        let payload = OrderPartsRequest(inspectionId: inspectionId, parts: parts)
        print("[Network] order-parts → \(InspectionConfig.apiBaseURL)/order-parts with \(parts.count) parts")
        return try await postJSON(
            url: "\(InspectionConfig.apiBaseURL)/order-parts",
            body: payload
        )
    }
    
    /// Call API /inventory — list inventory items, optionally filtered
    func listInventory(componentTag: String? = nil) async throws -> [[String: Any]] {
        var urlString = "\(InspectionConfig.apiBaseURL)/inventory"
        if let tag = componentTag, !tag.isEmpty {
            urlString += "?component_tag=\(tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag)"
        }
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InspectionError.serverError(status, String(data: data, encoding: .utf8) ?? "")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["data"] as? [[String: Any]] ?? []
    }
    
    /// Call API /orders — list orders for an inspection
    func listOrders(inspectionId: String? = nil) async throws -> [[String: Any]] {
        var urlString = "\(InspectionConfig.apiBaseURL)/orders"
        if let id = inspectionId {
            urlString += "?inspection_id=\(id)"
        }
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InspectionError.serverError(status, String(data: data, encoding: .utf8) ?? "")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["data"] as? [[String: Any]] ?? []
    }
    
    // MARK: - Helpers
    
    private func postJSON<T: Encodable, R: Decodable>(url: String, body: T) async throws -> R {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InspectionError.serverError(status, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }
}

enum InspectionError: LocalizedError {
    case serverError(Int, String)
    case noImage
    
    var errorDescription: String? {
        switch self {
        case .serverError(let code, let msg): return "Server error \(code): \(msg.prefix(200))"
        case .noImage: return "No image available for inspection"
        }
    }
}

// MARK: - Data helpers for multipart

extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
    
    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
