import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - AttachmentView

struct AttachmentView: View {
    @Binding var attachmentURLs: [URL]
    @Binding var pastedTexts: [String]

    @State private var showingFileImporter = false
    @State private var urlFieldText = ""
    @State private var urlFieldError: String? = nil

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Zone 1: File picker
                filePicker

                Divider()

                // Zone 2: URL field
                urlField

                Divider()

                // Zone 3: Paste zone
                pasteZone
            }
            .padding(8)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.text, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        attachmentURLs.append(url)
                    }
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Subviews

    private var filePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Add file…") {
                showingFileImporter = true
            }

            if !attachmentURLs.isEmpty {
                ForEach(Array(attachmentURLs.enumerated()), id: \.offset) { index, url in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            attachmentURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Paste a URL…", text: $urlFieldText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addURL() }

                Button("Add") {
                    addURL()
                }
            }

            if let error = urlFieldError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pasteZone: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Paste text") {
                if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                    pastedTexts.append(pasted)
                }
            }

            if !pastedTexts.isEmpty {
                Text("\(pastedTexts.count) block\(pastedTexts.count == 1 ? "" : "s") pasted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func addURL() {
        let trimmed = urlFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            urlFieldError = "Invalid URL — please include scheme (e.g. https://)"
            return
        }

        urlFieldError = nil
        attachmentURLs.append(url)
        urlFieldText = ""
    }
}
