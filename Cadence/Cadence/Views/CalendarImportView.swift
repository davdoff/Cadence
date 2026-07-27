import SwiftUI
import SwiftData
import EventKit

/// Preferences → "Import calendars": permission flow, the in-app calendar
/// picker (the OS grant is all-or-nothing — ours isn't), and management of
/// connected sources (calendar-import.md §2–§3).
struct CalendarImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CalendarImportSource.displayName) private var sources: [CalendarImportSource]
    @Environment(\.theme) private var theme

    @State private var authStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var isSyncing = false
    @State private var sourceToRemove: CalendarImportSource?
    @State private var feedURLText = ""
    @State private var isAddingFeed = false
    @State private var importError: String?
    /// Account groups the user has collapsed in the connected-calendars list.
    /// Absent = expanded (the default), so new groups start open.
    @State private var collapsedGroups: Set<String> = []

    private var deviceSources: [CalendarImportSource] {
        sources.filter { $0.kind == .deviceCalendar }
    }

    /// Fallback group name for device sources with no stored account (feeds
    /// never appear here; older sources connected before `accountName` existed).
    private static let ungroupedName = "Other calendars"

    /// Connected device calendars grouped by account, groups sorted by name.
    /// Order within a group follows the `sources` query (by displayName).
    private var deviceSourceGroups: [(account: String, sources: [CalendarImportSource])] {
        Dictionary(grouping: deviceSources) { $0.accountName ?? Self.ungroupedName }
            .map { (account: $0.key, sources: $0.value) }
            .sorted { $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
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
            theme.backgroundGradient.ignoresSafeArea()
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
        .toolbarBackground(theme.background, for: .navigationBar)
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
                ForEach(deviceSourceGroups, id: \.account) { group in
                    DisclosureGroup(isExpanded: expansionBinding(for: group.account)) {
                        ForEach(group.sources) { source in
                            sourceRow(source)
                        }
                    } label: {
                        groupHeader(account: group.account, groupSources: group.sources)
                    }
                }
            } header: {
                Text("Connected calendars")
            } footer: {
                Text("Imported events sync for the next \(CalendarImportService.syncWindowDays) days and update automatically when the device calendar changes.")
                    .font(.caption)
            }
        }
    }

    /// Collapsed/expanded binding for one account group (default expanded).
    private func expansionBinding(for account: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(account) },
            set: { expanded in
                if expanded { collapsedGroups.remove(account) }
                else { collapsedGroups.insert(account) }
            }
        )
    }

    /// Account row with a master toggle: on only when every calendar in the
    /// group is enabled; toggling it enables/disables all of them at once
    /// (enabling triggers a sync, mirroring the per-calendar toggle).
    private func groupHeader(account: String, groupSources: [CalendarImportSource]) -> some View {
        let enabledCount = groupSources.filter(\.isEnabled).count
        return Toggle(isOn: Binding(
            get: { enabledCount == groupSources.count },
            set: { enabled in
                for source in groupSources { source.isEnabled = enabled }
                try? context.save()
                if enabled { sync() }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account)
                Text("\(enabledCount) of \(groupSources.count) synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tint(theme.accent)
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
                    .foregroundColor(theme.accent)
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
                            .foregroundColor(theme.accent)
                        Spacer()
                        if isSyncing { ProgressView() }
                    }
                }
                .disabled(isSyncing)

                Button {
                    CalendarImportService.shared.pauseAllSyncing(context: context)
                } label: {
                    Label("Pause all syncing", systemImage: "pause.circle")
                        .foregroundColor(theme.accent)
                }
                .disabled(isSyncing)
            } footer: {
                Text("Pausing keeps every imported event where it is and stops auto-sync from changing them. Turn any calendar back on to resume.")
                    .font(.caption)
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
        .tint(theme.accent)
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
                        .foregroundColor(theme.accent)
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
                        .foregroundColor(theme.accent)
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
                .foregroundColor(theme.accent)
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
        source.accountName = account.isEmpty ? nil : account
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
