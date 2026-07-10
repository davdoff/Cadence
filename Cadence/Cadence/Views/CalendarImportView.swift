import SwiftUI
import SwiftData
import EventKit

/// Preferences → "Import calendars": permission flow, the in-app calendar
/// picker (the OS grant is all-or-nothing — ours isn't), and management of
/// connected sources (calendar-import.md §2–§3).
struct CalendarImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarImportSource.displayName) private var sources: [CalendarImportSource]
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var authStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var isSyncing = false
    @State private var sourceToRemove: CalendarImportSource?
    @State private var feedURLText = ""
    @State private var isAddingFeed = false
    @State private var importError: String?

    private var deviceSources: [CalendarImportSource] {
        sources.filter { $0.kind == .deviceCalendar }
    }

    private var feedSources: [CalendarImportSource] {
        sources.filter { $0.kind == .subscriptionURL }
    }

    /// Device calendars not connected yet, for the picker.
    private var availableCalendars: [EKCalendar] {
        let connected = Set(deviceSources.map(\.identifier))
        return EventKitReader.shared.deviceCalendars()
            .filter { !connected.contains($0.calendarIdentifier) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()
            List {
                connectedSection
                addSection
                feedsSection
                syncSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Import Calendars")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .onAppear { authStatus = EKEventStore.authorizationStatus(for: .event) }
        .alert(
            "Remove \(sourceToRemove?.displayName ?? "calendar")?",
            isPresented: Binding(
                get: { sourceToRemove != nil },
                set: { if !$0 { sourceToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let source = sourceToRemove {
                    CalendarImportService.shared.removeSource(source, context: context)
                }
                sourceToRemove = nil
            }
            Button("Cancel", role: .cancel) { sourceToRemove = nil }
        } message: {
            Text("All events imported from this calendar will be deleted from Cadence. The calendar itself is not affected.")
        }
        .alert(
            "Couldn't add calendar link",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Connected sources

    @ViewBuilder
    private var connectedSection: some View {
        if !deviceSources.isEmpty {
            Section {
                ForEach(deviceSources) { source in
                    sourceRow(source)
                }
            } header: {
                Text("Connected calendars")
            } footer: {
                Text("Imported events sync for the next \(CalendarImportService.syncWindowDays) days and update automatically when the device calendar changes.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Subscription feeds (§4 — parsed by the backend, never Apple Calendar)

    private var feedsSection: some View {
        Section {
            ForEach(feedSources) { source in
                sourceRow(source)
            }

            HStack {
                TextField("webcal:// or https://…ics", text: $feedURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") { addFeed() }
                    .buttonStyle(.borderless) // keep the row's TextField tappable
                    .disabled(isAddingFeed || feedURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .foregroundColor(.appAccent(accentColorHex))
            }
        } header: {
            Text("Calendar links")
        } footer: {
            Text("Paste an .ics feed link (class schedule, sports calendar, Luma/Eventbrite export). Events import into Cadence only — nothing is added to Apple Calendar, and Cadence owns their reminders.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        if sources.contains(where: \.isEnabled) {
            Section {
                Button {
                    sync()
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.clockwise")
                            .foregroundColor(.appAccent(accentColorHex))
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing)
            }
        }
    }

    private func sourceRow(_ source: CalendarImportSource) -> some View {
        Toggle(isOn: Binding(
            get: { source.isEnabled },
            set: { enabled in
                source.isEnabled = enabled
                try? context.save()
                if enabled { sync() }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                if let synced = source.lastSyncedAt {
                    Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .tint(Color(hex: accentColorHex))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                sourceToRemove = source
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Add / permission states

    @ViewBuilder
    private var addSection: some View {
        switch authStatus {
        case .fullAccess:
            Section {
                if availableCalendars.isEmpty {
                    Text(deviceSources.isEmpty ? "No calendars found on this device." : "All device calendars are connected.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                        Button { connect(calendar) } label: {
                            calendarRow(calendar)
                        }
                    }
                }
            } header: {
                Text("Add from device")
            } footer: {
                Text("Only accounts added at the system level appear here. Missing a calendar? Add the account in Settings → Calendar → Accounts.")
                    .font(.caption)
            }

        case .notDetermined:
            Section {
                Button {
                    Task {
                        _ = await EventKitReader.shared.ensureAccess()
                        authStatus = EKEventStore.authorizationStatus(for: .event)
                    }
                } label: {
                    Label("Connect device calendars", systemImage: "calendar.badge.plus")
                        .foregroundColor(.appAccent(accentColorHex))
                }
            } footer: {
                Text("Cadence reads your existing calendars so it can schedule around your commitments. You choose which calendars to import.")
                    .font(.caption)
            }

        default: // .denied, .restricted, .writeOnly — cannot read
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .foregroundColor(.appAccent(accentColorHex))
                }
            } footer: {
                Text("Cadence needs full calendar access to read events. Allow it under Settings → Apps → Cadence → Calendars.")
                    .font(.caption)
            }
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(calendar.cgColor.map { Color(cgColor: $0) } ?? .secondary)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.title)
                    .foregroundColor(.primary)
                if let account = calendar.source?.title, !account.isEmpty {
                    Text(account)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.appAccent(accentColorHex))
        }
    }

    // MARK: - Actions

    private func connect(_ calendar: EKCalendar) {
        let account = calendar.source?.title ?? ""
        let source = CalendarImportSource(
            kind: .deviceCalendar,
            displayName: account.isEmpty ? calendar.title : "\(calendar.title) (\(account))",
            identifier: calendar.calendarIdentifier
        )
        context.insert(source)
        try? context.save()
        sync()
    }

    private func sync() {
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            await CalendarImportService.shared.syncAll(context: context)
            isSyncing = false
        }
    }

    private func addFeed() {
        let urlString = feedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, !isAddingFeed else { return }
        isAddingFeed = true
        Task {
            do {
                try await CalendarImportService.shared.connectFeed(urlString: urlString, context: context)
                feedURLText = ""
            } catch {
                importError = error.localizedDescription
            }
            isAddingFeed = false
        }
    }
}
