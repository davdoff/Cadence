import SwiftUI
import SwiftData

/// Create or edit a day template. Works on a local draft and writes to
/// SwiftData only on Save, so backing out never leaves a half-edited template.
/// "Copy from a day…" fills the blocks from an existing day's events — the
/// "save this day as a template" flow.
struct DayTemplateEditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Event.startTime) private var allEvents: [Event]

    /// nil = creating a new template.
    let template: DayTemplate?

    @State private var name = ""
    @State private var symbolName: String?
    @State private var blocks: [TemplateBlock] = []
    @State private var loaded = false

    @State private var editingBlock: TemplateBlock?
    @State private var showCopySheet = false

    static let symbols = [
        "briefcase.fill", "book.fill", "figure.run", "dumbbell.fill",
        "sun.max.fill", "moon.fill", "house.fill", "leaf.fill", "star.fill",
    ]

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()
            Form {
                Section("Name") {
                    TextField("e.g. Work day", text: $name)
                    symbolPicker
                }

                Section {
                    if blocks.isEmpty {
                        Text("No blocks yet. Add one, or copy an existing day.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(sortedBlocks) { block in
                        Button { editingBlock = block } label: { blockRow(block) }
                            .foregroundColor(theme.text)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { sortedBlocks[$0].id }
                        blocks.removeAll { ids.contains($0.id) }
                    }
                    Button {
                        editingBlock = TemplateBlock(
                            title: "", startMinuteOfDay: nextFreeMinute, durationMinutes: 60,
                            categoryName: categories.first?.name ?? ""
                        )
                    } label: {
                        Label("Add block", systemImage: "plus")
                    }
                    Button { showCopySheet = true } label: {
                        Label("Copy from a day…", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("Blocks")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(template == nil ? "New Template" : "Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .sheet(item: $editingBlock) { block in
            TemplateBlockEditor(block: block, categories: categories) { edited in
                if let i = blocks.firstIndex(where: { $0.id == edited.id }) {
                    blocks[i] = edited
                } else {
                    blocks.append(edited)
                }
            }
        }
        .sheet(isPresented: $showCopySheet) {
            CopyDaySheet { day in blocks = Self.blocks(copying: day, from: allEvents) }
        }
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var symbolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        symbolName = symbolName == symbol ? nil : symbol
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 34, height: 34)
                            .foregroundColor(symbolName == symbol ? .white : theme.accent)
                            .background(symbolName == symbol ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.cardSurface))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func blockRow(_ block: TemplateBlock) -> some View {
        HStack(spacing: 12) {
            Text(Self.timeLabel(block.startMinuteOfDay))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title.isEmpty ? "Untitled" : block.title)
                    .font(.subheadline.weight(.medium))
                Text("\(block.durationMinutes) min · \(block.categoryName.isEmpty ? "No category" : block.categoryName)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var sortedBlocks: [TemplateBlock] {
        blocks.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
    }

    /// New blocks start where the last one ends (or 9:00 on an empty template).
    private var nextFreeMinute: Int {
        guard let last = sortedBlocks.last else { return 9 * 60 }
        return min(last.startMinuteOfDay + last.durationMinutes, 23 * 60)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !blocks.isEmpty
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let template else { return }
        name = template.name
        symbolName = template.symbolName
        blocks = template.blocks
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let template {
            template.name = trimmed
            template.symbolName = symbolName
            template.blocks = sortedBlocks
        } else {
            context.insert(DayTemplate(name: trimmed, symbolName: symbolName, blocks: sortedBlocks))
        }
        try? context.save()
        dismiss()
    }

    /// The day's events as template blocks. Missed/displaced events are left
    /// out (they didn't happen there); events running past midnight are cut at
    /// the end of the day.
    static func blocks(copying day: Date, from events: [Event], calendar: Calendar = .current) -> [TemplateBlock] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return events
            .filter { $0.status != .missed && $0.status != .displaced }
            .filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
            .map { event in
                let startMinute = Int(event.startTime.timeIntervalSince(dayStart) / 60)
                let end = min(event.endTime, dayEnd)
                let duration = max(5, Int(end.timeIntervalSince(event.startTime) / 60))
                return TemplateBlock(
                    title: event.title, startMinuteOfDay: startMinute,
                    durationMinutes: duration, categoryName: event.category?.name ?? ""
                )
            }
    }

    static func timeLabel(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

// MARK: - Block editor

private struct TemplateBlockEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var block: TemplateBlock
    let categories: [Category]
    let onSave: (TemplateBlock) -> Void

    private static let durations = [15, 30, 45, 60, 75, 90, 120, 150, 180, 240]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $block.title)
                DatePicker("Starts", selection: startBinding, displayedComponents: .hourAndMinute)
                Picker("Duration", selection: $block.durationMinutes) {
                    ForEach(durationOptions, id: \.self) { Text(Self.durationLabel($0)).tag($0) }
                }
                Picker("Category", selection: $block.categoryName) {
                    Text("None").tag("")
                    ForEach(categories) { Text($0.name).tag($0.name) }
                    // Keep a category that was deleted since the template was made
                    // selectable, so editing the block doesn't silently drop it.
                    if !block.categoryName.isEmpty, !categories.contains(where: { $0.name == block.categoryName }) {
                        Text(block.categoryName).tag(block.categoryName)
                    }
                }
            }
            .navigationTitle(block.title.isEmpty ? "Block" : block.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var saved = block
                        saved.title = saved.title.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(block.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Standard choices, plus the block's own duration when it came from a
    /// copied day and isn't one of them.
    private var durationOptions: [Int] {
        Self.durations.contains(block.durationMinutes)
            ? Self.durations
            : (Self.durations + [block.durationMinutes]).sorted()
    }

    /// Minute-of-day ↔ a Date on today, for the hour/minute DatePicker.
    private var startBinding: Binding<Date> {
        let today = Calendar.current.startOfDay(for: .now)
        return Binding(
            get: { today.addingTimeInterval(TimeInterval(block.startMinuteOfDay * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                block.startMinuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    static func durationLabel(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default:     return "\(h) h \(m) min"
        }
    }
}

// MARK: - Copy a day

private struct CopyDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    let onCopy: (Date) -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Text("Replaces the template's blocks with that day's events.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .navigationTitle("Copy from a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { onCopy(day); dismiss() }
                }
            }
        }
    }
}
