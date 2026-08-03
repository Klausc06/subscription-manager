import Foundation
import SubscriptionCore
import SwiftUI

private struct EditDateTaskPresentation: Identifiable {
    let source: SubscriptionDraft.DateSource

    var id: String {
        switch source {
        case .startDate:
            "start-date"
        case .nextRenewal:
            "next-renewal"
        }
    }
}

/// The direct editor for an existing subscription.
///
/// All editable values live in one `SubscriptionDraft`. The view only owns
/// the presentation state for the date task and the save result; it does not
/// parse money, derive billing dates, or mirror individual draft fields.
struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let workspace: SubscriptionWorkspace
    let subscription: Subscription
    let onRecordCancellation: () -> Void
    let onReactivate: () -> Void
    let onConfirmCharge: (ExpectedCharge) -> Void
    let onSave: (() -> Void)?
    let onCancel: (() -> Void)?

    @State private var draft: SubscriptionDraft
    @State private var dateTaskPresentation: EditDateTaskPresentation?
    @State private var didAttemptSave = false
    @State private var saveFailed = false
    private let initialDraft: SubscriptionDraft
    private let now: Date

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription,
        locale: Locale = .current,
        now: Date = Date(),
        onRecordCancellation: @escaping () -> Void = {},
        onReactivate: @escaping () -> Void = {},
        onConfirmCharge: @escaping (ExpectedCharge) -> Void = { _ in },
        onSave: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.subscription = subscription
        self.now = now
        self.onRecordCancellation = onRecordCancellation
        self.onReactivate = onReactivate
        self.onConfirmCharge = onConfirmCharge
        self.onSave = onSave
        self.onCancel = onCancel
        let initialDraft = SubscriptionDraft.editing(
            subscription: subscription,
            locale: locale
        )
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        Form {
            SubscriptionEditorSections(
                draft: $draft,
                nextExpectedCharge: editorNextExpectedCharge,
                catalogOfferAdjustment: workspace.catalogOfferAdjustment(
                    for: subscription
                ),
                showsValidation: didAttemptSave,
                onEditDate: beginDateTask
            )

            paymentHistorySection
            lifecycleSection

            if saveFailed {
                Section {
                    ValidationMessage(
                        "Couldn’t save changes. Try again.",
                        identifier: "subscription.validation.save"
                    )
                }
            }
        }
        .accessibilityIdentifier("subscription.form")
        .onAppear {
            workspace.beginEditing()
        }
        .navigationTitle("Edit Subscription")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    cancel()
                }
                .accessibilityIdentifier("subscription.form.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .accessibilityIdentifier("subscription.form.save")
            }
        }
        .sheet(item: $dateTaskPresentation) { presentation in
            NavigationStack {
                BillingDateTaskView(
                    draft: $draft,
                    source: presentation.source,
                    now: now
                )
            }
        }
    }

    @ViewBuilder
    private var paymentHistorySection: some View {
        if !workspace.paymentHistory.isEmpty {
            Section("Payment History") {
                ForEach(
                    Array(workspace.paymentHistory.enumerated()),
                    id: \.offset
                ) { _, entry in
                    EditorPaymentHistoryRow(
                        entry: entry,
                        timeZoneIdentifier:
                            currentSubscription.billingSchedule
                                .timeZoneIdentifier,
                        locale: locale,
                        canConfirm: canConfirm,
                        onConfirm: onConfirmCharge
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        Section {
            if currentSubscription.isArchived {
                LabeledContent("Status", value: String(localized: "Archived"))
                    .accessibilityIdentifier(
                        "subscription.editor.status"
                    )
            } else {
                switch editorStatus {
                case .trial, .active:
                    Button(
                        "Record Cancellation",
                        systemImage: "xmark.circle",
                        action: onRecordCancellation
                    )
                    .accessibilityIdentifier(
                        "subscription.lifecycle.record-cancellation"
                    )

                case .cancelledWithAccess, .expired:
                    Button(
                        "Reactivate",
                        systemImage: "arrow.clockwise",
                        action: onReactivate
                    )
                    .accessibilityIdentifier(
                        "subscription.lifecycle.reactivate"
                    )

                case nil:
                    EmptyView()
                }
            }
        } header: {
            Text("Lifecycle")
                .accessibilityIdentifier("subscription.lifecycle.section")
        }
    }

    private var currentSubscription: Subscription {
        guard case .loaded(
            let loadedSubscription,
            _,
            _
        ) = workspace.detailState,
        loadedSubscription.id == subscription.id
        else {
            return subscription
        }
        return loadedSubscription
    }

    private func canConfirm(_ expectedOccurrence: ExpectedCharge) -> Bool {
        let confirmedIDs = Set(
            currentSubscription.confirmedCharges.compactMap(
                \.sourceScheduledChargeID
            )
        )
        return ConfirmChargeEligibility.isEligible(
            expectedOccurrence: expectedOccurrence,
            confirmedIDs: confirmedIDs,
            now: now,
            billingTimeZone: billingTimeZone(
                identifier: currentSubscription.billingSchedule
                    .timeZoneIdentifier
            )
        )
    }

    private var editorStatus: SubscriptionStatus? {
        guard case .loaded(
            let loadedSubscription,
            let status,
            _
        ) = workspace.detailState,
        loadedSubscription.id == subscription.id
        else {
            return nil
        }
        guard !loadedSubscription.isArchived else { return nil }
        return status
    }

    private var editorNextExpectedCharge: ExpectedCharge? {
        guard case .loaded(
            let loadedSubscription,
            _,
            let nextExpectedCharge
        ) = workspace.detailState,
        loadedSubscription.id == subscription.id
        else {
            return nil
        }
        return nextExpectedCharge
    }

    private func beginDateTask(_ source: SubscriptionDraft.DateSource) {
        dateTaskPresentation = EditDateTaskPresentation(source: source)
    }

    private func save() {
        didAttemptSave = true
        saveFailed = false

        // `makeEditInput` is the sole app-layer conversion boundary. It
        // delegates money parsing, URL handling, date normalization, and the
        // lifecycle-aware schedule construction to the shared draft.
        guard let input = draft.makeEditInput(locale: locale) else {
            // The shared sections now reveal draft validation only after this
            // attempt. Leaving the draft untouched keeps every invalid value
            // visible for repair without presenting a persistence failure.
            return
        }

        // This is the one ordinary-edit persistence command. Do not retry or
        // issue a second update while waiting for the stored aggregate below.
        let didSave = workspace.editSubscription(
            id: subscription.id,
            input: input
        )

        guard didSave,
              workspace.editingValidationErrors.isEmpty,
              case .loaded(let savedSubscription, _, _) = workspace.detailState,
              savedSubscription.id == subscription.id
        else {
            // Validation or persistence failure keeps this editor (and its
            // draft) on screen. A successful command publishes the loaded
            // aggregate only after repository update has completed.
            saveFailed = true
            return
        }

        #if os(macOS)
        if let onSave {
            onSave()
        } else {
            draft = SubscriptionDraft.editing(
                subscription: savedSubscription,
                locale: locale
            )
            didAttemptSave = false
            workspace.beginEditing()
        }
        #else
        if let onSave {
            onSave()
        } else {
            dismiss()
        }
        #endif
    }

    private var isDirty: Bool {
        draft != initialDraft
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }
}

private struct EditorPaymentHistoryRow: View {
    let entry: SubscriptionHistoryEntry
    let timeZoneIdentifier: String
    let locale: Locale
    let canConfirm: (ExpectedCharge) -> Bool
    let onConfirm: (ExpectedCharge) -> Void

    var body: some View {
        switch entry {
        case .expected(let charge):
            HStack(spacing: 12) {
                historyDescription(
                    title: "Expected Charge",
                    date: charge.scheduledDate,
                    amount: charge.amount
                )

                if canConfirm(charge) {
                    Button {
                        onConfirm(charge)
                    } label: {
                        Label(
                            "Confirm Charge",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(
                        "subscription.history.expected.confirm"
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subscription.history.expected")

        case .confirmed(let charge):
            historyDescription(
                title: "Confirmed Payment",
                date: charge.chargedDate,
                amount: charge.amount
            )
            .accessibilityIdentifier("subscription.history.confirmed")

        case .priceChange(let change):
            historyDescription(
                title: "Price Change",
                date: change.effectiveDate,
                amount: change.amount
            )
            .accessibilityIdentifier("subscription.history.price-change")
        }
    }

    private func historyDescription(
        title: LocalizedStringKey,
        date: Date,
        amount: Money
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(
                    formattedBillingDate(
                        date,
                        timeZoneIdentifier: timeZoneIdentifier,
                        locale: locale
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(formattedMoney(amount))
        }
        .accessibilityElement(children: .combine)
    }
}
