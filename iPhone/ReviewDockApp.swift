import ImageIO
import PhotosUI
import SwiftUI
import UIKit

@main
struct ReviewDockApp: App {
    @StateObject private var store = ReviewStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { TodayView() }
                    .tabItem { Label("今天", systemImage: "sun.max") }
                ForEach(ReviewKind.allCases) { kind in
                    NavigationStack { CollectionView(kind: kind) }
                        .tabItem { Label(kind.title, systemImage: kind.icon) }
                }
            }
            .environmentObject(store)
            .safeAreaInset(edge: .top) {
                if let error = store.storageError {
                    Text(error).font(.footnote).padding(8)
                }
            }
        }
    }
}

private struct TodayView: View {
    @EnvironmentObject private var store: ReviewStore

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            List {
                ForEach(ReviewKind.allCases) { kind in
                    let due = store.items.filter { $0.kind == kind && $0.isDue(on: timeline.date) }
                    Section {
                        if due.isEmpty { Text("今天没有待完成项目").foregroundStyle(.secondary) }
                        ForEach(due) { ItemLink(item: $0) }
                    } header: {
                        Label("\(kind.title) · \(due.count)", systemImage: kind.icon)
                    }
                }
            }
        }
        .navigationTitle("今日复习")
    }
}

private struct CollectionView: View {
    @EnvironmentObject private var store: ReviewStore
    @State private var course = ""
    @State private var showEditor = false
    let kind: ReviewKind

    var body: some View {
        let items = store.items.filter { $0.kind == kind }
        let courses = Array(Set(items.map(\.course))).sorted()
        let filtered = course.isEmpty ? items : items.filter { $0.course == course }
        List {
            if courses.count > 1 {
                Picker("课程", selection: $course) {
                    Text("全部").tag("")
                    ForEach(courses, id: \.self) { Text($0).tag($0) }
                }
            }
            if filtered.isEmpty { Text("点右上角的 + 添加").foregroundStyle(.secondary) }
            ForEach(filtered) { item in ItemLink(item: item) }
        }
        .onChange(of: courses) { _, available in
            if !available.contains(course) { course = "" }
        }
        .navigationTitle(kind.title)
        .toolbar {
            Button("添加", systemImage: "plus") { showEditor = true }
        }
        .sheet(isPresented: $showEditor) {
            Editor(draft: ReviewItem(kind: kind, course: course))
        }
    }
}

private struct ItemLink: View {
    let item: ReviewItem

    var body: some View {
        NavigationLink {
            ItemDetail(id: item.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).lineLimit(2)
                Text("\(item.course) · \(item.done ? "已完成" : item.due.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ItemDetail: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAnswer = false
    @State private var editor: ReviewItem?
    @State private var confirmDelete = false
    let id: UUID

    var body: some View {
        if let item = store.items.first(where: { $0.id == id }) {
            List {
                Section(item.course) {
                    Text(item.title).font(.headline)
                    if let data = item.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .accessibilityLabel("错题原图")
                    }
                }
                if item.kind == .task {
                    Section {
                        LabeledContent("计划日期", value: item.due.formatted(date: .abbreviated, time: .omitted))
                        if let exam = item.exam {
                            LabeledContent("考试日期", value: exam.formatted(date: .abbreviated, time: .omitted))
                        }
                        Button(item.done ? "恢复待办" : "标为完成") { store.respond(to: item, value: !item.done) }
                    }
                } else {
                    Section {
                        if showAnswer {
                            Text(item.answer.isEmpty ? "还没有录入答案" : item.answer)
                            if !item.notes.isEmpty { Text(item.notes).foregroundStyle(.secondary) }
                            Button(item.kind == .mistake ? "独立做对" : "记住了") { grade(item, true) }
                            Button(item.kind == .mistake ? "还要再练" : "还不熟") { grade(item, false) }
                        } else {
                            Button("查看答案") { showAnswer = true }
                        }
                    }
                }
                if item.kind == .mistake {
                    Button("为这道题制作手表卡片") {
                        editor = ReviewItem(kind: .card, course: item.course, sourceMistake: item.id)
                    }
                }
                if let source = store.items.first(where: { $0.id == item.sourceMistake }) {
                    Section("关联错题") { ItemLink(item: source) }
                }
                Button("删除", role: .destructive) { confirmDelete = true }
            }
            .navigationTitle(item.kind.title)
            .toolbar { Button("编辑") { editor = item } }
            .sheet(item: $editor) { Editor(draft: $0) }
            .confirmationDialog("删除这项复习内容？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    store.delete(item)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("这项内容已删除", systemImage: "tray")
        }
    }

    private func grade(_ item: ReviewItem, _ recalled: Bool) {
        store.respond(to: item, value: recalled)
        showAnswer = false
        dismiss()
    }
}

private struct Editor: View {
    @EnvironmentObject private var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: ReviewItem
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var photoError = false

    private var valid: Bool {
        !draft.course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (draft.kind != .card || !draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (draft.exam.map { Calendar.current.startOfDay(for: draft.due) <= Calendar.current.startOfDay(for: $0) } ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("课程，例如概率论", text: $draft.course)
                TextField(draft.kind == .task ? "任务，例如重做第五章习题" : "题目或问题", text: $draft.title, axis: .vertical)
                if draft.kind == .mistake {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(draft.photo == nil ? "从照片添加题图" : "更换题图", systemImage: "photo")
                    }
                    if draft.photo != nil {
                        Button("移除题图", role: .destructive) { draft.photo = nil }
                            .disabled(loadingPhoto)
                    }
                    if loadingPhoto { ProgressView("正在读取题图") }
                    if photoError { Text("读取题图失败，请重新选取。").foregroundStyle(.red) }
                }
                if draft.kind != .task {
                    TextField("答案", text: $draft.answer, axis: .vertical)
                    if draft.kind == .mistake {
                        TextField("错因和关键步骤", text: $draft.notes, axis: .vertical)
                    }
                }
                DatePicker(draft.kind == .task ? "计划日期" : "下次复习", selection: $draft.due, displayedComponents: .date)
                if draft.kind == .task {
                    Toggle("设置考试日期", isOn: Binding(
                        get: { draft.exam != nil },
                        set: { draft.exam = $0 ? draft.due : nil }
                    ))
                    if draft.exam != nil {
                        DatePicker("考试日期", selection: Binding(
                            get: { draft.exam ?? draft.due },
                            set: { draft.exam = $0 }
                        ), displayedComponents: .date)
                    }
                    if let exam = draft.exam, Calendar.current.startOfDay(for: draft.due) > Calendar.current.startOfDay(for: exam) {
                        Text("计划日期应在考试当天或之前。").foregroundStyle(.red)
                    }
                }
                if let error = store.storageError { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(draft.kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.course = draft.course.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.save(draft)
                        if store.storageError == nil { dismiss() }
                    }
                    .disabled(!valid || loadingPhoto || store.storageError != nil)
                }
            }
        }
        .task(id: selection) {
            guard let selection else { return }
            loadingPhoto = true
            photoError = false
            let original = try? await selection.loadTransferable(type: Data.self)
            guard !Task.isCancelled else { return }
            if let original, let image = resizedPhoto(original) {
                draft.photo = image
            } else {
                photoError = true
            }
            loadingPhoto = false
        }
    }

    private func resizedPhoto(_ data: Data) -> Data? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1800
        ] as [CFString: Any]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}
