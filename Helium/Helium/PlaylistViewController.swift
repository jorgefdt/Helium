//
//  PlaylistViewController.swift
//  Helium
//
//  Created by Carlos D. Santiago on 2/15/17.
//  Copyright © 2017 Jaden Geller. All rights reserved.
//

import Foundation
import AVFoundation

struct k {
    static let play = "play"
    static let item = "item"
    static let name = "name"
    static let list = "list"
    static let link = "link"
    static let time = "time"
    static let rank = "rank"
}

class PlayTableView : NSTableView {
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers! == String(Character(UnicodeScalar(NSDeleteCharacter)!)) ||
           event.charactersIgnoringModifiers! == String(Character(UnicodeScalar(NSDeleteFunctionKey)!)) {
            // Take action in the delegate.
            let delegate: PlaylistViewController = self.delegate as! PlaylistViewController
            
            delegate.removePlaylist(self)
        }
        else
        {
            // still here?
            super.keyDown(with: event)
        }
    }
    
    func tableViewColumnDidResize(notification: NSNotification ) {
        // Pay attention to column resizes and aggressively force the tableview's
        // cornerview to redraw.
        self.cornerView?.needsDisplay = true
    }

}

class PlayItemCornerView : NSView {
    @IBOutlet weak var playlistArrayController: NSDictionaryController!
    @IBOutlet weak var playitemTableView: PlayTableView!
    override func draw(_ dirtyRect: NSRect) {
        let tote = NSImage.init(imageLiteralResourceName: "NSRefreshTemplate")
        let alignRect = tote.alignmentRect
        
        NSGraphicsContext.saveGraphicsState()
        tote.draw(in: NSMakeRect(2, 5, 7, 11), from: alignRect, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
    
    override func mouseDown(with event: NSEvent) {
        playitemTableView.beginUpdates()
        // Renumber playlist items
        let list = (playlistArrayController.selectedObjects.first as! NSDictionaryControllerKeyValuePair).value as! [PlayItem]
        let col = playitemTableView.column(withIdentifier: "rank")
        for row in 0...playitemTableView.numberOfRows-1 {
            let cell = playitemTableView.view(atColumn: col, row: row, makeIfNecessary: true) as! NSTableCellView
            cell.textField?.integerValue = row + 1
            list[row].rank = row + 1
        }
        playitemTableView.endUpdates()
    }
}

class PlayItemHeaderView : NSTableHeaderView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let action = #selector(PlaylistViewController.toggleColumnVisiblity(_ :))
        let target = self.tableView?.delegate
        let menu = NSMenu.init()
        var item: NSMenuItem
        
        //	We auto enable items as views present them
        menu.autoenablesItems = true
        
        //	TableView level column customizations
        for col in (self.tableView?.tableColumns)! {
            let title = col.headerCell.stringValue
            let state = col.isHidden
            
            item = NSMenuItem.init(title: title, action: action, keyEquivalent: "")
            item.image = NSImage.init(named: (state) ? "NSOnImage" : "NSOffImage")
            item.state = (state ? NSOffState : NSOnState)
            item.representedObject = col
            item.isEnabled = true
            item.target = target
            menu.addItem(item)
        }
        return menu
    }
}

extension NSURL {
    
    func compare(_ other: URL ) -> ComparisonResult {
        return (self.absoluteString?.compare(other.absoluteString))!
    }
//  https://stackoverflow.com/a/44908669/564870
    func resolvedFinderAlias() -> URL? {
        if (self.fileReferenceURL() != nil) { // item exists
            do {
                // Get information about the file alias.
                // If the file is not an alias files, an exception is thrown
                // and execution continues in the catch clause.
                let data = try NSURL.bookmarkData(withContentsOf: self as URL)
                // NSURLPathKey contains the target path.
                let rv = NSURL.resourceValues(forKeys: [ URLResourceKey.pathKey ], fromBookmarkData: data)
                var urlString = rv![URLResourceKey.pathKey] as! String
                if !urlString.hasPrefix("file://") {
                    urlString = "file://" + urlString
                }
                return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed)!)!
            } catch {
                // We know that the input path exists, but treating it as an alias
                // file failed, so we assume it's not an alias file so return nil.
                return nil
            }
        }
        return nil
    }
}

