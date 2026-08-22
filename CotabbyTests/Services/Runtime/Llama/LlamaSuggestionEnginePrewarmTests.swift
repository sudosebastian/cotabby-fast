import CoreGraphics
import Foundation
import XCTest
@testable import Cotabby

/// Tests for the llama half of prewarm-on-focus: a focus change used to leave the llama engine's
/// `prewarm` as the protocol no-op while the focus reset destroyed the native sequence, so the
/// first suggestion in every field paid the full cold prompt decode. These pin the new contract:
/// prewarm prefills through the runtime and primes the reuse hint only when the prefill succeeded.
/// Compatible generates await an in-flight prewarm instead of aborting it (abort collapses hybrid
/// KV to a cold fresh prefill).
@MainActor
final class LlamaSuggestionEnginePrewarmTests: XCTestCase {

    func test_prewarm_prefillsAndPrimesTheReuseHint() async throws {
        let runtime = RecordingPrewarmRuntime()
        let engine = LlamaSuggestionEngine(runtimeManager: runtime)
        let request = makeRequest(prompt: "hello wor")

        await engine.prewarm(for: request)

        XCTAssertEqual(runtime.prefillPrompts, ["hello wor"])

        _ = try await engine.generateSuggestion(for: request)
        XCTAssertEqual(
            runtime.generateCachedPrefixBytes,
            ["hello wor".utf8.count],
            "A successful prefill should let the next identical-context request advertise full reuse."
        )
    }

    func test_failedPrewarm_leavesReuseHintCold() async throws {
        let runtime = RecordingPrewarmRuntime()
        runtime.prefillError = LlamaRuntimeError.unavailable("not loaded")
        let engine = LlamaSuggestionEngine(runtimeManager: runtime)
        let request = makeRequest(prompt: "hello wor")

        await engine.prewarm(for: request)

        _ = try await engine.generateSuggestion(for: request)
        XCTAssertEqual(
            runtime.generateCachedPrefixBytes,
            [nil],
            "A failed prefill must not advertise reuse the native cache cannot back."
        )
    }

    func test_resetClearsThePrimedHint() async throws {
        let runtime = RecordingPrewarmRuntime()
        let engine = LlamaSuggestionEngine(runtimeManager: runtime)
        let request = makeRequest(prompt: "hello wor")

        await engine.prewarm(for: request)
        await engine.resetCachedGenerationContext()

        _ = try await engine.generateSuggestion(for: request)
        XCTAssertEqual(runtime.generateCachedPrefixBytes, [nil])
    }

    func test_generate_awaitsCompatiblePrewarmInsteadOfCancelling() async throws {
        let runtime = RecordingPrewarmRuntime()
        runtime.prefillGate = PrewarmGate()
        let engine = LlamaSuggestionEngine(runtimeManager: runtime)
        let warmRequest = makeRequest(prompt: "hello wor")
        let generateRequest = makeRequest(prompt: "hello world")

        let prewarm = Task {
            await engine.prewarm(for: warmRequest)
        }
        await runtime.prefillGate?.waitUntilEntered()

        let generate = Task {
            _ = try await engine.generateSuggestion(for: generateRequest)
        }
        runtime.prefillGate?.release()
        await prewarm.value
        _ = try await generate.value

        XCTAssertEqual(runtime.prefillPrompts, ["hello wor"])
        XCTAssertEqual(runtime.generateCallCount, 1)
        XCTAssertEqual(runtime.cancelCount, 0)
    }

    func test_generate_cancelsDivergentPrewarm() async throws {
        let runtime = RecordingPrewarmRuntime()
        runtime.prefillGate = PrewarmGate()
        let engine = LlamaSuggestionEngine(runtimeManager: runtime)
        let warmRequest = makeRequest(prompt: "alpha")
        let generateRequest = makeRequest(prompt: "beta")

        let prewarm = Task {
            await engine.prewarm(for: warmRequest)
        }
        await runtime.prefillGate?.waitUntilEntered()

        let generate = Task {
            _ = try await engine.generateSuggestion(for: generateRequest)
        }
        await Task.yield()
        runtime.prefillGate?.release()
        await prewarm.value
        _ = try await generate.value

        XCTAssertEqual(runtime.cancelCount, 1)
        XCTAssertEqual(runtime.generateCallCount, 1)
    }

    // MARK: - Helpers

    private func makeRequest(prompt: String) -> SuggestionRequest {
        let snapshot = FocusedInputSnapshot(
            applicationName: "TestApp",
            bundleIdentifier: "com.example.TestApp",
            processIdentifier: 123,
            elementIdentifier: "field",
            role: "AXTextField",
            subrole: nil,
            caretRect: .zero,
            inputFrameRect: nil,
            caretSource: "test",
            caretQuality: .exact,
            observedCharWidth: nil,
            precedingText: prompt,
            trailingText: "",
            selection: NSRange(location: prompt.count, length: 0),
            isSecure: false
        )
        let context = FocusedInputContext(snapshot: snapshot, generation: 1)

        return SuggestionRequest(
            context: context,
            prefixText: prompt,
            prompt: prompt,
            generation: context.generation,
            maxPredictionTokens: 8,
            temperature: 0.1,
            topK: 20,
            topP: 0.7,
            minP: 0.08,
            repetitionPenalty: 1.05,
            randomSeed: 42,
            maxSuffixCharacters: 192,
            completionLengthInstruction: "Return only the next few words.",
            userName: nil,
            customRules: [],
            languageInstruction: nil,
            clipboardContext: nil,
            visualContextSummary: nil,
            isMultiLineEnabled: false
        )
    }
}

/// Blocks `prefill` until `release()` so tests can interleave generate with an in-flight warmup.
@MainActor
private final class PrewarmGate {
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var isReleased = false

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func enterAndWaitForRelease() async {
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        if isReleased { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }
}

/// Records prefill calls and the reuse hints later generations advertise, so the prewarm contract
/// can be exercised without loading a real model.
@MainActor
private final class RecordingPrewarmRuntime: LlamaRuntimeGenerating {
    var prefillError: Error?
    var generateResult: Result<LlamaGenerationOutput, Error> = .success(.text("ok"))
    var prefillGate: PrewarmGate?
    private(set) var prefillPrompts: [String] = []
    private(set) var generateCachedPrefixBytes: [Int?] = []
    private(set) var generateCallCount = 0
    private(set) var cancelCount = 0

    var rejectsPartialKVTrims: Bool { false }

    func generate(
        prompt: String,
        cachedPrefixBytes: Int?,
        options: LlamaGenerationOptions
    ) async throws -> LlamaGenerationOutput {
        generateCallCount += 1
        generateCachedPrefixBytes.append(cachedPrefixBytes)
        return try generateResult.get()
    }

    func generate(
        prompt: String,
        cachedPrefixBytes: Int?,
        options: LlamaGenerationOptions,
        onPartialRawText: ((String) -> Void)?
    ) async throws -> LlamaGenerationOutput {
        try await generate(prompt: prompt, cachedPrefixBytes: cachedPrefixBytes, options: options)
    }

    func resetPromptCache() {}

    func prefill(prompt: String, cachedPrefixBytes: Int?, options: LlamaGenerationOptions) async throws {
        try await withTaskCancellationHandler {
            if let prefillGate {
                await prefillGate.enterAndWaitForRelease()
            }
            try Task.checkCancellation()
            if let prefillError {
                throw prefillError
            }
            prefillPrompts.append(prompt)
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelCount += 1
            }
        }
    }
}
