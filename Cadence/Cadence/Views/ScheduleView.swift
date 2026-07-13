import SwiftUI
import SwiftData

/// Two ways to browse the schedule. Week keeps a spacious, one-week-at-a-time
/// strip with full event cards; Month trades detail for density — a calendar
/// grid plus compact rows so more events fit at once.
enum ScheduleMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

struct ScheduleView: View {
    @Environment(\.theme) private var theme
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var categories: [Category]
    @Environment(\.modelContext) private var context

    @State private var selectedDate = Date.now
    @State private var selectedCategory: Category?
    @State private var editingEvent: Event?
    @State private var detailEvent: Event?
    @State private var showingAddEvent = false
    /// Swiped-to-delete occurrence of a recurring event, pending the
    /// "this one / this and future" choice.
    @State private var seriesDeleteTarget: Event?
    @State private var viewMode: ScheduleMode = .week

    // Which week/month the strip and grid are showing. Kept in sync with
    // selectedDate so tapping "Today" or picking a day snaps them into view.
    @State private var visibleWeekStart = Calendar.current
        .dateInterval(of: .weekOfYear, for: .now)!.start
    @State private var visibleMonth = Calendar.current
        .dateInterval(of: .month, for: .now)!.start

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Mode toggle, pinned snug under the nav title.
                modePicker
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                Group {
                    if viewMode == .week {
                        weekStrip
                    } else {
                        monthGrid
                    }
                }
                .padding(.bottom, 8)
                .onChange(of: selectedDate) { _, new in syncPeriods(to: new) }
                .onChange(of: viewMode) { _, _ in syncPeriods(to: selectedDate) }

