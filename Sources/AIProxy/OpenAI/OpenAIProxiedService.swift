//  OpenAIProxiedService.swift
//
//
//  Created by Lou Zell on 12/14/24.
//

import Foundation

private let legacyURL = "https://api.aiproxy.pro"

open class OpenAIProxiedService: OpenAIService, ProxiedService {
    private let partialKey: String
    private let serviceURL: String?
    private let clientID: String?
    private let requestFormat: OpenAIRequestFormat

    /// This initializer is not public on purpose.
    /// Customers are expected to use the factory `AIProxy.openAIService` defined in AIProxy.swift
    internal init(
        partialKey: String,
        serviceURL: String?,
        clientID: String?,
        requestFormat: OpenAIRequestFormat = .standard
    ) {
        self.partialKey = partialKey
        self.serviceURL = serviceURL
        self.clientID = clientID
        self.requestFormat = requestFormat
    }

    /// Initiates a non-streaming chat completion request to /v1/chat/completions.
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/chat/create
    /// - Returns: A ChatCompletionResponse. See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/object
    public func chatCompletionRequest(
        body: OpenAIChatCompletionRequestBody
    ) async throws -> OpenAIChatCompletionResponseBody {
        var body = body
        body.stream = false
        body.streamOptions = nil
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("chat/completions"),
            body: try body.serialize(),
            verb: .post,
            contentType: "application/json"
        )
        return try await self.makeRequestAndDeserializeResponse(request)
    }

    /// Initiates a streaming chat completion request to /v1/chat/completions.
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/chat/create
    /// - Returns: An async sequence of completion chunks. See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/streaming
    public func streamingChatCompletionRequest(
        body: OpenAIChatCompletionRequestBody
    ) async throws -> AsyncCompactMapSequence<AsyncLineSequence<URLSession.AsyncBytes>, OpenAIChatCompletionChunk> {
        var body = body
        body.stream = true
        body.streamOptions = .init(includeUsage: true)
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("chat/completions"),
            body: try body.serialize(),
            verb: .post,
            contentType: "application/json"
        )
        return try await self.makeRequestAndDeserializeStreamingChunks(request)
    }

    /// Initiates a create image request to /v1/images/generations
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/images/create
    /// - Returns: A ChatCompletionResponse. See this reference:
    ///            https://platform.openai.com/docs/api-reference/chat/object
    public func createImageRequest(
        body: OpenAICreateImageRequestBody
    ) async throws -> OpenAICreateImageResponseBody {
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("images/generations"),
            body:  try JSONEncoder().encode(body),
            verb: .post,
            contentType: "application/json"
        )
        return try await self.makeRequestAndDeserializeResponse(request)
    }

    /// Initiates a create transcription request to v1/audio/transcriptions
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/audio/createTranscription
    /// - Returns: An transcription response. See this reference:
    ///            https://platform.openai.com/docs/api-reference/audio/json-object
    public func createTranscriptionRequest(
        body: OpenAICreateTranscriptionRequestBody
    ) async throws -> OpenAICreateTranscriptionResponseBody {
        let boundary = UUID().uuidString
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("audio/transcriptions"),
            body: formEncode(body, boundary),
            verb: .post,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let (data, _) = try await BackgroundNetworker.makeRequestAndWaitForData(
            self.urlSession,
            request
        )
        if body.responseFormat == "text" {
            guard let text = String(data: data, encoding: .utf8) else {
                throw AIProxyError.assertion("Could not represent OpenAI's whisper response as string")
            }
            return OpenAICreateTranscriptionResponseBody(text: text, language: nil, duration: nil, words: nil, segments: nil)
        }

        return try OpenAICreateTranscriptionResponseBody.deserialize(from: data)
    }
    
    /// Initiates a create text to speech request to v1/audio/speech
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/audio/createSpeech
    /// - Returns: The audio file content. See this reference:
    ///            https://platform.openai.com/docs/api-reference/audio/createSpeech
    public func createTextToSpeechRequest(
        body: OpenAITextToSpeechRequestBody
    ) async throws -> Data {
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("audio/speech"),
            body:  try body.serialize(),
            verb: .post,
            contentType: "application/json"
        )
        let (data, _) = try await BackgroundNetworker.makeRequestAndWaitForData(
            self.urlSession,
            request
        )
        return data
    }

    /// Initiates a moderation request to /v1/moderations
    ///
    /// - Parameters:
    ///   - body: The request body to send to aiproxy and openai. See this reference:
    ///           https://platform.openai.com/docs/api-reference/moderations
    /// - Returns: A moderation response that contains a `flagged` boolean. See this reference:
    ///            https://platform.openai.com/docs/api-reference/moderations/object
    public func moderationRequest(
        body: OpenAIModerationRequestBody
    ) async throws -> OpenAIModerationResponseBody {
        let request = try await AIProxyURLRequest.create(
            partialKey: self.partialKey,
            serviceURL: self.serviceURL ?? legacyURL,
            clientID: self.clientID,
            proxyPath: self.resolvedPath("moderations"),
            body: try body.serialize(),
            verb: .post,
            contentType: "application/json"
        )
        return try await self.makeRequestAndDeserializeResponse(request)
    }

    private func resolvedPath(_ common: String) -> String {
        assert(common[common.startIndex] != "/")
        switch self.requestFormat {
        case .standard:
            return "/v1/\(common)"
        case .azureDeployment(let apiVersion):
            return "/\(common)?api-version=\(apiVersion)"
        }
    }
}
