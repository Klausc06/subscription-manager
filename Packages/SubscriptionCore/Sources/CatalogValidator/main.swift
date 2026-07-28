import Foundation
import SubscriptionCore

@main
struct CatalogValidator {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        guard let path = arguments.first, arguments.count == 1 else {
            fail("usage: CatalogValidator <catalog.json>")
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
                    + "presets=\(snapshot.presets.count)"
            )
        } catch {
            fail("invalid catalog: \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
