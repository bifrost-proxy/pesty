import AppKit
import SwiftUI

private final class HorizontalWheelScrollView: NSScrollView {
    private var pendingVerticalDelta: CGFloat = 0
    private var scrollUpdateScheduled = false

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = event.scrollingDeltaX
        let verticalDelta = event.scrollingDeltaY
        guard abs(verticalDelta) > abs(horizontalDelta),
              abs(verticalDelta) > 0.01,
              documentView != nil else {
            super.scrollWheel(with: event)
            return
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 28
        pendingVerticalDelta += verticalDelta * multiplier
        guard !scrollUpdateScheduled else { return }
        scrollUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingVerticalScroll()
        }
    }

    private func applyPendingVerticalScroll() {
        scrollUpdateScheduled = false
        guard let documentView else {
            pendingVerticalDelta = 0
            return
        }

        let delta = pendingVerticalDelta
        pendingVerticalDelta = 0
        var origin = contentView.bounds.origin
        let contentWidth = (documentView as? NSCollectionView)?
            .collectionViewLayout?.collectionViewContentSize.width
            ?? documentView.bounds.width
        let maximumX = max(0, contentWidth - contentView.bounds.width)
        origin.x = min(
            maximumX,
            max(0, origin.x - delta)
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
    private(set) static var quickPasteRequestCount = 0
    private(set) static var lastQuickPasteItemID: UUID?
    private(set) static var hostingRootCreationCount = 0
    private(set) static var cellConfigurationCount = 0

    static func reset() {
        createdCellCount = 0
        maximumVisibleCellCount = 0
        configuredItemIDs.removeAll(keepingCapacity: true)
        contentIndexRebuildCount = 0
        lastSelectedItemID = nil
        lastSelectedConfigurationTime = nil
        quickPasteRequestCount = 0
        lastQuickPasteItemID = nil
        hostingRootCreationCount = 0
        cellConfigurationCount = 0
    }

    static func recordCreatedCell() {
        guard AutomatedUITestProbe.isEnabled else { return }
        createdCellCount += 1
    }

    static func recordConfiguredItem(_ id: UUID, selected: Bool) {
        guard AutomatedUITestProbe.isEnabled else { return }
        cellConfigurationCount += 1
        configuredItemIDs.insert(id)
        if selected {
            lastSelectedItemID = id
            lastSelectedConfigurationTime = CFAbsoluteTimeGetCurrent()
        }
    }

    static func recordContentIndexRebuild() {
        guard AutomatedUITestProbe.isEnabled else { return }
        contentIndexRebuildCount += 1
    }

    static func recordVisibleCellCount(_ count: Int) {
        guard AutomatedUITestProbe.isEnabled else { return }
        maximumVisibleCellCount = max(maximumVisibleCellCount, count)
    }

    static func recordQuickPasteRequest(_ id: UUID) {
        guard AutomatedUITestProbe.isEnabled else { return }
        quickPasteRequestCount += 1
        lastQuickPasteItemID = id
    }

    static func recordHostingRootCreation() {
        guard AutomatedUITestProbe.isEnabled else { return }
        hostingRootCreationCount += 1
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
    final class Coordinator:
        NSObject,
        NSCollectionViewDataSource,
        ClipStripGeometryProviding
    {
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
            ClipStripGeometryBridge.shared.connect(self)
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
            ClipStripGeometryBridge.shared.disconnect(self)
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
                if let previousSelectedID, let index = indexByID[previousSelectedID] {
                    let indexPath = IndexPath(item: index, section: 0)
                    (collectionView.item(at: indexPath)
                        as? ClipCollectionViewItem)?
                        .updateSelection(false)
                }
                if let newSelectedID, let index = indexByID[newSelectedID] {
                    let indexPath = IndexPath(item: index, section: 0)
                    (collectionView.item(at: indexPath)
                        as? ClipCollectionViewItem)?
                        .updateSelection(true)
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

        func previewContext(for itemID: UUID) -> ClipPreviewContext? {
            guard let collectionView,
                  let window = collectionView.window,
                  let index = indexByID[itemID],
                  items.indices.contains(index) else {
                return nil
            }
            collectionView.layoutSubtreeIfNeeded()
            guard let attributes = collectionView.collectionViewLayout?
                .layoutAttributesForItem(
                    at: IndexPath(item: index, section: 0)
                ) else {
                return nil
            }
            let frameInWindow = collectionView.convert(
                attributes.frame,
                to: nil
            )
            return ClipPreviewContext(
                item: items[index],
                cardFrameInScreen: window.convertToScreen(frameInWindow)
            )
        }

        private func ensureSelectedIsVisibleAfterLayout() {
            let expectedID = selectedID
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.selectedID == expectedID,
                      let expectedID,
                      let index = self.indexByID[expectedID],
                      let collectionView = self.collectionView else { return }
                defer {
                    ClipPreviewWindowController.shared.selectionDidChange(
                        to: expectedID
                    )
                }
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
                let contentWidth = collectionView.collectionViewLayout?
                    .collectionViewContentSize.width
                    ?? collectionView.bounds.width
                let maximumX = max(0, contentWidth - visibleRect.width)
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

@Observable
@MainActor
private final class ClipCardPresentationState {
    struct Content: Equatable {
        let item: ClipItem
        let previewText: String
        let characterCount: Int
        let displayTitle: String

        init(item: ClipItem) {
            self.item = item
            previewText = ClipCardPreview.text(item.text)
            characterCount = item.charCount
            displayTitle = item.displayTitle
        }
    }

    var content: Content
    var index: Int
    var selected: Bool
    var height: CGFloat

    init(item: ClipItem, index: Int, selected: Bool, height: CGFloat) {
        content = Content(item: item)
        self.index = index
        self.selected = selected
        self.height = height
    }

    func update(
        item: ClipItem,
        index: Int,
        selected: Bool,
        height: CGFloat
    ) {
        if content.item.id != item.id || content.item != item {
            content = Content(item: item)
        }
        self.index = index
        self.selected = selected
        self.height = height
    }
}

private struct StatefulClipCardView: View {
    @Bindable var state: ClipCardPresentationState

    var body: some View {
        let content = state.content
        ClipCardView(
            item: content.item,
            index: state.index,
            selected: state.selected,
            previewText: content.previewText,
            characterCount: content.characterCount,
            displayTitle: content.displayTitle
        )
        .frame(width: Theme.cardWidth, height: state.height)
    }
}

@MainActor
final class ClipCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("PestyClipCard")

    private var hostingView: ClipCardHostingView?
    private var presentationState: ClipCardPresentationState?
    private var configuredItem: ClipItem?
    private var configuredIndex = -1
    private var configuredHeight: CGFloat = 0

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
        let contentChanged =
            configuredItem?.id != item.id
            || configuredItem != item
            || configuredIndex != index
            || configuredHeight != height
            || presentationState == nil

        configuredItem = item
        configuredIndex = index
        configuredHeight = height

        if hostingView != nil {
            if contentChanged {
                presentationState?.update(
                    item: item,
                    index: index,
                    selected: selected,
                    height: height
                )
            } else {
                updateSelection(selected)
            }
        } else {
            let state = ClipCardPresentationState(
                item: item,
                index: index,
                selected: selected,
                height: height
            )
            presentationState = state
            let hostingView = ClipCardHostingView(
                rootView: StatefulClipCardView(state: state)
            )
            VirtualizedClipStripMetrics.recordHostingRootCreation()
            hostingView.onPrimaryClick = { [weak self] clickCount in
                self?.handlePrimaryClick(clickCount: clickCount)
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
        if selected {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.layoutSubtreeIfNeeded()
                SelectedClipPopoverAnchor.shared.update(itemID: item.id, view: self.view)
            }
        }
    }

    func updateSelection(_ selected: Bool) {
        guard let configuredItem, let presentationState else { return }
        presentationState.selected = selected
        VirtualizedClipStripMetrics.recordConfiguredItem(
            configuredItem.id,
            selected: selected
        )
    }

    func performPrimaryClickForAutomatedTest(clickCount: Int) {
        guard AutomatedUITestProbe.isEnabled else { return }
        hostingView?.performPrimaryClick(clickCount: clickCount)
    }

    var eventSurfaceIdentityForAutomatedTest: ObjectIdentifier? {
        guard AutomatedUITestProbe.isEnabled, let hostingView else {
            return nil
        }
        return ObjectIdentifier(hostingView)
    }

    private func handlePrimaryClick(clickCount: Int) {
        guard let item = configuredItem else { return }
        ClipboardStore.shared.selectedID = item.id
        if clickCount == 2 {
            VirtualizedClipStripMetrics.recordQuickPasteRequest(item.id)
            if ProcessInfo.processInfo.environment[
                "PESTY_AUTOMATED_UI_TEST"
            ] == "mouse-selection" {
                return
            }
            AppController.shared.quickPasteItem(item)
        }
    }
}

private final class ClipCardHostingView: NSHostingView<StatefulClipCardView> {
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
