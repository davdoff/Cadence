import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var prefsResults: [UserPreferences]
    @Environment(\.modelContext) private var context

    private var prefs: UserPreferences? { prefsResults.first }

    // Scheduling prefs (loaded from SwiftData)
    @State private var workStartHour:          Double = 9
    @State private var workEndHour:            Double = 18
    @State private var bufferMinutes:          Double = 15
    @State private var aiLevel:                Double = 3
    @State private var notificationsEnabled:   Bool   = true
    @State private var defaultReminderMinutes: Double = 15

    // Personalisation (AppStorage = UserDefaults)
    @AppStorage("greetingName")    private var greetingName    = ""
    @AppStorage("accentColorHex")  private var accentColorHex = "#E8784D"

    private static let themeColors: [(name: String, hex: String)] = [
        ("Flame",   "#E8784D"),
        ("Rose",    "#E05272"),
        ("Plum",    "#8B52E0"),
        ("Ocean",   "#4A90E2"),
        ("Forest",  "#52C47A"),
        ("Gold",    "#C4A232"),
        ("Slate",   "#5A7A8A"),
    ]

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()
            Form {

                // Personalisation
                Section("Personalisation") {
                    HStack {
                        Label("Your name", systemImage: "person.fill")
                        Spacer()
                        TextField("Optional", text: $greetingName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("App theme", systemImage: "paintpalette.fill")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Self.themeColors, id: \.hex) { theme in
                                    themeChip(name: theme.name, hex: theme.hex)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Working hours
                Section("Working Hours") {
                    labeledSlider(
                        label: "Work starts",
                        value: $workStartHour,
                        range: 4...12,
                        display: hourLabel(workStartHour)
                    )
                    labeledSlider(
                        label: "Work ends",
                        value: $workEndHour,
                        range: 12...23,
                        display: hourLabel(workEndHour)
                    )
                }

                // Scheduling
                Section("Scheduling") {
                    labeledSlider(
                        label: "Buffer between events",
                        value: $bufferMinutes,
                        range: 0...60,
                        step: 5,
                        display: "\(Int(bufferMinutes)) min"
                    )
                }

                // AI
                Section("AI Behaviour") {
                    labeledSlider(
                        label: "AI aggressiveness",
                        value: $aiLevel,
                        range: 1...5,
                        display: "\(Int(aiLevel)) / 5"
                    )
                    Text("Higher = AI suggests more proactively")
                        .font(.caption).foregroundColor(.secondary)
                }

                // Notifications
                Section("Notifications") {
                    Toggle("Enable notifications", isOn: $notificationsEnabled)
                        .tint(Color(hex: accentColorHex))
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled { NotificationService.requestAuthorization() }
                        }

                    if notificationsEnabled {
                        labeledSlider(
                            label: "Default reminder",
                            value: $defaultReminderMinutes,
                            range: 0...60,
                            step: 5,
                            display: defaultReminderMinutes == 0
                                ? "At start"
                                : "\(Int(defaultReminderMinutes)) min before"
                        )

                        NavigationLink {
                            CategoryNotificationsView()
                        } label: {
                            Label("Per-category alerts", systemImage: "tag.fill")
                        }
                    }
                }

                // Food
                Section("Food") {
                    NavigationLink {
                        FoodPreferencesView()
                    } label: {
                        Label("Meal preferences", systemImage: "fork.knife")
                    }
                    NavigationLink {
                        WeeklyMealsView()
                    } label: {
                        Label("Meals this week", systemImage: "calendar.badge.clock")
                    }
                }

                // Categories
                Section("Categories") {
                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Label("Manage categories", systemImage: "tag.fill")
                    }
                }

                // Save
                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            Label("Save scheduling settings", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(hex: accentColorHex))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .onAppear(perform: loadPrefs)
    }

    // MARK: - Components

    private func themeChip(name: String, hex: String) -> some View {
        let isSelected = accentColorHex == hex
        return Button {
            withAnimation(.spring(duration: 0.25)) { accentColorHex = hex }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 34, height: 34)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(Color(hex: hex).opacity(0.4), lineWidth: isSelected ? 3 : 0)
                        .scaleEffect(isSelected ? 1.3 : 1)
                )
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: hex) : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func labeledSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(display).foregroundColor(Color(hex: accentColorHex))
            }
            Slider(value: value, in: range, step: step)
                .tint(Color(hex: accentColorHex))
        }
    }

    // MARK: - Logic

    private func loadPrefs() {
        guard let p = prefs else { return }
        workStartHour          = Double(p.workStartHour)
        workEndHour            = Double(p.workEndHour)
        bufferMinutes          = Double(p.bufferMinutes)
        aiLevel                = Double(p.aiAggressiveness)
        notificationsEnabled   = p.notificationsEnabled
        defaultReminderMinutes = Double(p.defaultReminderMinutes)
    }

    private func save() {
        guard let p = prefs else { return }
        p.workStartHour          = Int(workStartHour)
        p.workEndHour            = Int(workEndHour)
        p.bufferMinutes          = Int(bufferMinutes)
        p.aiAggressiveness       = Int(aiLevel)
        p.notificationsEnabled   = notificationsEnabled
        p.defaultReminderMinutes = Int(defaultReminderMinutes)
        p.compactPreferenceString = SchedulerService().compactPreferenceString(from: p, priorityCategories: [])
        try? context.save()
    }

    private func hourLabel(_ h: Double) -> String {
        let hour   = Int(h)
        let suffix  = hour >= 12 ? "PM" : "AM"
        let display = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(display):00 \(suffix)"
    }
}

// MARK: - Per-category notification toggles

struct CategoryNotificationsView: View {
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var prefsResults: [UserPreferences]
    @Environment(\.modelContext) private var context
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var perCatNotifs: [UUID: Bool] = [:]

    private var prefs: UserPreferences? { prefsResults.first }

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()
            List {
                Section {
                    ForEach(categories) { cat in
                        Toggle(isOn: Binding(
                            get: { perCatNotifs[cat.id] ?? true },
                            set: { perCatNotifs[cat.id] = $0; savePerCat() }
                        )) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hex: cat.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(cat.name)
                            }
                        }
                        .tint(Color(hex: accentColorHex))
                    }
                } footer: {
                    Text("Disable to silence reminders for events in that category.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Per-Category Alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .onAppear {
            perCatNotifs = prefs?.perCategoryNotifications() ?? [:]
        }
    }

    private func savePerCat() {
        prefs?.setPerCategoryNotifications(perCatNotifs)
        try? context.save()
    }
}
