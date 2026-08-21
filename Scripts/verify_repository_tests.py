import tempfile
import unittest
from pathlib import Path

from Scripts.verify_repository import (
    DuplicateJSONKey,
    has_complete_translation,
    load_json,
    verify_mac_new_item_command,
    verify_source,
)


class RepositoryVerificationTests(unittest.TestCase):
    def test_duplicate_json_keys_are_rejected(self) -> None:
        with self.assertRaises(DuplicateJSONKey):
            load_json('{"value": 1, "value": 2}')

    def test_every_translation_leaf_must_be_complete(self) -> None:
        localization = {
            "variations": {
                "plural": {
                    "one": {
                        "stringUnit": {
                            "state": "translated",
                            "value": "One item",
                        }
                    },
                    "other": {
                        "stringUnit": {
                            "state": "translated",
                            "value": "Many items",
                        }
                    },
                }
            }
        }

        self.assertTrue(has_complete_translation(localization))
        localization["variations"]["plural"]["other"]["stringUnit"][
            "state"
        ] = "new"
        self.assertFalse(has_complete_translation(localization))

    def verify_swift_fixture(self, source: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Fixture.swift"
            path.write_text(source, encoding="utf-8")
            return verify_source(path)

    def test_swift_policy_ignores_noncode_syntax(self) -> None:
        errors = self.verify_swift_fixture(
            r'''
            let bareRegex = /try! String\(decoding:/
            let rawRegex = #/try! String\(decoding:/#
            let literal = #"try! String(decoding:)"#
            let conditionalLiteral = """
            #if DEBUG
            try! String(decoding: bytes, as: UTF8.self)
            #else
            String(decoding: bytes, as: UTF8.self)
            #endif
            """
            let unmatchedConditionalLiteral = """
            #if DEBUG
            try! String(decoding: bytes, as: UTF8.self)
            """
            let conditionalRegex = #/
            #elseif STAGING
            try! String(decoding: bytes, as: UTF8.self)
            /#
            // try! String(decoding:)
            /* outer /* nested try! */ String(decoding:) */
            /*
            #if DEBUG
            try! String(decoding: bytes, as: UTF8.self)
            #endif
            */
            /*
            #else
            try! String(decoding: bytes, as: UTF8.self)
            */
            '''
        )

        self.assertEqual([], errors)

    def test_swift_policy_mixes_real_conditionals_with_noncode_lookalikes(
        self,
    ) -> None:
        errors = self.verify_swift_fixture(
            '''
            let literal = """
            #if STRING_LOOKALIKE
            try! loadFromString()
            """
            /*
            #elseif COMMENT_LOOKALIKE
            try! loadFromComment()
            */
            #if DEBUG
            let value = loadDebug()
            #else
            let value = try! loadRelease()
            #endif
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("force try expressions: at least 1", errors[0])
        self.assertNotIn("Swift parser failed", errors[0])

    def test_swift_policy_rejects_executable_constructs(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            let forced = try! load()
            let interpolated = "value: \\(try! load())"
            let decoded = String(decoding: bytes, as: UTF8.self)
            '''
        )

        self.assertEqual(2, len(errors))
        self.assertIn("force try expressions: at least 2", errors[0])
        self.assertIn("lossy UTF-8 decoding uses: at least 1", errors[1])

    def test_swift_policy_rejects_every_decoding_as_call_spelling(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            let direct = String(decoding: bytes, as: UTF8.self)
            let qualified = Swift.String(decoding: bytes, as: UTF8.self)
            let explicit = String.init(decoding: bytes, as: UTF8.self)
            let contextual: String = .init(decoding: bytes, as: UTF8.self)
            typealias Text = String
            let aliased = Text(decoding: bytes, as: UTF8.self)
            let initializer = String.init(decoding:as:)
            let contextualInitializer: ([UInt8], UTF8.Type) -> String =
                .init(decoding:as:)
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("lossy UTF-8 decoding uses: at least 7", errors[0])

    def test_swift_policy_inspects_every_conditional_branch(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            let sharedForced = try! loadShared()
            let sharedDecoded = String(decoding: sharedBytes, as: UTF8.self)
            #if DEBUG
            let debugForced = try! loadDebug()
            let debugDecoded = String(decoding: debugBytes, as: UTF8.self)
            #elseif STAGING
            let stagingForced = try! loadStaging()
            let stagingDecoded = String(
                decoding: stagingBytes,
                as: UTF8.self
            )
            #else
            let releaseForced = try! loadRelease()
            let releaseDecoded = Swift.String.init(
                decoding: releaseBytes,
                as: UTF8.self
            )
            #endif
            '''
        )

        self.assertEqual(2, len(errors))
        self.assertIn(
            "force try expressions: at least 2 in a compiler-parsed variant",
            errors[0],
        )
        self.assertIn(
            "lossy UTF-8 decoding uses: at least 2 in a compiler-parsed variant",
            errors[1],
        )

    def test_swift_policy_rejects_each_conditional_clause(self) -> None:
        cases = {
            "if": ("try! loadDebug()", "loadStaging()", "loadRelease()"),
            "elseif": ("loadDebug()", "try! loadStaging()", "loadRelease()"),
            "else": ("loadDebug()", "loadStaging()", "try! loadRelease()"),
        }

        for clause, (debug, staging, release) in cases.items():
            with self.subTest(clause=clause):
                errors = self.verify_swift_fixture(
                    f'''
                    #if DEBUG
                    let value = {debug}
                    #elseif STAGING
                    let value = {staging}
                    #else
                    let value = {release}
                    #endif
                    '''
                )

                self.assertEqual(1, len(errors))
                self.assertIn("force try expressions: at least 1", errors[0])

    def test_swift_policy_preserves_conditional_syntax_validation(self) -> None:
        fixtures = {
            "unterminated": '''
                #if DEBUG
                let value = 1
                ''',
            "misplaced": '''
                let value =
                #if DEBUG
                loadDebug()
                #else
                loadRelease()
                #endif
                ''',
        }

        for syntax, source in fixtures.items():
            with self.subTest(syntax=syntax):
                errors = self.verify_swift_fixture(source)

                self.assertEqual(1, len(errors))
                self.assertIn("Swift parser failed", errors[0])

    def test_swift_policy_inspects_nested_conditional_branches(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            #if DEBUG
                #if FEATURE
                let debugFeatureForced = try! loadDebugFeature()
                #else
                let debugFallbackForced = try! loadDebugFallback()
                #endif
            #elseif STAGING
            let stagingForced = try! loadStaging()
            #else
            let releaseForced = try! loadRelease()
            #endif
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("force try expressions: at least 1", errors[0])

    def test_swift_policy_rejects_each_nested_conditional_clause(self) -> None:
        cases = {
            "nested if": (
                "try! loadDebugFeature()",
                "loadDebugFallback()",
                "loadStaging()",
                "loadRelease()",
            ),
            "nested else": (
                "loadDebugFeature()",
                "try! loadDebugFallback()",
                "loadStaging()",
                "loadRelease()",
            ),
            "outer elseif": (
                "loadDebugFeature()",
                "loadDebugFallback()",
                "try! loadStaging()",
                "loadRelease()",
            ),
            "outer else": (
                "loadDebugFeature()",
                "loadDebugFallback()",
                "loadStaging()",
                "try! loadRelease()",
            ),
        }

        for clause, values in cases.items():
            feature, fallback, staging, release = values
            with self.subTest(clause=clause):
                errors = self.verify_swift_fixture(
                    f'''
                    #if DEBUG
                        #if FEATURE
                        let value = {feature}
                        #else
                        let value = {fallback}
                        #endif
                    #elseif STAGING
                    let value = {staging}
                    #else
                    let value = {release}
                    #endif
                    '''
                )

                self.assertEqual(1, len(errors))
                self.assertIn("force try expressions: at least 1", errors[0])

    def test_swift_policy_parses_mutually_exclusive_accessor_branches(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            var loadedValue: Int {
                #if DEBUG
                get { loadDebug() }
                #else
                get { try! loadRelease() }
                #endif
            }
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("force try expressions: at least 1", errors[0])

    def test_swift_policy_preserves_required_statement_context(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            switch state {
            case .ready:
                #if DEBUG
                loadDebug()
                #else
                try! loadRelease()
                #endif
            case .failed:
                break
            }
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("force try expressions: at least 1", errors[0])

    def test_swift_policy_selects_sibling_nested_required_contexts(self) -> None:
        errors = self.verify_swift_fixture(
            '''
            #if FEATURE
            switch state {
            case .first:
                #if DEBUG
                loadFirstDebug()
                #else
                loadFirstRelease()
                #endif
            case .second:
                #if DEBUG
                loadSecondDebug()
                #else
                try! loadSecondRelease()
                #endif
            }
            #else
            let fallback = 0
            #endif
            '''
        )

        self.assertEqual(1, len(errors))
        self.assertIn("force try expressions", errors[0])
        self.assertNotIn("Swift parser failed", errors[0])

    def test_mac_new_item_command_requires_replacement(self) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene {
                    WindowGroup {}
                        .commands { MacWindowCommands() }
                }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    CommandGroup(replacing: .newItem) {
                        Button("Add Subscription") {}
                    }
                    CommandGroup(after: .toolbar) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual([], errors)

    def test_mac_new_item_command_ignores_lookalikes_and_rejects_append(self) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene {
                    WindowGroup {}
                        .commands { MacWindowCommands() }
                }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    let lookalike = "CommandGroup(replacing: .newItem)"
                    // CommandGroup(replacing: .newItem) {}
                    CommandGroup(after: .newItem) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual(2, len(errors))
        self.assertIn("exactly one CommandGroup(replacing: .newItem)", errors[0])
        self.assertIn("CommandGroup(after: .newItem)", errors[1])

    def test_mac_new_item_command_must_be_installed_on_the_app_scene(self) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene { WindowGroup {} }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    CommandGroup(replacing: .newItem) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual(1, len(errors))
        self.assertIn("installs MacWindowCommands exactly once", errors[0])

    def test_mac_new_item_command_rejects_installation_in_dead_helper(self) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene { WindowGroup {} }

                private var unusedScene: some Scene {
                    WindowGroup {}
                        .commands { MacWindowCommands() }
                }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    CommandGroup(replacing: .newItem) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual(1, len(errors))
        self.assertIn("installs MacWindowCommands exactly once", errors[0])

    def test_mac_new_item_command_rejects_unattached_commands_lookalike(
        self,
    ) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene {
                    commands { MacWindowCommands() }
                    WindowGroup {}
                }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    CommandGroup(replacing: .newItem) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual(1, len(errors))
        self.assertIn("installs MacWindowCommands exactly once", errors[0])

    def test_mac_new_item_command_rejects_replacement_in_dead_helper(self) -> None:
        errors = verify_mac_new_item_command(
            '''
            struct SubscriptionManagerApp: App {
                var body: some Scene {
                    WindowGroup {}
                        .commands { MacWindowCommands() }
                }
            }
            #if os(macOS)
            private struct MacWindowCommands: Commands {
                var body: some Commands {
                    CommandGroup(after: .toolbar) {}
                }

                private var unusedCommands: some Commands {
                    CommandGroup(replacing: .newItem) {}
                }
            }
            #endif
            ''',
            "SubscriptionManager/App/SubscriptionManagerApp.swift",
        )

        self.assertEqual(1, len(errors))
        self.assertIn("exactly one CommandGroup(replacing: .newItem)", errors[0])


if __name__ == "__main__":
    unittest.main()
