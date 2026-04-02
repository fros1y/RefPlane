import UIKit

enum TestImageFactory {
    static func makeSolid(width: Int, height: Int, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func makeSplitColors(
        pixels: [(UInt8, UInt8, UInt8)],
        width: Int,
        height: Int
    ) -> UIImage {
        var data = [UInt8]()
        data.reserveCapacity(width * height * 4)

        for (r, g, b) in pixels {
            data.append(r)
            data.append(g)
            data.append(b)
            data.append(255)
        }

        return UIImage.fromPixelData(data, width: width, height: height) ?? makeSolid(width: width, height: height, color: .white)
    }

    static func makeHorizontalDepthRamp(width: Int, height: Int) -> UIImage {
        guard width > 1, height > 0 else {
            return makeSolid(width: max(width, 1), height: max(height, 1), color: .black)
        }

        var data: [UInt8] = []
        data.reserveCapacity(width * height * 4)

        for _ in 0..<height {
            for x in 0..<width {
                let value = UInt8((Double(x) / Double(width - 1) * 255).rounded())
                data.append(value)
                data.append(value)
                data.append(value)
                data.append(255)
            }
        }

        return UIImage.fromPixelData(data, width: width, height: height)
            ?? makeSolid(width: width, height: height, color: .black)
    }
}
