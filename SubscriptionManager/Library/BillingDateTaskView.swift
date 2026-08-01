import Foundation
import SwiftUI

/// A transactional date editor. The parent draft is written only after the
/// user taps Done; Cancel leaves the parent binding untouched.
struct BillingDateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding var draft: SubscriptionDraft
    let source: SubscriptionDraft.DateSource
    let now: Date

    @State private var workingDraft: SubscriptionDraft
    @State private var selectedDate: Date
    @State private var didApplySelection = false

    init(
        draft: Binding<SubscriptionDraft>,
        source: SubscriptionDraft.DateSource,
        now: Date
    ) {
        self._draft = draft
        self.source = source
        self.now = now
        let snapshot = draft.wrappedValue
        self._workingDraft = State(initialValue: snapshot)
        self._selectedDate = State(
            initialValue: source == .startDate
                ? snapshot.startDate
                : snapshot.confirmedNextRenewal
        )
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    LocalizedStringKey(sourceTitle),
                    selection: selectedDateBinding,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .accessibilityIdentifier("subscription.date-task.picker")
            }

            Section("Date Summary") {
                LabeledContent(
                    LocalizedStringKey(sourceTitle),
                    value: formattedBillingDate(
                        date(for: source),
                        timeZoneIdentifier:
                            workingDraft.billingTimeZoneIdentifier,
                        locale: locale
                    )
                )
                .accessibilityIdentifier("subscription.date-task.source-value")
                .accessibilityValue(accessibilityValue(for: source))

                LabeledContent(
                    LocalizedStringKey(counterpartTitle),
                    value: formattedBillingDate(
                        date(for: counterpart),
                        timeZoneIdentifier:
                            workingDraft.billingTimeZoneIdentifier,
                        locale: locale
                    )
                )
                .accessibilityIdentifier(
                    "subscription.date-task.counterpart-value"
                )
                .accessibilityValue(accessibilityValue(for: counterpart))
            }
        }
        .environment(
            \.timeZone,
            billingTimeZone(
                identifier: workingDraft.billingTimeZoneIdentifier
            )
        )
        .navigationTitle(LocalizedStringKey(sourceTitle))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("subscription.date-task.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    applySelectionAtLeastOnce()
                    draft = workingDraft
                    dismiss()
                }
                .accessibilityIdentifier("subscription.date-task.done")
            }
        }
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { selectedDate },
            set: { newValue in
                selectedDate = newValue
                applySelection(newValue)
            }
        )
    }

    private func applySelectionAtLeastOnce() {
        guard !didApplySelection else { return }
        applySelection(selectedDate)
    }

    private func applySelection(_ newDate: Date) {
        didApplySelection = true
        let applied: Bool
        switch source {
        case .startDate:
            applied = workingDraft.selectStartDate(newDate, asOf: now)
        case .nextRenewal:
            applied = workingDraft.selectNextRenewal(newDate, asOf: now)
        }
        guard applied else { return }
        selectedDate = date(for: source)
    }

    private func date(for source: SubscriptionDraft.DateSource) -> Date {
        switch source {
        case .startDate:
            workingDraft.startDate
        case .nextRenewal:
            workingDraft.confirmedNextRenewal
        }
    }

    private var counterpart: SubscriptionDraft.DateSource {
        switch source {
        case .startDate:
            .nextRenewal
        case .nextRenewal:
            .startDate
        }
    }

    private var sourceTitle: String {
        switch source {
        case .startDate:
            billingStartDateLabelKey(isTrial: isTrial)
        case .nextRenewal:
            billingNextDateLabelKey(isTrial: isTrial)
        }
    }

    private var counterpartTitle: String {
        switch counterpart {
        case .startDate:
            billingStartDateLabelKey(isTrial: isTrial)
        case .nextRenewal:
            billingNextDateLabelKey(isTrial: isTrial)
        }
    }

    private var isTrial: Bool {
        switch workingDraft.mode {
        case .creating(.trial), .editing(.trial):
            true
        default:
            false
        }
    }

    private var isActive: Bool {
        switch workingDraft.mode {
        case .creating(.active), .editing(.active):
            true
        default:
            false
        }
    }

    private func accessibilityValue(
        for source: SubscriptionDraft.DateSource
    ) -> String {
        let value = formattedBillingDate(
            date(for: source),
            timeZoneIdentifier: workingDraft.billingTimeZoneIdentifier,
            locale: locale
        )
        guard isActive else { return value }
        let role = workingDraft.dateSource == source
            ? String(localized: "Source")
            : String(localized: "Derived")
        return value + ", " + role
    }
}
