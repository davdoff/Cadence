import SwiftUI
import SwiftData

struct CategorySettingsView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Query(sort: \Category.name) private var categories: [Category]
    @Environment(\.modelContext) private var context

    @State private var showingAdd = false

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()

            List {
                ForEach(categories) { cat in
                    NavigationLink {
                        EditCategoryView(category: cat)
                    } label: {
                        CategoryRow(category: cat)
                    }
                    .listRowBackground(Color.white)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(categories[i]) }
                    try? context.save()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus").foregroundColor(.appAccent(accentColorHex))
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddCategoryView() }
    }
}

// MARK: - Category row

private struct CategoryRow: View {
    let category: Category
    var body: some View {
        let count = category.events.count
        let label = count == 1 ? "1 event" : "\(count) events"
        return HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: category.colorHex))
                .frame(width: 24, height: 24)
            Text(category.name)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var selectedColor = "#4A90E2"

    static let palette: [String] = [
        "#E8784D", "#E05252", "#E0528A", "#7B52E0",
        "#4A90E2", "#52B4E0", "#52C47A", "#C4A232",
        "#E0A052", "#8B6651", "#9B59B6", "#5A7A8A",
        "#6A6A6A", "#34495E", "#27AE60", "#E67E22"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground(accentColorHex).ignoresSafeArea()
                VStack(spacing: 20) {
                    // Preview
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: selectedColor))
                            .frame(width: 40, height: 40)
                        Text(name.isEmpty ? "Category name" : name)
                            .font(.headline)
                            .foregroundColor(name.isEmpty ? .secondary : .primary)
                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.04), radius: 5, y: 2)

                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.caption.weight(.semibold)).foregroundColor(.secondary).textCase(.uppercase)
                        TextField("e.g. Work, Study, Health", text: $name)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                    }

                    // Color
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colour").font(.caption.weight(.semibold)).foregroundColor(.secondary).textCase(.uppercase)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                            ForEach(Self.palette, id: \.self) { hex in
                                Button {
                                    withAnimation(.spring(duration: 0.2)) { selectedColor = hex }
                                } label: {
                                    ZStack {
                                        Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                        if selectedColor == hex {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.appAccent(accentColorHex))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundColor(.appAccent(accentColorHex))
                }
            }
        }
    }

    private func save() {
        context.insert(Category(
            name: name.trimmingCharacters(in: .whitespaces),
            colorHex: selectedColor
        ))
        try? context.save()
        dismiss()
    }
}

// MARK: - Edit Category

struct EditCategoryView: View {
    @AppStorage("accentColorHex") private var accentColorHex = "#E8784D"
    let category: Category
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var selectedColor: String

    private static let palette = AddCategoryView.palette

    init(category: Category) {
        self.category = category
        _name          = State(initialValue: category.name)
        _selectedColor = State(initialValue: category.colorHex)
    }

    var body: some View {
        ZStack {
            Color.appBackground(accentColorHex).ignoresSafeArea()
            VStack(spacing: 20) {
                // Preview
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: selectedColor)).frame(width: 40, height: 40)
                    Text(name.isEmpty ? "Category name" : name)
                        .font(.headline)
                        .foregroundColor(name.isEmpty ? .secondary : .primary)
                    Spacer()
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.04), radius: 5, y: 2)

                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.caption.weight(.semibold)).foregroundColor(.secondary).textCase(.uppercase)
                    TextField("Category name", text: $name)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colour").font(.caption.weight(.semibold)).foregroundColor(.secondary).textCase(.uppercase)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Self.palette, id: \.self) { hex in
                            Button {
                                withAnimation(.spring(duration: 0.2)) { selectedColor = hex }
                            } label: {
                                ZStack {
                                    Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                    if selectedColor == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground(accentColorHex), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundColor(.appAccent(accentColorHex))
            }
        }
    }

    private func save() {
        category.name     = name.trimmingCharacters(in: .whitespaces)
        category.colorHex = selectedColor
        try? context.save()
        dismiss()
    }
}
