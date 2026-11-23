import Foundation

enum ReviewKind: String, Codable, CaseIterable, Identifiable {
    case mistake, card, task

    var id: Self { self }

    var title: String {
        switch self {
        case .mistake: "错题重做"
        case .card: "知识卡片"
        case .task: "复习计划"
        }
    }

    var icon: String {
        switch self {
        case .mistake: "arrow.counterclockwise"
        case .card: "rectangle.on.rectangle"
        case .task: "calendar"
        }
    }
}

struct ReviewItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: ReviewKind
    var course = ""
    var title = ""
    var answer = ""
    var notes = ""
    var photo: Data?
    var due = Date()
    var exam: Date?
    var sourceMistake: UUID?
    var streak = 0
    var done = false
    var modified = Date()

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        !done && due < (calendar.dateInterval(of: .day, for: date)?.end ?? date)
    }

    mutating func grade(_ recalled: Bool, at date: Date, calendar: Calendar = .current) {
        let intervals = [1, 3, 7, 14, 30]
        let delay = recalled ? intervals[min(max(streak, 0), intervals.count - 1)] : 1
        streak = recalled ? min(max(streak, 0) + 1, intervals.count) : 0
        due = calendar.date(byAdding: .day, value: delay, to: calendar.startOfDay(for: date)) ?? date
        modified = date
    }
}

struct WatchResponse: Codable, Equatable {
    let itemID: UUID
    let value: Bool
    let date: Date

    func applying(to original: ReviewItem) -> ReviewItem {
        guard original.id == itemID, original.modified < date else { return original }
        var item = original
        switch item.kind {
        case .mistake: break
        case .card: item.grade(value, at: date)
        case .task:
            item.done = value
            item.modified = date
        }
        return item
    }
}
