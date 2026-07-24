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
        XCTAssertEqual(
            SuggestionConfiguration.llamaPromptTokenBudgetWhenKVReuseUnavailable,
            768
        )
        XCTAssertLessThan(
            SuggestionConfiguration.llamaPromptTokenBudgetWhenKVReuseUnavailable,
            SuggestionConfiguration.llamaPromptTokenBudgetCap
        )
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

    func test_latencyFirstPreferredModelOrderPutsSmallerQwenFirst() {
        XCTAssertEqual(
            LlamaRuntimeConfiguration.default.preferredModelNames.first,
            "Qwen3.5-0.8B-Base.i1-Q6_K.gguf"
        )
        XCTAssertEqual(
            Array(LlamaRuntimeConfiguration.default.preferredModelNames.prefix(2)),
            [
                "Qwen3.5-0.8B-Base.i1-Q6_K.gguf",
                "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"
            ]
        )
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
