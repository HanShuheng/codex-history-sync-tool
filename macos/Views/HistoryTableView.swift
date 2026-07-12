import AppKit
import SwiftUI

struct HistoryTableView: NSViewRepresentable {
    let items: [ThreadItem]
    @Binding var selectedIDs: Set<String>
    let taskTitle: String
    let assignmentTitle: String
    let statusTitle: String
    let updatedTitle: String
    let emptyValue: String
    let currentValue: String
    let pendingValue: String
    let date: (String) -> String
    let persistSelections: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .bezelBorder
        scrollView.contentView.postsBoundsChangedNotifications = true

        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 48
        let headerView = SelectAllHeaderView()
        headerView.toggleSelection = { [weak coordinator = context.coordinator] in
            coordinator?.toggleAllVisible()
        }
        tableView.headerView = headerView
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            coordinator?.updateDocumentFrame()
        }
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.configureColumns()
        context.coordinator.updateDocumentFrame()

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureColumns()
        context.coordinator.tableView?.reloadData()
        context.coordinator.updateDocumentFrame()
        context.coordinator.updateHeaderSelection()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HistoryTableView
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var boundsObserver: NSObjectProtocol?

        init(_ parent: HistoryTableView) { self.parent = parent }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func configureColumns() {
            guard let tableView else { return }
            let definitions: [(String, String, CGFloat, CGFloat, CGFloat)] = [
                ("select", "", 42, 42, 54),
                ("task", parent.taskTitle, 260, 360, 720),
                ("assignment", parent.assignmentTitle, 180, 230, 380),
                ("status", parent.statusTitle, 110, 130, 200),
                ("updated", parent.updatedTitle, 180, 210, 320)
            ]
            for (index, definition) in definitions.enumerated() {
                let column: NSTableColumn
                let isNewColumn = index >= tableView.tableColumns.count
                if !isNewColumn {
                    column = tableView.tableColumns[index]
                } else {
                    column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(definition.0))
                    tableView.addTableColumn(column)
                }
                column.title = definition.1
                if isNewColumn {
                    column.minWidth = definition.2
                    column.width = definition.3
                    column.maxWidth = definition.4
                }
                column.maxWidth = definition.4
                column.resizingMask = .userResizingMask
            }
            if let headerView = tableView.headerView as? SelectAllHeaderView {
                headerView.firstColumnWidth = tableView.tableColumns.first?.width ?? 0
                headerView.needsLayout = true
            }
        }

        func updateHeaderSelection() {
            guard let headerView = tableView?.headerView as? SelectAllHeaderView else { return }
            let visibleIDs = Set(parent.items.map(\.id))
            let selectedCount = visibleIDs.intersection(parent.selectedIDs).count
            headerView.state = selectedCount == 0 ? .off : selectedCount == visibleIDs.count ? .on : .mixed
        }

        func toggleAllVisible() {
            let ids = Set(parent.items.map(\.id))
            guard !ids.isEmpty else { return }
            let allSelected = ids.isSubset(of: parent.selectedIDs)
            if allSelected { parent.selectedIDs.subtract(ids) }
            else { parent.selectedIDs.formUnion(ids) }
            parent.persistSelections()
            updateHeaderSelection()
            tableView?.reloadData()
        }

        func updateDocumentFrame() {
            guard let tableView, let scrollView else { return }
            let columnWidth = tableView.tableColumns.reduce(CGFloat.zero) { $0 + $1.width }
            let viewportWidth = scrollView.contentView.bounds.width
            let rowHeight = tableView.rowHeight * CGFloat(max(parent.items.count, 1))
            let viewportHeight = scrollView.contentView.bounds.height
            tableView.frame = NSRect(
                x: 0,
                y: 0,
                width: max(columnWidth, viewportWidth),
                height: max(rowHeight + (tableView.headerView?.frame.height ?? 0), viewportHeight)
            )
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            updateDocumentFrame()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, parent.items.indices.contains(row) else { return nil }
            let item = parent.items[row]
            switch tableColumn.identifier.rawValue {
            case "select":
                let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
                button.state = parent.selectedIDs.contains(item.id) ? .on : .off
                button.identifier = NSUserInterfaceItemIdentifier(item.id)
                return centered(button)
            case "task":
                return cellContent(label(item.pinned ? "📌 \(item.title)" : item.title))
            case "assignment":
                return cellContent(stack([
                    label(item.provider.isEmpty ? parent.emptyValue : item.provider),
                    label(item.model.isEmpty ? parent.emptyValue : item.model, secondary: true)
                ]))
            case "status":
                return cellContent(label(item.isCurrent ? parent.currentValue : parent.pendingValue, color: item.isCurrent ? .systemGreen : .systemOrange))
            case "updated":
                return cellContent(label(parent.date(item.updatedAt)))
            default:
                return nil
            }
        }

        @objc func toggle(_ sender: NSButton) {
            guard let id = sender.identifier?.rawValue else { return }
            if parent.selectedIDs.contains(id) { parent.selectedIDs.remove(id) }
            else { parent.selectedIDs.insert(id) }
            parent.selectedIDs = parent.selectedIDs
            parent.persistSelections()
            updateHeaderSelection()
        }

        private func centered(_ view: NSView) -> NSView {
            let container = NSView()
            container.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }

        private func cellContent(_ view: NSView) -> NSView {
            let container = NSView()
            container.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }

        private func label(_ text: String, secondary: Bool = false, color: NSColor? = nil) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = secondary ? .systemFont(ofSize: 12) : .systemFont(ofSize: 14)
            field.textColor = color ?? (secondary ? .secondaryLabelColor : .labelColor)
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return field
        }

        private func stack(_ views: [NSView]) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            return stack
        }
    }
}

private final class SelectAllHeaderView: NSTableHeaderView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var firstColumnWidth: CGFloat = 42
    var toggleSelection: (() -> Void)?
    var state: NSControl.StateValue {
        get { checkbox.state }
        set { checkbox.state = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        checkbox.target = self
        checkbox.action = #selector(didToggle)
        checkbox.allowsMixedState = true
        checkbox.setAccessibilityLabel("全选当前结果")
        addSubview(checkbox)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = checkbox.fittingSize
        let columnWidth = tableView?.rect(ofColumn: 0).width ?? firstColumnWidth
        checkbox.frame = NSRect(
            x: max(0, (columnWidth - size.width) / 2),
            y: max(0, (bounds.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
    }

    @objc private func didToggle() { toggleSelection?() }
}
