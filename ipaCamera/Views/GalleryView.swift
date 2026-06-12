import SwiftUI

/// 图库视图
///
/// 以 3 列网格展示相机照片缩略图，支持下拉刷新、滚动加载更多、多选下载/删除。
struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @State private var selectedPreview: PhotoContent?
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.contents.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    scrollContent
                }

                // 加载指示器
                if viewModel.isLoading && viewModel.contents.isEmpty {
                    ProgressView("加载中...")
                        .scaleEffect(1.2)
                }

                // 批量下载进度浮层
                if viewModel.isDownloading {
                    downloadProgressOverlay
                }
            }
            .navigationTitle("照片图库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.contents.isEmpty && !viewModel.isDownloading {
                        Button(viewModel.isSelecting ? "取消" : "选择") {
                            viewModel.toggleSelectMode()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // 底部操作栏（选择模式下）
                if viewModel.isSelecting && !viewModel.isDownloading {
                    selectionBar
                }
            }
            .sheet(item: $selectedPreview) { content in
                ImagePreviewView(content: content)
            }
            // 错误提示
            .alert("错误", isPresented: $viewModel.showError) {
                Button("重试") {
                    Task { await viewModel.loadFirstPage() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
            // 删除确认
            .alert("确认删除", isPresented: $viewModel.showDeleteConfirmation) {
                Button("删除 \(viewModel.selectedIds.count) 张", role: .destructive) {
                    Task { await viewModel.confirmDeleteSelected() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将从相机 SD 卡中永久删除 \(viewModel.selectedIds.count) 张照片，此操作不可撤销。")
            }
            // 下载结果
            .alert("下载完成", isPresented: $viewModel.showDownloadResult) {
                Button("好", role: .cancel) {}
            } message: {
                Text(viewModel.downloadResultMessage ?? "")
            }
            .task {
                await viewModel.loadFirstPage()
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("暂无照片")
                .font(.title2)
                .fontWeight(.medium)
            Text("相机 SD 卡中未找到照片")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 下载进度浮层

    private var downloadProgressOverlay: some View {
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("正在下载...")
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView(value: viewModel.downloadProgress)
                        .tint(.white)
                        .frame(width: 200)
                    Text("\(Int(viewModel.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
    }

    // MARK: - 滚动内容

    private var scrollContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.contents) { content in
                    thumbnailCell(content: content)
                        .task {
                            await viewModel.loadThumbnail(for: content.id)
                        }
                        .onTapGesture {
                            if viewModel.isSelecting {
                                viewModel.toggleSelection(for: content.id)
                            } else {
                                selectedPreview = content
                            }
                        }
                        .onLongPressGesture {
                            if !viewModel.isSelecting {
                                viewModel.isSelecting = true
                                viewModel.toggleSelection(for: content.id)
                            }
                        }
                }

                // 加载更多指示器
                if viewModel.hasMore {
                    Color.clear
                        .frame(height: 50)
                        .task {
                            await viewModel.loadMore()
                        }
                        .overlay {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(.secondary)
                            }
                        }
                }
            }
            .padding(.horizontal, 1)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - 缩略图单元格

    private func thumbnailCell(content: PhotoContent) -> some View {
        ZStack(alignment: .topTrailing) {
            // 缩略图
            Group {
                if let image = viewModel.thumbnails[content.id] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                        .task {
                            await viewModel.loadThumbnail(for: content.id)
                        }
                }
            }
            .frame(minHeight: 120)
            .clipped()

            // 下载状态标记
            if let state = viewModel.downloadStates[content.id] {
                downloadBadge(state: state)
            }

            // 选中标记（选择模式下）
            if viewModel.isSelecting {
                selectionBadge(isSelected: viewModel.selectedIds.contains(content.id))
            }

            // RAW 标记
            if content.isRaw {
                rawBadge
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if !viewModel.isSelecting {
                Text(content.name)
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.4))
                    .padding(2)
            }
        }
    }

    // MARK: - 徽章

    private func downloadBadge(state: GalleryViewModel.DownloadState) -> some View {
        VStack {
            switch state {
            case .downloading:
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
                    .padding(4)
                    .background(Circle().fill(.blue.opacity(0.8)))
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(4)
                    .background(Circle().fill(.white.opacity(0.9)))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Circle().fill(.white.opacity(0.9)))
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .padding(4)
    }

    private func selectionBadge(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? .blue : .white.opacity(0.7))
                .frame(width: 24, height: 24)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(6)
    }

    private var rawBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("RAW")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6))
                    .cornerRadius(2)
                    .padding(4)
            }
        }
    }

    // MARK: - 底部操作栏

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                // 已选数量
                Text("已选 \(viewModel.selectedIds.count) 张")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // 全选/取消
                Button(viewModel.selectedIds.count == viewModel.contents.count ? "取消全选" : "全选") {
                    if viewModel.selectedIds.count == viewModel.contents.count {
                        viewModel.deselectAll()
                    } else {
                        viewModel.selectAll()
                    }
                }
                .font(.subheadline)
                .disabled(viewModel.selectedIds.isEmpty)

                // 下载到手机
                Button {
                    Task { await viewModel.downloadSelected() }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                }
                .disabled(viewModel.selectedIds.isEmpty)

                // 删除
                Button(role: .destructive) {
                    viewModel.requestDeleteSelected()
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.subheadline)
                }
                .disabled(viewModel.selectedIds.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }
}

#Preview {
    GalleryView()
}
