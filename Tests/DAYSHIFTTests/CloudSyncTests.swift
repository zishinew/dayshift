import XCTest
@testable import DAYSHIFT

final class CloudSyncTests: XCTestCase {
    func testSnapshotRecordsEditsAndDeletionsForTasksAndClasses() {
        let task = TaskItem(title: "Study", dueDate: Date(), priority: .medium)
        let classItem = ClassItem(code: "MATH237", name: "")
        let initial = SyncSnapshot.empty.changes(to: SyncSnapshot(tasks: [task], classes: [classItem]))
        XCTAssertEqual(initial.count, 2)
        XCTAssertEqual(initial.first { $0.entityType == .task }?.task, task)
        XCTAssertEqual(initial.first { $0.entityType == .classItem }?.classItem, classItem)

        let deletion = SyncSnapshot(tasks: [task], classes: [classItem]).changes(to: .empty)
        XCTAssertEqual(deletion.count, 2)
        XCTAssertTrue(deletion.allSatisfy { $0.payload == nil })
    }

    func testCloudWireFormatRoundTripsTaskPayload() throws {
        let userID = UUID()
        let task = TaskItem(title: "Quiz", dueDate: Date(), priority: .high, isEvent: true)
        let change = SyncChange(entityType: .task, entityID: task.id, payload: SyncPayload(task: task))
        let encoded = try JSONEncoder().encode(UploadChange(change, userID: userID))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["change_id"] as? String, change.changeID.uuidString)
        XCTAssertEqual(object["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(object["entity_type"] as? String, "task")

        var serverObject = object
        serverObject["sequence"] = 1
        let serverData = try JSONSerialization.data(withJSONObject: serverObject)
        let decoded = try JSONDecoder().decode(ServerChange.self, from: serverData)
        XCTAssertEqual(decoded.entityID, task.id)
        XCTAssertEqual(decoded.change.task, task)
    }

    @MainActor
    func testAccountCacheKeepsGuestDataSeparate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(fileURL: directory.appendingPathComponent("tasks.json"))
        store.add(ParsedTask(title: "Guest task", dueDate: Date(), priority: .medium, classCode: nil, repeatRule: nil))

        let userID = UUID()
        XCTAssertTrue(store.useAccount(userID))
        XCTAssertEqual(store.tasks.map(\.title), ["Guest task"])
        store.add(ParsedTask(title: "Account task", dueDate: Date(), priority: .medium, classCode: nil, repeatRule: nil))

        store.useAccount(nil)
        XCTAssertEqual(store.tasks.map(\.title), ["Guest task"])
        XCTAssertFalse(store.useAccount(userID))
        XCTAssertEqual(Set(store.tasks.map(\.title)), ["Guest task", "Account task"])
    }
}
