import Foundation
import Observation

enum SyncEntityType: String, Codable {
    case task
    case classItem = "class"
}

struct SyncPayload: Codable, Equatable {
    let task: TaskItem?
    let classItem: ClassItem?

    init(task: TaskItem? = nil, classItem: ClassItem? = nil) {
        self.task = task
        self.classItem = classItem
    }
}

struct SyncChange: Codable, Equatable {
    let changeID: UUID
    let entityType: SyncEntityType
    let entityID: UUID
    let payload: SyncPayload?

    var task: TaskItem? { payload?.task }
    var classItem: ClassItem? { payload?.classItem }
    var key: String { "\(entityType.rawValue):\(entityID.uuidString)" }

    init(entityType: SyncEntityType, entityID: UUID, payload: SyncPayload?) {
        self.changeID = UUID()
        self.entityType = entityType
        self.entityID = entityID
        self.payload = payload
    }
}

struct SyncSnapshot {
    let tasks: [TaskItem]
    let classes: [ClassItem]

    static let empty = SyncSnapshot(tasks: [], classes: [])

    func changes(to newer: SyncSnapshot) -> [SyncChange] {
        var result: [SyncChange] = []
        let oldTasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let newTasks = Dictionary(uniqueKeysWithValues: newer.tasks.map { ($0.id, $0) })
        for id in Set(oldTasks.keys).union(newTasks.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            if oldTasks[id] != newTasks[id] {
                result.append(SyncChange(
                    entityType: .task, entityID: id,
                    payload: newTasks[id].map { SyncPayload(task: $0) }
                ))
            }
        }

        let oldClasses = Dictionary(uniqueKeysWithValues: classes.map { ($0.id, $0) })
        let newClasses = Dictionary(uniqueKeysWithValues: newer.classes.map { ($0.id, $0) })
        for id in Set(oldClasses.keys).union(newClasses.keys).sorted(by: { $0.uuidString < $1.uuidString }) {
            if oldClasses[id] != newClasses[id] {
                result.append(SyncChange(
                    entityType: .classItem, entityID: id,
                    payload: newClasses[id].map { SyncPayload(classItem: $0) }
                ))
            }
        }
        return result
    }
}

private struct SyncState: Codable {
    var cursor: Int64 = 0
    var pending: [SyncChange] = []
}

struct ServerChange: Decodable {
    let sequence: Int64
    let entityType: SyncEntityType
    let entityID: UUID
    let payload: SyncPayload?

    private enum CodingKeys: String, CodingKey {
        case sequence, payload
        case entityType = "entity_type"
        case entityID = "entity_id"
    }

    var change: SyncChange {
        // The local change ID is only used for uploads. Reconstructing a new
        // value here is harmless because downloaded changes aren't re-uploaded.
        SyncChange(entityType: entityType, entityID: entityID, payload: payload)
    }
}

struct UploadChange: Encodable {
    let changeID: UUID
    let userID: UUID
    let entityType: SyncEntityType
    let entityID: UUID
    let payload: SyncPayload?

    private enum CodingKeys: String, CodingKey {
        case payload
        case changeID = "change_id"
        case userID = "user_id"
        case entityType = "entity_type"
        case entityID = "entity_id"
    }

    init(_ change: SyncChange, userID: UUID) {
        changeID = change.changeID
        self.userID = userID
        entityType = change.entityType
        entityID = change.entityID
        payload = change.payload
    }
}

@MainActor
@Observable
final class CloudSync {
    private(set) var status = "local only"
    private(set) var pendingCount = 0
    private(set) var lastSynced: Date?

    @ObservationIgnored private var activeUserID: UUID?
    @ObservationIgnored private var state = SyncState()
    @ObservationIgnored private var baseline = SyncSnapshot.empty
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private let stateDirectory: URL

    init(stateDirectory: URL? = nil) {
        if let stateDirectory {
            self.stateDirectory = stateDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.stateDirectory = base.appending(path: "DAYSHIFT/accounts")
        }
    }

    func activate(for account: CloudAccount, store: TaskStore) {
        let userID = account.userID
        guard userID != activeUserID else { return }
        activeUserID = userID
        let importedGuestData = store.useAccount(userID)
        guard let userID else {
            state = SyncState()
            baseline = SyncSnapshot(tasks: store.tasks, classes: store.classes)
            pendingCount = 0
            lastSynced = nil
            status = "local only"
            return
        }

        state = loadState(for: userID)
        let current = SyncSnapshot(tasks: store.tasks, classes: store.classes)
        baseline = current
        if importedGuestData {
            enqueue(SyncSnapshot.empty.changes(to: current))
        }
        pendingCount = state.pending.count
        status = "connecting"
        syncNow(account: account, store: store)
    }

