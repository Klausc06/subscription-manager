import Foundation
import SubscriptionCore
import SwiftUI

struct CatalogIndexSection: Identifiable, Equatable {
    let id: String
    let presets: [CatalogPreset]

    var title: String {
        id
    }
}

enum CatalogIndexProjection {
    static func sections(
        for presets: [CatalogPreset],
        locale: Locale
    ) -> [CatalogIndexSection] {
        let grouped = Dictionary(grouping: presets) { preset in
            initial(for: preset.serviceName.value(for: locale))
        }

        return grouped.map { initial, values in
            CatalogIndexSection(
                id: initial,
                presets: values.sorted {
                    let comparison = $0.serviceName.value(for: locale)
                        .localizedCompare($1.serviceName.value(for: locale))
                    return comparison == .orderedSame
                        ? $0.id < $1.id
                        : comparison == .orderedAscending
                }
            )
        }
        .sorted { sectionOrder($0.id) < sectionOrder($1.id) }
    }

    private static func initial(for name: String) -> String {
        let transliterated = name.applyingTransform(
            .mandarinToLatin,
            reverse: false
        ) ?? name
        let folded = transliterated
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en")
            )

        guard let scalar = folded.unicodeScalars.first,
              (65 ... 90).contains(Int(scalar.value))
                || (97 ... 122).contains(Int(scalar.value))
        else {
            return "#"
        }
        return String(Character(String(scalar))).uppercased()
    }

    private static func sectionOrder(_ initial: String) -> Int {
        guard initial != "#",
              let value = initial.unicodeScalars.first?.value
        else {
            return 26
        }
        return Int(value - 65)
    }
}

enum CatalogIndexHighlightExpiration {
    static func wait(
        for duration: Duration = .milliseconds(600)
    ) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

struct CatalogAlphabetIndex: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        select(letter)
                    } label: {
                        Text(letter)
                            .font(.caption2.weight(.semibold))
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(
                                activeLetter == letter
                                    ? Color.white
                                    : Color.accentColor
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                            .background {
                                if activeLetter == letter {
                                    Circle()
                                        .fill(.tint)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Jump to \(letter)"))
                    .accessibilityIdentifier(
                        "catalog.alphabet-index.\(letter)"
                    )
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectLetter(
                            at: value.location.y,
                            height: geometry.size.height
                        )
                    }
            )
        }
        .frame(width: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("catalog.alphabet-index")
        .task(id: activeLetter) {
            guard let selectedLetter = activeLetter else {
                return
            }
            guard await CatalogIndexHighlightExpiration.wait(),
                  activeLetter == selectedLetter
            else {
                return
            }
            activeLetter = nil
        }
    }

    private func selectLetter(
        at verticalPosition: CGFloat,
        height: CGFloat
    ) {
        guard !letters.isEmpty, height > 0 else {
            return
        }
        let fraction = verticalPosition / height
        let rawIndex = Int(fraction * CGFloat(letters.count))
        let index = min(max(rawIndex, 0), letters.count - 1)
        select(letters[index])
    }

    private func select(_ letter: String) {
        guard activeLetter != letter else {
            return
        }
        activeLetter = letter
        onSelect(letter)
    }
}
