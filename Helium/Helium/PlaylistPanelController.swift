//
//  PlaylistPanelController.swift
//  Helium
//
//  Created by Carlos D. Santiago on 2/15/17.
//  Copyright (c) 2017 Carlos D. Santiago. All rights reserved.
//

import Foundation

class PlaylistPanelController : NSWindowController,NSWindowDelegate {
    
    fileprivate var panel: NSPanel! {
        get {
            return (self.window as! NSPanel)
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        if let window = self.window, let pvc = window.contentViewController {
            //  call playlist view windowShouldClose() on close
            window.delegate = (pvc as! PlaylistViewController)
        }
    }
}