    func localStateChanged(store: TaskStore, account: CloudAccount) {
        guard activeUserID != nil else { return }
        let current = SyncSnapshot(tasks: store.tasks, classes: store.classes)
        let changes = baseline.changes(to: current)
        baseline = current
        guard !changes.isEmpty else { return }
        enqueue(changes)
        syncNow(account: account, store: store)
    }

    func syncNow(account: CloudAccount, store: TaskStore) {
        guard activeUserID != nil else { return }
        if isSyncing { needsAnotherPass = true; return }
        isSyncing = true
        Task {
            defer {
                isSyncing = false
                if needsAnotherPass {
                    needsAnotherPass = false
                    syncNow(account: account, store: store)
                }
            }
            do {
                try await sync(account: account, store: store)
                if activeUserID == account.userID {
                    status = "synced"
                    lastSynced = Date()
                }
            } catch {
                if activeUserID != nil {
                    status = state.pending.isEmpty ? "could not connect" : "offline · \(state.pending.count) waiting"
                }
            }
        }
    }

    private func sync(account: CloudAccount, store: TaskStore) async throws {
        guard let userID = activeUserID, userID == account.userID,
              let configuration = CloudConfiguration.bundled else { return }
        let token = try await account.accessToken()
        let api = CloudAPI(configuration: configuration)

        try await downloadChanges(api: api, token: token, userID: userID, store: store)
        guard activeUserID == userID, !state.pending.isEmpty else { return }

        while !state.pending.isEmpty && activeUserID == userID {
            let batch = Array(state.pending.prefix(100))
            let upload = batch.map { UploadChange($0, userID: userID) }
            let encoder = JSONEncoder()
            let body = try encoder.encode(upload)
            _ = try await api.request(
                "/rest/v1/dayshift_changes?on_conflict=user_id,change_id",
                method: "POST", body: body, accessToken: token,
                headers: ["Prefer": "resolution=ignore-duplicates,return=minimal"]
            )
            guard activeUserID == userID else { return }
            let uploadedIDs = Set(batch.map(\.changeID))
            state.pending.removeAll { uploadedIDs.contains($0.changeID) }
            pendingCount = state.pending.count
            saveState(for: userID)
        }
        try await downloadChanges(api: api, token: token, userID: userID, store: store)
    }

    private func downloadChanges(api: CloudAPI, token: String, userID: UUID, store: TaskStore) async throws {
        while activeUserID == userID {
            let path = "/rest/v1/dayshift_changes?select=sequence,entity_type,entity_id,payload"
                + "&user_id=eq.\(userID.uuidString.lowercased())"
                + "&sequence=gt.\(state.cursor)&order=sequence.asc&limit=500"
            let data = try await api.request(path, accessToken: token)
            let decoder = JSONDecoder()
            let rows = try decoder.decode([ServerChange].self, from: data)
            guard activeUserID == userID else { return }
            if rows.isEmpty { return }

            let pendingKeys = Set(state.pending.map(\.key))
            let applicable = rows.filter { !pendingKeys.contains($0.change.key) }.map(\.change)
            if !applicable.isEmpty {
                store.applySyncedChanges(applicable)
                baseline = SyncSnapshot(tasks: store.tasks, classes: store.classes)
            }
            state.cursor = rows.last!.sequence
            saveState(for: userID)
            if rows.count < 500 { return }
        }
    }

    private func enqueue(_ changes: [SyncChange]) {
        guard let userID = activeUserID, !changes.isEmpty else { return }
        let changedKeys = Set(changes.map(\.key))
        state.pending.removeAll { changedKeys.contains($0.key) }
        state.pending.append(contentsOf: changes)
        pendingCount = state.pending.count
        status = "\(pendingCount) waiting to sync"
        saveState(for: userID)
    }

    private func stateURL(for userID: UUID) -> URL {
        stateDirectory.appending(path: userID.uuidString.lowercased()).appendingPathComponent("sync.json")
    }

    private func loadState(for userID: UUID) -> SyncState {
        guard let data = try? Data(contentsOf: stateURL(for: userID)) else { return SyncState() }
        return (try? JSONDecoder().decode(SyncState.self, from: data)) ?? SyncState()
    }

    private func saveState(for userID: UUID) {
        let url = stateURL(for: userID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            status = "could not save pending changes"
        }
    }
}
