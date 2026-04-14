//
//  WorkflowGenerator.swift
//  leanring-buddy
//
//  Takes captured screenshot frames from a WorkflowRecordingSession and
//  sends them to Gemini 2.5 Flash to generate a step-by-step workflow
//  document. Gemini's 1M+ token context window allows sending far more
//  screenshots than other models, improving workflow accuracy.
//

import Combine
import Foundation

enum WorkflowOutputFormat: String, CaseIterable {
    case markdown = "Markdown"
    case python = "Python"
    case json = "JSON"
    case applescript = "AppleScript"
    case playwright = "Playwright"
    case appleShortcuts = "Shortcuts"
}

@MainActor
final class WorkflowGenerator: ObservableObject {
    @Published private(set) var isGenerating = false
    @Published private(set) var generatedWorkflowText = ""
    @Published private(set) var generationError: String?
    @Published private(set) var selectedFormat: WorkflowOutputFormat = .markdown

    /// Gemini supports a massive context window, but we still cap frames
    /// to keep payload size reasonable (~500KB per JPEG × 50 = ~25MB).
    private static let maximumFramesPerRequest = 50

    private var generationTask: Task<Void, Never>?

    func setSelectedFormat(_ format: WorkflowOutputFormat) {
        selectedFormat = format
    }

