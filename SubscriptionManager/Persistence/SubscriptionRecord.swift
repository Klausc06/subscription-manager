import Foundation
import SwiftData

@Model
final class SubscriptionRecord {
    var id: UUID

    init(id: UUID) {
        self.id = id
    }
}
