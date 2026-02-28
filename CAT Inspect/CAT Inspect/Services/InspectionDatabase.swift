//
//  InspectionDatabase.swift
//  CAT Inspect
//

import Foundation

struct FleetTaskRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var taskNumber: Int
    var title: String
    var detail: String
    var started: Bool
    var completed: Bool
    var feedbackText: String
    var photoFileNames: [String]
    var audioFileName: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case taskNumber
        case title
        case detail
        case started
        case completed
        case feedbackText
        case photoFileNames
        case photoFileName
        case audioFileName
        case updatedAt
    }

    init(
        id: UUID,
        taskNumber: Int,
        title: String,
        detail: String,
        started: Bool,
        completed: Bool,
        feedbackText: String,
        photoFileNames: [String],
        audioFileName: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.taskNumber = taskNumber
        self.title = title
        self.detail = detail
        self.started = started
        self.completed = completed
        self.feedbackText = feedbackText
        self.photoFileNames = photoFileNames
        self.audioFileName = audioFileName
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskNumber = try container.decode(Int.self, forKey: .taskNumber)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        started = try container.decode(Bool.self, forKey: .started)
        completed = try container.decode(Bool.self, forKey: .completed)
        feedbackText = try container.decodeIfPresent(String.self, forKey: .feedbackText) ?? ""
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
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
        try container.encode(taskNumber, forKey: .taskNumber)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(started, forKey: .started)
        try container.encode(completed, forKey: .completed)
        try container.encode(feedbackText, forKey: .feedbackText)
        try container.encode(photoFileNames, forKey: .photoFileNames)
        try container.encodeIfPresent(audioFileName, forKey: .audioFileName)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct FleetInspectionRecord: Identifiable, Codable, Hashable {
    let id: UUID
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

    func record(for id: UUID) -> FleetInspectionRecord? {
        inspections.first(where: { $0.id == id })
    }

    func markTaskStarted(inspectionID: UUID, taskID: UUID) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let taskIndex = inspections[inspectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        inspections[inspectionIndex].tasks[taskIndex].started = true
        inspections[inspectionIndex].tasks[taskIndex].updatedAt = Date()
        inspections[inspectionIndex].updatedAt = Date()
        save()
    }

    func saveTaskFeedback(
        inspectionID: UUID,
        taskID: UUID,
        feedbackText: String,
        photoFileNames: [String],
        audioFileName: String?
    ) {
        guard let inspectionIndex = inspections.firstIndex(where: { $0.id == inspectionID }),
              let taskIndex = inspections[inspectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        inspections[inspectionIndex].tasks[taskIndex].feedbackText = feedbackText
        inspections[inspectionIndex].tasks[taskIndex].photoFileNames = photoFileNames
        inspections[inspectionIndex].tasks[taskIndex].audioFileName = audioFileName
        inspections[inspectionIndex].tasks[taskIndex].completed = true
        inspections[inspectionIndex].tasks[taskIndex].updatedAt = Date()
        inspections[inspectionIndex].updatedAt = Date()
        save()
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
                taskNumber: index + 1,
                title: item.0,
                detail: item.1,
                started: false,
                completed: false,
                feedbackText: "",
                photoFileNames: [],
                audioFileName: nil,
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
}
