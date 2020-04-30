//
//  ViewController.swift
//  xliff-tool
//
//  Created by Remus Lazar on 06.01.16.
//  Copyright © 2016 Remus Lazar. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    private struct Configuration {
        // max number of items in the XLIFF file to allow dynamic row height for all table rows
        // else we will re-tile just the selected row after selection, the remaining cells remaining single lined
        static let maxItemsForDynamicRowHeight = 150
    }

    // MARK: private data
    private var xliffFile: XliffFile? { didSet { reloadUI() } }
    private var importedUnitIDs: [String: [String]] = [:]
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(ViewController.toggleCompactRowsMode(_:)) { // "Compact Rows" Setting
            // update the menu item state to match the current dynamicRowHeight setting
            if document == nil { return false }
            menuItem.state = dynamicRowHeight ? .off : .on
        }
        
        return true
    }
    
    private var dynamicRowHeight = false { didSet { outlineView?.reloadData() } }
    
    weak var document: Document? {
        didSet {
            if let xliffDocument = document?.xliffDocument {
                // already validated, this should never fail
                try! xliffFile = XliffFile(xliffDocument: xliffDocument)
                xliffFile!.filter = filter
                
                if let file = xliffFile, file.totalCount < Configuration.maxItemsForDynamicRowHeight {
                    dynamicRowHeight = true
                }
            } else {
                xliffFile = nil
            }
            outlineView?.reloadData()
            xliffFile?.files.forEach { outlineView?.expandItem($0) }
        }
    }
    
    
    // MARK: rowHeight Cache
    
    private var rowHeightsCache = [NSTableColumn: [String: CGFloat]]()

    private func purgeCachedHeightForItem(_ item: XliffFile.TransUnit) {
        for col in rowHeightsCache.keys {
            rowHeightsCache[col]!.removeValue(forKey: item.id)
        }
    }
    
    @objc func reloadUI() {
        outlineView?.reloadData()
        updateStatusBar()
    }
    
    private func updateStatusBar() {
        if let file = xliffFile {
            infoLabel?.stringValue = String.localizedStringWithFormat(
                NSLocalizedString("%d file(s), %d localizable string(s) available", comment: "Status bar label"),
                file.files.count, file.totalCount)
        } else {
            infoLabel?.stringValue = NSLocalizedString("No xliff file loaded", comment: "Status bar label when no xliff file is loaded")
        }
    }
    
    @objc func resizeTable(_ notification: Notification) {
        if let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn {
            // invalidate cache for the specific row
            rowHeightsCache.removeValue(forKey: col)
        }
        outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: Range(NSRange(location: 0,length: outlineView.numberOfRows)) ?? 0..<0))
    }
    
    // MARK: VC Lifecycle
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.reloadUI),
            name: NSNotification.Name.NSUndoManagerDidUndoChange, object: document!.undoManager)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.reloadUI),
            name: NSNotification.Name.NSUndoManagerDidRedoChange, object: document!.undoManager)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.resizeTable(_:)),
            name: NSOutlineView.columnDidResizeNotification, object: outlineView)
    }
   
    override func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func updateTranslation(for elem: XliffFile.TransUnit, newValue: String?) {
        
        // no change, bail out
        if elem.target == newValue { return }
        
        // register undo/redo operation
        if let undoTarget = document?.undoManager?.prepare(withInvocationTarget: self) {
            (undoTarget as AnyObject).updateTranslation(for: elem, newValue: elem.target)
        }
        
        // update the value in place
        elem.target = newValue
    }
    
    private var filter = XliffFile.Filter()
    
    private func reloadFilter() {
        if let xliffFile = xliffFile {
            xliffFile.filter = filter
            reloadUI()
        }
    }
    
    // MARK: Outlets
    
    @IBOutlet weak var outlineView: NSOutlineView!
    
    @IBAction func textFieldEndEditing(_ sender: NSTextField) {
        let row = outlineView.row(for: sender)
        if row != -1, let elem = outlineView.item(atRow: row) as? XliffFile.TransUnit {
            updateTranslation(for: elem, newValue: sender.stringValue)
            purgeCachedHeightForItem(elem)
            outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            outlineView.reloadItem(elem)
        }
    }
    
    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let selectedRow = outlineView.selectedRow
        if selectedRow > -1,
            let selectedElement = outlineView.item(atRow: selectedRow) as? XliffFile.TransUnit {
            do {
                try selectedElement.validate(targetString: fieldEditor.string)
            } catch {
                presentError(error)
                return false
            }
        }
        
        return true
    }
    
    @IBAction func filter(_ sender: NSSearchField) {
        filter.searchString = sender.stringValue
        reloadFilter()
    }

    @IBAction func toggleCompactRowsMode(_ sender: AnyObject) {
        if let menuItem = sender as? NSMenuItem {
            menuItem.state = menuItem.state == .on ? .off : .on
            dynamicRowHeight = menuItem.state == .off
        }
    }
    
    @IBOutlet weak var infoLabel: NSTextField! { didSet { updateStatusBar() } }
    
    @IBOutlet weak var searchField: NSSearchField!
    
    @IBOutlet weak var onlyNonTranslated: NSButton!
    
    @IBAction func toggleNonTranslatedFilterMode(_ sender: Any) {
        filter.onlyNonTranslated  = onlyNonTranslated.state == .on
        reloadFilter()
    }
    
    // MARK: Menu actions
    @IBAction func deleteTranslationForSelectedRow(_ sender: AnyObject) {
        if outlineView.selectedRow != -1,
            let elem = outlineView.item(atRow: outlineView.selectedRow) as? XliffFile.TransUnit {
            updateTranslation(for: elem, newValue: nil)
            outlineView.reloadData(forRowIndexes: IndexSet(integer: outlineView.selectedRow),
                                   columnIndexes: IndexSet(integer: outlineView.column(
                                    withIdentifier: NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.1"))))
        }
    }
    
    /** Copy the source string to target for further editing. If no row is selected, this method does nothing */
    @IBAction func copySourceToTargetForSelectedRow(_ sender: AnyObject) {
        if outlineView.selectedRow != -1,
            let elem = outlineView.item(atRow: outlineView.selectedRow) as? XliffFile.TransUnit {
            let newValue = elem.source
            updateTranslation(for: elem, newValue: newValue )
            outlineView.reloadData(forRowIndexes: IndexSet(integer: outlineView.selectedRow),
                                   columnIndexes: IndexSet(integer: outlineView.column(
                                    withIdentifier: NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.1"))))
        }
    }
    
    /** Activates the search/filter field in the UI so that the user can begin typing */
    @IBAction func activateSearchField(_ sender: AnyObject) {
        self.view.window?.makeFirstResponder(searchField)
    }

    @IBAction func exportToCSVMenuItemSelected(_ sender: AnyObject) {
        exportToCSVFiles()
    }

    @IBAction func importFromCSVMenuItemSelected(_ sender: AnyObject) {
        importFromCSVFile()
    }

    // MARK: NSOutlineView Delegate and Datasource
    
    private var lastSelectedRow: Int?
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if !dynamicRowHeight {
            // if not using the dynamicRowHeight behavior, resize the currently selected cell accordingly
            outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: outlineView.selectedRow))
            if let last = lastSelectedRow {
                outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: last))
            }
            lastSelectedRow = outlineView.selectedRow
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil, let xliffFile = xliffFile { // top level item
            return xliffFile.files.count
        } else if let file = item as? XliffFile.File {
            return file.items.count
        }
        
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // only top-level items are expandable
        return item is XliffFile.File
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { // root item
            return xliffFile!.files[index]
        } else {
            let file = item as! XliffFile.File
            return file.items[index]
        }
    }
    
    private func configureContentCell(_ cell: NSTableCellView, columnIdentifier identifier: NSUserInterfaceItemIdentifier, transUnit: XliffFile.TransUnit) {
        switch identifier.rawValue {
        case "AutomaticTableColumnIdentifier.0":
            cell.textField!.stringValue = transUnit.source
            break
        case "AutomaticTableColumnIdentifier.1":
            if let content = transUnit.target {
                cell.textField!.stringValue = content
                cell.textField?.placeholderString = nil

                // Colored imported trans units
                if isTransUnitImported(transUnit) {
                    cell.textField?.textColor = .systemGreen
                } else {
                    cell.textField?.textColor = .black
                }
            } else {
                cell.textField?.placeholderString = NSLocalizedString("No translation", comment: "Placeholder String when no translation is available")
                cell.textField?.stringValue = ""
            }
            break
        case "AutomaticTableColumnIdentifier.2":
            cell.textField!.stringValue = transUnit.note ?? ""
            break
        default: break
        }
    }
    
    private func configureGroupCell(_ cell: NSTableCellView, file: XliffFile.File) {
        cell.textField!.stringValue = String.localizedStringWithFormat(
            NSLocalizedString("%@ (source=%@, target=%@)", comment: "Group header cell text, will show up in the outline view as a separator for each file in the XLIFF container."),
            file.name,
            file.sourceLanguage ?? NSLocalizedString("?", comment: "Placeholder telling the user that the source language for a specific file is unavailable in the source xliff file"),
            file.targetLanguage ?? NSLocalizedString("?", comment: "Placeholder telling the user that the target language for a specific file is unavailable in the source xliff file")
        )
    }
    
    
    private func heightForItem(_ item: Any) -> CGFloat {
        let heights = outlineView.tableColumns.map { (col) -> CGFloat in
            let item = item as! XliffFile.TransUnit
            if let height = rowHeightsCache[col]?[item.id] { return height }
            
            let cell = outlineView.makeView(withIdentifier: col.identifier, owner: nil) as! NSTableCellView
            
            configureContentCell(cell, columnIdentifier: col.identifier, transUnit: item)
            cell.layoutSubtreeIfNeeded()
            let column = outlineView.column(withIdentifier: col.identifier)
            var width = outlineView.tableColumns[column].width
            
            if (col.identifier == NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")) {
                // because we're using NSOutliveView, the first level is indended by this amount
                width -= outlineView.indentationPerLevel + 14.0
            }
           
            let size = cell.textField!.sizeThatFits(CGSize(width: width, height: 10000))
            let height = size.height + 2.0 // some spacing between the table rows
            
            if rowHeightsCache[col] != nil {
                rowHeightsCache[col]![item.id] = height
            } else {
                rowHeightsCache[col] = [item.id: height]
            }
            
            return height
        }
        return heights.max()!
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = outlineView.makeView(withIdentifier: tableColumn == nil ? NSUserInterfaceItemIdentifier("GroupedItemCellIdentifier") : tableColumn!.identifier, owner: self) as! NSTableCellView
        
        // configure the cell
        if let file = item as? XliffFile.File {
            configureGroupCell(cell, file: file)
        } else if let unit = item as? XliffFile.TransUnit {
            configureContentCell(cell, columnIdentifier: tableColumn!.identifier, transUnit: unit)
        }

        return cell
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is XliffFile.File
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is XliffFile.File { return outlineView.rowHeight }
        if dynamicRowHeight {
            return heightForItem(item as AnyObject)
        } else if let item = item as? XliffFile.TransUnit,
            let selectedItem = outlineView.item(atRow: outlineView.selectedRow) as? XliffFile.TransUnit {
            if item.source == selectedItem.source {
                return heightForItem(item)
            }
        }
        return outlineView.rowHeight
    }
    
}

// MARK: - Export to CSV functionality
extension ViewController {

    private func exportToCSVFiles() {
        // Use same folder as xliff file for export folder (otherwise user home folder)
        var outputFolder: URL
        //        if let doc = document, let docURL = doc.fileURL {
        //            outputFolder = docURL.deletingLastPathComponent()
        //        } else {
        //            outputFolder = FileManager.default
        //        }

        // Get Downloads directory for user (due to file system restriction on macOS Catalina)
        // TODO: Examine new macOS permission system to access file system etc.
        let dirURLs = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        outputFolder = dirURLs[0]

        guard let window = view.window else { return }

        let panel = NSSavePanel()
        panel.directoryURL = outputFolder

        panel.beginSheetModal(for: window) { (result) in
            if result == .OK,
                let url = panel.url {

                // Filter XliffFile to empty translations only
                var noTransFilter = XliffFile.Filter()
                noTransFilter.onlyNonTranslated = true

                if let xliffFile = self.xliffFile {
                    xliffFile.filter = noTransFilter
                    self.exportToCSVFilesFor(xliffFile, outputFolder: url.deletingLastPathComponent())
                }
            }
        }
    }

    private func exportToCSVFilesFor(_ xliffFile: XliffFile, outputFolder: URL) {
        // Check files that have at least one item
        for file in xliffFile.files where !file.items.isEmpty {
            // Filename

            if let filenameAsURL = URL(string: file.name) {
                let filepathToName = filenameAsURL.pathComponents.reduce("") { (result, component) -> String in
                    return result + (!result.isEmpty ? "_" : "") + component
                }

                let filename = "\(filepathToName)-\(file.sourceLanguage ?? "")_\(file.targetLanguage ?? "").csv"
                let fileURL = outputFolder.appendingPathComponent(filename)
                let csvString = csvStringForXliffSubFile(file)

                do {
                    try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Error on saving CSV file: \(error)")
                }
            }

        }
    }

    private func csvStringForXliffSubFile(_ file: XliffFile.File) -> String {
        var csvString: String = ""

        // Parse file items
        for unit in file.items {
            csvString.append("\"\(unit.source)\";")
            csvString.append("\"\(unit.note ?? "")\";")
            csvString.append("\"\(unit.target ?? "")\"\n")
        }

        return csvString
    }
}

// MARK: - Import from CSV functionality
extension ViewController {

    private func importFromCSVFile() {
        // Choose file
        guard let window = view.window else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.beginSheetModal(for: window) { (result) in
            if result == .OK, let url = panel.url {
                self.parseCSVFile(url)
                self.reloadUI()
            }
        }
    }

    private func parseCSVFile(_ csvFile: URL) {
        // Read file
        guard let csvString = try? String(contentsOf: csvFile, encoding: .utf8) else { return }

        // CSV parsing
        let csvModel = CSwiftV(with: csvString, separator: ";", headers: ["Source", "Note", "Target"])

        // Find File item in XLIFF-File
        guard let xliffFile = xliffFile else { return }
        let fileItemName = "iOSMO/Resources/Localizations/en.lproj/Localizable.strings"
        var fileItem: XliffFile.File?
        for afileItem in xliffFile.files {
            if afileItem.name == fileItemName {
                fileItem = afileItem
                break
            }
        }

        if let fileItem = fileItem {
            matchImportedUnits(csvModel, for: fileItem)
        }
    }

    private func matchImportedUnits(_ csvModel: CSwiftV, for file: XliffFile.File) {
        // Reset imported indexes
        var unitIDs: [String] = []

        // Matching (only when target translation is not empty)
        for csvUnit in csvModel.rows where !csvUnit[2].isEmpty {
            let matchedIndex = file.items.firstIndex { (transUnit) -> Bool in
                return transUnit.source == csvUnit[0]
            }

            if let index = matchedIndex {
                let matchedUnit = file.items[index]
                matchedUnit.target = csvUnit[2]
                unitIDs.append(matchedUnit.id)
            }
        }

        importedUnitIDs[file.name] = unitIDs
    }

    private func isTransUnitImported(_ transUnit: XliffFile.TransUnit) -> Bool {
        var found = false

        outerloop: for (_, transIDs) in importedUnitIDs {
            for transID in transIDs {
                if transUnit.id == transID {
                    found = true
                    break outerloop
                }
            }
        }

        return found
    }
}
