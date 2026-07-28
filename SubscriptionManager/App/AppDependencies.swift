import Foundation
import SwiftData
import SubscriptionCore

@MainActor
struct AppDependencies {
    let modelContainer: ModelContainer
    let workspace: SubscriptionWorkspace

    static func live(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        storeDirectory: URL? = nil
    ) -> AppStartupState {
        let schema = Schema([SubscriptionRecord.self])

        return make {
            let configuration: ModelConfiguration
            switch try storeSelection(arguments: arguments) {
            case .namedUITesting(let token):
                let rootDirectory: URL
                if let storeDirectory {
                    rootDirectory = storeDirectory
                } else {
                    rootDirectory = try FileManager.default.url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                }
                let directory = rootDirectory.appending(
                    path: "SubscriptionManagerUITests",
                    directoryHint: .isDirectory
                )
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                configuration = ModelConfiguration(
                    "UITesting-\(token)",
                    schema: schema,
                    url: directory.appending(path: "\(token).store"),
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            case .ephemeralUITesting:
                configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
            case .production:
                configuration = ModelConfiguration(schema: schema)
            }
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        }
    }

    static func make(
        modelContainer: () throws -> ModelContainer
    ) -> AppStartupState {
        do {
            let modelContainer = try modelContainer()
            let repository = SwiftDataSubscriptionRepository(
                modelContainer: modelContainer
            )
            return .ready(
                AppDependencies(
                    modelContainer: modelContainer,
                    workspace: SubscriptionWorkspace(repository: repository)
                )
            )
        } catch {
            return .failed(AppStartupFailure(underlyingError: error))
        }
    }

    static func storeSelection(
        arguments: [String]
    ) throws -> AppStoreSelection {
        guard arguments.contains("--ui-testing") else {
            return .production
        }
        if let token = try namedUITestingStoreToken(in: arguments) {
            return .namedUITesting(token: token)
        }
        return .ephemeralUITesting
    }

    private static func namedUITestingStoreToken(
        in arguments: [String]
    ) throws -> String? {
        guard let argumentIndex = arguments.firstIndex(
            of: "--ui-testing-store"
        ) else {
            return nil
        }
        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            throw UITestingStoreError.missingToken
        }
        let token = arguments[valueIndex]
        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard !token.isEmpty,
              token.unicodeScalars.allSatisfy(allowedCharacters.contains)
        else {
            throw UITestingStoreError.invalidToken
        }
        return token
    }
}

enum AppStoreSelection: Equatable {
    case production
    case ephemeralUITesting
    case namedUITesting(token: String)
}

private enum UITestingStoreError: Error {
    case missingToken
    case invalidToken
}

struct AppStartupFailure {
    let underlyingError: any Error
}

enum AppStartupState {
    case ready(AppDependencies)
    case failed(AppStartupFailure)
}
