import SwiftUI

struct AddMealView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"

    @State private var name = ""
    @State private var prepMinutes = 20

    let onAdd: (String, Int) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground(accentColorHex).ignoresSafeArea()
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
            .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
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
                    .tint(Color(hex: accentColorHex))
                }
            }
        }
    }
}
