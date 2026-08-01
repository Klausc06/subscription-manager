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

    @State private var draft: SubscriptionDraft
    @State private var dateTaskPresentation: EditDateTaskPresentation?
    @State private var didAttemptSave = false
    @State private var saveFailed = false
    private let now: Date

    init(
        workspace: SubscriptionWorkspace,
        subscription: Subscription,
        locale: Locale = .current,
        now: Date = Date()
    ) {
        self.workspace = workspace
        self.subscription = subscription
        self.now = now
        _draft = State(
            initialValue: SubscriptionDraft.editing(
                subscription: subscription,
                locale: locale
            )
        )
    }

    var body: some View {
        Form {
            SubscriptionEditorSections(
                draft: $draft,
                status: editorStatus,
                nextExpectedCharge: editorNextExpectedCharge,
                catalogOfferAdjustment: workspace.catalogOfferAdjustment(
                    for: subscription
                ),
                showsValidation: didAttemptSave,
                onEditDate: beginDateTask
            )

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
        .toolbar {
            // The enclosing NavigationStack supplies the system Back action.
            // Edit intentionally exposes only Save here so a second Cancel
            // action cannot compete with that native navigation affordance.
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
        workspace.editSubscription(id: subscription.id, input: input)

        guard workspace.editingValidationErrors.isEmpty,
              case .loaded(let savedSubscription, _, _) = workspace.detailState,
              savedSubscription.id == subscription.id
        else {
            // Validation or persistence failure keeps this editor (and its
            // draft) on screen. A successful command publishes the loaded
            // aggregate only after repository update has completed.
            saveFailed = true
            return
        }

        dismiss()
    }
}
