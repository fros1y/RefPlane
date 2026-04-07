import ImageIO
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImagePickerView: UIViewControllerRepresentable {
    let onImageSelected: (ImportedImagePayload) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView

        init(parent: ImagePickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }

            let provider = result.itemProvider
            if let typeIdentifier = provider.registeredTypeIdentifiers.first(
                where: { UTType($0)?.conforms(to: .image) == true }
            ) {
                loadImageData(from: provider, typeIdentifier: typeIdentifier)
            } else {
                loadFallbackImage(from: provider)
            }
        }

        private func loadImageData(from provider: NSItemProvider, typeIdentifier: String) {
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                guard let self else { return }

                if let data,
                   let image = UIImage(data: data) {
                    let metadata = Self.readMetadata(from: data, fallbackTypeIdentifier: typeIdentifier)
                    let embeddedDepth = DepthEstimator.extractEmbeddedDepth(from: data)
                    self.deliverSelection(
                        ImportedImagePayload(
                            image: image,
                            metadata: metadata,
                            embeddedDepthMap: embeddedDepth
                        )
                    )
                } else {
                    self.loadFallbackImage(from: provider)
                }
            }
        }

        private func loadFallbackImage(from provider: NSItemProvider) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else { return }
                self?.deliverSelection(ImportedImagePayload(image: image))
            }
        }

        private func deliverSelection(_ payload: ImportedImagePayload) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onImageSelected(payload)
            }
        }

        private static func readMetadata(
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
}
