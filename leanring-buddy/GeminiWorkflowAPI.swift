//
//  GeminiWorkflowAPI.swift
//  leanring-buddy
//
//  Gemini API client for workflow generation. Sends screenshot sequences
//  to Gemini 2.5 Flash via the Cloudflare Worker proxy and streams back
//  the generated workflow text. Gemini's large context window (1M+ tokens)
//  allows sending many more screenshots than Claude, improving workflow
//  accuracy for longer recordings.
//

import Foundation

class GeminiWorkflowAPI {
    private let proxyURL: URL
    private let session: URLSession

    init(proxyURL: String) {
        self.proxyURL = URL(string: proxyURL)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    /// Sends a multimodal request to Gemini with screenshot images and streams
    /// the response text back chunk by chunk.
    func generateWorkflowStreaming(
        images: [(data: Data, label: String)],
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 8192,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> (text: String, duration: TimeInterval) {
        let startTime = Date()

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build Gemini request body
        // Format: { contents: [{ parts: [...] }], systemInstruction: {...}, generationConfig: {...} }
        var parts: [[String: Any]] = []

        for image in images {
            let mimeType = image.data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
                ? "image/png"
                : "image/jpeg"

            parts.append([
                "inline_data": [
                    "mime_type": mimeType,
                    "data": image.data.base64EncodedString()
                ]
            ])
            parts.append([
                "text": image.label
            ])
        }

        parts.append([
            "text": userPrompt
        ])

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": parts]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.7
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        let payloadMB = Double(bodyData.count) / 1_048_576.0
        print("🌐 Gemini workflow request: \(String(format: "%.1f", payloadMB))MB, \(images.count) image(s)")

        let (byteStream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "GeminiWorkflowAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyChunks: [String] = []
            for try await line in byteStream.lines {
                errorBodyChunks.append(line)
            }
            let errorBody = errorBodyChunks.joined(separator: "\n")
            throw NSError(
                domain: "GeminiWorkflowAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Gemini API Error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }

        // Parse Gemini SSE stream
        // Format: "data: {json}" where json contains candidates[0].content.parts[0].text
        var accumulatedResponseText = ""

        for try await line in byteStream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let jsonData = jsonString.data(using: .utf8),
                  let eventPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let candidates = eventPayload["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            for part in parts {
                if let textChunk = part["text"] as? String {
                    accumulatedResponseText += textChunk
                    let currentText = accumulatedResponseText
                    await onTextChunk(currentText)
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        print("🌐 Gemini workflow response: \(accumulatedResponseText.count) chars in \(String(format: "%.1f", duration))s")
        return (text: accumulatedResponseText, duration: duration)
    }
}
