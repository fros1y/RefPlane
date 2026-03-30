import Foundation

// MARK: - Pigment decomposition engine
//
// Decomposes target Oklab colors into sparse pigment recipes (≤3 pigments)
// using Kubelka-Munk spectral mixing and a two-phase approach:
//   1. Precomputed lookup table of all 1/2/3-pigment mixes
//   2. Nelder-Mead refinement of concentrations

enum PigmentDecomposer {

    // MARK: - Lookup table entry

    private struct LookupEntry {
        let pigmentIndices: [Int]       // indices into pigment array
        let concentrations: [Float]     // corresponding concentrations (sum to 1)
        let color: OklabColor           // predicted Oklab color of this mix
    }

    // MARK: - Public API

    /// Decompose an array of target colors into pigment recipes.
    static func decompose(
        targetColors: [OklabColor],
        pigments: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int = 3,
        minConcentration: Float = 0.02,
        concurrent: Bool = true
    ) -> [PigmentRecipe] {
        guard !targetColors.isEmpty else { return [] }
        
        let clamped = min(max(maxPigments, 1), 3)
        let lookup = buildLookupTable(pigments: pigments, database: database, maxPigments: clamped)
        
        if concurrent {
            var recipes = [PigmentRecipe?](repeating: nil, count: targetColors.count)
            let lock = NSLock()
            
            DispatchQueue.concurrentPerform(iterations: targetColors.count) { i in
                let recipe = findBestRecipe(
                    target: targetColors[i],
                    pigments: pigments,
                    database: database,
                    lookup: lookup,
                    maxPigments: clamped,
                    minConcentration: minConcentration
                )
                lock.lock()
                recipes[i] = recipe
                lock.unlock()
            }
            return recipes.compactMap { $0 }
        } else {
            return targetColors.map { t in
                findBestRecipe(
                    target: t,
                    pigments: pigments,
                    database: database,
                    lookup: lookup,
                    maxPigments: clamped,
                    minConcentration: minConcentration
                )
            }
        }
    }

    // MARK: - Lookup table construction