    func generateWorkflow(
        from capturedFrames: [WorkflowScreenshotFrame],
        using geminiAPI: GeminiWorkflowAPI
    ) {
        guard !capturedFrames.isEmpty else {
            print("⚠️ WorkflowGenerator: no frames to process")
            return
        }

        generationTask?.cancel()
        generatedWorkflowText = ""
        generationError = nil
        isGenerating = true

        generationTask = Task {
            do {
                let sampledFrames = Self.sampleFramesEvenly(
                    from: capturedFrames,
                    targetCount: Self.maximumFramesPerRequest
                )

                let labeledImages = sampledFrames.enumerated().map { index, frame in
                    let timestamp = String(format: "%.0f", frame.timestampSinceRecordingStart)
                    let label = "Screenshot \(index + 1) of \(sampledFrames.count) — captured at \(timestamp)s into the recording"
                    return (data: frame.imageData, label: label)
                }

                let systemPrompt = Self.systemPrompt(for: selectedFormat)
                let userPrompt = Self.userPrompt(
                    for: selectedFormat,
                    totalFrameCount: capturedFrames.count,
                    sampledFrameCount: sampledFrames.count
                )

                let (fullText, duration) = try await geminiAPI.generateWorkflowStreaming(
                    images: labeledImages,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: 8192,
                    onTextChunk: { [weak self] accumulatedText in
                        self?.generatedWorkflowText = accumulatedText
                    }
                )

                guard !Task.isCancelled else { return }

                generatedWorkflowText = fullText
                isGenerating = false
                generationTask = nil
                print("📋 Workflow generated in \(String(format: "%.1f", duration))s — \(fullText.count) characters")
            } catch {
                guard !Task.isCancelled else { return }
                isGenerating = false
                generationTask = nil
                generationError = error.localizedDescription
                print("⚠️ WorkflowGenerator: \(error.localizedDescription)")
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    func clearResult() {
        generatedWorkflowText = ""
        generationError = nil
    }

    // MARK: - Frame Sampling

    /// Selects frames evenly distributed across the recording timeline.
    /// Always includes the first and last frames to capture the full
    /// before/after context of the workflow.
    static func sampleFramesEvenly(
        from frames: [WorkflowScreenshotFrame],
        targetCount: Int
    ) -> [WorkflowScreenshotFrame] {
        guard !frames.isEmpty else { return [] }
        guard targetCount >= 2 else { return [frames.first!] }
        guard frames.count > targetCount else { return frames }

        var sampled: [WorkflowScreenshotFrame] = []
        sampled.append(frames.first!)

        let remainingSlots = targetCount - 2 // minus first and last
        let step = Double(frames.count - 1) / Double(remainingSlots + 1)

        for slotIndex in 1...remainingSlots {
            let frameIndex = Int(round(Double(slotIndex) * step))
            let clampedIndex = min(frameIndex, frames.count - 2)
            sampled.append(frames[clampedIndex])
        }

        sampled.append(frames.last!)
        return sampled
    }

    // MARK: - Prompts

    private static func systemPrompt(for format: WorkflowOutputFormat) -> String {
        let baseInstructions = """
        you are a workflow documentation expert. the user has recorded a sequence of screenshots while performing a task on their mac. your job is to analyze the screenshot sequence and produce a clear, step-by-step workflow document describing exactly what the user did.

        rules:
        - the screenshots are in chronological order with timestamps
        - infer what actions the user took BETWEEN screenshots by comparing consecutive frames
        - be specific about which app, which button, which menu, which field was used
        - if you see text being typed, include what was typed
        - if you see app switches, note which apps were involved
        - group related micro-steps into logical higher-level steps
        - if a step is unclear from the screenshots, say so rather than guessing wrong
        - use clear, concise language that someone unfamiliar with the task could follow
        """

        switch format {
        case .markdown:
            return baseInstructions + """

            output format: a markdown document with:
            - a title (## heading) describing the overall task
            - numbered steps, each with a brief description
            - sub-steps indented under main steps where needed
            - notes or warnings where relevant (use > blockquotes)
            - no code fences around the entire output — just clean markdown
            """

        case .python:
            return baseInstructions + """

            output format: a python script using pyautogui that automates the recorded workflow.
            - include comments explaining each step
            - use pyautogui.click(), pyautogui.write(), pyautogui.hotkey() etc.
            - add appropriate pyautogui.sleep() delays between steps
            - include a docstring at the top describing the workflow
            - add a warning comment that coordinates are approximate and may need adjustment
            - wrap the main logic in a if __name__ == "__main__" block
            """

        case .json:
            return baseInstructions + """

            output format: a JSON object describing the workflow steps, suitable for import into automation tools like n8n, Make, or Zapier.
            - top-level keys: "name", "description", "steps"
            - each step: {"id", "action", "target", "value" (optional), "notes" (optional)}
            - action types: "click", "type", "navigate", "select", "scroll", "hotkey", "wait", "switch_app"
            - output valid JSON only, no markdown code fences
            """

        case .applescript:
            return baseInstructions + """

            output format: an AppleScript that automates the recorded workflow on macOS.
            - use `tell application` blocks for each app involved
            - use `System Events` for UI interactions (click, keystroke)
            - include comments explaining each step
            - add appropriate `delay` commands between steps
            - include error handling with try blocks where interactions might fail
            """

        case .playwright:
            return baseInstructions + """

            output format: a Playwright test script in TypeScript that automates the recorded browser workflow.
            - import { test, expect } from '@playwright/test'
            - wrap the workflow in a test() block with a descriptive name
            - use page.goto(), page.click(), page.fill(), page.getByRole(), page.getByText() etc.
            - prefer accessible locators (getByRole, getByLabel, getByText) over CSS selectors
            - add await expect() assertions after key steps to verify the workflow succeeded
            - add appropriate await page.waitForLoadState() or waitForSelector() between navigation steps
            - include comments explaining each step
            - if the workflow involves non-browser desktop apps, add a comment noting those steps must be done manually
            - output valid TypeScript only, no markdown code fences
            """

        case .appleShortcuts:
            return baseInstructions + """

            output format: a step-by-step Apple Shortcuts recipe described in a structured format that the user can manually recreate in the Shortcuts app on macOS/iOS.
            - start with the shortcut name and a one-line description
            - list each action as a numbered step with:
              - the exact Shortcuts action name (e.g. "Open App", "Get Contents of URL", "Show Alert", "Set Variable", "If", "Repeat")
              - the parameters to configure for that action
              - a brief note explaining what this step does in the workflow
            - group related actions under labeled sections
            - use Shortcuts-native actions wherever possible: Open App, Open URL, Run Shell Script, Get Contents of URL, Show Alert, Ask for Input, Set Variable, If/Otherwise/End If, Repeat, Wait
            - when a step requires interacting with a specific app's UI (clicking buttons, typing in fields), use "Run AppleScript" or "Run Shell Script" actions and include the script content
            - at the end, list any required permissions or apps the shortcut needs
            - output as clean structured text, not JSON or code
            """
        }
    }

    private static func userPrompt(
        for format: WorkflowOutputFormat,
        totalFrameCount: Int,
        sampledFrameCount: Int
    ) -> String {
        var prompt = "here are \(sampledFrameCount) screenshots from a workflow recording"
        if sampledFrameCount < totalFrameCount {
            prompt += " (sampled from \(totalFrameCount) total frames)"
        }
        prompt += ". analyze them and generate a \(format.rawValue.lowercased()) workflow document."
        return prompt
    }
}
