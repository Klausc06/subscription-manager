import Foundation
import SwiftUI

/// Value-only transaction state for a date task. Applying a date mutates only
/// the working copy; callers must commit the returned draft explicitly.
struct BillingDateTaskState: Equatable {
    let source: SubscriptionDraft.DateSource
    let now: Date
    private(set) var workingDraft: SubscriptionDraft
    private(set) var selectedDate: Date
    private(set) var didApplySelection = false

    init(
        draft: SubscriptionDraft,
        source: SubscriptionDraft.DateSource,
        now: Date
    ) {
        self.source = source
        self.now = now
        self.workingDraft = draft
        self.selectedDate = source == .startDate
            ? draft.startDate
            : draft.confirmedNextRenewal
    }

    @discardableResult
    mutating func applySelection(_ newDate: Date) -> Bool {
        var candidate = workingDraft
        let applied: Bool
        switch source {
        case .startDate:
            applied = candidate.selectStartDate(newDate, asOf: now)
        case .nextRenewal:
            applied = candidate.selectNextRenewal(newDate, asOf: now)
        }
        guard applied else { return false }

        workingDraft = candidate
        selectedDate = date(for: source, in: candidate)
        didApplySelection = true
        return true
    }

    mutating func commit() -> SubscriptionDraft? {
        if !didApplySelection {
            guard applySelection(selectedDate) else { return nil }
        }
        return workingDraft
    }

    private func date(
        for source: SubscriptionDraft.DateSource,
        in draft: SubscriptionDraft
    ) -> Date {
        switch source {
        case .startDate:
            draft.startDate
        case .nextRenewal:
            draft.confirmedNextRenewal
        }
    }
}

func billingDateRoleText(
    source: SubscriptionDraft.DateSource,
    selectedSource: SubscriptionDraft.DateSource,
    locale: Locale
) -> String {
    if source == selectedSource {
        return String(
            localized: LocalizedStringResource(
                "Source",
                defaultValue: "Source",
                table: "Localizable",
                locale: locale,
                bundle: .main
            )
        )
    }
    return String(
        localized: LocalizedStringResource(
            "Derived",
            defaultValue: "Derived",
            table: "Localizable",
            locale: locale,
            bundle: .main
        )
    )
}

/// A transactional date editor. The parent draft is written only after the
/// user taps Done; Cancel leaves the parent binding untouched.
struct BillingDateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding var draft: SubscriptionDraft
    let source: SubscriptionDraft.DateSource
    let now: Date

    @State private var taskState: BillingDateTaskState

    init(
        draft: Binding<SubscriptionDraft>,
        source: SubscriptionDraft.DateSource,
        now: Date
    ) {
        self._draft = draft
        self.source = source
        self.now = now
        let snapshot = draft.wrappedValue
        self._taskState = State(
            initialValue: BillingDateTaskState(
                draft: snapshot,
                source: source,
                now: now
            )
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
                            taskState.workingDraft.billingTimeZoneIdentifier,
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
                            taskState.workingDraft.billingTimeZoneIdentifier,
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
                identifier: taskState.workingDraft.billingTimeZoneIdentifier
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
                    guard let committedDraft = taskState.commit() else {
                        return
                    }
                    draft = committedDraft
                    dismiss()
                }
                .accessibilityIdentifier("subscription.date-task.done")
            }
        }
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { taskState.selectedDate },
            set: { newValue in
                _ = taskState.applySelection(newValue)
            }
        )
    }

    private func date(for source: SubscriptionDraft.DateSource) -> Date {
        switch source {
        case .startDate:
            taskState.workingDraft.startDate
        case .nextRenewal:
            taskState.workingDraft.confirmedNextRenewal
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
        switch taskState.workingDraft.mode {
        case .creating(.trial), .editing(.trial):
            true
        default:
            false
        }
    }

    private var isActive: Bool {
        switch taskState.workingDraft.mode {
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
            timeZoneIdentifier: taskState.workingDraft.billingTimeZoneIdentifier,
            locale: locale
        )
        guard isActive else { return value }
        let role = billingDateRoleText(
            source: source,
            selectedSource: taskState.workingDraft.dateSource,
            locale: locale
        )
        return value + ", " + role
    }
}
