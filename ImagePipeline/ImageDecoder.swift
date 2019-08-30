import CoreGraphics
import Foundation
import WebPDecoder

public protocol ImageDecoding {
  func decode(data: Data) -> UIImage?
}

public struct ImageDecoder: ImageDecoding {
  public init() {}

  public func decode(data: Data) -> UIImage? {
    return decode(data: data, size: .zero)
  }

  public func decode(data: Data, size: CGSize) -> UIImage? {
    guard data.count > 12 else {
      return nil
    }

    let bytes = Array(data)
    if isJPEG(bytes: bytes) || isPNG(bytes: bytes) || isGIF(bytes: bytes) {
      return UIImage(data: data)
    }

    guard isWebP(bytes: bytes) else {
      return nil
    }

    return data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in

      var config = WebPDecoderConfig()
      WebPInitDecoderConfig(&config)

      guard WebPGetFeatures(bytes, data.count, &config.input) == VP8_STATUS_OK else {
        return nil
      }

      config.output.colorspace = config.input.has_alpha != 0 ? MODE_bgrA : MODE_RGB

      if size.width > 0, size.height > 0,
        Int(size.width) < config.input.width, Int(size.height) < config.input.height {
        config.options.use_scaling = 1
        config.options.scaled_width = Int32(size.width)
        config.options.scaled_height = Int32(size.height)
      }

      guard WebPDecode(bytes, data.count, &config) == VP8_STATUS_OK else {
        return nil
      }

      var width: Int32 = config.input.width
      var height: Int32 = config.input.height
      if config.options.use_scaling != 0 {
        width = config.options.scaled_width
        height = config.options.scaled_height
      }

      guard let provider = CGDataProvider(dataInfo: nil,
                                          data: config.output.u.RGBA.rgba,
                                          size: config.output.u.RGBA.size,
                                          releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }) else {
        return nil
      }

      let bitmapInfo: CGBitmapInfo = config.input.has_alpha != 0
        ? [.byteOrder32Little, .init(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
        : [.byteOrder32Big]
      let components: size_t = config.input.has_alpha != 0 ? 4 : 3

      guard let cgImage = CGImage(width: Int(width),
                                  height: Int(height),
                                  bitsPerComponent: 8,
                                  bitsPerPixel: components * 8,
                                  bytesPerRow: components * Int(width),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo,
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: false,
                                  intent: .defaultIntent) else {
        return nil
      }

      return UIImage(cgImage: cgImage)
    }
  }

  private func isJPEG(bytes: [UInt8]) -> Bool {
    return bytes[0...2] == [0xFF, 0xD8, 0xFF]
  }

  private func isPNG(bytes: [UInt8]) -> Bool {
    return bytes[0...3] == [0x89, 0x50, 0x4E, 0x47]
  }

  private func isGIF(bytes: [UInt8]) -> Bool {
    return bytes[0...2] == [0x47, 0x49, 0x46]
  }

  private func isWebP(bytes: [UInt8]) -> Bool {
    return bytes[8...11] == [0x57, 0x45, 0x42, 0x50]
  }
}

private struct WebPSize: Equatable {
  var width: Int32
  var height: Int32

  static var zero: WebPSize {
    return .init(width: 0, height: 0)
  }
}

extension WebPSize {
  init(_ size: CGSize) {
    width = Int32(size.width)
    height = Int32(size.height)
  }

  init(_ features: WebPBitstreamFeatures) {
    width = features.width
    height = features.height
  }

  init(_ buffer: WebPDecBuffer) {
    width = buffer.width
    height = buffer.height
  }
}

private extension WEBP_CSP_MODE {
  var isAlpha: Bool {
    return WebPIsAlphaMode(self) == 1
  }

  var isPremultiplied: Bool {
    return WebPIsPremultipliedMode(self) == 1
  }

  var cgImageAlphaInfo: CGImageAlphaInfo {
    switch (isAlpha, isPremultiplied) {
    case (false, _): return .none
    case (true, false): return .last
    case (true, true): return .premultipliedLast
    }
  }
}
