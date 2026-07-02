import SwiftUI
import SwiftData

struct WeeklyMealsView: View {
    @Query(sort: \Event.startTime) private var allEvents: [Event]
    @Query private var allMeals: [Meal]
    @Query private var prefsResults: [UserPreferences]
    @Query private var categories: [Category]
    @Environment(\.modelContext) private var context
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var isRunningPass = false
    @State private var isFetchingSuggestions = false
    @State private var suggestionOptions: [AIService.MealSuggestionResult] = []
    @State private var showingSuggestionSheet = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var prefs: UserPreferences? { prefsResults.first }

    private var weekDates: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
        let daysSinceMonday = (weekday + 5) % 7           // Sun→6, Mon→0, Tue→1 …
        let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private var hasPrefsSet: Bool {
        guard let p = prefs else { return false }
        return p.breakfastEnabled || !p.knownMealIDs.isEmpty
    }

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()

            if !hasPrefsSet {
                emptyState
            } else {
                weekList
            }
        }
        .navigationTitle("Meals This Week")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .overlay(alignment: .top) {
            if isRunningPass {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(hex: accentColorHex))
                    .frame(height: 2)
            }
        }
        .task {
            runDailyPass()
        }
        .sheet(isPresented: $showingSuggestionSheet) {
            suggestionSheet
        }
        .alert("Meals", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Week list

    private var weekList: some View {
        List {
            if prefs?.newMealSuggestionEnabled == true {
                discoverCard
                    .listRowBackground(Color.appBackground(accentColorHex))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            ForEach(weekDates, id: \.self) { date in
                dayCard(for: date)
                    .listRowBackground(Color.appBackground(accentColorHex))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func dayCard(for date: Date) -> some View {
        let cal = Calendar.current
        let isPast = date < cal.startOfDay(for: Date())
        let isToday = cal.isDateInToday(date)
        let isFuture = !isPast && !isToday
        let events = mealEvents(for: date)
        let breakfast = events.first { $0.title == "Breakfast" }
        let dinner = events.first { $0.title != "Breakfast" }

        return HStack(alignment: .top, spacing: 14) {
            // Day label column
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundColor(isToday ? Color(hex: accentColorHex) : .primary)
            }
            .frame(width: 34)
            .padding(.top, 2)

            // Meal slots
            VStack(alignment: .leading, spacing: 10) {
                breakfastSlot(event: breakfast, isFuture: isFuture)
                dinnerSlot(event: dinner, isFuture: isFuture)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .opacity(isPast ? 0.55 : (isFuture ? 0.75 : 1))
    }

    // MARK: - Discover card

    private var isDiscoveryDue: Bool {
        guard let last = prefs?.lastNewMealSuggestedDate else { return true }
        return (Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0) >= 7
    }

    private var canFetchToday: Bool { prefs?.canFetchMealSuggestion() ?? false }

    private var discoverCard: some View {
        Button {
            Task { await fetchSuggestions() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(canFetchToday ? Color(hex: accentColorHex) : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover a new meal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(canFetchToday ? .primary : .secondary)
                    Text(canFetchToday
                         ? (isDiscoveryDue ? "It's been a while — get 3 fresh ideas for tonight" : "Get 3 ideas for tonight's dinner")
                         : "2 suggestions used today — back tomorrow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isFetchingSuggestions {
                    ProgressView()
                } else if canFetchToday {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if isDiscoveryDue && canFetchToday {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: accentColorHex).opacity(0.5), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!canFetchToday || isFetchingSuggestions)
    }

    // MARK: - Suggestion sheet

    private var suggestionSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground(accentColorHex).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Text("Tap one to add it to tonight's schedule")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(suggestionOptions, id: \.meal.id) { option in
                            suggestionCard(option)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Tonight's Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSuggestionSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func suggestionCard(_ option: AIService.MealSuggestionResult) -> some View {
        Button {
            acceptSuggestion(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(option.meal.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(option.meal.prepTimeMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(option.scheduledStart, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(option.meal.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: accentColorHex))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: accentColorHex).opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slot rows

    @ViewBuilder
    private func breakfastSlot(event: Event?, isFuture: Bool) -> some View {
        if let event {
            slotContent(
                icon: "sunrise.fill",
                title: event.title,
                time: event.startTime,
                isAIPick: false
            )
        } else if isFuture {
            emptySlot(icon: "sunrise.fill", label: "Planned on the day")
        } else {
            emptySlot(icon: "sunrise.fill", label: "Skipped")
        }
    }

    @ViewBuilder
    private func dinnerSlot(event: Event?, isFuture: Bool) -> some View {
        if let event {
            HStack(spacing: 8) {
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    slotContent(
                        icon: "fork.knife",
                        title: event.title,
                        time: event.startTime,
                        isAIPick: isAIPick(event: event)
                    )
                }
                .buttonStyle(.plain)

                if canSwap(event) {
                    Spacer()
                    Button {
                        swapMeal(event)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: accentColorHex))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if isFuture {
            emptySlot(icon: "fork.knife", label: "Planned on the day")
        } else {
            emptySlot(icon: "fork.knife", label: "No slot")
        }
    }

    private func slotContent(icon: String, title: String, time: Date, isAIPick: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accentLight(accentColorHex))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)

                    if isAIPick {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7, weight: .bold))
                            Text("AI pick")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: accentColorHex))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color(hex: accentColorHex).opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Text(time, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func emptySlot(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.3))
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentLight(accentColorHex).opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "fork.knife")
                    .font(.system(size: 38))
                    .foregroundColor(.accentLight(accentColorHex))
            }
            Text("No meal preferences set")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Set up your meal preferences to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            NavigationLink {
                FoodPreferencesView()
            } label: {
                Text("Set Up Meals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(Color.appAccent(accentColorHex))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func mealEvents(for date: Date) -> [Event] {
        let cal = Calendar.current
        return allEvents.filter {
            cal.isDate($0.startTime, inSameDayAs: date) &&
            $0.category?.name == "Meal" &&
            $0.source == .ai
        }
    }

    private func isAIPick(event: Event) -> Bool {
        allMeals.contains { $0.name == event.title && !$0.isUserDefined }
    }

    private func canSwap(_ event: Event) -> Bool {
        Calendar.current.isDateInToday(event.startTime) && event.status == .pending
    }

    // MARK: - Suggestions

    @MainActor
    private func fetchSuggestions() async {
        guard let p = prefs, p.canFetchMealSuggestion() else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let slots = MealSchedulerService().remainingDinnerSlots(
            for: [today],
            existingEvents: allEvents,
            scheduledDinnerEvents: [],
            preferences: p
        )
        guard !slots.isEmpty else {
            alertMessage = "No free dinner slot left today — try again tomorrow."
            showingAlert = true
            return
        }

        isFetchingSuggestions = true
        defer { isFetchingSuggestions = false }
        p.recordMealSuggestionFetch()
        try? context.save()

        do {
            suggestionOptions = try await AIService().suggestMealOptions(
                existingMeals: allMeals,
                freeDinnerSlots: slots,
                preferences: p,
                referenceWeek: [today]
            )
            showingSuggestionSheet = true
        } catch {
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }

    private func acceptSuggestion(_ option: AIService.MealSuggestionResult) {
        guard let p = prefs else { return }
        context.insert(option.meal)
        p.knownMealIDs.append(option.meal.id)

        let event = Event(
            title: option.meal.name,
            startTime: option.scheduledStart,
            endTime: option.scheduledEnd,
            category: categories.first { $0.name == "Meal" },
            source: .ai
        )
        event.notificationIdentifier = NotificationService()
            .scheduleMealNotification(for: event, reminderMinutes: p.defaultReminderMinutes)
        context.insert(event)
        p.lastNewMealSuggestedDate = Date()
        try? context.save()
        showingSuggestionSheet = false
    }

    // MARK: - Swap

    private func swapMeal(_ event: Event) {
        guard let p = prefs else { return }
        let known = Set(p.knownMealIDs)
        let cookable = allMeals.filter { known.contains($0.id) }

        guard let swap = MealSchedulerService().swapDinner(
            for: event,
            meals: cookable,
            existingEvents: allEvents,
            preferences: p
        ) else {
            alertMessage = "No other meal fits tonight's slot."
            showingAlert = true
            return
        }

        let notifications = NotificationService()
        notifications.cancelEventNotifications(for: event)
        event.title = swap.meal.name
        event.endTime = swap.endTime
        event.notificationIdentifier = notifications
            .scheduleMealNotification(for: event, reminderMinutes: p.defaultReminderMinutes)
        try? context.save()
    }

    // MARK: - Daily pass

    private func runDailyPass() {
        guard let p = prefs else { return }
        isRunningPass = true
        defer { isRunningPass = false }

        let mealCategory = categories.first { $0.name == "Meal" }
        let coordinator = MealPlanningCoordinator(mealCategory: mealCategory)
        let result = coordinator.runDailyPass(
            existingEvents: allEvents,
            allMeals: allMeals,
            preferences: p
        )
        for event in result.eventsToDelete {
            context.delete(event)
        }
        for event in result.newEvents {
            context.insert(event)
        }
        try? context.save()
    }
}
