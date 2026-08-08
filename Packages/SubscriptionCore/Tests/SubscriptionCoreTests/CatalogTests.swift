import Foundation
import SubscriptionCore
import Testing

@Suite("Bundled catalog domain")
struct CatalogTests {
    @Test("Legacy catalog presets decode without offers")
    func legacyCatalogPresetsDecodeWithoutOffers() throws {
        let preset = try JSONDecoder().decode(
            CatalogPreset.self,
            from: Data("""
            {
              "id": "legacy",
              "serviceName": { "en": "Legacy", "zhHans": "旧服务" },
              "category": { "en": "Other", "zhHans": "其他" },
              "suggestedInterval": "monthly",
              "managementURL": null,
              "icon": "other",
              "assetProvenance": {
                "kind": "originalSymbol",
                "license": "CC0-1.0",
                "source": "legacy"
              }
            }
            """.utf8)
        )

        #expect(preset.matchAliases.isEmpty)
        #expect(preset.offers.isEmpty)
        #expect(preset.categoryID == "other")
    }

    @Test("Stable category IDs round-trip and titles remain localized")
    func stableCategoryIDRoundTrips() throws {
        let preset = CatalogPreset(
            id: "chatgpt",
            serviceName: CatalogLocalizedText(en: "ChatGPT", zhHans: "ChatGPT"),
            category: CatalogLocalizedText(en: "AI", zhHans: "AI 工具"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .productivity,
            categoryID: "ai"
        )

        let decoded = try JSONDecoder().decode(
            CatalogPreset.self,
            from: JSONEncoder().encode(preset)
        )

        #expect(decoded.categoryID == "ai")
        #expect(decoded.category.en == "AI")
        #expect(decoded.category.zhHans == "AI 工具")
    }

    @Test("Category filtering uses the stable ID in both locales")
    func categoryFilteringUsesStableIDInBothLocales() throws {
        let chatGPT = CatalogPreset(
            id: "chatgpt",
            serviceName: CatalogLocalizedText(en: "ChatGPT", zhHans: "ChatGPT"),
            category: CatalogLocalizedText(en: "AI", zhHans: "AI 工具"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .productivity,
            categoryID: "ai",
            offers: [verifiedOffer()]
        )
        let productivity = CatalogPreset(
            id: "wps-office",
            serviceName: CatalogLocalizedText(en: "WPS Office", zhHans: "WPS Office"),
            category: CatalogLocalizedText(en: "Productivity", zhHans: "效率"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .productivity,
            categoryID: "productivity",
            offers: [verifiedOffer(id: "productivity-monthly-us-web")]
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [chatGPT, productivity]
        )

        #expect(
            Set(snapshot.categories(locale: Locale(identifier: "en")).map(\.id))
                == ["ai", "productivity"]
        )
        #expect(
            Set(snapshot.categories(locale: Locale(identifier: "zh-Hans")).map(\.id))
                == ["ai", "productivity"]
        )
        #expect(
            snapshot.categories(locale: Locale(identifier: "zh-Hans"))
                .first(where: { $0.id == "ai" })?.title.zhHans == "AI 工具"
        )
        #expect(chatGPT.categoryID == "ai")
        #expect(productivity.categoryID != chatGPT.categoryID)
    }

    @Test("Catalog rejects empty or normalized duplicate match aliases")
    func catalogRejectsInvalidMatchAliases() {
        for aliases in [
            ["   "],
            ["ChatGPT Plus", "  chátgpt   PLUS "],
        ] {
            let preset = CatalogPreset(
                id: "chatgpt",
                serviceName: CatalogLocalizedText(
                    en: "ChatGPT",
                    zhHans: "ChatGPT"
                ),
                category: CatalogLocalizedText(
                    en: "Productivity",
                    zhHans: "效率"
                ),
                suggestedInterval: .monthly,
                managementURL: nil,
                icon: .productivity,
                matchAliases: aliases
            )

            do {
                _ = try CatalogSnapshot(
                    schemaVersion: CatalogSnapshot.currentSchemaVersion,
                    presets: [preset]
                )
                Issue.record("Expected invalid aliases to be rejected.")
            } catch let error as CatalogLoadError {
                #expect(error.field == .matchAliases)
            } catch {
                Issue.record("Expected CatalogLoadError, got \(error)")
            }
        }
    }

