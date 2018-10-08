//
//  MixerStripCollectionViewItem.swift
//  Plink
//
//  Created by acb on 30/08/2018.
//  Copyright © 2018 Kineticfactory. All rights reserved.
//

import Cocoa

class MixerStripCollectionViewItem: NSCollectionViewItem {
    
    var channel: AudioSystem.Channel? = nil
    
    // arguments: the view from which the request was launched
    var onRequestInstrumentChoice: ((NSView)->())?
    var onRequestInsertAdd: ((NSView)->())?

    var onRequestAUInterfaceWindowOpen: ((AudioUnitGraph.Node)->())?

    @IBOutlet var nameField: NSTextField!
    @IBOutlet var levelSlider: NSSlider!
    @IBOutlet var panSlider: NSSlider!
    @IBOutlet var nodesCollectionView: NSCollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        ["MixerStripAddNodeCollectionViewItem","MixerStripNodeCollectionViewItem"].forEach { (nib) in
            nodesCollectionView.register(NSNib(nibNamed: nib, bundle: nil), forItemWithIdentifier: NSUserInterfaceItemIdentifier(nib))
        }
    }
    
    public func refresh() {
        self.nodesCollectionView.reloadData()
    }
    
    @IBAction func nameChanged(_ sender: Any) {
        self.channel?.name = self.nameField.stringValue
    }
    
    @IBAction func levelChanged(_ sender: Any) {
        self.channel?.gain = self.levelSlider.floatValue
    }
    
    @IBAction func panChanged(_ sender: Any) {
        self.channel?.pan = self.panSlider.floatValue
    }
}

extension MixerStripCollectionViewItem: NSCollectionViewDataSource {
    
    enum Section: Int {
        case instrument = 0
        case inserts = 1
    }
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 2
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        switch(section) {
        case Section.instrument.rawValue: return 1
        case Section.inserts.rawValue : return (self.channel?.inserts.count).map { $0 + 1 } ?? 0
        default: return 0
        }
    }
    
    private func node(forIndexPath indexPath: IndexPath) -> AudioUnitGraph.Node? {
        switch(indexPath[0]) {
        case Section.instrument.rawValue: return channel?.instrument
        case Section.inserts.rawValue:
            guard let inserts = channel?.inserts else { return nil }
            guard indexPath[1]<inserts.count else { return nil }
            return inserts[indexPath[1]]
        default: return nil
            //        case 0:
            //            return
        }
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        
        guard let node = self.node(forIndexPath: indexPath) else {
            let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MixerStripAddNodeCollectionViewItem"), for: indexPath) as! OneButtonCollectionViewItem
            item.onPress = (indexPath[0] == 0 ? self.onRequestInstrumentChoice : self.onRequestInsertAdd)
            return item
        }
        
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MixerStripNodeCollectionViewItem"), for: indexPath)
        guard let collectionViewItem = item as? MixerStripNodeCollectionViewItem else {
            return item
        }
        collectionViewItem.view.wantsLayer = true
        collectionViewItem.view.layer?.backgroundColor = (indexPath[0] == Section.instrument.rawValue) ? NSColor.instrumentNode.cgColor : NSColor.audioEffectNode.cgColor
        collectionViewItem.view.layer?.cornerRadius = 2.0
        collectionViewItem.titleLabel.stringValue = (try? node.getInstance())?.getAudioUnitComponent()?.componentName ?? ""
        collectionViewItem.onChangePressed = self.onRequestInstrumentChoice
        collectionViewItem.onShowWindowPressed = { [weak self] () in self?.onRequestAUInterfaceWindowOpen?(node) }
        return item
    }
}

extension MixerStripCollectionViewItem: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        return NSSize(width: self.view.bounds.width - 4.0, height: 30.0)
    }
}