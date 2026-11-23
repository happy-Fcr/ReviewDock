import SwiftUI

@main
struct ReviewDockWatchApp: App {
    @StateObject private var store = ReviewStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimelineView(.everyMinute) { timeline in
                    TodayOnWatch(date: timeline.date)
                }
                .navigationTitle("今日复习")
            }
            .environmentObject(store)
        }
    }
}

private struct TodayOnWatch: View {
    @EnvironmentObject private var store: ReviewStore
    let date: Date

    var body: some View {
        let due = store.items.filter { $0.isDue(on: date) }
        List {
            if let error = store.storageError {
                Text(error).font(.caption)
            }
            Section {
                let cards = due.filter { $0.kind == .card }
                if cards.isEmpty { Text("暂无待背卡片").foregroundStyle(.secondary) }
                ForEach(cards) { card in
                    NavigationLink {
                        CardOnWatch(id: card.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.title).lineLimit(3)
                            Text(card.course).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("知识卡片", systemImage: ReviewKind.card.icon)
            }
            Section {
                let tasks = store.items.filter {
                    $0.kind == .task && ($0.isDue(on: date) ||
                    ($0.done && Calendar.current.isDate($0.modified, inSameDayAs: date)))
                }
                if tasks.isEmpty { Text("暂无今日任务").foregroundStyle(.secondary) }
                ForEach(tasks) { task in
                    Button {
                        store.respond(to: task, value: !task.done)
                    } label: {
                        Label(task.title, systemImage: task.done ? "checkmark.circle.fill" : "circle")
                    }
                    .accessibilityValue(task.done ? "已完成" : "待完成")
                }
            } header: {
                Label("复习计划", systemImage: ReviewKind.task.icon)
            }
        }
    }
}

private struct CardOnWatch: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAnswer = false
    let id: UUID

    var body: some View {
        if let card = store.items.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(card.course).font(.caption).foregroundStyle(.secondary)
                    Text(card.title).font(.headline)
                    if showAnswer {
                        Text(card.answer)
                        Button("记住了") { answer(card, true) }.buttonStyle(.borderedProminent)
                        Button("还不熟") { answer(card, false) }
                    } else {
                        Button("翻看答案") { showAnswer = true }.buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        } else {
            Text("这张卡片已删除")
        }
    }

    private func answer(_ card: ReviewItem, _ value: Bool) {
        store.respond(to: card, value: value)
        dismiss()
    }
}