    private static func buildLookupTable(
        pigments: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int
    ) -> [LookupEntry] {
        let n = pigments.count
        var entries: [LookupEntry] = []
        entries.reserveCapacity(n + n * (n - 1) / 2 * 11 + (maxPigments >= 3 ? n * (n - 1) * (n - 2) / 6 * 6 : 0))

        // Single pigments
        for i in 0..<n {
            let color = KubelkaMunkMixer.pigmentToOklab(kOverS: pigments[i].kOverS, database: database)
            entries.append(LookupEntry(pigmentIndices: [i], concentrations: [1.0], color: color))
        }

        // Two-pigment mixes at 11 concentration steps
        if maxPigments >= 2 {
            let steps: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
            for i in 0..<n {
                for j in (i + 1)..<n {
                    for c in steps {
                        let c1 = c
                        let c2 = 1.0 - c
                        let color = KubelkaMunkMixer.mixToOklab(
                            pigments: [
                                (kOverS: pigments[i].kOverS, concentration: c1),
                                (kOverS: pigments[j].kOverS, concentration: c2)
                            ],
                            database: database
                        )
                        entries.append(LookupEntry(
                            pigmentIndices: [i, j],
                            concentrations: [c1, c2],
                            color: color
                        ))
                    }
                }
            }
        }

        // Three-pigment mixes at coarser steps
        if maxPigments >= 3 {
            let tripleSteps: [(Float, Float, Float)] = generateTripleSteps(resolution: 5)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    for k in (j + 1)..<n {
                        for (c1, c2, c3) in tripleSteps {
                            let color = KubelkaMunkMixer.mixToOklab(
                                pigments: [
                                    (kOverS: pigments[i].kOverS, concentration: c1),
                                    (kOverS: pigments[j].kOverS, concentration: c2),
                                    (kOverS: pigments[k].kOverS, concentration: c3)
                                ],
                                database: database
                            )
                            entries.append(LookupEntry(
                                pigmentIndices: [i, j, k],
                                concentrations: [c1, c2, c3],
                                color: color
                            ))
                        }
                    }
                }
            }
        }

        return entries
    }

    /// Generate concentration triples that sum to 1.0, at the given resolution.
    /// resolution=5 gives steps of 0.2: (0.2,0.2,0.6), (0.2,0.4,0.4), (0.2,0.6,0.2), etc.
    private static func generateTripleSteps(resolution: Int) -> [(Float, Float, Float)] {
        var result: [(Float, Float, Float)] = []
        let step = 1.0 / Float(resolution)
        for a in 1..<resolution {
            for b in 1..<(resolution - a) {
                let c = resolution - a - b
                if c >= 1 {
                    result.append((Float(a) * step, Float(b) * step, Float(c) * step))
                }
            }
        }
        return result
    }

    // MARK: - Best recipe search

    private static func findBestRecipe(
        target: OklabColor,
        pigments: [PigmentData],
        database: SpectralDatabase,
        lookup: [LookupEntry],
        maxPigments: Int,
        minConcentration: Float
    ) -> PigmentRecipe {
        // Phase 1: Find best lookup entry
        var bestEntry = lookup[0]
        var bestDist = oklabDistance(target, lookup[0].color)

        for entry in lookup.dropFirst() {
            let dist = oklabDistance(target, entry.color)
            if dist < bestDist {
                bestDist = dist
                bestEntry = entry
            }
        }

        // Phase 2: Refine concentrations with Nelder-Mead
        let refined = refineConcentrations(
            target: target,
            pigmentIndices: bestEntry.pigmentIndices,
            initialConcentrations: bestEntry.concentrations,
            pigments: pigments,
            database: database
        )

        // Also try greedy expansion if we have room for more pigments
        var finalIndices = refined.indices
        var finalConcentrations = refined.concentrations

        if refined.indices.count < maxPigments {
            let expanded = greedyExpand(
                target: target,
                currentIndices: refined.indices,
                currentConcentrations: refined.concentrations,
                pigments: pigments,
                database: database,
                maxPigments: maxPigments
            )
            let expandedDist = oklabDistance(target, expanded.color)
            let refinedDist = oklabDistance(target, refined.color)
            if expandedDist < refinedDist - 0.0001 {
                finalIndices = expanded.indices
                finalConcentrations = expanded.concentrations
            }
        }

        var validTuples = zip(finalIndices, finalConcentrations).filter { $0.1 >= minConcentration }
        if validTuples.isEmpty, let maxTuple = zip(finalIndices, finalConcentrations).max(by: { $0.1 < $1.1 }) {
            validTuples = [maxTuple]
        }
        
        let sum = validTuples.reduce(0) { $0 + $1.1 }
        if sum > 0 {
            validTuples = validTuples.map { ($0.0, $0.1 / sum) }
        } else {
            let fallback = 1.0 / Float(max(1, validTuples.count))
            validTuples = validTuples.map { ($0.0, fallback) }
        }

        let strictColor = evaluateMix(
            indices: validTuples.map { $0.0 },
            concentrations: validTuples.map { $0.1 },
            pigments: pigments,
            database: database
        )
        let exactDeltaE = sqrtf(oklabDistance(target, strictColor))

        let components = validTuples
            .map { (idx, conc) in
                RecipeComponent(
                    pigmentId: pigments[idx].id,
                    pigmentName: pigments[idx].name,
                    concentration: conc
                )
            }
            .sorted { $0.concentration > $1.concentration }

        return PigmentRecipe(
            components: components,
            predictedColor: strictColor,
            deltaE: exactDeltaE
        )
    }

    // MARK: - Greedy expansion

    private struct RefinementResult {
        let indices: [Int]
        let concentrations: [Float]
        let color: OklabColor
    }

    private static func greedyExpand(
        target: OklabColor,
        currentIndices: [Int],
        currentConcentrations: [Float],
        pigments: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int
    ) -> RefinementResult {
        var bestIndices = currentIndices
        var bestConcentrations = currentConcentrations
        var bestColor = evaluateMix(indices: currentIndices, concentrations: currentConcentrations, pigments: pigments, database: database)
        var bestDist = oklabDistance(target, bestColor)

        var indices = currentIndices
        var concentrations = currentConcentrations

        while indices.count < maxPigments {
            var candidateBestIdx = -1
            var candidateBestDist = bestDist

            let usedSet = Set(indices)
            for i in 0..<pigments.count where !usedSet.contains(i) {
                // Try adding pigment i at 20% and re-normalize
                var tryIndices = indices + [i]
                var tryConc = concentrations.map { $0 * 0.8 } + [0.2]

                let refined = refineConcentrations(
                    target: target,
                    pigmentIndices: tryIndices,
                    initialConcentrations: tryConc,
                    pigments: pigments,
                    database: database
                )
                let dist = oklabDistance(target, refined.color)
                if dist < candidateBestDist - 0.0001 {
                    candidateBestDist = dist
                    candidateBestIdx = i
                    tryIndices = refined.indices
                    tryConc = refined.concentrations
                }
            }

            if candidateBestIdx < 0 { break }

            indices.append(candidateBestIdx)
            concentrations = concentrations.map { $0 * 0.8 } + [0.2]
            let refined = refineConcentrations(
                target: target,
                pigmentIndices: indices,
                initialConcentrations: concentrations,
                pigments: pigments,
                database: database
            )
            indices = refined.indices
            concentrations = refined.concentrations
            bestColor = refined.color
            bestDist = oklabDistance(target, bestColor)

            if bestDist < candidateBestDist + 0.0001 {
                bestIndices = indices
                bestConcentrations = concentrations
            }
        }

        return RefinementResult(indices: bestIndices, concentrations: bestConcentrations, color: bestColor)
    }

    // MARK: - Nelder-Mead concentration refinement

    private static func refineConcentrations(
        target: OklabColor,
        pigmentIndices: [Int],
        initialConcentrations: [Float],
        pigments: [PigmentData],
        database: SpectralDatabase
    ) -> RefinementResult {
        let n = pigmentIndices.count
        guard n > 1 else {
            let color = evaluateMix(indices: pigmentIndices, concentrations: [1.0], pigments: pigments, database: database)
            return RefinementResult(indices: pigmentIndices, concentrations: [1.0], color: color)
        }

        // Optimize in (n-1) dimensional simplex space.
        // Use free variables for first n-1 concentrations; last = 1 - sum.
        let dims = n - 1

        func concentrationsFromFree(_ free: [Float]) -> [Float] {
            var conc = free.map { max(0, $0) }
            let sum = conc.reduce(0, +)
            let last = max(0, 1.0 - sum)
            conc.append(last)
            // Normalize
            let total = conc.reduce(0, +)
            if total > 0 {
                for i in 0..<conc.count { conc[i] /= total }
            }
            return conc
        }

        func objective(_ free: [Float]) -> Float {
            let conc = concentrationsFromFree(free)
            let color = evaluateMix(indices: pigmentIndices, concentrations: conc, pigments: pigments, database: database)
            return oklabDistance(target, color)
        }

        // Nelder-Mead simplex
        var simplex: [[Float]] = []
        let initFree = Array(initialConcentrations.prefix(dims))
        simplex.append(initFree)
        for d in 0..<dims {
            var vertex = initFree
            vertex[d] = min(1.0, vertex[d] + 0.15)
            simplex.append(vertex)
        }

        var values = simplex.map { objective($0) }

        let alpha: Float = 1.0
        let gamma: Float = 2.0
        let rho: Float = 0.5
        let sigma: Float = 0.5
        let maxIter = 80

        for _ in 0..<maxIter {
            // Sort
            let sorted = zip(simplex.indices, values).sorted { $0.1 < $1.1 }
            simplex = sorted.map { simplex[$0.0] }
            values = sorted.map { $0.1 }

            // Convergence check
            if values.last! - values.first! < 1e-8 { break }

            // Centroid of all but worst
            var centroid = [Float](repeating: 0, count: dims)
            for i in 0..<(simplex.count - 1) {
                for d in 0..<dims { centroid[d] += simplex[i][d] }
            }
            let divisor = Float(simplex.count - 1)
            for d in 0..<dims { centroid[d] /= divisor }

            let worst = simplex.last!
            let worstVal = values.last!

            // Reflection
            var reflected = [Float](repeating: 0, count: dims)
            for d in 0..<dims { reflected[d] = centroid[d] + alpha * (centroid[d] - worst[d]) }
            let reflectedVal = objective(reflected)

            if reflectedVal < values.first! {
                // Expansion
                var expanded = [Float](repeating: 0, count: dims)
                for d in 0..<dims { expanded[d] = centroid[d] + gamma * (reflected[d] - centroid[d]) }
                let expandedVal = objective(expanded)
                if expandedVal < reflectedVal {
                    simplex[simplex.count - 1] = expanded
                    values[values.count - 1] = expandedVal
                } else {
                    simplex[simplex.count - 1] = reflected
                    values[values.count - 1] = reflectedVal
                }
            } else if reflectedVal < worstVal {
                simplex[simplex.count - 1] = reflected
                values[values.count - 1] = reflectedVal
            } else {
                // Contraction
                var contracted = [Float](repeating: 0, count: dims)
                for d in 0..<dims { contracted[d] = centroid[d] + rho * (worst[d] - centroid[d]) }
                let contractedVal = objective(contracted)
                if contractedVal < worstVal {
                    simplex[simplex.count - 1] = contracted
                    values[values.count - 1] = contractedVal
                } else {
                    // Shrink
                    let best = simplex[0]
                    for i in 1..<simplex.count {
                        for d in 0..<dims {
                            simplex[i][d] = best[d] + sigma * (simplex[i][d] - best[d])
                        }
                        values[i] = objective(simplex[i])
                    }
                }
            }
        }

        let bestFree = simplex[values.enumerated().min(by: { $0.1 < $1.1 })!.offset]
        let bestConc = concentrationsFromFree(bestFree)
        let bestColor = evaluateMix(indices: pigmentIndices, concentrations: bestConc, pigments: pigments, database: database)

        return RefinementResult(indices: pigmentIndices, concentrations: bestConc, color: bestColor)
    }

    // MARK: - Helpers

    private static func evaluateMix(
        indices: [Int],
        concentrations: [Float],
        pigments: [PigmentData],
        database: SpectralDatabase
    ) -> OklabColor {
        let pairs = zip(indices, concentrations).map { (kOverS: pigments[$0].kOverS, concentration: $1) }
        return KubelkaMunkMixer.mixToOklab(pigments: pairs, database: database)
    }

    // MARK: - Limited Palette Helpers

    static func selectTubes(
        preliminaryRecipes: [PigmentRecipe],
        pixelCounts: [Int],
        clusterSalience: [Float],
        maxTubes: Int,
        allPigments: [PigmentData],
        database: SpectralDatabase
    ) -> [PigmentData] {
        guard !preliminaryRecipes.isEmpty, maxTubes > 0 else { return [] }
        
        var scores = [String: Float]()
        
        for (i, recipe) in preliminaryRecipes.enumerated() {
            let count = i < pixelCounts.count ? Float(pixelCounts[i]) : 1.0
            let salience = i < clusterSalience.count ? clusterSalience[i] : 1.0
            let effectiveWeight = count * salience
            
            for comp in recipe.components {
                scores[comp.pigmentId, default: 0] += comp.concentration * effectiveWeight
            }
        }
        
        struct Candidate {
            let pigment: PigmentData
            let score: Float
        }
        
        var allCandidates = allPigments
            .compactMap { p -> Candidate? in
                guard let score = scores[p.id], score > 0 else { return nil }
                return Candidate(pigment: p, score: score)
            }
            .sorted { $0.score > $1.score }
            
        var selected = [PigmentData]()
        var masstones = [OklabColor]()
        
        var i = 0
        while i < allCandidates.count && selected.count < maxTubes {
            var bestIdx = i
            // Check if next candidate is within 10% score
            if i + 1 < allCandidates.count, allCandidates[i+1].score >= allCandidates[i].score * 0.9 {
                let c1 = allCandidates[i].pigment
                let c2 = allCandidates[i+1].pigment
                let m1 = KubelkaMunkMixer.pigmentToOklab(kOverS: c1.kOverS, database: database)
                let m2 = KubelkaMunkMixer.pigmentToOklab(kOverS: c2.kOverS, database: database)
                
                let dist1 = selected.isEmpty ? 0 : selected.indices.map { oklabDistance(m1, masstones[$0]) }.min() ?? 0
                let dist2 = selected.isEmpty ? 0 : selected.indices.map { oklabDistance(m2, masstones[$0]) }.min() ?? 0
                
                if dist2 > dist1 {
                    bestIdx = i + 1
                }
            }
            
            let chosen = allCandidates[bestIdx]
            selected.append(chosen.pigment)
            masstones.append(KubelkaMunkMixer.pigmentToOklab(kOverS: chosen.pigment.kOverS, database: database))
            
            if bestIdx == i + 1 {
                allCandidates.swapAt(i, i+1)
            }
            i += 1
        }
        
        return selected
    }

    static func improveTubeSet(
        seedTubes: [PigmentData],
        targetColors: [OklabColor],
        clusterWeights: [Float],
        allPigments: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int,
        minConcentration: Float
    ) -> [PigmentData] {
        var currentTubes = seedTubes
        guard !currentTubes.isEmpty, currentTubes.count < allPigments.count else { return currentTubes }
        
        // Filter the target colors to only the most salient ones (e.g. top 8)
        // This avoids running expensive Nelder-Mead on all 48 minor clusters for every 1-off pigment swap.
        let topCount = min(8, targetColors.count)
        let sortedIndices = clusterWeights.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(topCount)
            .map { $0.offset }
        
        let topColors = sortedIndices.map { targetColors[$0] }
        let topWeights = sortedIndices.map { clusterWeights[$0] }
        
        func evaluateApproxError(tubes: [PigmentData]) -> Float {
            let clamped = min(max(maxPigments, 1), 3)
            let lookup = buildLookupTable(pigments: tubes, database: database, maxPigments: clamped)
            var totalError: Float = 0
            for (i, target) in topColors.enumerated() {
                var bestDist = Float.greatestFiniteMagnitude
                for entry in lookup {
                    let d = oklabDistance(target, entry.color)
                    if d < bestDist { bestDist = d }
                }
                totalError += sqrtf(bestDist) * topWeights[i]
            }
            return totalError
        }
        
        var improved = true
        var swapCount = 0
        
        while improved && swapCount < 3 { // bounded search budget
            improved = false
            let currentApproxError = evaluateApproxError(tubes: currentTubes)
            let unselected = allPigments.filter { p in !currentTubes.contains(where: { $0.id == p.id }) }
            
            struct SwapCandidate {
                let tubeIndex: Int
                let tubes: [PigmentData]
            }
            var candidates = [SwapCandidate]()
            for unsel in unselected {
                for i in 0..<currentTubes.count {
                    var candidateTubes = currentTubes
                    candidateTubes[i] = unsel
                    candidates.append(SwapCandidate(tubeIndex: i, tubes: candidateTubes))
                }
            }
            
            var bestCandidate: SwapCandidate? = nil
            var bestError = currentApproxError
            let lock = NSLock()
            
            DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
                let candidate = candidates[i]
                let candidateError = evaluateApproxError(tubes: candidate.tubes)
                
                lock.lock()
                if candidateError < bestError - 0.001 {
                    bestError = candidateError
                    bestCandidate = candidate
                }
                lock.unlock()
            }
            
            if let best = bestCandidate {
                currentTubes = best.tubes
                improved = true
                swapCount += 1
            }
        }
        
        return currentTubes
    }

    static func mergeRecipes(
        recipes: [PigmentRecipe],
        pixelCounts: [Int],
        colorThreshold: Float = 0.015,
        concentrationThreshold: Float = 0.05
    ) -> (recipes: [PigmentRecipe], labelMapping: [Int]) {
        var mergedRecipes = [PigmentRecipe]()
        var labelMapping = [Int](repeating: 0, count: recipes.count)
        var recipeWeights = [Int]() 
        
        for (i, recipe) in recipes.enumerated() {
            let count = i < pixelCounts.count ? pixelCounts[i] : 0
            guard count > 0 else {
                labelMapping[i] = 0 // mapped properly in final pass below
                continue
            }
            
            var matchedIndex: Int? = nil
            for (j, existing) in mergedRecipes.enumerated() {
                let dist = sqrtf(oklabDistance(recipe.predictedColor, existing.predictedColor))
                let colorMatch = dist < colorThreshold

                // Compare recipe structure
                let r1Names = Set(recipe.components.map { $0.pigmentId })
                let r2Names = Set(existing.components.map { $0.pigmentId })
                var structureMatch = false
                if r1Names == r2Names {
                    var concDiffOk = true
                    for comp1 in recipe.components {
                        let comp2 = existing.components.first { $0.pigmentId == comp1.pigmentId }
                        let diff = abs(comp1.concentration - (comp2?.concentration ?? 0))
                        if diff > concentrationThreshold {
                            concDiffOk = false
                            break
                        }
                    }
                    structureMatch = concDiffOk
                }

                if colorMatch || structureMatch {
                    matchedIndex = j
                    break
                }
            }
            
            if let targetIdx = matchedIndex {
                labelMapping[i] = targetIdx
                // The larger cluster absorbs the smaller
                if count > recipeWeights[targetIdx] {
                    mergedRecipes[targetIdx] = recipe
                }
                recipeWeights[targetIdx] += count
            } else {
                labelMapping[i] = mergedRecipes.count
                mergedRecipes.append(recipe)
                recipeWeights.append(count)
            }
        }
        
        // Map empty clusters to nearest survivor
        for i in 0..<recipes.count {
            let count = i < pixelCounts.count ? pixelCounts[i] : 0
            if count == 0 {
                var bestDist = Float.greatestFiniteMagnitude
                var bestIdx = 0
                for (j, surv) in mergedRecipes.enumerated() {
                    let d = oklabDistance(recipes[i].predictedColor, surv.predictedColor)
                    if d < bestDist {
                        bestDist = d
                        bestIdx = j
                    }
                }
                labelMapping[i] = bestIdx
            }
        }
        
        return (mergedRecipes, labelMapping)
    }
}
