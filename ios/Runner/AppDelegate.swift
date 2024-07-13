import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        let livenessChannel = FlutterMethodChannel(name: "com.benamorn.liveness",
                                                   binaryMessenger: controller.binaryMessenger)
        
        livenessChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            switch call.method {
            case "checkLiveness":
                self.checkLiveness(call: call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func checkLiveness(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let platforms = args["platforms"] as? [FlutterStandardTypedData],
          let strides = args["strides"] as? [Int],
          let width = args["width"] as? Int,
          let height = args["height"] as? Int else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
        return
    }
    
    print("Received image data: Width = \(width), Height = \(height)")
    print("Number of planes: \(platforms.count)")
    print("Planes sizes: \(platforms.map { $0.data.count })")
    print("Strides: \(strides)")
    
    // Handle different plane configurations
    let yPlane: Data
    let uPlane: Data
    let vPlane: Data
    
    if platforms.count == 1 {
        // Assume single plane is NV21 or NV12
        let fullPlane = platforms[0].data
        let ySize = width * height
        yPlane = fullPlane.prefix(ySize)
        uPlane = fullPlane.suffix(from: ySize)
        vPlane = fullPlane.suffix(from: ySize)
    } else if platforms.count == 2 {
        // Assume two planes: Y and interleaved UV
        yPlane = platforms[0].data
        uPlane = platforms[1].data
        vPlane = platforms[1].data
    } else if platforms.count >= 3 {
        yPlane = platforms[0].data
        uPlane = platforms[1].data
        vPlane = platforms[2].data
    } else {
        result(FlutterError(code: "INVALID_DATA", message: "Unsupported number of image planes: \(platforms.count)", details: nil))
        return
    }
    
    let yStride = strides[0]
    let uvStride = strides.count > 1 ? strides[1] : width / 2
    
    do {
        let nv12Data = try convertYUVToNV12(yPlane: yPlane, uPlane: uPlane, vPlane: vPlane, width: width, height: height, yStride: yStride, uvStride: uvStride)
        let rgbaData = convertNV12ToRGBA(nv12Data: nv12Data, width: width, height: height)
        
        let ciImage = CIImage(bitmapData: rgbaData, bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            result(FlutterError(code: "IMAGE_CONVERSION_FAILED", message: "Failed to create CGImage", details: nil))
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            result(FlutterError(code: "IMAGE_CONVERSION_FAILED", message: "Failed to create JPEG data", details: nil))
            return
        }
        
        result(FlutterStandardTypedData(bytes: jpegData))
    } catch {
        result(FlutterError(code: "CONVERSION_FAILED", message: "Failed to convert image: \(error.localizedDescription)", details: nil))
    }
}
    
   private func convertYUVToNV12(yPlane: Data, uPlane: Data, vPlane: Data, width: Int, height: Int, yStride: Int, uvStride: Int) throws -> Data {
    let ySize = width * height
    let uvSize = (width * height) / 4
    
    print("Converting to NV12: ySize = \(ySize), uvSize = \(uvSize)")
    print("Y plane size: \(yPlane.count), U plane size: \(uPlane.count), V plane size: \(vPlane.count)")
    
    var nv12Data = Data(count: ySize + uvSize * 2)
    
    // Copy Y plane
    for row in 0..<height {
        let yOffset = row * yStride
        let nv12Offset = row * width
        let rowSize = min(width, yPlane.count - yOffset)
        nv12Data.replaceSubrange(nv12Offset..<nv12Offset+rowSize, with: yPlane.subdata(in: yOffset..<yOffset+rowSize))
    }
    
    // Interleave U and V planes
    let uvHeight = height / 2
    let uvWidth = width / 2
    var uvOffset = ySize
    
    if uPlane.count == vPlane.count {
        // Separate U and V planes
        for row in 0..<uvHeight {
            let uOffset = row * uvStride
            let vOffset = row * uvStride
            
            for col in 0..<uvWidth {
                if uvOffset + 1 < nv12Data.count && uOffset + col < uPlane.count && vOffset + col < vPlane.count {
                    nv12Data[uvOffset] = vPlane[vOffset + col]
                    nv12Data[uvOffset + 1] = uPlane[uOffset + col]
                    uvOffset += 2
                } else {
                    break
                }
            }
        }
    } else if uPlane.count == vPlane.count * 2 {
        // Interleaved UV plane
        for row in 0..<uvHeight {
            let uvOffset = row * uvStride
            
            for col in 0..<uvWidth {
                if uvOffset + (col * 2) + 1 < uPlane.count {
                    nv12Data[ySize + (row * width) + (col * 2)] = uPlane[uvOffset + (col * 2) + 1]
                    nv12Data[ySize + (row * width) + (col * 2) + 1] = uPlane[uvOffset + (col * 2)]
                } else {
                    break
                }
            }
        }
    } else {
        throw NSError(domain: "ImageProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported UV plane format"])
    }
    
    return nv12Data
}
    
    private func convertNV12ToRGBA(nv12Data: Data, width: Int, height: Int) -> Data {
        var rgbaData = Data(count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let yIndex = y * width + x
                let uvIndex = width * height + (y / 2) * width + (x - (x % 2))
                
                let yValue = Float(nv12Data[yIndex])
                let uValue = Float(nv12Data[uvIndex + 1])
                let vValue = Float(nv12Data[uvIndex])
                
                let c = yValue - 16
                let d = uValue - 128
                let e = vValue - 128
                
                let r = abs(1.164 * c + 1.596 * e)
                let g = abs(1.164 * c - 0.813 * e - 0.391 * d)
                let b = abs(1.164 * c + 2.018 * d)
                
                let rgbaIndex = (y * width + x) * 4
                rgbaData[rgbaIndex] = UInt8(min(max(r, 0), 255))
                rgbaData[rgbaIndex + 1] = UInt8(min(max(g, 0), 255))
                rgbaData[rgbaIndex + 2] = UInt8(min(max(b, 0), 255))
                rgbaData[rgbaIndex + 3] = 255 // Alpha channel
            }
        }
        
        return rgbaData
    }
}