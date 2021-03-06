//
//  UnitInterfaceViewController.swift
//  Plink
//
//  Created by acb on 08/10/2018.
//  Copyright © 2018 Kineticfactory. All rights reserved.
//

import Cocoa

// some simple protocols to make this compose nicely
protocol AcceptsAUInstance {
    var audioUnitInstance: ManagedAudioUnitInstance? { get set }
}
protocol ContainsView {
    var containedView: NSView? { get set }
}

/** The parent view controller for the unit interface window */
class UnitInterfaceViewController: NSViewController, AcceptsAUInstance {
    @IBOutlet var containerView: NSView!
    
    var audioUnitInstance: ManagedAudioUnitInstance? {
        didSet {
            self.containedView = self.audioUnitInstance?.loadInterfaceView(withSize: CGSize(width: 640, height: 480)) 
        }
    }
    var containedView: NSView? {
        didSet {
            let tabBarHeight: CGFloat = 27 // FIXME: this is a fudge; determine this empirically
            let 𝛥 = self.view.bounds.size.height - self.containerView.bounds.size.height + tabBarHeight
            if let vsize = containedView?.bounds.size {
                self.view.window?.setContentSize(CGSize(width: vsize.width, height: vsize.height+𝛥))
            }
            self.pushContainedView()
        }
    }
    var tabViewController: NSTabViewController?
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tabController = segue.destinationController as? NSTabViewController {
            self.tabViewController = tabController
        }
    }
    
    private func pushContainedView() {
        for vc in self.tabViewController?.children ?? [] {
            if var cv = vc as? ContainsView {
                cv.containedView = self.containedView
            }
            if var ai = vc as? AcceptsAUInstance {
                ai.audioUnitInstance = self.audioUnitInstance
            }
        }
    }
    
}
