import Foundation
import ImageIO
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
	print("Usage: hdr-resize <path-to-image>")
	exit(1)
}

let inputImagePath = CommandLine.arguments[1]
let outputDirectory = "./output"

func writeImage(image: CIImage, to: String, auxiliary: CFDictionary? = nil) {
	let ctx = CIContext()
	guard let cgImage = ctx.createCGImage(image, from: image.extent) else {
		print("Could not create CGImage from CIImage")
		exit(1)
	}
	writeImage(image: cgImage, to: to, auxiliary: auxiliary)
}

func writeImage(image: CGImage, to: String, auxiliary: CFDictionary? = nil) {
	let outputUrl = URL(filePath: to)
	var fileType: UTType
	switch outputUrl.pathExtension.lowercased() {
		case "jpg", "jpeg":
			fileType = .jpeg
		case "heic":
		   fileType = .heic
		default:
			print("Invalid output file type")
			exit(1)
	}

	guard let dst = CGImageDestinationCreateWithURL(outputUrl as CFURL, fileType.identifier as CFString, 1, nil) else {
		print("Failed to create image destination at \(to)")
		exit(1)
	}
	CGImageDestinationAddImage(dst, image, nil)

	if let auxData = auxiliary {
		CGImageDestinationAddAuxiliaryDataInfo(dst, kCGImageAuxiliaryDataTypeHDRGainMap, auxData)
	}

	guard CGImageDestinationFinalize(dst) else {
		print("Failed to finalize image")
		exit(1)
	}
}

func resizeCGImage(cgImage: CGImage, to size: CGSize) -> CGImage? {
	guard let colorSpace = cgImage.colorSpace else { return nil }
	guard let ctx = CGContext(
		data: nil,
		width: Int(size.width),
		height: Int(size.height),
		bitsPerComponent: cgImage.bitsPerComponent,
		bytesPerRow: 0,
		space: colorSpace,
		bitmapInfo: cgImage.bitmapInfo.rawValue
	) else {
		return nil
	}

	ctx.interpolationQuality = .high
	ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))

	return ctx.makeImage()
}

func resizeCIImage(ciImage: CIImage, to size: CGSize) -> CIImage? {
	let orig = ciImage.extent.size
	let scale = CGAffineTransform(
		scaleX: size.width / orig.width,
		y: size.height / orig.height
	)
	return ciImage.transformed(by: scale)
}

let imageUrl = URL(filePath: inputImagePath)

guard let imageSrc = CGImageSourceCreateWithURL(imageUrl as CFURL, nil) else {
	print("Failed to create image source from URL: \(imageUrl)")
	exit(1)
}

guard let cgImage = CGImageSourceCreateImageAtIndex(imageSrc, 0, nil) else {
	print("Failed to create image from source")
	exit(1)
}

guard let metaRaw = CGImageSourceCopyPropertiesAtIndex(imageSrc, 0, nil) else {
	print("Failed to get metadata")
	exit(1)
}
let metadata = metaRaw as! Dictionary<String, Any>

guard let gainMapRaw = CGImageSourceCopyAuxiliaryDataInfoAtIndex(imageSrc, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [CFString:Any] else {
	print("Failed to extract gain map data")
	exit(1)
}

let gainMapData = gainMapRaw[kCGImageAuxiliaryDataInfoDataDescription] as! [CFString:Any]
guard let gainMapWidth = gainMapData[kCGImagePropertyWidth] as? Int else {
	print("Faild to get gain map width")
	exit(1)
}
guard let gainMapHeight = gainMapData[kCGImagePropertyHeight] as? Int else {
	print("Faild to get gain map height")
	exit(1)
}
let gainMapSize = CGSize(width: gainMapWidth, height: gainMapHeight)

guard let gainMapBytesPerRow = gainMapData[kCGImagePropertyBytesPerRow] as? Int else {
	print("Failed to get gain map bytes per row")
	exit(1)
}

guard let gainMapImgData = gainMapRaw[kCGImageAuxiliaryDataInfoData] as? Data else {
	print("Failed to get gain map image data")
	exit(1)
}

let gainMapImage = CIImage(bitmapData: gainMapImgData, bytesPerRow: gainMapBytesPerRow, size: gainMapSize, format: .L8, colorSpace: nil)
writeImage(image: gainMapImage, to: outputDirectory + "/gain_map.jpg")


let halfSize = CGSize(width: cgImage.width / 2, height: cgImage.height / 2)
let doubleSize = CGSize(width: cgImage.width * 2, height: cgImage.height * 2)

guard let halfImage = resizeCGImage(cgImage: cgImage, to: halfSize) else {
	print("Failed to produce half-sized image")
	exit(1)
}
guard let halfGainMap = resizeCIImage(ciImage: gainMapImage, to: CGSize(width: gainMapSize.width / 2, height: gainMapSize.height / 2)) else {
	print("Failed to resize gain map")
	exit(1)
}

let gmBPR = Int(halfGainMap.extent.width * 1) // L8 format is 1 byte per pixel
let gmDataSize = gmBPR * Int(halfGainMap.extent.height)
var gmImgData = Data(count: gmDataSize)
let ctx = CIContext()
gmImgData.withUnsafeMutableBytes { buffer in
	guard let base = buffer.baseAddress else { return }
	ctx.render(
		halfGainMap,
		toBitmap: base,
		rowBytes: gmBPR,
		bounds: halfGainMap.extent,
		format: .L8,
		colorSpace: nil
	)
}

var modifiedGMData = gainMapData
modifiedGMData[kCGImagePropertyWidth] = Int(halfGainMap.extent.width)
modifiedGMData[kCGImagePropertyHeight] = Int(halfGainMap.extent.height)
modifiedGMData[kCGImagePropertyBytesPerRow] = gmBPR

var modifiedGM = gainMapRaw
modifiedGM[kCGImageAuxiliaryDataInfoData] = gmImgData
modifiedGM[kCGImageAuxiliaryDataInfoDataDescription] = modifiedGMData

writeImage(image: halfImage, to: outputDirectory + "/half.jpg", auxiliary: modifiedGM as CFDictionary)
