import AppKit
import SwiftUI

private final class HorizontalWheelScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = event.scrollingDeltaX
        let verticalDelta = event.scrollingDeltaY
        guard abs(verticalDelta) > abs(horizontalDelta),
              abs(verticalDelta) > 0.01,
              let documentView else {
            super.scrollWheel(with: event)
            return
        }

        var origin = contentView.bounds.origin
        let maximumX = max(0, documentView.bounds.width - contentView.bounds.width)
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 28
        origin.x = min(
            maximumX,
            max(0, origin.x - verticalDelta * multiplier)
        )
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

@MainActor
enum VirtualizedClipStripMetrics {
    private(set) static var createdCellCount = 0
    private(set) static var maximumVisibleCellCount = 0
    private(set) static var configuredItemIDs = Set<UUID>()
    private(set) static var contentIndexRebuildCount = 0
    private(set) static var lastSelectedItemID: UUID?
    private(set) static var lastSelectedConfigurationTime: CFAbsoluteTime?

    static func reset() {
        createdCellCount = 0
        maximumVisibleCellCount = 0
        configuredItemIDs.removeAll(keepingCapacity: true)
        contentIndexRebuildCount = 0
        lastSelectedItemID = nil
        lastSelectedConfigurationTime = nil
    }

    static func recordCreatedCell() {
        createdCellCount += 1
    }

    static func recordConfiguredItem(_ id: UUID, selected: Bool) {
        configuredItemIDs.insert(id)
        if selected {
            lastSelectedItemID = id
            lastSelectedConfigurationTime = CFAbsoluteTimeGetCurrent()
        }
    }

    static func recordContentIndexRebuild() {
        contentIndexRebuildCount += 1
    }

    static func recordVisibleCellCount(_ count: Int) {
        maximumVisibleCellCount = max(maximumVisibleCellCount, count)
    }
}

struct VirtualizedClipStrip: NSViewRepresentable {
    let items: [ClipItem]
    let contentRevision: UInt64
    let selectedID: UUID?
    let cardHeight: CGFloat
    let language: AppLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = Theme.cardSpacing
        layout.minimumLineSpacing = Theme.cardSpacing
        layout.sectionInset = NSEdgeInsets(top: 4, left: 18, bottom: 18, right: 18)
        layout.itemSize = NSSize(
            width: Theme.cardWidth,
            height: min(cardHeight, 160)
        )

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = context.coordinator
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(
            ClipCollectionViewItem.self,
            forItemWithIdentifier: ClipCollectionViewItem.reuseIdentifier
        )

        let scrollView = HorizontalWheelScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = collectionView

