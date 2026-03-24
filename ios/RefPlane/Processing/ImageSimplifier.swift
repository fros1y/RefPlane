import UIKit
import CoreImage

// MARK: - Image simplification using Core Image filters
// Structure supports dropping in a Core ML model by replacing the CI pipeline.

enum ImageSimplifier {

    static func simplify(image: UIImage) async -> UIImage {
        return await Task.detached(priority: .userInitiated) {
            guard let ciImage = CIImage(image: image) else { return image }
            let context = CIContext(options: [.useSoftwareRenderer: false])

            // Step 1: Upscale 1.5× with Lanczos interpolation
            let scale: CGFloat = 1.5
            let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
            scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
            scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
            scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            guard let scaledCI = scaleFilter.outputImage else { return image }

            // Step 2: Noise reduction
            let noiseFilter = CIFilter(name: "CINoiseReduction")!
            noiseFilter.setValue(scaledCI, forKey: kCIInputImageKey)
            noiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
            noiseFilter.setValue(0.4,  forKey: "inputSharpness")
            guard let denoisedCI = noiseFilter.outputImage else { return image }

            // Step 3: Sharpen luminance
            let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
            sharpenFilter.setValue(denoisedCI, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
            guard let sharpenedCI = sharpenFilter.outputImage else { return image }

            // Step 4: Downscale back to original size
            let originalSize = image.size
            let downscale: CGFloat = 1.0 / scale
            let downFilter = CIFilter(name: "CILanczosScaleTransform")!
            downFilter.setValue(sharpenedCI, forKey: kCIInputImageKey)
            downFilter.setValue(downscale, forKey: kCIInputScaleKey)
            downFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            guard let finalCI = downFilter.outputImage else { return image }

            guard let cgImage = context.createCGImage(
                finalCI,
                from: finalCI.extent
            ) else { return image }

            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }
}
