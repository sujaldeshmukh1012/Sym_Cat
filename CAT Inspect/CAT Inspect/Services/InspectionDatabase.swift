//
//  InspectionDatabase.swift
//  CAT Inspect
//

import Foundation

enum TaskReportStatus: String, CaseIterable, Codable {
    case monitor = "Moderate"
    case pass = "Pass"
    case normal = "Normal"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "monitor", "moderate":
            self = .monitor
        case "pass":
            self = .pass
        case "normal":
            self = .normal
        default:
            self = .normal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct StructuredTaskReportInput: Codable, Hashable, Identifiable {
    let id: UUID
    let backendTaskID: Int64?
    let taskNumber: Int
    let sourceTitle: String
    var summaryTitle: String
    var status: TaskReportStatus
    var taskFeedback: String
}

struct StructuredInspectionReportFormData: Codable, Hashable {
    var generalInfo: String
    var comments: String
    var taskInputs: [StructuredTaskReportInput]
    var signatureVector: String
}

struct FleetTaskRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var backendTaskID: Int64?
    var taskNumber: Int
    var title: String
    var detail: String
    var started: Bool
    var completed: Bool
    var feedbackText: String
    var photoFileNames: [String]
    var audioFileName: String?
    var backendSyncStatus: String
    var backendError: String
    var walkthroughStatus: TaskReportStatus
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case backendTaskID
        case taskNumber
        case title
        case detail
        case started
        case completed
        case feedbackText
        case photoFileNames
        case photoFileName
        case audioFileName
        case backendSyncStatus
        case backendError
        case walkthroughStatus
        case updatedAt
    }

    init(
        id: UUID,
        backendTaskID: Int64? = nil,
        taskNumber: Int,
        title: String,
        detail: String,
        started: Bool,
        completed: Bool,
        feedbackText: String,
        photoFileNames: [String],
        audioFileName: String?,
        backendSyncStatus: String = "pending",
        backendError: String = "",
        walkthroughStatus: TaskReportStatus = .normal,
        updatedAt: Date
    ) {
        self.id = id
        self.backendTaskID = backendTaskID
        self.taskNumber = taskNumber
        self.title = title
        self.detail = detail
        self.started = started
        self.completed = completed
        self.feedbackText = feedbackText
        self.photoFileNames = photoFileNames
        self.audioFileName = audioFileName
        self.backendSyncStatus = backendSyncStatus
        self.backendError = backendError
        self.walkthroughStatus = walkthroughStatus
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        backendTaskID = try container.decodeIfPresent(Int64.self, forKey: .backendTaskID)
        taskNumber = try container.decode(Int.self, forKey: .taskNumber)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        started = try container.decode(Bool.self, forKey: .started)
        completed = try container.decode(Bool.self, forKey: .completed)
        feedbackText = try container.decodeIfPresent(String.self, forKey: .feedbackText) ?? ""
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        backendSyncStatus = try container.decodeIfPresent(String.self, forKey: .backendSyncStatus) ?? "pending"
        backendError = try container.decodeIfPresent(String.self, forKey: .backendError) ?? ""
        walkthroughStatus = try container.decodeIfPresent(TaskReportStatus.self, forKey: .walkthroughStatus) ?? .normal
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        if let list = try container.decodeIfPresent([String].self, forKey: .photoFileNames) {
            photoFileNames = list
        } else if let single = try container.decodeIfPresent(String.self, forKey: .photoFileName) {
            photoFileNames = [single]
        } else {
            photoFileNames = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(backendTaskID, forKey: .backendTaskID)
        try container.encode(taskNumber, forKey: .taskNumber)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(started, forKey: .started)
        try container.encode(completed, forKey: .completed)
        try container.encode(feedbackText, forKey: .feedbackText)
        try container.encode(photoFileNames, forKey: .photoFileNames)
        try container.encodeIfPresent(audioFileName, forKey: .audioFileName)
        try container.encode(backendSyncStatus, forKey: .backendSyncStatus)
        try container.encode(backendError, forKey: .backendError)
        try container.encode(walkthroughStatus, forKey: .walkthroughStatus)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct FleetInspectionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var backendInspectionID: Int64?
    var backendFleetID: Int64?
    var createdAt: Date
    var updatedAt: Date
    var inspectorName: String
    var assetName: String
    var serialNumber: String
    var model: String
    var serviceMeterValue: String
    var productFamily: String
    var make: String
    var assetID: String
    var location: String
    var customerUCID: String
    var customerName: String
    var customerPhone: String
    var customerEmail: String
    var workOrderNumber: String
    var additionalEmails: [String]
    var generalInfo: String
    var comments: String
    var tasks: [FleetTaskRecord]
}

struct FleetInspectionFormData {
    var backendFleetID: Int64?
    var inspectorName: String
    var assetName: String
    var serialNumber: String
    var model: String
    var serviceMeterValue: String
    var productFamily: String
    var make: String
    var assetID: String
    var location: String
    var customerUCID: String
    var customerName: String
    var customerPhone: String
    var customerEmail: String
    var workOrderNumber: String
    var additionalEmails: [String]
    var generalInfo: String
    var comments: String
}

@MainActor
final class InspectionDatabase: ObservableObject {
    @Published private(set) var inspections: [FleetInspectionRecord] = []

    private let backend = SupabaseInspectionBackend.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func createInspection(from form: FleetInspectionFormData) -> FleetInspectionRecord {
        let now = Date()
        let tasks = Self.defaultTasks()
        let record = FleetInspectionRecord(
            id: UUID(),
            backendInspectionID: nil,
            backendFleetID: form.backendFleetID,
            createdAt: now,
            updatedAt: now,
            inspectorName: form.inspectorName,
            assetName: form.assetName,
            serialNumber: form.serialNumber,
            model: form.model,
            serviceMeterValue: form.serviceMeterValue,
            productFamily: form.productFamily,
            make: form.make,
            assetID: form.assetID,
            location: form.location,
            customerUCID: form.customerUCID,
            customerName: form.customerName,
            customerPhone: form.customerPhone,
            customerEmail: form.customerEmail,
            workOrderNumber: form.workOrderNumber,
            additionalEmails: form.additionalEmails.filter { !$0.isEmpty },
            generalInfo: form.generalInfo,
            comments: form.comments,
            tasks: tasks
        )
        inspections.insert(record, at: 0)
        save()
        return record
    }

    func createInspectionFromBackend(from form: FleetInspectionFormData) async throws -> FleetInspectionRecord {
        print("[BackendSync] createInspectionFromBackend.start serial=\(form.serialNumber) asset=\(form.assetName)")
        let backendResult = try await backend.createInspection(from: form)
        print("[BackendSync] createInspectionFromBackend.success inspectionID=\(backendResult.inspectionID) fleetID=\(backendResult.fleetID) tasks=\(backendResult.tasks.count)")
        let now = Date()
        let seededTasks = backendResult.tasks.enumerated().map { offset, backendTask in
            FleetTaskRecord(
                id: UUID(),
                backendTaskID: backendTask.taskID,
                taskNumber: backendTask.order == 0 ? (offset + 1) : backendTask.order,
                title: backendTask.title,
                detail: backendTask.detail,
                started: false,
                completed: false,
                feedbackText: "",
                photoFileNames: [],
                audioFileName: nil,
                backendSyncStatus: "pending",
                backendError: "",
                walkthroughStatus: .normal,
                updatedAt: now
            )
        }

        let tasks = seededTasks.isEmpty ? Self.defaultTasks() : seededTasks
        let resolvedAssetName: String = {
            let backendName = backendResult.fleetName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !backendName.isEmpty { return backendName }
            let formName = form.assetName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !formName.isEmpty { return formName }
            let modelName = form.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelName.isEmpty { return modelName }
            return "Fleet Asset"
        }()
        let record = FleetInspectionRecord(
            id: UUID(),
            backendInspectionID: backendResult.inspectionID,
            backendFleetID: backendResult.fleetID,
            createdAt: now,
            updatedAt: now,
            inspectorName: form.inspectorName,
            assetName: resolvedAssetName,
            serialNumber: form.serialNumber.isEmpty ? backendResult.serialNumber : form.serialNumber,
            model: form.model.isEmpty ? backendResult.model : form.model,
            serviceMeterValue: form.serviceMeterValue,
            productFamily: form.productFamily.isEmpty ? backendResult.family : form.productFamily,
            make: form.make.isEmpty ? backendResult.make : form.make,
            assetID: form.assetID,
            location: form.location,
            customerUCID: form.customerUCID,
            customerName: form.customerName,
            customerPhone: form.customerPhone,
            customerEmail: form.customerEmail,
            workOrderNumber: form.workOrderNumber,
            additionalEmails: form.additionalEmails.filter { !$0.isEmpty },
            generalInfo: form.generalInfo,
            comments: form.comments,
            tasks: tasks
        )
        inspections.insert(record, at: 0)
        save()
        return record
    }

    func record(for id: UUID) -> FleetInspectionRecord? {
        inspections.first(where: { $0.id == id })
    }

    func markTaskStarted(inspectionID: UUID, taskID: UUID) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let taskIndex = inspections[inspectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        inspections[inspectionIndex].tasks[taskIndex].started = true
        inspections[inspectionIndex].tasks[taskIndex].updatedAt = Date()
        inspections[inspectionIndex].updatedAt = Date()
        let backendTaskID = inspections[inspectionIndex].tasks[taskIndex].backendTaskID
        save()
        if let backendTaskID {
            Task {
                try? await backend.markTaskStarted(taskID: backendTaskID)
            }
        }
    }

    func saveTaskFeedback(
        inspectionID: UUID,
        taskID: UUID,
        feedbackText: String,
        photoFileNames: [String],
        audioFileName: String?,
        walkthroughStatus: TaskReportStatus
    ) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let taskIndex = inspections[inspectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        inspections[inspectionIndex].tasks[taskIndex].feedbackText = feedbackText
        inspections[inspectionIndex].tasks[taskIndex].photoFileNames = photoFileNames
        inspections[inspectionIndex].tasks[taskIndex].audioFileName = audioFileName
        inspections[inspectionIndex].tasks[taskIndex].walkthroughStatus = walkthroughStatus
        inspections[inspectionIndex].tasks[taskIndex].completed = true
        inspections[inspectionIndex].tasks[taskIndex].updatedAt = Date()
        inspections[inspectionIndex].updatedAt = Date()
        save()
    }

    func saveTaskFeedbackAndSync(
        inspectionID: UUID,
        taskID: UUID,
        feedbackText: String,
        photoFileNames: [String],
        audioFileName: String?,
        walkthroughStatus: TaskReportStatus
    ) async -> String {
        print("[BackendSync] saveTaskFeedbackAndSync.start inspectionID=\(inspectionID) taskID=\(taskID) photos=\(photoFileNames.count)")
        saveTaskFeedback(
            inspectionID: inspectionID,
            taskID: taskID,
            feedbackText: feedbackText,
            photoFileNames: photoFileNames,
            audioFileName: audioFileName,
            walkthroughStatus: walkthroughStatus
        )

        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let taskIndex = inspections[inspectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            print("[BackendSync] saveTaskFeedbackAndSync.localOnly reason=record_not_found")
            return "Saved locally."
        }

        guard let backendTaskID = inspections[inspectionIndex].tasks[taskIndex].backendTaskID else {
            inspections[inspectionIndex].tasks[taskIndex].backendSyncStatus = "local_only"
            save()
            print("[BackendSync] saveTaskFeedbackAndSync.localOnly reason=missing_backend_task_id")
            return "Saved locally (backend task pending)."
        }

        do {
            let backendInspectionID = inspections[inspectionIndex].backendInspectionID
            let localPhotos = photoFileNames.compactMap { name -> (fileName: String, data: Data, mimeType: String)? in
                let url = localMediaURL(fileName: name)
                guard let data = try? Data(contentsOf: url) else { return nil }
                let lower = name.lowercased()
                let mime = lower.hasSuffix(".png") ? "image/png" : "image/jpeg"
                return (fileName: name, data: data, mimeType: mime)
            }
            let imageRefs: [String]
            if let backendInspectionID {
                imageRefs = try await backend.uploadTaskImages(
                    inspectionID: backendInspectionID,
                    taskID: backendTaskID,
                    localPhotos: localPhotos
                )
            } else {
                imageRefs = photoFileNames.map { "local://\($0)" }
            }
            let fleetIDContext = inspections[inspectionIndex].backendFleetID.map(String.init) ?? "unknown"
            let inspectionContext = inspections[inspectionIndex].backendInspectionID.map(String.init) ?? "unknown"
            let voiceContext = audioFileName.map { "voice_note=\($0)" } ?? "voice_note=none"
            let combinedFeedback = """
            \(feedbackText)
            [context inspection_id=\(inspectionContext) fleet_id=\(fleetIDContext) task_status=\(walkthroughStatus.rawValue) \(voiceContext) images=\(imageRefs.joined(separator: ","))]
            """
            try await backend.submitTaskFeedback(
                taskID: backendTaskID,
                feedbackText: combinedFeedback,
                imageURLs: imageRefs,
                anomalies: []
            )
            inspections[inspectionIndex].tasks[taskIndex].backendSyncStatus = "synced"
            inspections[inspectionIndex].tasks[taskIndex].backendError = ""
            save()
            print("[BackendSync] saveTaskFeedbackAndSync.synced backendTaskID=\(backendTaskID)")
            return "Feedback synced."
        } catch {
            inspections[inspectionIndex].tasks[taskIndex].backendSyncStatus = "failed"
            inspections[inspectionIndex].tasks[taskIndex].backendError = error.localizedDescription
            save()
            print("[BackendSync] saveTaskFeedbackAndSync.failed backendTaskID=\(backendTaskID) error=\(error.localizedDescription)")
            return "Saved locally. Sync failed."
        }
    }

    func requestReportGeneration(for inspectionID: UUID) async throws -> String {
        print("[BackendSync] requestReportGeneration.start inspectionID=\(inspectionID)")
        guard let record = record(for: inspectionID),
              let backendInspectionID = record.backendInspectionID else {
            print("[BackendSync] requestReportGeneration.failed reason=missing_backend_inspection")
            throw BackendError.missingInspection
        }
        let taskIDs = record.tasks.compactMap(\.backendTaskID)
        let result = try await backend.requestReportGeneration(inspectionID: backendInspectionID, taskIDs: taskIDs)
        print("[BackendSync] requestReportGeneration.success reportID=\(result.reportID)")
        return "Report request submitted (\(result.reportID))."
    }

    func submitStructuredReport(
        for inspectionID: UUID,
        form: StructuredInspectionReportFormData
    ) async throws -> (reportID: Int64, reportURL: String, reportBody: String) {
        guard let record = record(for: inspectionID),
              let backendInspectionID = record.backendInspectionID else {
            throw BackendError.missingInspection
        }

        let backendTaskIDs = form.taskInputs.compactMap(\.backendTaskID)
        let reportPayload = buildReportPayload(record: record, form: form)
        let result = try await backend.submitFinalReport(
            inspectionID: backendInspectionID,
            taskIDs: backendTaskIDs,
            reportPayload: reportPayload
        )
        let reportBody = renderReportDocumentBody(record: record, form: form)
        return (result.reportID, result.reportPDF, reportBody)
    }

    private func buildReportPayload(
        record: FleetInspectionRecord,
        form: StructuredInspectionReportFormData
    ) -> BackendReportPayload {
        let overallStatus: String = form.taskInputs.contains(where: { $0.status == .monitor }) ? "AMBER" : "GREEN"
        let anomalies: [[String: String]] = form.taskInputs.map { task in
            let severity: String = {
                switch task.status {
                case .monitor:
                    return "Moderate"
                case .normal, .pass:
                    return "Normal"
                }
            }()
            return [
                "component": task.summaryTitle,
                "issue": "Task \(task.taskNumber) status: \(task.status.rawValue)",
                "description": task.taskFeedback.isEmpty ? task.sourceTitle : task.taskFeedback,
                "severity": severity,
                "recommended_action": form.comments.isEmpty ? "Review and close task findings." : form.comments
            ]
        }
        let component = form.taskInputs.first?.summaryTitle ?? record.assetName
        let impact = "\(form.generalInfo)\n\(form.comments)".trimmingCharacters(in: .whitespacesAndNewlines)
        return BackendReportPayload(
            componentIdentified: component.isEmpty ? "Fleet Inspection" : component,
            overallStatus: overallStatus,
            operationalImpact: impact.isEmpty ? "Inspection summary submitted." : impact,
            anomalies: anomalies,
            inspectorName: record.inspectorName
        )
    }

    private func renderReportDocumentBody(
        record: FleetInspectionRecord,
        form: StructuredInspectionReportFormData
    ) -> String {
        let inspectionIDText = record.backendInspectionID.map(String.init) ?? record.id.uuidString
        let fleetSerialText = record.backendFleetID.map(String.init) ?? record.serialNumber
        let generatedAt = ISO8601DateFormatter().string(from: Date())

        let taskLines = form.taskInputs
            .sorted(by: { $0.taskNumber < $1.taskNumber })
            .map {
                [
                    "- task_number: \($0.taskNumber)",
                    "  backend_task_id: \($0.backendTaskID.map(String.init) ?? "n/a")",
                    "  summarized_title: \($0.summaryTitle)",
                    "  status: \($0.status.rawValue)",
                    "  feedback: \($0.taskFeedback)"
                ].joined(separator: "\n")
            }
            .joined(separator: "\n")

        return """
        CAT_INSPECTION_REPORT_V1
        generated_at: \(generatedAt)

        NON_EDITABLE:
        inspection_id: \(inspectionIDText)
        fleet_serial: \(fleetSerialText)
        inspector: \(record.inspectorName)
        location: \(record.location)

        EDITABLE:
        general_info: \(form.generalInfo)
        comments: \(form.comments)

        TASKS:
        \(taskLines)

        DIGITAL_SIGNATURE:
        \(form.signatureVector)
        """
    }

    static func defaultTasks() -> [FleetTaskRecord] {
        let template: [(String, String)] = [
            ("Exterior Walkaround", "Check visible frame and body condition for damage or wear."),
            ("Fluid Leakage Check", "Inspect hydraulic lines, joints, and undercarriage for leaks."),
            ("Engine Bay Condition", "Validate hoses, belts, and fasteners around engine components."),
            ("Safety Components", "Verify alarms, lights, emergency shutoff and warning labels."),
            ("Attachment Interface", "Inspect couplers, pins, and locking mechanisms."),
            ("Operator Feedback", "Capture operator comments for performance and unusual behavior.")
        ]
        return template.enumerated().map { index, item in
            FleetTaskRecord(
                id: UUID(),
                backendTaskID: nil,
                taskNumber: index + 1,
                title: item.0,
                detail: item.1,
                started: false,
                completed: false,
                feedbackText: "",
                photoFileNames: [],
                audioFileName: nil,
                backendSyncStatus: "pending",
                backendError: "",
                walkthroughStatus: .normal,
                updatedAt: Date()
            )
        }
    }

    private var dbFileURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("inspection_database.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: dbFileURL),
              let decoded = try? decoder.decode([FleetInspectionRecord].self, from: data) else {
            inspections = []
            return
        }
        inspections = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(inspections) else { return }
        try? data.write(to: dbFileURL, options: [.atomic])
    }

    private func localMediaURL(fileName: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(fileName)
    }
}
