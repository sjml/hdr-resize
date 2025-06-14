import Foundation
import ArgumentParser
import ImageIO
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

enum HDRResizeError: Error {
	case invalidArguments
	case invalidTargetSize
	case loadFailed
	case invalidQuality
	case gainMapLoadFailed
	case resizeFailed
	case encodingFailed
	case unsupportedFormat
	case writeFailed
}

func parseSizeString(_ str: String) throws -> CGSize {
	let parts = str.split(separator: "x", omittingEmptySubsequences: false)
	guard parts.count == 2 else { throw HDRResizeError.invalidTargetSize }

	let tws = String(parts[0])
	let ths = String(parts[1])

	if let w = Int(tws), let h = Int(ths) {
		return CGSize(width: w, height: h)
	}
	else if let w = Int(tws), ths.isEmpty {
		return CGSize(width: w, height: -1)
	}
	else if tws.isEmpty, let h = Int(ths) {
		return CGSize(width: -1, height: h)
	}
	else {
		throw HDRResizeError.invalidTargetSize
	}
}

@main
struct HDRResize: ParsableCommand {
	@Option(name: .shortAndLong, help: "Path to input image", completion: .file(extensions: [".jpeg", ".jpg", ".heic"]))
	var input: String

	@Option(name: .shortAndLong, help: "Path to output image")
	var output: String

	@Option(name: .shortAndLong, help: "Target size in WxH, Wx, or xH")
	var sizeString: String

	@Option(name: .shortAndLong, help: "Output image quality (1-100)")
	var quality: Int = 85

	func run() throws {
		let inputURL = URL(filePath: input)
		let outputURL = URL(filePath: output)

		if quality < 1 || quality > 100 {
			throw HDRResizeError.invalidQuality
		}

		guard let imgSrc = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
			throw HDRResizeError.loadFailed
		}
		guard let cgImg = CGImageSourceCreateImageAtIndex(imgSrc, 0, nil) else {
			throw HDRResizeError.loadFailed
		}

		let originalSize = CGSize(width: cgImg.width, height: cgImg.height)
		let aspect = originalSize.width / originalSize.height
		var targetSize = try parseSizeString(sizeString)
		if targetSize.width == -1 {
			targetSize.width = targetSize.height * aspect
		}
		else if targetSize.height == -1 {
			targetSize.height = targetSize.width / aspect
		}

		try performResize(img: cgImg, imgSrc: imgSrc, targetSize: targetSize, outputUrl: outputURL, quality: quality)
	}
}

