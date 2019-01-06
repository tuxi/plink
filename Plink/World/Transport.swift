//
//  Transport.swift
//  Plink
//
//  Created by acb on 29/12/2018.
//  Copyright © 2018 Kineticfactory. All rights reserved.
//

import Foundation

/** This handles the transport: the play position, play state and such; it also owns the Score, and is responsible for playing it */
public class Transport {
    /// The clock transmission state: i.e., how the clock gets converted to the program position, if at all
    enum TransmissionState {
        case stopped(TickTime)  // Stopped; the value is the tick time
        case starting(TickTime) // will start at the next tick from the given time
        case running(TickOffset) // pos = masterTickTime+offset
    }
    
    var transmissionState: TransmissionState = .stopped(0) {
        didSet(old) {
            print("transmissionState: \(old) -> \(self.transmissionState)")
        }
    }

    /// the metronome
    var metronome: Metronome
    
    var score: ScoreModel
    
    /// functions called to execute various score data in playback
    var cuePlayCallback: ((ScoreModel.Cue)->())?
    
    private var playContext: PlayContext?
    
    static let cueListChanged = Notification.Name("Transport.CueListChanged")
    
    init(metronome: Metronome) {
        self.metronome = metronome
        self.score = ScoreModel(cueList: [])
        self.score.onCueListChanged = {
            NotificationCenter.default.post(name: Transport.cueListChanged, object: nil)
        }
    }

    //MARK: Transmission control
    
    private func start(at time: TickTime) {
        self.playContext = PlayContext(score: self.score, time: time)
        self.transmissionState = .starting(time)
    }
    
    public func startInPlace() {
        if case let .stopped(t) = self.transmissionState {
            self.start(at: t)
        }
    }
    
    public func rewindAndStart() {
        self.start(at: 0)
    }
    
    public func stop() {
        self.transmissionState = .stopped(self.programPosition)
    }
    
    //MARK:
    

    /// The program position
    var programPosition: TickTime {
        switch(self.transmissionState) {
        case .stopped(let t): return t
        case .starting(let t): return t
        case .running(let offset): return metronome.tickTime + offset
        }
    }

    //#MARK: notifications
    public var onRunningStateChange: (()->())?

    /// callbacks to be notified of a tick if the state is currently running
    public var onRunningTick: [((TickTime)->())] = []
    
    
    private func runPlayContext(forPos pos: TickTime) {
        guard let ctx = self.playContext else { return }
        // cue list
        while let cue = ctx.nextCue(forTime: pos) {
            self.cuePlayCallback?(cue)
        }
        
    }

    /// Handle a tick from the metronome
    func metronomeTick(_ time: TickTime) {
        if case let .starting(t) = self.transmissionState {
            self.transmissionState = .running(t-self.metronome.tickTime)
        }
        if case .running(_) = self.transmissionState {
            let pos = self.programPosition
            self.runPlayContext(forPos: pos)
            for client in self.onRunningTick {
                client(pos)
            }
        }

    }
}