class PlaylistViewController: NSViewController,NSTableViewDataSource,NSTableViewDelegate {

    @IBOutlet var playlistArrayController: NSDictionaryController!
    @IBOutlet var playitemArrayController: NSArrayController!

    @IBOutlet var playlistTableView: PlayTableView!
    @IBOutlet var playitemTableView: PlayTableView!
    @IBOutlet var playlistSplitView: NSSplitView!

    //    cache playlists read and saved to defaults
    var appDelegate: AppDelegate = NSApp.delegate as! AppDelegate
    var defaults = UserDefaults.standard
    dynamic var playlists = Dictionary<String, Any>()
    dynamic var playCache = Dictionary<String, Any>()
    
    override func viewDidLoad() {
        let types = ["public.data",kUTTypeURL as String,
                     PlayItem.className(),
                     NSFilenamesPboardType,
                     NSURLPboardType]

        playlistTableView.register(forDraggedTypes: types)
        playitemTableView.register(forDraggedTypes: types)

        playitemTableView.doubleAction = #selector(playPlaylist(_:))
        self.restorePlaylists(restoreButton)
        //  Maintain a history of titles

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gotNewHistoryItem(_:)),
            name: NSNotification.Name(rawValue: "HeliumNewHistoryItem"),
            object: nil)

        //  Restore hidden columns in playitems using defaults
        let hideit = ["link","rect","label","hover","alpha","trans"]
        for col in playitemTableView.tableColumns {
            let identifier = col.identifier
            let pref = String(format: "hide.%@", identifier)
            var isHidden = false
            
            //	If have a preference, honor it, else apply hidden default
            if defaults.value(forKey: pref) != nil
            {
                isHidden = defaults.bool(forKey: pref)
                hiddenColumns[pref] = String(isHidden)
            }
            else
            if hideit.contains(identifier)
            {
                isHidden = true
            }
            col.isHidden = isHidden
        }

    }

    var historyCache: NSDictionaryControllerKeyValuePair? = nil
    override func viewWillAppear() {
        // add existing history entry if any
        if historyCache == nil && appDelegate.histories.count > 0 {
            playlists[UserSettings.HistoryName.value] = nil
            
            // overlay in history using NSDictionaryControllerKeyValuePair Protocol setKey
            historyCache = playlistArrayController.newObject() as NSDictionaryControllerKeyValuePair
            historyCache!.key = UserSettings.HistoryName.value
            historyCache!.value = appDelegate.histories
        }
        else
        if historyCache != nil
        {
            historyCache!.value = appDelegate.histories
        }
        playlistArrayController.addObject(historyCache!)
        
        // cache our list before editing
        playCache = playlists
        
        self.playlistSplitView.setPosition(120, ofDividerAt: 0)
        NSApp.activate(ignoringOtherApps: true)
        self.view.window?.makeKeyAndOrderFront(self)
    }

    @IBAction func addPlaylist(_ sender: NSButton) {
        let whoAmI = self.view.window?.firstResponder
        
        if whoAmI == playlistTableView, let selectedPlaylist = playlistArrayController.selectedObjects.first as? NSDictionaryControllerKeyValuePair {
            let list: Array<PlayItem> = selectedPlaylist.value as! Array
            let item = PlayItem(name:"item#",link:URL.init(string: "http://")!,time:0.0,rank:list.count + 1);
            let temp = NSString(format:"%p",item) as String
            item.name += String(temp.characters.suffix(3))

            playitemArrayController.addObject(item)

            DispatchQueue.main.async {
                self.playitemTableView.scrollRowToVisible(list.count - 1)
            }
        }
        else
        if whoAmI == playlistTableView {
            let item = playlistArrayController.newObject()
            let list = Array <PlayItem>()

            let temp = NSString(format:"%p",list) as String
            let name = "play#" + String(temp.characters.suffix(3))
            item.key = name
            item.value = list
            
            playlistArrayController.addObject(item)

            DispatchQueue.main.async {
                self.playlistTableView.scrollRowToVisible(self.playlists.count - 1)
            }
        }
        else
        {
            Swift.print("firstResponder: \(String(describing: whoAmI))")
        }
    }

    @IBAction func removePlaylist(_ sender: AnyObject) {
        let whoAmI = self.view.window?.firstResponder

        if whoAmI == playlistTableView, let selectedPlaylist = playlistArrayController.selectedObjects.first as? NSDictionaryControllerKeyValuePair {
            playlistArrayController.removeObject(selectedPlaylist)
        }
        else
        if whoAmI == playitemTableView, let selectedPlayItem = playitemArrayController.selectedObjects.first as? PlayItem {
            playitemArrayController.removeObject(selectedPlayItem)
        }
        else
        if let selectedPlayItem = playitemArrayController.selectedObjects.first as? PlayItem {
            playitemArrayController.removeObject(selectedPlayItem)
        }
        else
        if let selectedPlaylist = playlistArrayController.selectedObjects.first as? Dictionary<String,AnyObject> {
            playlistArrayController.removeObject(selectedPlaylist)
        }
        else
        {
            Swift.print("firstResponder: \(String(describing: whoAmI))")
            AudioServicesPlaySystemSound(1051);
        }
    }

    // Our playlist panel return point if any
    var webViewController: WebViewController? = nil
    
    @IBAction func playPlaylist(_ sender: AnyObject) {
        let whoAmI = self.view.window?.firstResponder

        if whoAmI == playitemTableView, let selectedPlayItem = playitemArrayController.selectedObjects.first as? PlayItem {
            super.dismiss(sender)

            if (webViewController != nil) {
                webViewController?.loadURL(url: selectedPlayItem.link)
            }
            else
            {
                if let first = NSApp.windows.first {
                    if let hpc = first.windowController as? HeliumPanelController {
                        hpc.webViewController.loadURL(url: selectedPlayItem.link)
                    }
                }
             }
        }
        else
        if whoAmI == playlistTableView, let selectedPlaylist = playlistArrayController.selectedObjects.first as? NSDictionaryControllerKeyValuePair {
            let list: Array<PlayItem> = selectedPlaylist.value as! Array
            
            if list.count > 0 {
                super.dismiss(sender)
                // TODO: For now just log what we would play once we figure out how to determine when an item finishes so we can start the next
                print("play \(selectedPlaylist) \(list.count)")
                for (i,item) in list.enumerated() {
                    print("\(i) \(item.rank) \(item.name)")
                }
            }
        }
        else
        {
            Swift.print("firstResponder: \(String(describing: whoAmI))")
        }
    }
    
    // Return notification from webView controller
    @objc func gotNewHistoryItem(_ note: Notification) {
        historyCache!.value = appDelegate.histories
    }

    @IBOutlet weak var restoreButton: NSButton!
    @IBAction func restorePlaylists(_ sender: NSButton) {
        if playCache.count > 0 {
            playlists = playCache
        }
        else
        if let playArray = defaults.array(forKey: UserSettings.Playlists.keyPath) {
            playlistArrayController.remove(contentsOf: playlistArrayController.arrangedObjects as! [AnyObject])

            for playlist in playArray {
                let play = playlist as! Dictionary<String,AnyObject>
                let items = play[k.list] as! [Dictionary <String,AnyObject>]
                var list : [PlayItem] = [PlayItem]()
                for playitem in items {
                    let item = playitem as Dictionary <String,AnyObject>
                    let name = item[k.name] as! String
                    let path = item[k.link] as! String
                    let time = item[k.time] as? TimeInterval
                    let link = URL.init(string: path)
                    let rank = item[k.rank] as! Int
                    let temp = PlayItem(name:name, link:link!, time:time!, rank:rank)
                    list.append(temp)
                }
                let name = play[k.name] as? String

                // Use NSDictionaryControllerKeyValuePair Protocol setKey
                let temp = playlistArrayController.newObject() as NSDictionaryControllerKeyValuePair
                temp.key = name
                temp.value = list
                playlistArrayController.addObject(temp)
            }
        }
    }

    @IBOutlet weak var saveButton: NSButton!
    @IBAction func savePlaylists(_ sender: AnyObject) {
        let playArray = playlistArrayController.arrangedObjects as! [NSDictionaryControllerKeyValuePair]
        var temp = [Dictionary<String,AnyObject>]()
        for playlist in playArray {
            var list = Array<AnyObject>()
            for playitem in playlist.value as! [PlayItem] {
                let item : [String:AnyObject] = [k.name:playitem.name as AnyObject, k.link:playitem.link.absoluteString as AnyObject, k.time:playitem.time as AnyObject, k.rank:playitem.rank as AnyObject]
                list.append(item as AnyObject)
            }
            temp.append([k.name:playlist.key as AnyObject, k.list:list as AnyObject])
        }
        defaults.set(temp, forKey: UserSettings.Playlists.keyPath)
        defaults.synchronize()
    }
    
    @IBAction override func dismiss(_ sender: Any?) {
        super.dismiss(sender)
        
        //  If we were run modally as a window, close it
        if let ppc = self.view.window?.windowController {
            if ppc.isKind(of: PlaylistPanelController.self) {
                NSApp.abortModal()
            }
        }
        
        //    Save or go
        switch (sender! as AnyObject).tag == 0 {
            case true:
                // Save history info which might have changed
                if historyCache != nil {
                    appDelegate.histories = historyCache?.value as! Array<PlayItem>
                    UserSettings.HistoryName.value = (historyCache?.key)!
                }
                // Save to the cache
                playCache = playlists
                break
            case false:
                // Restore from cache
                playlists = playCache
        }
    }

    dynamic var hiddenColumns = Dictionary<String, Any>()
    @IBAction func toggleColumnVisiblity(_ sender: NSMenuItem) {
        let col = sender.representedObject as! NSTableColumn
        let identifier = col.identifier
        let pref = String(format: "hide.%@", identifier)
        let isHidden = !col.isHidden
        
        hiddenColumns.updateValue(String(isHidden), forKey: pref)
        defaults.set(isHidden, forKey: pref)
        col.isHidden = isHidden
     }

    // MARK:- Drag-n-Drop
    
    func draggingEntered(_ sender: NSDraggingInfo!) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard()

        if pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboardURLReadingFileURLsOnlyKey]) {
            return .copy
        }
        return .copy
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        
        item.setString(String(row), forType: "public.data")
        
        return item
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        let data = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
        let registeredTypes:[String] = ["public.data"]

        pboard.declareTypes(registeredTypes, owner: self)
        pboard.setData(data, forType: "public.data")
        
        return true
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation {
        let sourceTableView = info.draggingSource() as? NSTableView

        if sourceTableView == tableView {
            Swift.print("drag same")
        }
        else
        if sourceTableView == playlistTableView {
            Swift.print("drag from playlist")
        }
        else
        if sourceTableView == playitemTableView {
            Swift.print("drag from playitem")
        }
        if dropOperation == .above {
            let pboard = info.draggingPasteboard();
            let options = [NSPasteboardURLReadingFileURLsOnlyKey : true,
                           NSPasteboardURLReadingContentsConformToTypesKey : [kUTTypeMovie as String]] as [String : Any]
            let items = pboard.readObjects(forClasses: [NSURL.classForCoder()], options: options)
            if items!.count > 0 {
                for item in items! {
                    if (item as! NSURL).isFileReferenceURL() {
                        let fileURL : NSURL? = (item as AnyObject).filePathURL!! as NSURL
                        
                        //    if it's a video file, get and set window content size to its dimentions
                        let track0 = AVURLAsset(url:fileURL! as URL, options:nil).tracks[0]
                        if track0.mediaType != AVMediaTypeVideo
                        {
                            return NSDragOperation()
                        }
                    } else {
                        print("validate item -> \(item)")
                    }
                }
            }
            Swift.print("drag move")
            return .move
        }
        Swift.print("drag \(NSDragOperation())")
        return .every
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard()
        let options = [NSPasteboardURLReadingFileURLsOnlyKey : true,
                       NSPasteboardURLReadingContentsConformToTypesKey : [kUTTypeMovie as String]] as [String : Any]
        let sourceTableView = info.draggingSource() as? NSTableView
        var oldIndexes = [Int]()
        var oldIndexOffset = 0
        var newIndexOffset = 0

        // We have intra tableView drag-n-drop ?
        if tableView == sourceTableView {
            info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) {
                tableView.beginUpdates()

                if let str = ($0.0.item as! NSPasteboardItem).string(forType: "public.data"), let index = Int(str) {
                    oldIndexes.append(index)
                }
                // For simplicity, the code below uses `tableView.moveRowAtIndex` to move rows around directly.
                // You may want to move rows in your content array and then call `tableView.reloadData()` instead.
                
                for oldIndex in oldIndexes {
                    if oldIndex < row {
                        tableView.moveRow(at: oldIndex + oldIndexOffset, to: row - 1)
                        oldIndexOffset -= 1
                    } else {
                        tableView.moveRow(at: oldIndex, to: row + newIndexOffset)
                        newIndexOffset += 1
                    }
                }
                tableView.endUpdates()
            }
        }
        else

        // We have inter tableView drag-n-drop ?
        // if source is a playlist, drag its items into the destination via copy
        // if source is a playitem, drag all items into the destination playlist
        // creating a new playlist item unless, we're dropping onto an existing.
        
        if sourceTableView == playlistTableView {
            let selectedRowIndexes = sourceTableView?.selectedRowIndexes
            
            tableView.beginUpdates()
            for index in selectedRowIndexes! {
                let source = (playlistArrayController.arrangedObjects as! [Any])[index] as! NSDictionaryControllerKeyValuePair
                for playItem in source.value as! [PlayItem] {
                    
                    playitemArrayController.addObject(playItem)

                }
            }
            tableView.endUpdates()
        }
        else
        
        if sourceTableView == playitemTableView {
            // These playitems get dropped into a new or append a playlist
            let items: [PlayItem] = playitemArrayController.arrangedObjects as! [PlayItem]
            var selectedPlaylist: NSDictionaryControllerKeyValuePair? = playlistArrayController.selectedObjects.first as? NSDictionaryControllerKeyValuePair
            let selectedRowIndexes = sourceTableView?.selectedRowIndexes
            var list: [PlayItem]? = nil

            tableView.beginUpdates()
            if selectedPlaylist != nil && row < tableView.numberOfRows {
                selectedPlaylist = (playlistArrayController.arrangedObjects as! Array)[row]
                list = (selectedPlaylist?.value as! [PlayItem])
            }
            else
            {
                selectedPlaylist = playlistArrayController.newObject()
                list = [PlayItem]()
                let temp = NSString(format:"%p",list!) as String
                let name = "play#" + String(temp.characters.suffix(3))
                selectedPlaylist?.value = list
                selectedPlaylist?.key = name
                playlistArrayController.addObject(selectedPlaylist!)
                tableView.scrollRowToVisible(row)
                playlistTableView.reloadData()
            }
            tableView.selectRowIndexes(IndexSet.init(integer: row), byExtendingSelection: false)

            for index in selectedRowIndexes! {
                playitemArrayController.addObject(items[index])
            }
            tableView.endUpdates()
        }
        else

        //    We have a Finder drag-n-drop of file or location URLs ?
        if let items: Array<AnyObject> = pasteboard.readObjects(forClasses: [NSURL.classForCoder()], options: options) as Array<AnyObject>? {
            var play = playlistArrayController.selectedObjects.first as? NSDictionaryControllerKeyValuePair
            var okydoKey = false
            
            if (play == nil) {
                play = playlistArrayController.newObject() as NSDictionaryControllerKeyValuePair
                play?.value = Array <PlayItem>()
            
                playlistArrayController.addObject(play!)
                
                DispatchQueue.main.async {
                    self.playlistTableView.scrollRowToVisible(self.playlists.count - 1)
                }
            }
            else
            {
                okydoKey = true
            }
            
            for itemURL in items {
                if (itemURL as! NSURL).isFileReferenceURL() {
                    let fileURL : URL? = (itemURL as AnyObject).filePathURL

                    // Capture playlist name from origin folder of 1st item
                    if !okydoKey {
                        let spec = fileURL?.deletingLastPathComponent
                        let head = spec!().absoluteString
                        play?.key = head
                        okydoKey = true
                    }
                    
                    let path = fileURL!.absoluteString//.stringByRemovingPercentEncoding
                    let attr = appDelegate.metadataDictionaryForFileAt((fileURL?.path)!)
                    let time = attr?[kMDItemDurationSeconds] as! TimeInterval
                    let fuzz = (itemURL as AnyObject).deletingPathExtension!!.lastPathComponent as NSString
                    let name = fuzz.removingPercentEncoding
                    let item = PlayItem(name:name!,
                                        link:URL.init(string: path)!,
                                        time:time,
                                        rank:(playitemArrayController.arrangedObjects as AnyObject).count + 1)
                    playitemArrayController.insert(item, atArrangedObjectIndex: row + newIndexOffset)
                    newIndexOffset += 1
                } else {
                    print("accept item -> \((itemURL as AnyObject).absoluteString)")
                }
            }
            
            // Try to pick off whatever they sent us
            if items.count == 0 {
                for element in pasteboard.pasteboardItems! {
                    for type in element.types {
                        if !okydoKey {
                            play?.key = type
                        }
                        let item = element.string(forType:type)
                        var url: URL?
                        switch (type) {
                        case "public.url":
                            url = URL(string: item!)
                            break
                        case "public.file-url":
                            url = URL(string: item!)?.standardizedFileURL
                            break
                        case "com.apple.finder.node":
                            continue // handled as public.file-url
                        default:
                            Swift.print("type \(type) \(item!)")
                            continue
                        }
                        if let original = (url! as NSURL).resolvedFinderAlias() {
                            url = original
                        }

                        let attr = appDelegate.metadataDictionaryForFileAt((url?.path)!)
                        let time = attr?[kMDItemDurationSeconds] as! TimeInterval
                        let fuzz = url?.deletingPathExtension().lastPathComponent
                        let name = fuzz?.removingPercentEncoding
                        let temp = PlayItem(name: name!,
                                            link: url!,
                                            time: time,
                                            rank: (playitemArrayController.arrangedObjects as AnyObject).count + 1)
                        playitemArrayController.insert(temp, atArrangedObjectIndex: row + newIndexOffset)
                        newIndexOffset += 1

                    }
                }
            }
            
            DispatchQueue.main.async {
                let rows = IndexSet.init(integersIn: NSMakeRange(row, newIndexOffset).toRange() ?? 0..<0)
                self.playitemTableView.selectRowIndexes(rows, byExtendingSelection: false)
            }
        }
        else
        {
            Swift.print("WTF \(info)")
            return false
        }
        return true
    }

}
