import SwiftUI

struct BarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable private var store = ClipboardStore.shared
    @Bindable private var settings = Settings.shared
    @Bindable private var updater = UpdateManager.shared

    private var palette: ThemePalette { Theme.palette(for: colorScheme) }

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground)
            palette.panelTint.swiftUIColor
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                topBar
                strip
            }
        }
        .clipShape(RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight]))
        .ignoresSafeArea()
        .id(settings.language)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            syncButton
            searchIndicator
            PinboardTabs()
                .layoutPriority(1)
            Spacer(minLength: 8)
            if updater.showInClipboardBar, let release = updater.availableRelease {
                updateButton(release)
            }
            moreMenu
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var syncButton: some View {
        Button {
            AppController.shared.toggleICloudSync()
        } label: {
            Image(systemName: settings.iCloudSync ? "checkmark.icloud.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(settings.iCloudSync
                    ? palette.selection.swiftUIColor
                    : palette.textSecondary.swiftUIColor)
        }
        .buttonStyle(.plain)
        .help(settings.iCloudSync ? L10n.iCloudSyncOn : L10n.turnOnICloudSync)
    }

    private var searchIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(store.searchText.isEmpty
                    ? palette.textSecondary.swiftUIColor
                    : palette.textPrimary.swiftUIColor)
            if !store.searchText.isEmpty {
                Text(store.searchText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.textPrimary.swiftUIColor)
                    .lineLimit(1)
                Button { store.searchText = ""; store.selectFirst() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textTertiary.swiftUIColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, store.searchText.isEmpty ? 0 : 10)
        .frame(height: 30)
        .background(
            store.searchText.isEmpty
                ? Color.clear
                : palette.fieldBackground.swiftUIColor,
            in: Capsule()
        )
        .animation(.easeOut(duration: 0.15), value: store.searchText.isEmpty)
    }

    private var moreMenu: some View {
        Menu {
            Button(L10n.checkForUpdates) {
                AppController.shared.checkForUpdatesManually()
            }
            .disabled(updater.activity == .checking || updater.isInstalling)
            Divider()
            Button(L10n.settings) { AppController.shared.showSettings() }
            Button(L10n.clearHistory) { store.clearHistory() }
            Divider()
            Button(L10n.aboutPesty) { AppController.shared.showAbout() }
            Button(L10n.quitPesty) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34)
        .fixedSize()
    }

    private func updateButton(_ release: AppRelease) -> some View {
        Button {
            updater.installAvailableUpdate()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: updater.isInstalling
                      ? "arrow.triangle.2.circlepath"
                      : "arrow.down.circle.fill")
                Text(updateButtonTitle(release))
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(palette.selection.swiftUIColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(updater.isInstalling)
        .help(L10n.updateAvailableMessage(release.version))
        .accessibilityIdentifier("pesty-update-button")
    }

    private func updateButtonTitle(_ release: AppRelease) -> String {
        switch updater.activity {
        case .downloading:
            return L10n.downloadingUpdate(release.version)
        case .installing:
            return L10n.installingUpdate(release.version)
        default:
            return L10n.updateToVersion(release.version)
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.cardSpacing) {
                    ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                        ClipCardView(item: item,
                                     index: index,
                                     selected: item.id == store.selectedID)
                            .frame(height: cardHeight)
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.92).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: store.visibleItems.count)
                .frame(height: cardHeight + 22)
            }
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .overlay { if store.visibleItems.isEmpty { emptyState } }
        }
        .frame(maxHeight: .infinity)
    }

    private var cardHeight: CGFloat {
        max(160, CGFloat(settings.barHeight) - 78)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.textTertiary.swiftUIColor)
            Text(store.searchText.isEmpty
                 ? L10n.nothingCopied
                 : L10n.noMatches(store.searchText))
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary.swiftUIColor)
        }
    }
}

struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
}