        context.coordinator.attach(collectionView: collectionView)
        context.coordinator.update(
            items: items,
            contentRevision: contentRevision,
            selectedID: selectedID,
            cardHeight: cardHeight,
            language: language
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            items: items,
            contentRevision: contentRevision,
            selectedID: selectedID,
            cardHeight: cardHeight,
            language: language
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource {
        private weak var collectionView: NSCollectionView?
        private var items: [ClipItem] = []
        private var itemIDs: [UUID] = []
        private var indexByID: [UUID: Int] = [:]
        private var contentRevision: UInt64?
        private var selectedID: UUID?
        private var cardHeight: CGFloat = 0
        private var effectiveCardHeight: CGFloat = 0
        private var language: AppLanguage = .systemDefault
        private var presentationObserver: NSObjectProtocol?

        func attach(collectionView: NSCollectionView) {
            self.collectionView = collectionView
            presentationObserver = NotificationCenter.default.addObserver(
                forName: .pestyBarDidFinishPresentation,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshAfterPresentation()
                }
            }
        }

        func detach() {
            if let presentationObserver {
                NotificationCenter.default.removeObserver(presentationObserver)
            }
            presentationObserver = nil
            collectionView = nil
        }

        func update(
            items newItems: [ClipItem],
            contentRevision newContentRevision: UInt64,
            selectedID newSelectedID: UUID?,
            cardHeight newCardHeight: CGFloat,
            language newLanguage: AppLanguage
        ) {
            guard let collectionView else { return }

            let contentChanged = newContentRevision != contentRevision
            let selectedChanged = newSelectedID != selectedID
            let layoutChanged = newCardHeight != cardHeight
            let languageChanged = newLanguage != language
            let previousSelectedID = selectedID

            items = newItems
            if contentChanged {
                VirtualizedClipStripMetrics.recordContentIndexRebuild()
                let newIDs = newItems.map(\.id)
                itemIDs = newIDs
                indexByID = Dictionary(
                    uniqueKeysWithValues: newIDs.enumerated().map { ($1, $0) }
                )
            }
            contentRevision = newContentRevision
            selectedID = newSelectedID
            cardHeight = newCardHeight
            language = newLanguage

            let effectiveHeightChanged = updateItemSizeIfPossible()

            if contentChanged || layoutChanged || languageChanged || effectiveHeightChanged {
                collectionView.reloadData()
            } else if selectedChanged {
                var changed = Set<IndexPath>()
                if let previousSelectedID, let index = indexByID[previousSelectedID] {
                    changed.insert(IndexPath(item: index, section: 0))
                }
                if let newSelectedID, let index = indexByID[newSelectedID] {
                    changed.insert(IndexPath(item: index, section: 0))
                }
                if !changed.isEmpty {
                    collectionView.reloadItems(at: changed)
                }
            }

            recordVisibleCellCount()
            if contentChanged || selectedChanged || layoutChanged {
                ensureSelectedIsVisibleAfterLayout()
            }
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            1
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            guard indexPath.item < items.count else {
                return NSCollectionViewItem()
            }
            let viewItem = collectionView.makeItem(
                withIdentifier: ClipCollectionViewItem.reuseIdentifier,
                for: indexPath
            )
            guard let cell = viewItem as? ClipCollectionViewItem else {
                return viewItem
            }
            let item = items[indexPath.item]
            cell.configure(
                item: item,
                index: indexPath.item,
                selected: item.id == selectedID,
                height: effectiveCardHeight > 0
                    ? effectiveCardHeight
                    : cardHeight
            )
            VirtualizedClipStripMetrics.recordConfiguredItem(
                item.id,
                selected: item.id == selectedID
            )
            recordVisibleCellCount()
            return cell
        }

        private func ensureSelectedIsVisibleAfterLayout() {
            let expectedID = selectedID
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.selectedID == expectedID,
                      let expectedID,
                      let index = self.indexByID[expectedID],
                      let collectionView = self.collectionView else { return }
                collectionView.layoutSubtreeIfNeeded()
                if self.updateItemSizeIfPossible() {
                    collectionView.reloadData()
                    collectionView.layoutSubtreeIfNeeded()
                }
                guard let attributes = collectionView.collectionViewLayout?
                    .layoutAttributesForItem(
                        at: IndexPath(item: index, section: 0)
                    ) else { return }
                // A click can only target a card that is already visible. Keep
                // the user's scroll position stable in that case. Keyboard
                // navigation to an off-screen card should reveal it with the
                // smallest possible horizontal movement instead of centering.
                guard !collectionView.visibleRect.intersects(attributes.frame) else {
                    self.recordVisibleCellCount()
                    return
                }
                guard let scrollView = collectionView.enclosingScrollView else {
                    return
                }
                let visibleRect = collectionView.visibleRect
                let requestedX = attributes.frame.maxX <= visibleRect.minX
                    ? attributes.frame.minX
                    : attributes.frame.maxX - visibleRect.width
                let maximumX = max(
                    0,
                    collectionView.bounds.width - visibleRect.width
                )
                var origin = scrollView.contentView.bounds.origin
                origin.x = min(maximumX, max(0, requestedX))
                scrollView.contentView.scroll(to: origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                collectionView.layoutSubtreeIfNeeded()
                self.recordVisibleCellCount()
            }
        }

        private func refreshAfterPresentation() {
            guard let collectionView else { return }
            if updateItemSizeIfPossible() {
                collectionView.reloadData()
            }
            collectionView.collectionViewLayout?.invalidateLayout()
            collectionView.layoutSubtreeIfNeeded()
            ensureSelectedIsVisibleAfterLayout()
        }

        @discardableResult
        private func updateItemSizeIfPossible() -> Bool {
            guard let collectionView,
                  let layout = collectionView.collectionViewLayout
                    as? NSCollectionViewFlowLayout else { return false }
            let scrollInsets = collectionView.enclosingScrollView?.contentInsets
                ?? NSEdgeInsets()
            let viewportHeight = collectionView.enclosingScrollView?.contentSize.height
                ?? collectionView.bounds.height
            let availableHeight = viewportHeight
                - layout.sectionInset.top
                - layout.sectionInset.bottom
                - scrollInsets.top
                - scrollInsets.bottom
            guard availableHeight > 1 else { return false }
            // The viewport loses roughly one scrollbar-width while AppKit
            // completes its first collection layout. Reserve that transition
            // only for the initial resolution; subsequent passes can use the
            // final measured height directly.
            let safetyMargin: CGFloat = effectiveCardHeight == 0 ? 16 : 1
            let resolvedHeight = min(
                cardHeight,
                floor(availableHeight) - safetyMargin
            )
            guard resolvedHeight > 0 else { return false }
            let newSize = NSSize(
                width: Theme.cardWidth,
                height: resolvedHeight
            )
            guard layout.itemSize != newSize else {
                effectiveCardHeight = resolvedHeight
                return false
            }
            effectiveCardHeight = resolvedHeight
            layout.itemSize = newSize
            layout.invalidateLayout()
            return true
        }

        private func recordVisibleCellCount() {
            guard let collectionView else { return }
            VirtualizedClipStripMetrics.recordVisibleCellCount(
                collectionView.visibleItems().count
            )
        }
    }
}

