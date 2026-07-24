import XCTest
@testable import Cotabby

/// Locks the latency-oriented generation defaults that bound llama prefill + decode cost.
/// Recent Requests Duration is engine wall clock; these knobs are what move that number.
final class SuggestionLatencyDefaultsTests: XCTestCase {
    func test_standardConfigurationUsesLatencyFirstLengthAndPromptCaps() {
        let configuration = SuggestionConfiguration.standard

        XCTAssertEqual(configuration.defaultWordCountPreset, .fourToSeven)
        XCTAssertEqual(configuration.maxPrefixWords, 80)
        XCTAssertEqual(configuration.maxPrefixCharacters, 1200)
        XCTAssertEqual(configuration.llamaPromptTokenBudget, 1024)
        XCTAssertLessThanOrEqual(
            SuggestionConfiguration.derivedLlamaPromptTokenBudget,
            SuggestionConfiguration.llamaPromptTokenBudgetCap
        )
    }

    func test_runtimeContextWindowMatchesLatencyProfile() {
        XCTAssertEqual(LlamaRuntimeConfiguration.default.contextWindowTokens, 1536)
        XCTAssertEqual(LlamaRuntimeConfiguration.default.batchSize, 512)
        XCTAssertEqual(LlamaRuntimeConfiguration.default.gpuLayerCount, -1)
    }

    func test_fourToSevenEnglishBudgetStaysNearTenTokens() {
        let tokens = SuggestionWordRange.predictionTokenBudget(
            highWords: SuggestionWordCountPreset.fourToSeven.range.highWords,
            tokensPerWord: 1.3
        )
        XCTAssertEqual(tokens, 10)
    }

    func test_basePromptDefaultBudgetStaysAlignedWithTokenCap() {
        XCTAssertEqual(BaseCompletionPromptRenderer.defaultContextBudget, 1600)
    }
}
