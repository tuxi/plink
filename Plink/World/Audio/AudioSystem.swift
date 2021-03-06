//
//  AudioSystem.swift
//  Plink
//
//  Created by acb on 07/10/2018.
//  Copyright © 2018 Kineticfactory. All rights reserved.
//

import Foundation
import AudioToolbox

class AudioSystem {
    // TODO: what is the provenance of this?
    let numSamplesPerBuffer: UInt32 = 512
    // TODO someday: make this configurable
    let sampleRate = 44100
    var bufferDuration: Float64 { return Float64(numSamplesPerBuffer)/Float64(sampleRate) }
    
    public enum OutputMode: CaseIterable {
        /// Play the output to the hardware output in real time
        case play
        /// Render the output offline, for the benefit of anything recording the buffers
        case offlineRender
    }
    
    /// The current output mode
    var outputMode: OutputMode = .play {
        didSet(prev) {
            guard self.outputMode != prev else { return }
            // TODO: rewire the graph here
            
            self.outNode = nil // remove the old output node
            let outputDescriptionForMode: [OutputMode: AudioComponentDescription] = [
                .play: .defaultOutput,
                .offlineRender: .genericOutput
            ]
            self.outNode = try! self.graph.addNode(withDescription: outputDescriptionForMode[self.outputMode]!)
        }
    }

    let graph: AudioUnitGraph<ManagedAudioUnitInstance>
    let mixerNode: AudioUnitGraph<ManagedAudioUnitInstance>.Node
    var outNode: AudioUnitGraph<ManagedAudioUnitInstance>.Node? {
        willSet(v) {
            if v == nil && self.outNode != nil {
                try! self.mixerNode.disconnectOutput()
                try! self.outNode!.removeFromGraph()
            }
        }
        didSet(prev) {
            if let outNode = self.outNode {
                try! self.mixerNode.connect(to: outNode)
                try! self.setUpAudioRenderCallback()
            }
        }
    }
    
    struct ChannelLevelReading {
        let average: AudioUnitParameterValue
        let peak: AudioUnitParameterValue
    }

    typealias StereoLevelReading = StereoPair<ChannelLevelReading>
    
    // Add the render notify function here

    private func setUpAudioRenderCallback() throws {
        guard let outinst = try self.outNode?.getInstance() else {
            return
        }

        let audioRenderCallback: AURenderCallback = { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumFrames, ioData) -> OSStatus in
            
            let instance = unsafeBitCast(inRefCon, to: AudioSystem.self)
            
            let actionFlags = ioActionFlags.pointee
            if actionFlags.contains(.unitRenderAction_PreRender) {
                // instance.preRender(inTimeStamp.pointee.mSampleTime)
                // NOTE: the timestamp is reset every time the graph is stopped/started
                instance.onPreRender?(Int(inNumFrames), instance.sampleRate)
            }
            if ioActionFlags.pointee.contains(.unitRenderAction_PostRender) && instance.outputMode == OutputMode.offlineRender {
                //                print("post-render; buffers = \(ioData), tap = \(instance.postRenderTap)")
            }
            if ioActionFlags.pointee.contains(.unitRenderAction_PostRender),
                let buffers = ioData,
                let tap = instance.postRenderTap
            {
                //                print("- calling post-render tap")
                tap(buffers, inNumFrames)
            }
            
            return noErr
        }
        
