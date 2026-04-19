import ImageIO
import SwiftUI

private struct SampleItem: Identifiable {
    let id: String
    let category: String
    let displayName: String
    let assetName: String
    let description: String
    let recommendedMode: RefPlaneMode
    let suggestedAbstractionStrength: Double
    let suggestedBackgroundMode: BackgroundMode?
    var bundledFilename: String? = nil
    var bundledTypeIdentifier: String? = nil
}

private let sampleImages: [SampleItem] = [
    SampleItem(
        id: "chair-spatial-value",
        category: "Portraits",
        displayName: "Chair Spatial",
        assetName: "sample-statue",
        description: "Start in Value to see the big planes, then use depth to knock back the room.",
        recommendedMode: .value,
        suggestedAbstractionStrength: 0.2,
        suggestedBackgroundMode: .compress,
        bundledFilename: "chair-spatial",
        bundledTypeIdentifier: "public.heic"
    ),
    SampleItem(
        id: "statue-tonal",
        category: "Portraits",
        displayName: "Sculpture",
        assetName: "sample-statue",
        description: "A clean tonal study for reading form without committing to banded values yet.",
        recommendedMode: .tonal,
        suggestedAbstractionStrength: 0.15,
        suggestedBackgroundMode: BackgroundMode.none
    ),
    SampleItem(
        id: "eye-value",
        category: "Portraits",
        displayName: "Eye Close-Up",
        assetName: "sample-eye",
        description: "Use Value to simplify subtle skin shifts into paintable value bands.",
        recommendedMode: .value,
        suggestedAbstractionStrength: 0.25,
        suggestedBackgroundMode: BackgroundMode.none
    ),
    SampleItem(
        id: "still-life-color",
        category: "Still Life",
        displayName: "Still Life Color",
        assetName: "sample-still-life",
        description: "Jump straight to Color to preview palette recipes for local color relationships.",
        recommendedMode: .color,
        suggestedAbstractionStrength: 0.2,
        suggestedBackgroundMode: BackgroundMode.none
    ),
    SampleItem(
        id: "still-life-value",
        category: "Still Life",
        displayName: "Still Life Value",
        assetName: "sample-still-life",
        description: "Block in the fruit and cloth with a value map before worrying about hue.",
        recommendedMode: .value,
        suggestedAbstractionStrength: 0.25,
        suggestedBackgroundMode: BackgroundMode.none
    ),
    SampleItem(
        id: "still-life-tonal",
        category: "Still Life",
        displayName: "Still Life Tonal",
        assetName: "sample-still-life",
        description: "A softer tonal pass for checking value grouping without hard band edges.",
        recommendedMode: .tonal,
        suggestedAbstractionStrength: 0.2,
        suggestedBackgroundMode: BackgroundMode.none
    ),
    SampleItem(
        id: "chair-spatial-depth",
        category: "Spatial",
        displayName: "Depth Portrait",
        assetName: "sample-statue",
        description: "This one is all about the spatial workflow: isolate the subject, then paint.",
        recommendedMode: .value,
        suggestedAbstractionStrength: 0.2,
        suggestedBackgroundMode: .blur,
        bundledFilename: "chair-spatial",
        bundledTypeIdentifier: "public.heic"
    ),
    SampleItem(
        id: "chair-spatial-color",
        category: "Spatial",
        displayName: "Depth Color",
        assetName: "sample-statue",
        description: "Keep the subject forward while using Color mode to study simplified palette notes.",
        recommendedMode: .color,
        suggestedAbstractionStrength: 0.15,
        suggestedBackgroundMode: .compress,
        bundledFilename: "chair-spatial",
        bundledTypeIdentifier: "public.heic"
    ),
    SampleItem(
        id: "statue-contours",
        category: "Edges & Form",
        displayName: "Contour Sculpture",
        assetName: "sample-statue",
        description: "A form-study reference that pairs well with contours once background depth is active.",
        recommendedMode: .tonal,
        suggestedAbstractionStrength: 0.1,
        suggestedBackgroundMode: .compress
    ),
    SampleItem(
        id: "eye-simplify",
        category: "Edges & Form",
        displayName: "Simplified Eye",
        assetName: "sample-eye",
        description: "Use simplification first to find the largest shapes before refining features.",
        recommendedMode: .original,
        suggestedAbstractionStrength: 0.35,
        suggestedBackgroundMode: BackgroundMode.none
    ),
]

