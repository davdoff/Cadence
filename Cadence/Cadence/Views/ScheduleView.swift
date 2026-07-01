import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var categories: [Category]
    @Environment(\.modelContext) private var context

    @State private var selectedDate = Date.now
    @State private var selectedCategory: Category?
    @State private var editingEvent: Event?

    var body: some View {
        ZStack {
            Color.cadenceCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Week strip
                weekStrip
                    .padding(.vertical, 10)
                    .background(Color.cadenceCream)

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
                    .foregroundColor(.cadenceOrange)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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

                Divider().overlay(Color.cadenceCreamDeep)

                dayEventList
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cadenceCream, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { selectedDate = .now }
                } label: {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.cadenceOrange)
                }
            }
        }
        .sheet(item: $editingEvent) { event in
            AddEventView(editingEvent: event)
        }
    }

    // MARK: - Week strip

    private var weekDates: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (-90...90).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var weekStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(weekDates, id: \.self) { date in
                        dayPill(date).id(date)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                proxy.scrollTo(Calendar.current.startOfDay(for: selectedDate), anchor: .center)
            }
            .onChange(of: selectedDate) { _, new in
                withAnimation(.spring(duration: 0.25)) {
                    proxy.scrollTo(Calendar.current.startOfDay(for: new), anchor: .center)
                }
            }
        }
    }

    private func dayPill(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday    = Calendar.current.isDateInToday(date)
        let dayLetter  = date.formatted(.dateTime.weekday(.narrow))
        let dayNumber  = Calendar.current.component(.day, from: date)

        // Dot indicator: has events
        let start = Calendar.current.startOfDay(for: date)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let hasEvents = allEvents.contains { $0.startTime >= start && $0.startTime < end }

        return Button {
            withAnimation(.spring(duration: 0.25)) { selectedDate = date }
        } label: {
            VStack(spacing: 4) {
                Text(dayLetter)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? .cadenceOrange : .primary))
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.6) : Color.cadenceOrange)
                    .frame(width: 5, height: 5)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(width: 42, height: 62)
            .background(isSelected ? Color.cadenceOrange : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day stats

    private var selectedDayEvents: [Event] {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start)!
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
                    RoundedRectangle(cornerRadius: 3).fill(Color.cadenceCreamDeep)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cadenceOrange)
                        .frame(width: geo.size.width * rate)
                        .animation(.easeOut(duration: 0.4), value: rate)
                }
            }
            .frame(height: 5)

            Text("\(Int(rate * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundColor(.cadenceOrange)
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

        let chipColor: Color = cat == nil ? .cadenceOrange : Color(hex: cat!.colorHex)

        return Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedCategory = (cat == nil) ? nil : (selectedCategory?.id == cat!.id ? nil : cat)
            }
        } label: {
            HStack(spacing: 5) {
                if let cat {
                    Circle().fill(chipColor).frame(width: 7, height: 7)
                    Text(cat.name)
                } else {
                    Text("All")
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? chipColor : Color.cadenceCreamDeep)
            .foregroundColor(isSelected ? .white : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day event list

    @ViewBuilder
    private var dayEventList: some View {
        if filteredDayEvents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 40)).foregroundColor(.cadenceOrangeLight)
                Text(selectedCategory == nil ? "No events" : "No \(selectedCategory!.name) events")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(filteredDayEvents) { event in
                    EventRowView(event: event, onEdit: { editingEvent = event })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteEvent(event)
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
        context.delete(event)
        try? context.save()
    }
}
