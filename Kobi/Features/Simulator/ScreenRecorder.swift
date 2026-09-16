//
//  ScreenRecorder.swift
//  Kobi
//

import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit

enum ScreenRecorderError: LocalizedError {
    case noWindow
    case alreadyRecording
    case notRecording
    case writerSetupFailed

    var errorDescription: String? {
        switch self {
        case .noWindow: String(localized: "export.error.recordingNoWindow")
        case .alreadyRecording: String(localized: "export.error.recordingAlreadyRunning")
        case .notRecording: String(localized: "export.error.recordingNotRunning")
        case .writerSetupFailed: String(localized: "export.error.recordingSetupFailed")
        }
    }
}

/// Records a cropped region of the app's own window via `ScreenCaptureKit`, muxing frames into
/// an H.264 MP4 through `AVAssetWriter`. Requires no App Sandbox entitlement — this project is
/// direct-distributed (see docs/ROADMAP.md), so only the OS-level Screen Recording permission
/// prompt applies, not a sandbox capability.
@MainActor
@Observable
final class ScreenRecorder {
    private(set) var isRecording = false
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var lastError: String?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var streamOutput: StreamOutput?
    private var streamDelegate: StreamDelegate?
    private var timer: Timer?

    private let outputQueue = DispatchQueue(label: "com.kobi.screenrecorder.output")

    func start(region: RecordingRegion) async throws {
        guard !isRecording else { throw ScreenRecorderError.alreadyRecording }
        guard let window = region.window, region.frameInWindow.width > 0, region.frameInWindow.height > 0 else {
            throw ScreenRecorderError.noWindow
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let windowID = CGWindowID(window.windowNumber)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenRecorderError.noWindow
        }

        let scale = window.backingScaleFactor
        let pixelWidth = Int((region.frameInWindow.width * scale).rounded())
        let pixelHeight = Int((region.frameInWindow.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { throw ScreenRecorderError.noWindow }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.sourceRect = region.frameInWindow
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 5

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobi-recording-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight
            ]
        )
        guard writer.canAdd(input) else { throw ScreenRecorderError.writerSetupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw ScreenRecorderError.writerSetupFailed }

        let output = StreamOutput(writer: writer, input: input, adaptor: adaptor)
        let delegate = StreamDelegate(recorder: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()

        self.stream = stream
        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.outputURL = tempURL
        self.streamOutput = output
        self.streamDelegate = delegate
        isRecording = true
        elapsedSeconds = 0
        lastError = nil
        startTimer()
    }

    func stop() async throws -> URL {
        guard isRecording, let stream, let writer = assetWriter, let input = videoInput, let outputURL else {
            throw ScreenRecorderError.notRecording
        }

        timer?.invalidate()
        timer = nil

        try await stream.stopCapture()
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        self.stream = nil
        self.assetWriter = nil
        self.videoInput = nil
        self.pixelBufferAdaptor = nil
        self.outputURL = nil
        self.streamOutput = nil
        self.streamDelegate = nil
        isRecording = false

        return outputURL
    }

    /// Called when `ScreenCaptureKit` stops the stream on its own (permission revoked, source
    /// window closed, display reconfigured) — without this, `isRecording` would stay stuck
    /// `true` and a later `stop()` call would fail against an already-dead stream.
    private func handleStreamStoppedUnexpectedly(error: Error) async {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil

        videoInput?.markAsFinished()
        if let writer = assetWriter {
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        stream = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        streamOutput = nil
        streamDelegate = nil
        isRecording = false
        lastError = error.localizedDescription
    }

    private func startTimer() {
        let startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedSeconds = Date().timeIntervalSince(startDate)
            }
        }
    }

    /// `SCStreamOutput` is a plain `NSObject` protocol delivered on a background queue, so this
    /// helper is deliberately not `@MainActor` — it only touches the `AVAssetWriter` pipeline,
    /// which is safe to drive off the main actor.
    private final class StreamOutput: NSObject, SCStreamOutput {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private var sessionStarted = false

        init(writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor) {
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, sampleBuffer.isValid, isCompleteFrame(sampleBuffer),
                  let imageBuffer = sampleBuffer.imageBuffer else { return }

            let presentationTime = sampleBuffer.presentationTimeStamp

            if !sessionStarted {
                writer.startSession(atSourceTime: presentationTime)
                sessionStarted = true
            }

            guard input.isReadyForMoreMediaData else { return }
            adaptor.append(imageBuffer, withPresentationTime: presentationTime)
        }

        private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRawValue = attachments[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue) else {
                return false
            }
            return status == .complete
        }
    }

    private final class StreamDelegate: NSObject, SCStreamDelegate {
        private weak var recorder: ScreenRecorder?

        init(recorder: ScreenRecorder) {
            self.recorder = recorder
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            Task { @MainActor [weak recorder] in
                await recorder?.handleStreamStoppedUnexpectedly(error: error)
            }
        }
    }
}
