import SwiftUI

private struct SampleItem: Identifiable {
    let id: String
    let displayName: String
    let assetName: String
    let description: String
}

private let sampleImages: [SampleItem] = [
    SampleItem(
        id: "colorchecker",
        displayName: "Color Checker",
        assetName: "sample-colorchecker",
        description: "Synthetic reference chart for evaluating color accuracy"
    ),
    SampleItem(
        id: "portrait",
        displayName: "Portrait",
        assetName: "sample-portrait",
        description: "Real-world subject for tonal and value studies"
    ),
    SampleItem(
        id: "landscape",
        displayName: "Landscape",
        assetName: "sample-landscape",
        description: "Wide scene for color and composition studies"
    ),
]

struct SampleImagePickerView: View {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failedSample: SampleItem?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sampleImages) { sample in
                        SampleThumbnailButton(sample: sample) {
                            if let image = UIImage(named: sample.assetName) {
                                onImageSelected(image)
                                dismiss()
                            } else {
                                failedSample = sample
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Sample Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
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
}

private struct SampleThumbnailButton: View {
    let sample: SampleItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(sample.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .clipped()
                    .cornerRadius(10)

                Text(sample.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text(sample.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sample.displayName)
        .accessibilityHint(sample.description)
    }
}
