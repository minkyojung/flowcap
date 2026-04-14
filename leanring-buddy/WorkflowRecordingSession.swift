//
//  WorkflowRecordingSession.swift
//  leanring-buddy
//
//  Holds the state and captured screenshots for a single workflow recording
//  session. Created when the user starts recording, populated with periodic
//  screenshots, and handed off for workflow generation when recording stops.
//

import Foundation

struct WorkflowScreenshotFrame {
    /// The JPEG image data for this frame.
    let imageData: Data
    /// Timestamp relative to the recording start (seconds).
    let timestampSinceRecordingStart: TimeInterval
    /// Human-readable label for the display this was captured from.
    let displayLabel: String
}

@MainActor
final class WorkflowRecordingSession: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var capturedFrames: [WorkflowScreenshotFrame] = []
    @Published private(set) var recordingDuration: TimeInterval = 0

    private var recordingStartDate: Date?
    private var screenshotCaptureTimer: Timer?

    /// How often to capture a screenshot (seconds).
    private let screenshotIntervalInSeconds: TimeInterval = 4
    /// Safety cap to prevent unbounded memory growth. At ~500KB per JPEG
    /// frame, 200 frames ≈ 100MB which covers ~13 minutes of recording.
    private let maximumFrameCount = 200

    func startRecording() {
        guard !isRecording else { return }

        capturedFrames = []
        recordingStartDate = Date()
        recordingDuration = 0
        isRecording = true

        // Capture the first frame immediately
        captureScreenshot()

        // Then capture on a repeating interval
        screenshotCaptureTimer = Timer.scheduledTimer(
            withTimeInterval: screenshotIntervalInSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.captureScreenshot()
            }
        }

        print("📹 Workflow recording started")
    }

    func stopRecording() {
        guard isRecording else { return }

        screenshotCaptureTimer?.invalidate()
        screenshotCaptureTimer = nil
        isRecording = false

        if let startDate = recordingStartDate {
            recordingDuration = Date().timeIntervalSince(startDate)
        }

        // Capture one final frame, then nil out the start date so any
        // straggler timer tasks (already dispatched before invalidation)
        // bail out in captureScreenshot()'s guard.
        captureScreenshot()
        recordingStartDate = nil

        print("📹 Workflow recording stopped — \(capturedFrames.count) frames captured over \(String(format: "%.1f", recordingDuration))s")
    }

    private func captureScreenshot() {
        Task {
            // Bail out if recording was stopped before this task executes
            // (e.g. a straggler timer callback that was already dispatched).
            guard let recordingStartDate else { return }

            do {
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                let timestampSinceRecordingStart = Date().timeIntervalSince(recordingStartDate)

                // Only keep the cursor screen (primary focus) to save memory.
                // Multi-monitor support can be added later if needed.
                if let cursorScreenCapture = screenCaptures.first(where: { $0.isCursorScreen }) ?? screenCaptures.first {
                    let frame = WorkflowScreenshotFrame(
                        imageData: cursorScreenCapture.imageData,
                        timestampSinceRecordingStart: timestampSinceRecordingStart,
                        displayLabel: cursorScreenCapture.label
                    )
                    capturedFrames.append(frame)

                    if capturedFrames.count > maximumFrameCount {
                        capturedFrames.removeFirst()
                    }
                }
            } catch {
                print("⚠️ Workflow recording: screenshot capture failed — \(error.localizedDescription)")
            }
        }
    }
}