                // Meals this week entry point
                NavigationLink { WeeklyMealsView() } label: {
                    HStack {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Meals this week")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .cardStyle()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)

                // Day stats bar
                if !selectedDayEvents.isEmpty {
                    dayStatsBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                // Category filter
                categoryFilter
                    .padding(.bottom, 6)

                Divider().overlay(theme.deep)

                dayEventList
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !Calendar.current.isDateInToday(selectedDate) {
                    Button {
                        withAnimation { selectedDate = .now }
                    } label: {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.accent)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddEvent = true } label: {
                    Image(systemName: "plus")
                        .foregroundColor(theme.accent)
                }
                .accessibilityLabel("Add event")
            }
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(editingEvent: event)
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventView(initialDate: selectedDate)
        }
        .navigationDestination(item: $detailEvent) { EventDetailView(event: $0) }
        .confirmationDialog(
            "This is a repeating event.",
            isPresented: Binding(
                get: { seriesDeleteTarget != nil },
                set: { if !$0 { seriesDeleteTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: seriesDeleteTarget
        ) { event in
            Button("Delete This Event", role: .destructive) {
                deleteEvent(event)
            }
            Button("Delete This and Future Events", role: .destructive) {
                RecurrenceService.shared.deleteFuture(from: event, context: context)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Snap the strip and grid to whatever period contains `date`.
    private func syncPeriods(to date: Date) {
        withAnimation(.spring(duration: 0.25)) {
            visibleWeekStart = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            visibleMonth = calendar.dateInterval(of: .month, for: date)!.start
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(duration: 0.25)) { viewMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.cadFootnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(viewMode == mode ? .white : theme.chipText)
                        .background(
                            viewMode == mode
                                ? AnyShapeStyle(theme.pillGradient)
                                : AnyShapeStyle(Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: viewMode == mode ? theme.pillGlow.opacity(0.6) : .clear,
                                radius: 6, y: 2)
                        // Whole segment (full width + padding) is the tap target,
                        // not just the label glyphs.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.chipBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Week strip (paged, one week at a time)

    /// Half a year of weeks either side of today.
    private var weeks: [[Date]] {
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        return (-26...26).map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekStart)!
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
    }

    private var weekStrip: some View {
        // One pass over allEvents instead of one filter per pill (UI_REVIEW §4).
        let eventDays = Set(allEvents.map { calendar.startOfDay(for: $0.startTime) })
        return TabView(selection: $visibleWeekStart) {
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { date in
                        dayPill(date, hasEvents: eventDays.contains(calendar.startOfDay(for: date)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .tag(week.first!)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 72)
    }

    private func dayPill(_ date: Date, hasEvents: Bool) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday    = calendar.isDateInToday(date)
        let dayLetter  = date.formatted(.dateTime.weekday(.narrow))
        let dayNumber  = calendar.component(.day, from: date)

        return Button {
            withAnimation(.spring(duration: 0.25)) { selectedDate = date }
        } label: {
            VStack(spacing: 4) {
                Text(dayLetter)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? theme.accent : .primary))
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.6) : theme.accent)
                    .frame(width: 5, height: 5)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? AnyShapeStyle(theme.pillGradient) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isSelected ? theme.pillGlow : .clear, radius: 7, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month grid

    /// Event count per day, computed once for dot density in the grid.
    private var eventCountByDay: [Date: Int] {
        Dictionary(allEvents.map { (calendar.startOfDay(for: $0.startTime), 1) },
                   uniquingKeysWith: +)
    }

    /// Weekday header letters, rotated to match the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Leading blanks + each day of `visibleMonth`, aligned to first weekday.
    private var monthCells: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        return cells
    }

    private var monthGrid: some View {
        let counts = eventCountByDay
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(spacing: 8) {
            // Month header with prev/next navigation.
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Spacer()
                Text(visibleMonth, format: .dateTime.month(.wide).year())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .foregroundColor(theme.accent)
            .padding(.horizontal, 16)

            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    if let date = cell {
                        monthDayCell(date, count: counts[calendar.startOfDay(for: date)] ?? 0)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func monthDayCell(_ date: Date, count: Int) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday    = calendar.isDateInToday(date)

        return Button {
            withAnimation(.spring(duration: 0.2)) { selectedDate = date }
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? theme.accent : .primary))
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.8) : theme.accent)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? AnyShapeStyle(theme.pillGradient) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: isSelected ? theme.pillGlow.opacity(0.7) : .clear, radius: 5, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.spring(duration: 0.25)) {
            visibleMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth)!
        }
    }

    // MARK: - Day stats

    private var selectedDayEvents: [Event] {
        let start = calendar.startOfDay(for: selectedDate)
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!
        return allEvents.filter { $0.startTime >= start && $0.startTime < end }
    }

    private var filteredDayEvents: [Event] {
        guard let cat = selectedCategory else { return selectedDayEvents }
        return selectedDayEvents.filter { $0.category?.id == cat.id }
    }

    private var dayStatsBar: some View {
        let completed = selectedDayEvents.filter { $0.status == .completed }.count
        let total     = selectedDayEvents.count
        let rate      = total > 0 ? Double(completed) / Double(total) : 0.0

        return HStack(spacing: 10) {
            Text("\(total) event\(total == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.deep)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.barGradient)
                        .frame(width: geo.size.width * rate)
                        .animation(.easeOut(duration: 0.4), value: rate)
                }
            }
            .frame(height: 5)

            Text("\(Int(rate * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundColor(theme.accent)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(height: 18)
    }

    // MARK: - Category filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil)
                ForEach(categories) { cat in
                    categoryChip(cat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(_ cat: Category?) -> some View {
        let isSelected = cat == nil
            ? selectedCategory == nil
            : selectedCategory?.id == cat!.id

        let chipColor: Color = cat == nil ? theme.accent : Color(hex: cat!.colorHex)

        return Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedCategory = (cat == nil) ? nil : (selectedCategory?.id == cat!.id ? nil : cat)
            }
        } label: {
            HStack(spacing: 5) {
                if let cat {
                    // Dot uses the category's own gradient, not a flat fill (§4).
                    Circle()
                        .fill(theme.categoryGradient(hex: cat.colorHex))
                        .frame(width: 7, height: 7)
                    Text(cat.name)
                } else {
                    Text("All")
                }
            }
            .font(.cadFootnote)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? AnyShapeStyle(chipColor) : AnyShapeStyle(theme.chipBg))
            .foregroundColor(isSelected ? .white : theme.chipText)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day event list

    @ViewBuilder
    private var dayEventList: some View {
        if filteredDayEvents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 40)).foregroundColor(theme.light)
                Text(selectedCategory == nil ? "No events" : "No \(selectedCategory!.name) events")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let compact = viewMode == .month
            List {
                ForEach(filteredDayEvents) { event in
                    EventRowView(event: event,
                                 onEdit: compact ? nil : { editingEvent = event },
                                 compact: compact)
                        .contentShape(Rectangle())
                        .onTapGesture { detailEvent = event }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: compact ? 3 : 5, leading: 16,
                                                  bottom: compact ? 3 : 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                // Series occurrences get the "this one / this
                                // and future" choice instead of instant delete.
                                if event.isRecurring {
                                    seriesDeleteTarget = event
                                } else {
                                    deleteEvent(event)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func deleteEvent(_ event: Event) {
        NotificationService().cancelEventNotifications(for: event)
        // Imported events: tombstone so the next calendar sync doesn't re-insert it.
        CalendarImportService.shared.noteLocalDeletion(of: event, context: context)
        context.delete(event)
        try? context.save()
        WidgetSync.refresh()
    }
}
