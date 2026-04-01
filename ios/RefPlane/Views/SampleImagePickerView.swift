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
    @State private var showLoadError = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sampleImages) { sample in
                        let image = UIImage(named: sample.assetName)
                        SampleThumbnailButton(sample: sample, image: image) {
                            if let image {
                                onImageSelected(image)
                                dismiss()
                            } else {
                                showLoadError = true
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
            .alert("Unable to Load Sample", isPresented: $showLoadError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The sample image could not be loaded. Please try a different one.")
            }
        }
    }
}

private struct SampleThumbnailButton: View {
    let sample: SampleItem
    let image: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipped()
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 110)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }

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
