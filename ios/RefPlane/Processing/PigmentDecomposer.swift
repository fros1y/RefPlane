import Foundation

// MARK: - Pigment decomposition engine
//
// Decomposes target Oklab colors into sparse pigment recipes (≤3 pigments)
// using Kubelka-Munk spectral mixing.
//
// Two modes:
//   Fast (default): uses a precomputed PigmentLookupTable loaded from
//     PigmentLookup.bin, which covers all 78 pigments × full 0/8…8/8 simplex
//     grid.  No Kubelka-Munk arithmetic at query time.
//   Fallback: builds a runtime lookup table from the active pigment subset
//     (original behaviour, used when the binary asset is unavailable).

enum PigmentDecomposer {

    // MARK: - Runtime lookup table entry (fallback path)

    private struct LookupEntry {
        let pigmentIndices: [Int]       // indices into pigment array
        let concentrations: [Float]     // corresponding concentrations (sum to 1)
        let color: OklabColor           // predicted Oklab color of this mix
    }

    // MARK: - Public API

    /// Decompose an array of target colors into pigment recipes.
    ///
    /// - Parameters:
    ///   - targetColors:  Oklab colors to match.
    ///   - pigments:      Active paint tubes (subset of the full database).
    ///   - database:      Full spectral database (used for index mapping and KMM).
    ///   - maxPigments:   Max paints per mix (1–3).
    ///   - minConcentration: Components below this threshold are pruned.
    ///   - concurrent:    Use `DispatchQueue.concurrentPerform`.
    ///   - lookupTable:   Pre-computed table (pass `SpectralDataStore.sharedLookupTable`).
    ///                    When provided, zero Kubelka-Munk math is done per query.
    static func decompose(
        targetColors: [OklabColor],
        pigments: [PigmentData],
        database: SpectralDatabase,
        maxPigments: Int = 3,
        minConcentration: Float = 0.02,
        concurrent: Bool = true,
        lookupTable: PigmentLookupTable? = nil
    ) -> [PigmentRecipe] {
        guard !targetColors.isEmpty else { return [] }

        let clamped = min(max(maxPigments, 1), 3)

        // ── Fast path: precomputed table ────────────────────────────────────
        if let table = lookupTable {
            let globalIdx = globalIndices(for: pigments, in: database)
            if concurrent {
                var recipes = [PigmentRecipe?](repeating: nil, count: targetColors.count)
                let lock = NSLock()
                DispatchQueue.concurrentPerform(iterations: targetColors.count) { i in
                    let r = recipeFromTable(
                        target: targetColors[i],
                        globalIndices: globalIdx,
                        database: database,
                        table: table,
                        maxPigments: clamped,
                        minConcentration: minConcentration
                    )
                    lock.lock(); recipes[i] = r; lock.unlock()
                }
                return recipes.compactMap { $0 }
            } else {
                return targetColors.compactMap {
                    recipeFromTable(
                        target: $0,
                        globalIndices: globalIdx,
                        database: database,
                        table: table,
                        maxPigments: clamped,
                        minConcentration: minConcentration
                    )
                }
            }
        }

        // ── Fallback path: runtime table build ─────────────────────────────
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
                lock.lock(); recipes[i] = recipe; lock.unlock()
            }
            return recipes.compactMap { $0 }
        } else {
            return targetColors.map {
                findBestRecipe(
                    target: $0,
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

        // Two-pigment mixes at 1/8 concentration steps
        if maxPigments >= 2 {
            let steps: [Float] = (1...7).map { Float($0) / 8.0 }
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

        // Three-pigment mixes at 1/8 steps
        if maxPigments >= 3 {
            let tripleSteps: [(Float, Float, Float)] = generateTripleSteps(resolution: 8)
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

    // MARK: - Precomputed table helpers

    /// Return the global pigment indices (ascending) for a subset of pigments.
    static func globalIndices(for pigments: [PigmentData], in database: SpectralDatabase) -> [Int] {
        pigments.compactMap { pig in
            database.pigments.firstIndex(where: { $0.id == pig.id })
        }.sorted()
    }

    /// Find the best recipe for `target` using the precomputed lookup table.
    /// This path performs zero Kubelka-Munk arithmetic.
    private static func recipeFromTable(
        target: OklabColor,
        globalIndices: [Int],
        database: SpectralDatabase,
        table: PigmentLookupTable,
        maxPigments: Int,
        minConcentration: Float
    ) -> PigmentRecipe? {
        guard let (entry, distSq) = table.findBest(
            for: target,
            enabledGlobalIndices: globalIndices,
            maxPigments: maxPigments
        ) else { return nil }

        let a0 = entry.a0, a1 = entry.a1, a2 = entry.a2
        var slots: [(globalIdx: Int, conc: Float)] = []
        if a0 > 0 { slots.append((Int(entry.i0), Float(a0) / 8.0)) }
        if a1 > 0 { slots.append((Int(entry.i1), Float(a1) / 8.0)) }
        if a2 > 0 { slots.append((Int(entry.i2), Float(a2) / 8.0)) }

        // minConcentration prune (all 1/8-step values ≥ 0.125, so pruning is
        // rare in practice; kept for correctness with future resolution changes)
        var valid = slots.filter { $0.conc >= minConcentration }
        if valid.isEmpty {
            valid = [slots.max(by: { $0.conc < $1.conc })!]
        }

        let sum = valid.reduce(0.0) { $0 + $1.conc }
        if sum > 0 { valid = valid.map { ($0.globalIdx, $0.conc / sum) } }

        let components = valid.map { (gIdx, conc) in
            RecipeComponent(
                pigmentId:   database.pigments[gIdx].id,
                pigmentName: database.pigments[gIdx].name,
                concentration: conc
            )
        }.sorted { $0.concentration > $1.concentration }

        return PigmentRecipe(
            components: components,
            predictedColor: entry.color,
            deltaE: sqrtf(distSq)
        )
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

        // With fractions of 1/8, no continuous Nelder-Mead interpolation is done.
        let finalIndices = bestEntry.pigmentIndices
        let finalConcentrations = bestEntry.concentrations

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
        minConcentration: Float,
        lookupTable: PigmentLookupTable? = nil
    ) -> [PigmentData] {
        var currentTubes = seedTubes
        guard !currentTubes.isEmpty, currentTubes.count < allPigments.count else { return currentTubes }

        let sortedIndices = clusterWeights.enumerated()
            .sorted { $0.element > $1.element }
            .map { $0.offset }

        let topColors  = sortedIndices.map { targetColors[$0] }
        let topWeights = sortedIndices.map { clusterWeights[$0] }
        let clamped    = min(max(maxPigments, 1), 3)

        func evaluateApproxError(tubes: [PigmentData]) -> Float {
            var totalError: Float = 0

            if let table = lookupTable {
                // Fast path: index into the precomputed table — no KMM math.
                let gIdx = globalIndices(for: tubes, in: database)
                for (i, target) in topColors.enumerated() {
                    if let (_, dSq) = table.findBest(
                        for: target,
                        enabledGlobalIndices: gIdx,
                        maxPigments: clamped
                    ) {
                        totalError += sqrtf(dSq) * topWeights[i]
                    }
                }
            } else {
                // Fallback: build a runtime lookup for this tube subset.
                let lookup = buildLookupTable(pigments: tubes, database: database, maxPigments: clamped)
                for (i, target) in topColors.enumerated() {
                    var bestDist = Float.greatestFiniteMagnitude
                    for entry in lookup {
                        let d = oklabDistance(target, entry.color)
                        if d < bestDist { bestDist = d }
                    }
                    totalError += sqrtf(bestDist) * topWeights[i]
                }
            }
            return totalError
        }
        
        var improved = true
        var swapCount = 0
        let maxSwaps = max(3, currentTubes.count * 2) // scale up search budget with tube complexity
        
        while improved && swapCount < maxSwaps { // bounded search budget
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
