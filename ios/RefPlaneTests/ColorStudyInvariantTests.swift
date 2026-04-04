import UIKit
import Testing
@testable import Underpaint

@Suite(.serialized)
struct ColorStudyInvariantTests {
    let database = SpectralDataStore.shared
    let pigments = SpectralDataStore.essentialPigments

    // Helper to calculate RMSE of Oklab Distance (global color error)
    private func computeGlobalError(originalLab: [Float], result: PaintPaletteResult) -> Float {
        var sumSquaredError: Float = 0
        let total = originalLab.count / 3
        
        // Handle gracefully if there is some mismatch
        guard total == result.pixelLabels.count else { return Float.greatestFiniteMagnitude }

        for i in 0..<total {
            let label = Int(result.pixelLabels[i])
            if label < 0 || label >= result.recipes.count { continue }
            let recipeColor = result.recipes[label].predictedColor
            let og = OklabColor(L: originalLab[i*3], a: originalLab[i*3+1], b: originalLab[i*3+2])
            
            // oklabDistance is squared distance
            let dist = oklabDistance(og, recipeColor) 
            sumSquaredError += dist
        }
        
        return sqrtf(sumSquaredError / Float(total))
    }

    private func loadImage(named: String) throws -> UIImage {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // RefPlaneTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // RefPlane
        
        let url = repoRoot.appendingPathComponent("tests/\(named)")
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load test image \(named)"])
        }
        return image
    }

    @Test
    func errorShouldDecreaseWithMoreShades() throws {
        let image = try loadImage(named: "atkinsonrealworld.jpg")
        
        // Process the image ONCE into colors, so the frontend K-means clustering is constant
        // This isolates our testing to exactly the invariants within PaintPaletteBuilder
        var baseConfig = ColorConfig()
        baseConfig.numShades = 24
        let regions = ColorRegionsProcessor.process(image: image, config: baseConfig, overclusterK: 48)!
        
        func errorForShades(_ shades: Int) throws -> Float {
            var clone = baseConfig
            clone.numShades = shades
            clone.maxPigmentsPerMix = 3
            
            let result = try PaintPaletteBuilder.build(
                colorRegions: regions,
                config: clone,
                database: self.database,
                pigments: self.pigments
            )
            return computeGlobalError(originalLab: regions.pixelLab, result: result)
        }
        
        let error4 = try errorForShades(4)
        let error8 = try errorForShades(8)
        let error16 = try errorForShades(16)
        let error24 = try errorForShades(24)

        // Give a tiny tolerance for floating point merging heuristic shifts (e.g. 0.0005)
        let tolerance: Float = 0.0005
        #expect(error8 <= error4 + tolerance, "Increasing shades from 4 to 8 should not significantly increase error. error4: \(error4), error8: \(error8)")
        #expect(error16 <= error8 + tolerance, "Increasing shades from 8 to 16 should not significantly increase error. error8: \(error8), error16: \(error16)")
        #expect(error24 <= error16 + tolerance, "Increasing shades from 16 to 24 should not significantly increase error. error16: \(error16), error24: \(error24)")
    }

    @Test
    func errorShouldDecreaseWithMoreTubes() throws {
        let image = try loadImage(named: "atkinsonrealworld.jpg")
        
        var baseConfig = ColorConfig()
        baseConfig.numShades = 12
        let regions = ColorRegionsProcessor.process(image: image, config: baseConfig, overclusterK: 24)!

        // Build pigment subsets of increasing size from the essential pigments
        let allEssential = SpectralDataStore.essentialPigments
        let sorted = allEssential.sorted { $0.name < $1.name }

        func errorForTubeCount(_ count: Int) throws -> Float {
            var clone = baseConfig
            clone.enabledPigmentIDs = Set(sorted.prefix(count).map(\.id))
            clone.maxPigmentsPerMix = 3
            
            let subset = sorted.prefix(count).map { $0 }
            let result = try PaintPaletteBuilder.build(
                colorRegions: regions,
                config: clone,
                database: self.database,
                pigments: subset
            )
            return computeGlobalError(originalLab: regions.pixelLab, result: result)
        }
        
        let error4 = try errorForTubeCount(4)
        let error8 = try errorForTubeCount(8)
        let error12 = try errorForTubeCount(12)
        
        let tolerance: Float = 0.001
        #expect(error8 <= error4 + tolerance, "Increasing tubes from 4 to 8 should not increase error. error4: \(error4), error8: \(error8)")
        #expect(error12 <= error8 + tolerance, "Increasing tubes from 8 to 12 should not increase error. error8: \(error8), error12: \(error12)")
    }

    @Test
    func errorShouldDecreaseWithMoreAllowedPigments() throws {
        let image = try loadImage(named: "atkinsonrealworld.jpg")
        
        var baseConfig = ColorConfig()
        baseConfig.numShades = 8
        // Pre-process for 8 shades
        let regions = ColorRegionsProcessor.process(image: image, config: baseConfig, overclusterK: 16)!
        
        func errorForPigs(_ maxPigments: Int) throws -> Float {
            var clone = baseConfig
            clone.maxPigmentsPerMix = maxPigments
            
            let result = try PaintPaletteBuilder.build(
                colorRegions: regions,
                config: clone,
                database: self.database,
                pigments: self.pigments
            )
            return computeGlobalError(originalLab: regions.pixelLab, result: result)
        }
        
        let error1 = try errorForPigs(1)
        let error2 = try errorForPigs(2)
        let error3 = try errorForPigs(3)
        
        let tolerance: Float = 0.001
        #expect(error2 <= error1 + tolerance, "Increasing pigments per mix from 1 to 2 should not increase error.")
        #expect(error3 <= error2 + tolerance, "Increasing pigments per mix from 2 to 3 should not increase error.")
    }

    @Test
    func singleTubePaletteBuildShouldNotCrashOrReturnEmptyRecipes() throws {
        let image = try loadImage(named: "atkinsonrealworld.jpg")

        var config = ColorConfig()
        config.numShades = 6
        config.maxPigmentsPerMix = 1
        config.paletteSelectionEnabled = true

        let singleTube = try #require(
            SpectralDataStore.essentialPigments.first(where: { $0.id == "titanium_white" })
                ?? SpectralDataStore.essentialPigments.first
        )
        config.enabledPigmentIDs = [singleTube.id]

        let regions = try #require(
            ColorRegionsProcessor.process(image: image, config: config, overclusterK: 12)
        )

        let result = try PaintPaletteBuilder.build(
            colorRegions: regions,
            config: config,
            database: database,
            pigments: [singleTube]
        )

        #expect(!result.recipes.isEmpty)
        #expect(result.recipes.allSatisfy { recipe in
            recipe.components.count == 1 && recipe.components[0].pigmentId == singleTube.id
        })
        #expect(result.pixelLabels.count == regions.pixelLabels.count)
    }
}
