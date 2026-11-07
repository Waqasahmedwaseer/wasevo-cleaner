import Foundation
import Vision
import ImageIO
import CoreGraphics

// Wasevo Cleaner — Photo Cleaner. Finds near-identical shots and camera photos that are blurry,
// too dark or blown out. Everything is analysed on this Mac with Apple's Vision framework.
// Never touches the Apple Photos library (it is a bundle, so it is never entered).

let PHOTO_EXTS: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
/// Feature-print distance (Vision revision 2) below which two images count as "similar".
/// Calibrated: the same photo resized/re-saved = 0.20–0.36; different photos = 0.79–1.2; blurred/darkened copy = 0.5–0.74.
let SIMILAR_DISTANCE: Float = 0.40
/// Screenshots and graphics share layouts, so they only count as similar when nearly identical (re-saves).
let SIMILAR_DISTANCE_GRAPHICS: Float = 0.15

enum PhotoIssue: String { case blurry = "Blurry", dark = "Too dark", bright = "Overexposed" }

struct PhotoInfo: Identifiable, Hashable {
    var id: String { file.path }
    let file: UserFile
    let sharpness: Double      // variance of the Laplacian on a 256 px grey copy; higher = sharper
    let brightness: Double     // 0…1 mean luminance
    let isCameraPhoto: Bool    // has camera EXIF (screenshots and graphics do not)
    var issue: PhotoIssue? {
        guard isCameraPhoto else { return nil }
        if brightness < 0.12 { return .dark }
        if brightness > 0.94 { return .bright }
        if sharpness < 40 { return .blurry }   // sharp photos measured 390–1080, blurred 64–166
        return nil
    }
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    var photos: [PhotoInfo]     // sharpest first: that one is kept by default
}

/// Small, orientation-correct copy of an image (never loads the full-resolution photo).
func thumbnail(_ path: String, maxPixels: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                 kCGImageSourceCreateThumbnailWithTransform: true,
                                 kCGImageSourceThumbnailMaxPixelSize: maxPixels]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

func isCameraPhoto(_ path: String) -> Bool {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return false }
    let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    return tiff?[kCGImagePropertyTIFFMake] != nil && props[kCGImagePropertyExifDictionary] != nil
}

/// (sharpness, brightness) from a 256 px greyscale copy.
func measure(_ img: CGImage) -> (Double, Double) {
    let w = 256, hgt = max(1, Int(Double(img.height) / Double(img.width) * 256))
    var px = [UInt8](repeating: 0, count: w * hgt)
    guard let ctx = CGContext(data: &px, width: w, height: hgt, bitsPerComponent: 8, bytesPerRow: w,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return (999, 0.5) }
    ctx.interpolationQuality = .medium
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: hgt))
    var sum = 0.0, sumSq = 0.0, n = 0.0, bright = 0.0
    for y in 1..<(hgt - 1) {
        for x in 1..<(w - 1) {
            let c = Double(px[y * w + x])
            let lap = Double(px[(y - 1) * w + x]) + Double(px[(y + 1) * w + x]) + Double(px[y * w + x - 1]) + Double(px[y * w + x + 1]) - 4 * c
            sum += lap; sumSq += lap * lap; n += 1; bright += c
        }
    }
    guard n > 0 else { return (999, 0.5) }
    let mean = sum / n
    return (sumSq / n - mean * mean, bright / n / 255)
}

func featurePrint(_ img: CGImage) -> VNFeaturePrintObservation? {
    let req = VNGenerateImageFeaturePrintRequest()
    try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
    return req.results?.first as? VNFeaturePrintObservation
}

func analyzePhotos(limit: Int = 4000, progress: @escaping (String) -> Void) -> (similar: [PhotoGroup], bad: [PhotoInfo]) {
    var files: [UserFile] = []
    walkUserFiles(minSize: 50_000, exts: PHOTO_EXTS, limit: limit) { files.append($0) }
    var infos: [PhotoInfo] = []
    var prints: [VNFeaturePrintObservation?] = []
    for (i, f) in files.enumerated() {
        if i % 20 == 0 { progress("Looking at photo \(i + 1) of \(files.count)…") }
        autoreleasepool {
            guard let img = thumbnail(f.path, maxPixels: 512) else { return }
            let (sharp, bright) = measure(img)
            infos.append(PhotoInfo(file: f, sharpness: sharp, brightness: bright, isCameraPhoto: isCameraPhoto(f.path)))
            prints.append(featurePrint(img))
        }
    }

    // Group near-identical images. Each photo must be close to the group's first photo, so groups
    // never chain (A~B, B~C does not pull unrelated A and C together).
    progress("Grouping similar photos…")
    var taken = [Bool](repeating: false, count: infos.count)
    var clusters: [[PhotoInfo]] = []
    for i in 0..<infos.count where !taken[i] {
        guard let a = prints[i] else { continue }
        var group = [infos[i]]
        for j in (i + 1)..<max(i + 1, infos.count) where !taken[j] {
            guard let b = prints[j], infos[i].isCameraPhoto == infos[j].isCameraPhoto else { continue }
            let limit = infos[i].isCameraPhoto ? SIMILAR_DISTANCE : SIMILAR_DISTANCE_GRAPHICS
            var d: Float = 99
            if (try? a.computeDistance(&d, to: b)) != nil, d < limit { group.append(infos[j]); taken[j] = true }
        }
        if group.count > 1 { taken[i] = true; clusters.append(group) }
    }
    let similar = clusters
        .map { PhotoGroup(photos: $0.sorted { $0.sharpness > $1.sharpness }) }
        .sorted { $0.photos.reduce(0) { $0 + $1.file.size } > $1.photos.reduce(0) { $0 + $1.file.size } }
    let bad = infos.filter { $0.issue != nil }.sorted { $0.file.size > $1.file.size }
    return (similar, bad)
}
