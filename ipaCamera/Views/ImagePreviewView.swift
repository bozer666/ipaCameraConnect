import SwiftUI

/// 全屏图片预览视图
///
/// 显示照片原图，支持缩放手势和滑动关闭。
struct ImagePreviewView: View {
    let content: PhotoContent
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isLoading = true
    @State private var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    private let contentService = ContentService()
    private let cacheManager = ImageCacheManager.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景（黑色）
                Color.black
                    .ignoresSafeArea()

                // 图片
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .gesture(magnificationGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                scale = scale == 1.0 ? 2.5 : 1.0
                                if scale == 1.0 {
                                    offset = .zero
                                }
                            }
                        }
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("图片加载失败")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                // 关闭按钮
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(16)
                }
            }
            .overlay(alignment: .bottom) {
                // 底部信息栏
                infoBar
                    .opacity(scale > 1.0 ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: scale)
            }
        }
        .ignoresSafeArea()
        .task {
            await loadImage()
        }
    }

    // MARK: - 底部信息

    private var infoBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(content.dimensionsDescription)
                        .font(.caption2)
                    Text(content.formattedSize)
                        .font(.caption2)
                    if content.isRaw {
                        Text("RAW")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            if let date = content.date {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                // 向下滑动关闭
                if value.translation.height > 100 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3)) {
                        offset = .zero
                    }
                }
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                scale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3)) {
                        scale = 1.0
                        offset = .zero
                    }
                    lastScale = 1.0
                }
            }
    }

    // MARK: - 加载

    private func loadImage() async {
        isLoading = true

        // 先检查缓存
        let cacheKey = ImageCacheManager.originalKey(for: content.id)
        if let cachedImage = cacheManager.getImage(forKey: cacheKey) {
            image = cachedImage
            isLoading = false
            return
        }

        // 从相机加载
        do {
            let loadedImage = try await contentService.getOriginalImage(id: content.id)
            cacheManager.setImage(loadedImage, forKey: cacheKey, toDisk: false)
            image = loadedImage
        } catch {
            logger.warning("⚠️ 原图加载失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private let logger = Logger(subsystem: "com.ipaCamera", category: "ImagePreview")
}

#Preview {
    ImagePreviewView(
        content: PhotoContent(
            id: "100CANON/IMG_0001.JPG",
            name: "IMG_0001.JPG",
            size: 4_567_890,
            date: Date(),
            width: 6960,
            height: 4640,
            isRaw: false,
            directory: "/100CANON"
        )
    )
}
