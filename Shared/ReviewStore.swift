import Foundation
import SwiftUI
import WatchConnectivity

@MainActor
final class ReviewStore: NSObject, ObservableObject, WCSessionDelegate {
    private struct DataFile: Codable {
        var items: [ReviewItem] = []
        var responses: [WatchResponse] = []
    }

    @Published private var file: DataFile
    @Published var storageError: String?
    private let fileURL: URL

    var items: [ReviewItem] {
        file.items.map { item in
#if os(watchOS)
            return file.responses.first { $0.itemID == item.id }?.applying(to: item) ?? item
#else
            return item
#endif
        }
        .sorted { $0.due < $1.due }
    }

    override init() {
        let location = URL.applicationSupportDirectory.appending(path: "ReviewDock/review.json")
        fileURL = location
        var loadError: String?
        if FileManager.default.fileExists(atPath: location.path) {
            do {
                file = try JSONDecoder().decode(DataFile.self, from: Data(contentsOf: location))
            } catch {
                file = DataFile()
                loadError = "�޷���ȡ��ϰ���ݡ����ļ��ѱ����������´� App��"
            }
        } else {
            file = DataFile()
        }
        super.init()
        storageError = loadError
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func save(_ value: ReviewItem) {
        var item = value
        item.modified = Date()
        replace(item)
    }

    func delete(_ value: ReviewItem) {
        var next = file
        next.items.removeAll { $0.id == value.id }
        commit(next)
    }

    func respond(to item: ReviewItem, value: Bool) {
        let response = WatchResponse(itemID: item.id, value: value, date: Date())
#if os(watchOS)
        var next = file
        next.responses.removeAll { $0.itemID == item.id }
        next.responses.append(response)
        commit(next)
#else
        if item.kind == .mistake {
            var updated = item
            updated.grade(value, at: response.date)
            replace(updated)
        } else {
            replace(response.applying(to: item))
        }
#endif
    }

    private func replace(_ item: ReviewItem) {
        var next = file
        next.items.removeAll { $0.id == item.id }
        next.items.append(item)
        commit(next)
    }

    private func commit(_ next: DataFile, sync: Bool = true) {
        guard storageError == nil else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
            file = next
            if sync { publish() }
        } catch {
            storageError = "����ʧ�ܡ������豸�洢�ռ�����´� App��"
        }
    }

    private func publish() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
#if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let cardsAndTasks = file.items.filter { $0.kind != .mistake }
        guard let data = try? JSONEncoder().encode(cardsAndTasks) else { return }
        try? session.updateApplicationContext(["items": data])
#else
        guard let data = try? JSONEncoder().encode(file.responses) else { return }
        try? session.updateApplicationContext(["responses": data])
#endif
    }

    private func receive(_ data: Data) {
#if os(iOS)
        guard let responses = try? JSONDecoder().decode([WatchResponse].self, from: data) else { return }
        let byID = Dictionary(responses.map { ($0.itemID, $0) }, uniquingKeysWith: { $0.date > $1.date ? $0 : $1 })
        var next = file
        next.items = next.items.map { byID[$0.id]?.applying(to: $0) ?? $0 }
        if next.items != file.items { commit(next) }
#else
        guard let items = try? JSONDecoder().decode([ReviewItem].self, from: data) else { return }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { $0.modified > $1.modified ? $0 : $1 })
        var next = file
        next.items = items
        next.responses = next.responses.filter { response in
            guard let item = byID[response.itemID] else { return false }
            return response.date > item.modified
        }
        if next.items != file.items || next.responses != file.responses { commit(next, sync: false) }
#endif
    }

    nonisolated private static var incomingKey: String {
#if os(iOS)
        "responses"
#else
        "items"
#endif
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let data = session.receivedApplicationContext[Self.incomingKey] as? Data
        Task { @MainActor in
            if let data { receive(data) }
            publish()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.incomingKey] as? Data else { return }
        Task { @MainActor in receive(data) }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in publish() }
    }
#endif
}