func performResize(img: CGImage, imgSrc: CGImageSource, targetSize: CGSize, outputUrl: URL, quality: Int) throws {
	let metadata = CGImageSourceCopyPropertiesAtIndex(imgSrc, 0, nil)

	guard let gainMapRaw = CGImageSourceCopyAuxiliaryDataInfoAtIndex(imgSrc, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [CFString: Any],
		  let gainMapData = gainMapRaw[kCGImageAuxiliaryDataInfoDataDescription] as? [CFString: Any],
		  let gainMapBytesPerRow = gainMapData[kCGImagePropertyBytesPerRow] as? Int,
		  let gainMapWidth = gainMapData[kCGImagePropertyWidth] as? Int,
		  let gainMapHeight = gainMapData[kCGImagePropertyHeight] as? Int,
		  let gainMapImageData = gainMapRaw[kCGImageAuxiliaryDataInfoData] as? Data
	else {
		throw HDRResizeError.gainMapLoadFailed
	}
	let gainMapSize = CGSize(width: gainMapWidth, height: gainMapHeight)

	let gainMapBase = CIImage(
		bitmapData: gainMapImageData,
		bytesPerRow: gainMapBytesPerRow,
		size: gainMapSize,
		format: .L8,
		colorSpace: nil
	)

	let gainMap = gainMapBase

	// documentation indicates that the gain map should have orientation applied to it, but
	//   empirically that seems to not be true? leaving this here in case it has to come back
	// let orientationRaw = (metadata as? [String: Any])?[kCGImagePropertyOrientation as String] as? UInt32
	// if orientationRaw == nil {
	// 	fputs("WARNING: No orientation metadata found. Assuming \"up\".\n", stderr)
	// }
	// let orientation = CGImagePropertyOrientation(rawValue: orientationRaw ?? 1) ?? {
	// 	fputs("WARNING: Invalid orientation value \(orientationRaw!). Assuming \"up\".\n", stderr)
	// 	return .up
	// }()
	// let gainMap = gainMapBase.oriented(orientation)

	guard let resizedMain = resizeCGImage(img, to: targetSize) else {
		throw HDRResizeError.resizeFailed
	}

	let gmWidth = resizedMain.width / 2
	let gmHeight = resizedMain.height / 2
	let gmBytesPerPoxel = 1 // just one for .L8
	let unalignedRowBytes = gmWidth * gmBytesPerPoxel
	let gmBPR = (unalignedRowBytes + 3) & ~3 // round up to next multiple of 4
	let resizedGainMap = resizeCIImage(gainMap, to: CGSize(width: gmWidth, height: gmHeight))
	var gmData = Data(count: gmBPR * gmHeight)

	let ctx = CIContext()
	try gmData.withUnsafeMutableBytes { buffer in
		guard let base = buffer.baseAddress else {
			throw HDRResizeError.encodingFailed
		}
		ctx.render(
			resizedGainMap,
			toBitmap: base,
			rowBytes: gmBPR,
			bounds: resizedGainMap.extent,
			format: .L8,
			colorSpace: nil
		)
	}

	var modifiedGainMapData = gainMapData
	modifiedGainMapData[kCGImagePropertyWidth] = gmWidth
	modifiedGainMapData[kCGImagePropertyHeight] = gmHeight
	modifiedGainMapData[kCGImagePropertyBytesPerRow] = gmBPR

	var modifiedGainMapRaw = gainMapRaw
	modifiedGainMapRaw[kCGImageAuxiliaryDataInfoData] = gmData
	modifiedGainMapRaw[kCGImageAuxiliaryDataInfoDataDescription] = modifiedGainMapData

	var outMeta = metadata
	if var md = metadata as? [String: Any] {
		md[kCGImageDestinationLossyCompressionQuality as String] = (Float(quality) / 100.0) as CFNumber
		outMeta = md as CFDictionary
	}
	try writeImage(resizedMain, to: outputUrl, auxiliary: modifiedGainMapRaw as CFDictionary, properties: outMeta)
}

func resizeCIImage(_ image: CIImage, to size: CGSize) -> CIImage {
	let sx = size.width / image.extent.width
	let sy = size.height / image.extent.height
	return image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
}

func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage? {
	guard let colorSpace = image.colorSpace else { return nil }

	guard let ctx = CGContext(
		data: nil,
		width: Int(size.width),
		height: Int(size.height),
		bitsPerComponent: image.bitsPerComponent,
		bytesPerRow: 0,
		space: colorSpace,
		bitmapInfo: image.bitmapInfo.rawValue
	) else {
		return nil
	}

	ctx.interpolationQuality = .high
	ctx.draw(image, in: CGRect(origin: .zero, size: size))

	return ctx.makeImage()
}

func writeImage(_ img: CGImage, to url: URL, auxiliary: CFDictionary? = nil, properties: CFDictionary? = nil) throws {
	var fileType: UTType
	switch url.pathExtension.lowercased() {
		case "jpg", "jpeg":
			fileType = .jpeg
		case "heic":
			fileType = .heic
		default:
			throw HDRResizeError.unsupportedFormat
	}

	guard let dst = CGImageDestinationCreateWithURL(url as CFURL, fileType.identifier as CFString, 1, nil) else {
		throw HDRResizeError.writeFailed
	}
	CGImageDestinationAddImage(dst, img, properties)

	if let auxiliary = auxiliary {
		CGImageDestinationAddAuxiliaryDataInfo(dst, kCGImageAuxiliaryDataTypeHDRGainMap, auxiliary)
	}

	guard CGImageDestinationFinalize(dst) else {
		throw HDRResizeError.writeFailed
	}
}