@MainActor
final class ClipCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("PestyClipCard")

    private var hostingView: ClipCardHostingView?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        VirtualizedClipStripMetrics.recordCreatedCell()
    }

    func configure(
        item: ClipItem,
        index: Int,
        selected: Bool,
        height: CGFloat
    ) {
        let rootView = AnyView(
            ClipCardView(item: item, index: index, selected: selected)
                .frame(width: Theme.cardWidth, height: height)
                .id(item.id)
        )

        if let hostingView {
            hostingView.rootView = rootView
            hostingView.onPrimaryClick = { [weak self] clickCount in
                self?.handlePrimaryClick(item: item, clickCount: clickCount)
            }
        } else {
            let hostingView = ClipCardHostingView(rootView: rootView)
            hostingView.onPrimaryClick = { [weak self] clickCount in
                self?.handlePrimaryClick(item: item, clickCount: clickCount)
            }
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            self.hostingView = hostingView
        }
    }

    func performPrimaryClickForAutomatedTest(clickCount: Int) {
        guard AutomatedUITestProbe.isEnabled else { return }
        hostingView?.performPrimaryClick(clickCount: clickCount)
    }

    private func handlePrimaryClick(item: ClipItem, clickCount: Int) {
        ClipboardStore.shared.selectedID = item.id
        if clickCount == 2 {
            AppController.shared.quickPasteItem(item)
        }
    }
}

final class ClipCardHostingView: NSHostingView<AnyView> {
    var onPrimaryClick: ((Int) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        performPrimaryClick(clickCount: event.clickCount)
    }

    func performPrimaryClick(clickCount: Int) {
        window?.makeFirstResponder(nil)
        ClipboardStore.shared.isSearchFieldActive = false
        onPrimaryClick?(clickCount)
    }
}

extension Notification.Name {
    static let pestyBarDidFinishPresentation =
        Notification.Name("PestyBarDidFinishPresentation")
}
