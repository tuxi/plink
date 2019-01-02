//
//  ScoreModel.swift
//  Plink
//
//  Created by acb on 02/01/2019.
//  Copyright © 2019 Kineticfactory. All rights reserved.
//

import Foundation

/** The model encapsulating the Score, i.e., all events (not defined in code) mapped to a transport time. */
struct ScoreModel {
    // MARK: The Cue: a global list of timestamped actions (typically code statements to execute)
    struct Cue {
        enum Action {
            case codeStatement(String)
        }
        
        let time: TickTime
        let action: Action
    }
    
    var cueList: [Cue]
    
    init(cueList: [Cue] = []) {
        self.cueList = cueList
    }
}

extension ScoreModel.Cue: Codable {
    enum CodingKeys: String, CodingKey {
        case time
        case code
    }
    
    struct DecodingError: Swift.Error { }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.time = TickTime(try container.decode(Int.self, forKey: .time))
        if let code = try container.decodeIfPresent(String.self, forKey: .code) {
            self.action = .codeStatement(code)
        } else {
            throw DecodingError()
        }

    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.time.value, forKey: .time)
        switch(self.action) {
        case .codeStatement(let code): try container.encode(code, forKey: .code)
        }
    }
}

extension ScoreModel: Codable {
    enum CodingKeys: String, CodingKey {
        case cueList
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cueList = try container.decode([Cue].self, forKey: .cueList)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.cueList, forKey: .cueList)
    }
}