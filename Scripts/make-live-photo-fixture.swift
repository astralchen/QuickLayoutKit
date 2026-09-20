// Run: swift Scripts/make-live-photo-fixture.swift <output-directory>
// Original, synthetic test artwork. Generates a matching JPEG/MOV pair without Photos access.
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let identifier = "BB974039-7490-4D71-BB32-67BD99AD9A10"
let width = 480, height = 640, frames = 90
let movieURL = output.appendingPathComponent("live-photo.mov")
let photoURL = output.appendingPathComponent("live-photo.jpg")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for url in [movieURL, photoURL] { try? FileManager.default.removeItem(at: url) }

func draw(_ context: CGContext, frame: Int) {
    context.setFillColor(CGColor(red: 0.10, green: 0.20, blue: 0.36, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for index in 0..<10 {
        context.setFillColor(CGColor(red: 0.15, green: 0.27, blue: 0.44, alpha: 1))
        context.fill(CGRect(x: index * 60, y: 0, width: 3, height: height))
        context.fill(CGRect(x: 0, y: index * 70, width: width, height: 3))
    }
    let phase = Double(frame) / Double(frames - 1)
    context.setFillColor(CGColor(red: 1, green: 0.70, blue: 0.20, alpha: 1))
    context.fillEllipse(in: CGRect(x: 40 + phase * 260, y: 240 + sin(phase * .pi * 2) * 100, width: 140, height: 140))
    context.setFillColor(CGColor(red: 0.30, green: 0.85, blue: 0.74, alpha: 1))
    context.fill(CGRect(x: 30, y: 70, width: 420 * phase, height: 20))
}
let colorSpace = CGColorSpaceCreateDeviceRGB()
let still = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
draw(still, frame: 45)
let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, still.makeImage()!, [kCGImagePropertyMakerAppleDictionary: ["17": identifier]] as CFDictionary)
precondition(CGImageDestinationFinalize(destination))

let writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
let contentID = AVMutableMetadataItem()
contentID.identifier = .quickTimeMetadataContentIdentifier
contentID.value = identifier as NSString
contentID.dataType = kCMMetadataBaseDataType_UTF8 as String
writer.metadata = [contentID]
let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width, AVVideoHeightKey: height])
let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(video)
var format: CMMetadataFormatDescription?
let spec = [kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"]
precondition(CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
    metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &format) == noErr)
let metadata = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)
writer.add(metadata)
precondition(writer.startWriting(), "Writer failed: \(String(describing: writer.error))")
writer.startSession(atSourceTime: .zero)
let keyTime = AVMutableMetadataItem()
keyTime.keySpace = .quickTimeMetadata
keyTime.key = "com.apple.quicktime.still-image-time" as NSString
keyTime.value = NSNumber(value: Int8(0))
keyTime.dataType = "com.apple.metadata.datatype.int8"
precondition(metadataAdaptor.append(AVTimedMetadataGroup(items: [keyTime], timeRange: CMTimeRange(
    start: CMTime(value: 45, timescale: 30), duration: CMTime(value: 1, timescale: 30)))))
metadata.markAsFinished()
for frame in 0..<frames {
    while !video.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferPoolCreatePixelBuffer(nil, pixels.pixelBufferPool!, &buffer) == kCVReturnSuccess)
    let value = buffer!
    CVPixelBufferLockBaseAddress(value, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(value), width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(value), space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    draw(context, frame: frame)
    CVPixelBufferUnlockBaseAddress(value, [])
    precondition(pixels.append(value, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
}
video.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
precondition(writer.status == .completed, "\(String(describing: writer.error))")
print("Generated matching Live Photo resources: \(photoURL.path), \(movieURL.path)")
