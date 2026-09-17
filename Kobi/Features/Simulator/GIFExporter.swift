//
//  GIFExporter.swift
//  Kobi
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a recorded MP4 into a frame-sampled animated GIF. GIF has no native H.264-style
/// temporal compression, so this deliberately downsamples frame rate/size rather than
/// re-encoding every source frame — full-rate GIFs of screen recordings balloon to hundreds of
/// MB for a few seconds of video.
enum GIFExporter {
    static func convert(mp4URL: URL, frameRate: Double = 8, maxDimension: CGFloat = 480) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: mp4URL)
            let duration = try await asset.load(.duration).seconds
            guard duration > 0 else { throw CaptureExportError.renderFailed }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

            let frameCount = max(Int(duration * frameRate), 1)
            let times = (0 ..< frameCount).map { CMTime(seconds: Double($0) / frameRate, preferredTimescale: 600) }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kobi-export-\(UUID().uuidString)")
                .appendingPathExtension("gif")

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.gif.identifier as CFString,
                frameCount,
                nil
            ) else {
                throw CaptureExportError.renderFailed
            }

            let loopProperties: [CFString: Any] = [kCGImagePropertyGIFLoopCount: 0]
            CGImageDestinationSetProperties(
                destination,
                [kCGImagePropertyGIFDictionary: loopProperties] as CFDictionary
            )

            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / frameRate],
            ]

            for time in times {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }

            guard CGImageDestinationFinalize(destination) else {
                throw CaptureExportError.renderFailed
            }
            return outputURL
        }.value
    }
}
