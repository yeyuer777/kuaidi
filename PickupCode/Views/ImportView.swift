import SwiftUI
import PhotosUI
import UIKit

struct ImportView: View {

    @EnvironmentObject private var store: PickupStore

    @State private var text = ""
    @State private var pendingSource: PickupItem.Source = .paste
    @State private var preview: [PickupItem] = []
    @State private var photoSelection: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var isRecognizing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    inputCard
                    toolButtons
                    previewSection
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(Theme.pageBackground)
            .navigationTitle("导入")
            .onChange(of: text) { newValue in
                refreshPreview(newValue)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoSelection,
                matching: .images
            )
            .onChange(of: photoSelection) { newItem in
                guard let newItem else { return }
                Task { await recognize(newItem) }
            }
            .alert("识别失败", isPresented: errorBinding) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 输入区

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("短信内容")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !text.isEmpty {
                    Button("清空") {
                        text = ""
                        preview = []
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("把快递短信整段粘进来，多条也可以。\n比如：\n【菜鸟驿站】您的包裹已到……取件码：8-2-3021")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.subheadline)
                    .frame(minHeight: 132)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, -4)
            }
        }
        .cardStyle()
    }

    private var toolButtons: some View {
        HStack(spacing: 10) {
            toolButton(
                title: "粘贴剪贴板",
                icon: "doc.on.clipboard",
                disabled: false
            ) {
                if let clip = UIPasteboard.general.string, !clip.isEmpty {
                    pendingSource = .paste
                    text = clip
                } else {
                    store.toast = "剪贴板是空的"
                }
            }

            toolButton(
                title: isRecognizing ? "识别中…" : "选截图识别",
                icon: isRecognizing ? "hourglass" : "text.viewfinder",
                disabled: isRecognizing
            ) {
                showPhotoPicker = true
            }
        }
    }

    private func toolButton(
        title: String,
        icon: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
            .foregroundStyle(disabled ? Color.secondary : Theme.accent)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - 预览

    @ViewBuilder
    private var previewSection: some View {
        if !preview.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("识别到 \(preview.count) 个取件码")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(preview) { item in
                    previewRow(item)
                }

                Button {
                    saveAll()
                } label: {
                    Label("全部保存", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Theme.accent)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("这段内容里没找到取件码。确认一下是不是取件通知，或者换个格式重试。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func previewRow(_ item: PickupItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.code)
                    .font(Theme.codeFontSmall)
                    .foregroundStyle(Theme.accent)
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                    if !item.displaySubtitle.isEmpty {
                        Text("·")
                        Text(item.displaySubtitle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let address = item.address {
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        }
        .cardStyle(padding: 14)
    }

    // MARK: - 动作

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func refreshPreview(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = []
            return
        }
        preview = PickupParser.parse(text: trimmed, source: pendingSource)
    }

    private func saveAll() {
        let added = store.add(preview)
        if added > 0 {
            store.toast = "已保存 \(added) 个取件码"
        } else {
            store.toast = "这些取件码已经在列表里了"
        }
        text = ""
        preview = []
    }

    private func recognize(_ item: PhotosPickerItem) async {
        await MainActor.run { isRecognizing = true }
        defer {
            Task { @MainActor in isRecognizing = false }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    errorMessage = "图片读取失败"
                    photoSelection = nil
                }
                return
            }

            let recognized = try await TextRecognizer.recognize(image: image)
            await MainActor.run {
                pendingSource = .ocr
                text = recognized
                photoSelection = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                photoSelection = nil
            }
        }
    }
}
