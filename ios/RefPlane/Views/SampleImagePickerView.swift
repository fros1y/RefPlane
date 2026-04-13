import SwiftUI
import ImageIO

private struct SampleItem: Identifiable {
    let id: String
    let displayName: String
    let assetName: String
    let description: String
    var bundledFilename: String? = nil
    var bundledTypeIdentifier: String? = nil
}

private let sampleImages: [SampleItem] = [
    SampleItem(
        id: "chair-spatial",
        displayName: "Chair Spatial",
        assetName: "sample-statue",
        description: "Spatial HEIC sample with embedded depth/disparity for depth-aware workflows",
        bundledFilename: "chair-spatial",
        bundledTypeIdentifier: "public.heic"
    ),
    SampleItem(
        id: "statue",
        displayName: "Sculpture",
        assetName: "sample-statue",
        description: "Classical bust study for planes, edges, and form shadows"
    ),
    SampleItem(
        id: "eye",
        displayName: "Eye Close-Up",
        assetName: "sample-eye",
        description: "Macro reference for iris texture and subtle skin values"
    ),
    SampleItem(
        id: "still-life",
        displayName: "Still Life",
        assetName: "sample-still-life",
        description: "Studio setup with fruit and cloth for color and material studies"
    ),
]

struct SampleImagePickerView: View {
    let onImageSelected: (ImportedImagePayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failedSample: SampleItem?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sampleImages) { sample in
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
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sample Images")
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
                embeddedDepthMap: embeddedDepth
            )
        }

        guard let image = UIImage(named: sample.assetName) else { return nil }
        return ImportedImagePayload(image: image)
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

                Text(sample.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(sample.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        .accessibilityLabel(sample.displayName)
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

#Preview("Samples") {
    SampleImagePickerView { _ in }
}
