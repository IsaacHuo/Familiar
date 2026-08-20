import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

public actor FastVLMLocalRuntime {
    private var container: ModelContainer?
    private var loadedDirectory: URL?

    public init() {
        FastVLM.register(modelFactory: VLMModelFactory.shared)
    }

    public func answer(modelDirectory: URL, imageURL: URL, prompt: String, maximumTokens: Int = 240) async throws -> String {
        let modelContainer = try await load(modelDirectory: modelDirectory)
        guard let image = CIImage(contentsOf: imageURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let input = UserInput(prompt: .text(prompt), images: [.ciImage(image)])
        return try await modelContainer.perform { context in
            let prepared = try await context.processor.prepare(input: input)
            let result = try MLXLMCommon.generate(
                input: prepared,
                parameters: GenerateParameters(temperature: 0),
                context: context
            ) { tokens in
                if Task.isCancelled || tokens.count >= maximumTokens { return .stop }
                return .more
            }
            return result.output
        }
    }

    public func unload() {
        container = nil
        loadedDirectory = nil
        MLX.GPU.clearCache()
    }

    private func load(modelDirectory: URL) async throws -> ModelContainer {
        if let container, loadedDirectory == modelDirectory { return container }
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
        let configuration = ModelConfiguration(directory: modelDirectory)
        let value = try await VLMModelFactory.shared.loadContainer(configuration: configuration)
        container = value
        loadedDirectory = modelDirectory
        return value
    }
}