struct SampleImagePickerView: View {
    let onImageSelected: (ImportedImagePayload) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var failedSample: SampleItem?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    private var categories: [(title: String, samples: [SampleItem])] {
        Dictionary(grouping: sampleImages, by: \.category)
            .keys
            .sorted()
            .map { title in
                (
                    title,
                    sampleImages.filter { $0.category == title }
                )
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !state.sessionStore.sessions.isEmpty {
                        recentSection
                    }

                    ForEach(categories, id: \.title) { category in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(category.title)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(category.samples) { sample in
                                    SampleThumbnailButton(sample: sample) {
                                        if let payload = payloadForSample(sample) {
                                            onImageSelected(payload)
                                            dismiss()
                                        } else {
                                            failedSample = sample
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Samples & Recent")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("sample-picker.grid")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("sample-picker.cancel")
                }
            }
            .alert(
                "Unable to Load Sample",
                isPresented: Binding(
                    get: { failedSample != nil },
                    set: { if !$0 { failedSample = nil } }
                )
            ) {
                Button("OK", role: .cancel) { failedSample = nil }
            } message: {
                if let name = failedSample?.displayName {
                    Text("\"\(name)\" could not be loaded. Please try a different sample.")
                } else {
                    Text("The sample image could not be loaded. Please try a different one.")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(state.sessionStore.sessions.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(state.sessionStore.sessions) { session in
                        SessionHistoryCard(session: session)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func payloadForSample(_ sample: SampleItem) -> ImportedImagePayload? {
        if let filename = sample.bundledFilename,
           let url = Bundle.main.url(forResource: filename, withExtension: "heic"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            let metadata = readMetadata(
                from: data,
                fallbackTypeIdentifier: sample.bundledTypeIdentifier ?? "public.heic"
            )
            let embeddedDepth = DepthEstimator.extractEmbeddedDepth(from: data)
            return ImportedImagePayload(
                image: image,
                metadata: metadata,
                embeddedDepthMap: embeddedDepth,
                referenceName: sample.displayName,
                sampleIdentifier: sample.id,
                suggestedMode: sample.recommendedMode,
                suggestedAbstractionStrength: sample.suggestedAbstractionStrength,
                suggestedBackgroundMode: sample.suggestedBackgroundMode
            )
        }

        guard let image = UIImage(named: sample.assetName) else { return nil }
        return ImportedImagePayload(
            image: image,
            referenceName: sample.displayName,
            sampleIdentifier: sample.id,
            suggestedMode: sample.recommendedMode,
            suggestedAbstractionStrength: sample.suggestedAbstractionStrength,
            suggestedBackgroundMode: sample.suggestedBackgroundMode
        )
    }

    private func readMetadata(
        from data: Data,
        fallbackTypeIdentifier: String
    ) -> SourceImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return SourceImageMetadata(
                properties: [:],
                uniformTypeIdentifier: fallbackTypeIdentifier
            )
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let typeIdentifier = (CGImageSourceGetType(source) as String?) ?? fallbackTypeIdentifier
        return SourceImageMetadata(
            properties: properties,
            uniformTypeIdentifier: typeIdentifier
        )
    }
}

private struct SampleThumbnailButton: View {
    let sample: SampleItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    thumbnailImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: 132)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(height: 132)

                HStack(alignment: .top) {
                    Text(sample.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    SampleModeBadge(mode: sample.recommendedMode)
                }

                Text(sample.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sample.displayName), \(sample.recommendedMode.label)")
        .accessibilityHint(sample.description)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sample-picker.\(sample.id)")
    }

    private var thumbnailImage: Image {
        if let filename = sample.bundledFilename,
           let url = Bundle.main.url(forResource: filename, withExtension: "heic"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return Image(uiImage: image)
        }

        return Image(sample.assetName)
    }
}

private struct SessionHistoryCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let session: StoredSession

    var body: some View {
        Button {
            state.restoreSession(session)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let image = state.sessionStore.image(for: session) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 180, height: 112)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 180, height: 112)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.referenceName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(session.snapshot.activeMode.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                state.sessionStore.deleteSession(id: session.id)
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
    }
}

private struct SampleModeBadge: View {
    let mode: RefPlaneMode

    var body: some View {
        Label(mode.label, systemImage: mode.iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05), in: Capsule())
    }
}

#Preview("Samples") {
    SampleImagePickerView { _ in }
        .environment(AppState())
}