    @Test("Catalog rejects preset identifiers with surrounding whitespace")
    func catalogRejectsPresetIdentifiersWithSurroundingWhitespace() {
        for id in [
            " chatgpt",
            "chatgpt ",
            "\nchatgpt",
            "chatgpt\n",
            "\tchatgpt\t",
            "   \n\t"
        ] {
            do {
                _ = try CatalogSnapshot(
                    schemaVersion: CatalogSnapshot.currentSchemaVersion,
                    presets: [
                        CatalogPreset(
                            id: id,
                            serviceName: CatalogLocalizedText(
                                en: "Example",
                                zhHans: "示例"
                            ),
                            category: CatalogLocalizedText(
                                en: "Other",
                                zhHans: "其他"
                            ),
                            suggestedInterval: .monthly,
                            managementURL: nil,
                            icon: .other,
                            assetProvenance: CatalogAssetProvenance(
                                kind: .originalSymbol,
                                license: "CC0-1.0",
                                source: id.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            )
                        )
                    ]
                )
                Issue.record("Expected padded preset ID to be rejected: \(id.debugDescription)")
            } catch let error as CatalogLoadError {
                #expect(error.field == .id)
            } catch {
                Issue.record("Expected CatalogLoadError, got \(error)")
            }
        }

        do {
            _ = try CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                presets: [catalogPreset(id: "chatgpt")]
            )
        } catch {
            Issue.record("Expected clean preset ID to be accepted, got \(error)")
        }
    }

    @Test("Catalog canonicalizes legacy preset identifiers")
    func catalogCanonicalizesLegacyPresetIdentifiers() throws {
        let preset = CatalogPreset(
            id: "chatgpt",
            serviceName: CatalogLocalizedText(en: "ChatGPT", zhHans: "ChatGPT"),
            category: CatalogLocalizedText(en: "Productivity", zhHans: "效率"),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://chatgpt.com/"),
            icon: .productivity,
            legacyPresetIDs: ["chatgpt-plus"],
            offers: [verifiedOffer()]
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [preset]
        )

        #expect(snapshot.canonicalPresetID(for: "chatgpt") == "chatgpt")
        #expect(snapshot.canonicalPresetID(for: "chatgpt-plus") == "chatgpt")
        #expect(snapshot.canonicalPresetID(for: "unknown") == nil)
    }

    @Test("Catalog rejects hostless preset management URLs")
    func catalogRejectsHostlessPresetManagementURLs() {
        for rawURL in ["https:/account", "https:javascript:alert(1)"] {
            guard let managementURL = URL(string: rawURL) else {
                Issue.record("Expected URL to be constructible: \(rawURL)")
                continue
            }

            do {
                _ = try CatalogSnapshot(
                    schemaVersion: CatalogSnapshot.currentSchemaVersion,
                    presets: [catalogPreset(managementURL: managementURL)]
                )
                Issue.record(
                    "Expected hostless management URL to be rejected: \(rawURL)"
                )
            } catch let error as CatalogLoadError {
                #expect(error.field == .managementURL)
            } catch {
                Issue.record("Expected CatalogLoadError, got \(error)")
            }
        }
    }

    @Test("Verified catalog offers round-trip with provenance")
    func verifiedCatalogOffersRoundTrip() throws {
        let offer = CatalogOffer(
            id: "plus-monthly-us-web",
            planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
            price: Money(minorUnits: 2_000, currency: .usd),
            billingInterval: .monthly,
            market: "US",
            purchaseChannel: .web,
            sourceURL: try #require(URL(string: "https://example.com/pricing")),
            verifiedOn: "2026-07-30",
            reviewStatus: .verified
        )
        let preset = catalogPreset(
            offers: [offer],
            matchAliases: ["Example Plus"]
        )

        let decoded = try JSONDecoder().decode(
            CatalogPreset.self,
            from: JSONEncoder().encode(preset)
        )

        #expect(decoded.offers == [offer])
        #expect(decoded.matchAliases == ["Example Plus"])
    }

    @Test("Catalog rejects duplicate offer identifiers")
    func catalogRejectsDuplicateOfferIdentifiers() {
        let offer = verifiedOffer(id: "duplicate")

        assertOffersAreInvalid([offer, offer])
    }

    @Test("Catalog rejects zero-price offers")
    func catalogRejectsZeroPriceOffers() {
        assertOffersAreInvalid([
            catalogOffer(price: Money(minorUnits: 0, currency: .usd))
        ])
    }

    @Test("Catalog rejects offers with non-HTTPS sources")
    func catalogRejectsOffersWithNonHTTPSSources() {
        assertOffersAreInvalid([
            catalogOffer(sourceURL: URL(string: "http://example.com/pricing")!)
        ])
    }

    @Test("Catalog rejects offers with empty markets")
    func catalogRejectsOffersWithEmptyMarkets() {
        assertOffersAreInvalid([catalogOffer(market: " \n ")])
    }

    @Test("Catalog rejects offers with empty verification dates")
    func catalogRejectsOffersWithEmptyVerificationDates() {
        assertOffersAreInvalid([catalogOffer(verifiedOn: "")])
    }

    @Test("Catalog rejects offers with invalid billing intervals")
    func catalogRejectsOffersWithInvalidBillingIntervals() {
        assertOffersAreInvalid([
            catalogOffer(billingInterval: .custom(value: 0, unit: .month))
        ])
    }

    @Test("Catalog rejects custom weekly intervals that overflow day arithmetic")
    func catalogRejectsOverflowingCustomWeeklyIntervals() {
        assertOffersAreInvalid([
            catalogOffer(
                billingInterval: .custom(value: .max, unit: .week)
            )
        ])
    }

    @Test("Catalog validation identifies the preset and field")
    func catalogValidationIdentifiesPresetAndField() throws {
        let preset = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .music,
            assetProvenance: CatalogAssetProvenance(
                kind: .originalSymbol,
                license: "CC0-1.0",
                source: "unrelated-source"
            )
        )

        do {
            _ = try CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                catalogVersion: 1,
                presets: [preset]
            )
            Issue.record("Expected invalid provenance to be rejected")
        } catch let error as CatalogLoadError {
            #expect(error.presetID == "music.example")
            #expect(error.field == .assetProvenance)
        }
    }

    @Test("Catalog snapshots carry a positive catalog version and CC0 provenance")
    func catalogSnapshotCarriesVersionAndProvenance() throws {
        let preset = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(en: "Music", zhHans: "音乐"),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/manage"),
            icon: .music,
            assetProvenance: CatalogAssetProvenance(
                kind: .originalSymbol,
                license: "CC0-1.0",
                source: "music.example"
            ),
            offers: [verifiedOffer()]
        )

        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            catalogVersion: 2,
            presets: [preset]
        )

        #expect(snapshot.catalogVersion == 2)
        #expect(preset.assetProvenance.license == "CC0-1.0")
    }

    @Test("Catalog search uses localized service and category text")
    func localizedSearchUsesServiceAndCategory() throws {
        let music = CatalogPreset(
            id: "music.example",
            serviceName: CatalogLocalizedText(
                en: "Example Music",
                zhHans: "示例音乐"
            ),
            category: CatalogLocalizedText(
                en: "Music",
                zhHans: "音乐"
            ),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/manage"),
            icon: .music,
            offers: [verifiedOffer()]
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [music]
        )

        #expect(
            snapshot.search(
                query: "音乐",
                locale: Locale(identifier: "zh-Hans")
            ) == [music]
        )
        #expect(
            snapshot.search(
                query: "music",
                locale: Locale(identifier: "en")
            ) == [music]
        )
    }

    @Test("Catalog search matches unaccented localized text")
    func searchMatchesUnaccentedLocalizedText() throws {
        let cafe = CatalogPreset(
            id: "cafe.example",
            serviceName: CatalogLocalizedText(
                en: "Café",
                zhHans: "咖啡馆"
            ),
            category: CatalogLocalizedText(en: "Food", zhHans: "餐饮"),
            suggestedInterval: .monthly,
            managementURL: URL(string: "https://example.com/manage"),
            icon: .other,
            offers: [verifiedOffer()]
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [cafe]
        )

        #expect(
            snapshot.search(
                query: "cafe",
                locale: Locale(identifier: "en")
            ) == [cafe]
        )
    }

    @Test("Catalog search includes explicit service aliases")
    func searchIncludesAliases() throws {
        let membership = CatalogPreset(
            id: "taobao-88vip",
            serviceName: CatalogLocalizedText(
                en: "Taobao Membership",
                zhHans: "淘宝会员"
            ),
            category: CatalogLocalizedText(
                en: "Membership",
                zhHans: "会员"
            ),
            suggestedInterval: .yearly,
            managementURL: URL(string: "https://www.taobao.com/"),
            icon: .membership,
            matchAliases: ["88VIP"],
            offers: [verifiedOffer()]
        )
        let snapshot = try CatalogSnapshot(
            schemaVersion: CatalogSnapshot.currentSchemaVersion,
            presets: [membership]
        )

        #expect(
            snapshot.search(
                query: "88",
                locale: Locale(identifier: "en")
            ) == [membership]
        )
    }

    @Test("Catalog snapshot rejects duplicate stable identifiers")
    func catalogSnapshotRejectsDuplicateIdentifiers() {
        let preset = CatalogPreset(
            id: "duplicate.example",
            serviceName: CatalogLocalizedText(en: "Duplicate", zhHans: "重复"),
            category: CatalogLocalizedText(en: "Other", zhHans: "其他"),
            suggestedInterval: .monthly,
            managementURL: nil,
            icon: .other
        )

        #expect(throws: CatalogLoadError.self) {
            try CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                presets: [preset, preset]
            )
        }
    }

    private func catalogPreset(
        id: String = "example",
        managementURL: URL? = nil,
        offers: [CatalogOffer] = [],
        matchAliases: [String] = []
    ) -> CatalogPreset {
        CatalogPreset(
            id: id,
            serviceName: CatalogLocalizedText(en: "Example", zhHans: "示例"),
            category: CatalogLocalizedText(en: "Other", zhHans: "其他"),
            suggestedInterval: .monthly,
            managementURL: managementURL,
            icon: .other,
            matchAliases: matchAliases,
            offers: offers.isEmpty ? [verifiedOffer()] : offers
        )
    }

    private func verifiedOffer(id: String = "plus-monthly-us-web") -> CatalogOffer {
        catalogOffer(id: id)
    }

    private func catalogOffer(
        id: String = "plus-monthly-us-web",
        price: Money = Money(minorUnits: 2_000, currency: .usd),
        billingInterval: BillingInterval = .monthly,
        market: String = "US",
        sourceURL: URL = URL(string: "https://example.com/pricing")!,
        verifiedOn: String = "2026-07-30"
    ) -> CatalogOffer {
        CatalogOffer(
            id: id,
            planName: CatalogLocalizedText(en: "Plus", zhHans: "Plus"),
            price: price,
            billingInterval: billingInterval,
            market: market,
            purchaseChannel: .web,
            sourceURL: sourceURL,
            verifiedOn: verifiedOn,
            reviewStatus: .verified
        )
    }

    private func assertOffersAreInvalid(_ offers: [CatalogOffer]) {
        do {
            _ = try CatalogSnapshot(
                schemaVersion: CatalogSnapshot.currentSchemaVersion,
                presets: [catalogPreset(offers: offers)]
            )
            Issue.record("Expected invalid offers to be rejected")
        } catch let error as CatalogLoadError {
            #expect(error.field == .offers)
        } catch {
            Issue.record("Expected CatalogLoadError, got \(error)")
        }
    }
}