        AudioUnitAddRenderNotify(outinst.auRef, audioRenderCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))

    }
    
    private func getMeterLevel(forScope scope: AudioUnitScope, element: AudioUnitElement) -> StereoLevelReading? {
        guard
            let audioUnit = mixerNode._audioUnit
        else { return nil }
        do {
            let lavg = try audioUnit.getParameterValue(kMultiChannelMixerParam_PostAveragePower, scope: scope, element: element)
            let lpeak = try audioUnit.getParameterValue(kMultiChannelMixerParam_PostPeakHoldLevel, scope: scope, element: element)
            let ravg = try audioUnit.getParameterValue(kMultiChannelMixerParam_PostAveragePower+1, scope: scope, element: element)
            let rpeak = try audioUnit.getParameterValue(kMultiChannelMixerParam_PostPeakHoldLevel+1, scope: scope, element: element)
            return StereoLevelReading(left: ChannelLevelReading(average: lavg, peak: lpeak), right: ChannelLevelReading(average: ravg, peak: rpeak))

        } catch {
            print("getMeterLevel: error \(error)")
            return nil
        }
    }
    public var masterLevel: StereoLevelReading? {
        return self.getMeterLevel(forScope: kAudioUnitScope_Output, element: 0)
    }
    public func level(forChannel channel: Int) -> StereoLevelReading? {
        return self.getMeterLevel(forScope: kAudioUnitScope_Input, element: AudioUnitElement(channel))
    }
    
    
    var channels: [Channel] = []
    
    /// posted when the script text changes or the script is eval'd
    static let channelsChangedNotification = Notification.Name("AudioSystem.ChannelsChanged")

    internal func channelsChanged() {
        NotificationCenter.default.post(name: AudioSystem.channelsChangedNotification, object: nil)
    }
    
    /// The callback, called from the pre-render method, to advance the time by a number of frames and cause any pending actions from the currently playing sequence and/or immediate queue to be executed, with effect on the audio system
    /// arguments: number of frames, number of frames per second (sample rate)
    typealias PreRenderCallback = ((Int, Int)->())
    var onPreRender: PreRenderCallback?
    
    /// If present, this function is called with the freshly rendered buffers immediately after rendering.
    public var postRenderTap: ((UnsafeMutablePointer<AudioBufferList>, UInt32) -> ())? = nil
    
    /// called when the audio processing graph is stopped; used to cancel any pending operations, &c.
    var onAudioInterruption: (()->())?
    
    internal func startGraph() throws {
        try self.graph.start()
    }
    
    internal func stopGraph() throws {
        try self.graph.stop()
        self.onAudioInterruption?()
    }
    
    internal func modifyingGraph(reinit: Bool = true, _ actions: (() throws ->())) throws {
        try stopGraph()
        if reinit { try graph.uninitialize() }
        try actions()
        if reinit { try graph.initialize() }
        try startGraph()
    }

    //MARK: ---
    
    init() throws {
        let graph = try AudioUnitGraph<ManagedAudioUnitInstance>()
        self.graph = graph
        self.mixerNode = try self.graph.addNode(withDescription: .multiChannelMixer)
        self.outNode = try self.graph.addNode(withDescription: .defaultOutput)
        try self.mixerNode.connect(to: self.outNode!)
        try graph.open()
        let mixerinst = try self.mixerNode.getInstance()
        try mixerinst.setParameterValue(kMultiChannelMixerParam_Volume, scope: kAudioUnitScope_Output, element: 0, to: 1.0)
        try mixerinst.setProperty(withID: kAudioUnitProperty_MeteringMode, scope: kAudioUnitScope_Output, element: 0, to: UInt32(1))
        try graph.initialize()
        
        try self.setUpAudioRenderCallback()
    }
    
    func clear() throws {
        try self.modifyingGraph {
            for ch in self.channels {
                for insert in ch._inserts {
                    try insert.disconnectAll()
                    try insert.removeFromGraph()
                }
                try ch.instrument?.disconnectAll()
                try ch.instrument?.removeFromGraph()
            }
            self.channels = []
            self.channelsChanged()
        }
    }
    
    /// add a Channel
    
    func add(channel: Channel) throws {
        let index = self.channels.count
        try self.modifyingGraph {
            try channel.headNode?.connect(element: 0, to: self.mixerNode, destElement: UInt32(index))
            try self.mixerNode._audioUnit?.setProperty(withID: kAudioUnitProperty_MeteringMode, scope: kAudioUnitScope_Input, element: UInt32(index), to: UInt32(1))
            try self.mixerNode.getInstance().setProperty(withID: kAudioUnitProperty_MeteringMode, scope: kAudioUnitScope_Output, element: 0, to: UInt32(1))
            channel.onHeadNodeChanged = { (_, _) in
                do {
                    try channel.headNode?.connect(element: 0, to: self.mixerNode, destElement: UInt32(index))
                    try self.mixerNode._audioUnit?.setProperty(withID: kAudioUnitProperty_MeteringMode, scope: kAudioUnitScope_Input, element: UInt32(index), to: UInt32(1))
                } catch {
                    fatalError("Failed to reconnect head node: \(error)")
                }
            }
            self.channels.append(channel)
            channel.audioSystem = self
            channel.index = index
            try self.mixerNode.getInstance().setParameterValue(kMultiChannelMixerParam_Volume, scope: kAudioUnitScope_Input, element: AudioUnitElement(index), to: 1.0)
            self.channelsChanged()
        }
        
    }
    
    /// Create a new Channel, with a default name and no inserts/instrument
    @discardableResult func createChannel() throws -> Channel {
        let channel = Channel(name: "ch\(self.channels.count+1)")
        try self.add(channel: channel)
        return channel
    }
    
    /// Look up a channel by name
    func channelNamed(_ name: String) -> Channel? {
        return self.channels.first(where: { $0.name == name })
    }
    
    //MARK: internal functions called from the channel
    internal func getGain(forChannelIndex index: Int) throws -> AudioUnitParameterValue {
        return try self.mixerNode.getInstance().getParameterValue(kMultiChannelMixerParam_Volume, scope: kAudioUnitScope_Input, element: AudioUnitElement(index))
    }
    internal func getPan(forChannelIndex index: Int) throws -> AudioUnitParameterValue {
        return try self.mixerNode.getInstance().getParameterValue(kMultiChannelMixerParam_Pan, scope: kAudioUnitScope_Input, element: AudioUnitElement(index))
    }
    internal func setGain(forChannelIndex index: Int, to value: AudioUnitParameterValue) throws {
        return try self.mixerNode.getInstance().setParameterValue(kMultiChannelMixerParam_Volume, scope: kAudioUnitScope_Input, element: AudioUnitElement(index), to: value)
    }
    internal func setPan(forChannelIndex index: Int, to value: AudioUnitParameterValue) throws {
        return try self.mixerNode.getInstance().setParameterValue(kMultiChannelMixerParam_Pan, scope: kAudioUnitScope_Input, element: AudioUnitElement(index), to: value)
    }
    
    //MARK: save/restore
    
    func snapshot() throws -> AudioSystemModel {
        return AudioSystemModel(channels: try self.channels.map { try $0.snapshot() })
    }
    
    func set(from snapshot: AudioSystemModel) throws {
        try self.clear()
        for ch in snapshot.channels {
            try self.add(channel: try Channel(graph: self.graph, snapshot: ch))
        }
    }
    
    //MARK: Rendering
    
    typealias RenderFrameCallback = (()->())
    
    /// a recording context, holding data through a recording process
    struct RenderContext {
        let bufferListPtr: UnsafeMutableAudioBufferListPointer
        let recordingUnit: ManagedAudioUnitInstance
        let numSamplesPerBuffer: UInt32
        var consumer: AudioBufferConsumer
        var time = AudioTimeStamp()
        var trailingSilenceCounter: TrailingSilenceCounter = TrailingSilenceCounter(count: 0, threshold: 0.00003) /* <1/32768 */
        var isRunOut: Bool
        
        init(recordingUnit: ManagedAudioUnitInstance, consumer: AudioBufferConsumer, numSamplesPerBuffer: UInt32) {
            let numChannels = 2
            self.bufferListPtr = AudioBufferList.allocate(maximumBuffers: numChannels)
            self.recordingUnit = recordingUnit
            self.consumer = consumer
            self.time.mFlags = AudioTimeStampFlags.sampleTimeValid
            self.isRunOut = false
            self.numSamplesPerBuffer = numSamplesPerBuffer
        }
        
        mutating func renderFrame() {
            do {
                try self.recordingUnit.render(timeStamp: self.time, numberOfFrames: numSamplesPerBuffer, data: &(self.bufferListPtr.unsafeMutablePointer.pointee))
                self.consumer.feed(self.bufferListPtr, self.numSamplesPerBuffer)
                self.trailingSilenceCounter.feed(bufferList: self.bufferListPtr)
                self.time.mSampleTime += Double(self.numSamplesPerBuffer)
            } catch {
                print("Error rendering frame: \(error)")
            }

        }
    }
    
    private var renderContext: RenderContext? = nil
    
    /// Cause one frame to be rendered from within the recording function; this is kept private, and passed in a callback to the function.
    private func renderFrame() {
        self.renderContext?.renderFrame()
    }
    
    /// The runout mode; what to do after the function running the rendering process has completed.
    enum RenderRunoutMode {
        /// No runout; cut off the recording immediately upon completion
        case none
        /// keep running until we get silence (S samples below the threshold) for a maximum number of buffers
        case toSilence(Int, Int)
    }
    
    func render(toConsumer consumer: (() throws -> AudioBufferConsumer), runoutMode: RenderRunoutMode = .none, running action: (RenderFrameCallback)->()) throws {
        try self.stopGraph()
        try self.graph.uninitialize()
        
        self.outputMode = .offlineRender

        try self.graph.initialize()

        // do the actual recording here
        
        let sourceNode = self.outNode!
        let outInst = try sourceNode.getInstance()
        
        self.renderContext = RenderContext(recordingUnit: outInst, consumer: try consumer(), numSamplesPerBuffer: self.numSamplesPerBuffer)
        
        action(self.renderFrame)

        switch(runoutMode) {
        case .none: break
        case .toSilence(let samples, let maxFrames):
            self.renderContext!.isRunOut = true
            var trailingFrames: Int = 0
            while self.renderContext?.trailingSilenceCounter.count ?? 0 < samples && trailingFrames < maxFrames {
                self.renderFrame()
                trailingFrames += 1
            }
            break
        }
        self.renderContext = nil
        try! self.graph.uninitialize()
        self.outputMode = .play
        try! self.graph.initialize()
        try! self.startGraph()
    }
    
    func render(toURL url: URL, runoutMode: RenderRunoutMode = .none, running action: (RenderFrameCallback)->()) throws {
        let makeRecorder = { () throws -> AudioBufferConsumer in
            let sourceNode = self.outNode!
            let outInst = try sourceNode.getInstance()
            let typeID: AudioFileTypeID = kAudioFileAIFFType // FIXME
            let asbd: AudioStreamBasicDescription = try outInst.getProperty(withID: kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Global, element: 0)
            return try AudioBufferFileRecorder(to: url, ofType: typeID, forStreamDescription: asbd)
        }
        try self.render(toConsumer: makeRecorder, runoutMode: runoutMode, running: action)
    }
    
    func render(to file: String, runoutMode: RenderRunoutMode = .none, running action: (RenderFrameCallback)->()) throws {
        try self.render(toURL: URL(fileURLWithPath: file), runoutMode: runoutMode, running: action)
    }
}

