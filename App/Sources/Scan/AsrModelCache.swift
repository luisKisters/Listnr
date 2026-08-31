import FluidAudio
import Foundation

/// Everything the app knows about the speech model on this device: whether it
/// is here, and how to fetch it. One seam, so a test can walk the whole
/// once-per-install path without touching the network.
struct AsrModelCache: Sendable {
    var isDownloaded: @Sendable () -> Bool
    /// Reports the honest fraction from FluidAudio as it goes.
    var download: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void

    static func onDisk(at directory: URL = AsrModels.defaultCacheDirectory()) -> AsrModelCache {
        AsrModelCache(
            isDownloaded: { AsrModels.modelsExist(at: directory) },
            download: { onProgress in _ = try await Transcriber.loadModels(onProgress: onProgress) })
    }

    static let present = AsrModelCache(isDownloaded: { true }, download: { _ in })
    static let absent = AsrModelCache(isDownloaded: { false }, download: { _ in })
}
