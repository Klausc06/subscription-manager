import Foundation
import SubscriptionCore

@main
struct CatalogValidator {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard let path = arguments.first, arguments.count <= 2 else {
            fail("usage: CatalogValidator <catalog.json> [audit.jsonl]")
        }

        do {
            let data = try Data(contentsOf: URL(filePath: path))
            let snapshot = try JSONDecoder().decode(
                CatalogSnapshot.self,
                from: data
            )
            print(
                "valid catalog: schema=\(snapshot.schemaVersion) "
                    + "version=\(snapshot.catalogVersion) "
                    + "presets=\(snapshot.presets.count) "
                    + "offers=\(snapshot.presets.flatMap(\.offers).count) "
                    + "selectable=\(selectableOfferCount(in: snapshot)) "
                    + "reviewRequired=\(reviewRequiredOfferCount(in: snapshot))"
            )

            if let auditPath = arguments.dropFirst().first {
                let rows = try loadAuditRows(from: String(auditPath))
                printAuditSummary(rows)
            }
        } catch {
            fail("invalid catalog: \(error)")
        }
    }

    private static func selectableOfferCount(in snapshot: CatalogSnapshot) -> Int {
        snapshot.presets
            .flatMap(\.offers)
            .filter { $0.reviewStatus == .verified }
            .count
    }

    private static func reviewRequiredOfferCount(in snapshot: CatalogSnapshot) -> Int {
        snapshot.presets
            .flatMap(\.offers)
            .filter { $0.reviewStatus == .reviewRequired }
            .count
    }

    private static func loadAuditRows(
        from path: String
    ) throws -> [CatalogAuditRow] {
        let data = try Data(contentsOf: URL(filePath: path))
        let decoder = JSONDecoder()
        var rows: [CatalogAuditRow] = []

        for (lineNumber, line) in String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .enumerated()
        {
            do {
                let row = try decoder.decode(
                    CatalogAuditRow.self,
                    from: Data(line.utf8)
                )
                try row.validate()
                rows.append(row)
            } catch {
                throw CatalogAuditError(
                    lineNumber: lineNumber + 1,
                    message: String(describing: error)
                )
            }
        }

        guard !rows.isEmpty else {
            throw CatalogAuditError(lineNumber: nil, message: "manifest is empty")
        }
        return rows
    }

    private static func printAuditSummary(_ rows: [CatalogAuditRow]) {
        let grouped = Dictionary(grouping: rows, by: \.batch)
        print("audit manifest: rows=\(rows.count) batches=\(grouped.count)")
        for batch in grouped.keys.sorted() {
            let batchRows = grouped[batch, default: []]
            let counts = Dictionary(
                grouping: batchRows,
                by: \.status
            ).mapValues(\.count)
            print(
                "  \(batch): verified=\(counts["verified", default: 0]) "
                    + "conflict=\(counts["conflict", default: 0]) "
                    + "unresolved=\(counts["unresolved", default: 0]) "
                    + "not_checked=\(counts["not_checked", default: 0])"
            )
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}

private struct CatalogAuditRow: Decodable {
    let batch: String
    let service: String
    let plan: String?
    let variant: String?
    let market: String
    let purchaseChannel: String
    let status: String
    let evidenceIDs: [String]
    let priceMinorUnits: Int?
    let currency: String?
    let billingInterval: String?
    let renewalMeaning: String?

    func validate() throws {
        let allowedStatuses = Set([
            "verified", "conflict", "unresolved", "not_checked"
        ])
        let hasPlanOrVariant = [plan, variant].contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        let hasVerifiedProof = status != "verified"
            || (!evidenceIDs.isEmpty
                && (priceMinorUnits ?? 0) > 0
                && !(currency ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && !(billingInterval ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && !(renewalMeaning ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty)
        guard !batch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !market.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !purchaseChannel.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              allowedStatuses.contains(status),
              hasPlanOrVariant,
              hasVerifiedProof
        else {
            throw CatalogAuditError(
                lineNumber: nil,
                message: "missing required audit field or invalid status"
            )
        }
    }
}

private struct CatalogAuditError: Error, CustomStringConvertible {
    let lineNumber: Int?
    let message: String

    var description: String {
        if let lineNumber {
            return "audit manifest line \(lineNumber): \(message)"
        }
        return "audit manifest: \(message)"
    }
}
