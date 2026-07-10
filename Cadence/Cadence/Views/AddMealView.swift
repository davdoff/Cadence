import SwiftUI

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var prepMinutes = 20

    let onAdd: (String, Int) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                theme.backgroundGradient.ignoresSafeArea()
                Form {
                    Section("Meal Details") {
                        TextField("Name", text: $name)
                        Stepper("Prep time: \(prepMinutes) min", value: $prepMinutes, in: 5...120, step: 5)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onAdd(trimmed, prepMinutes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(theme.accent)
                }
            }
        }
    }
}
