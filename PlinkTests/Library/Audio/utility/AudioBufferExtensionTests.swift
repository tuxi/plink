//
//  AudioBufferExtensionTests.swift
//  PlinkTests
//
//  Created by acb on 20/03/2019.
//  Copyright © 2019 Kineticfactory. All rights reserved.
//

import XCTest
@testable import Plink

class AudioBufferExtensionTests: XCTestCase {

    func testAudioBufferFromArray() {
        let buf = AudioBuffer([Float32(3.0), -1.0, 0.5, 0.0, -23.4])
        XCTAssertEqual(buf[0], Float32(3.0))
        XCTAssertEqual(buf[1], Float32(-1.0))
        XCTAssertEqual(buf[4], Float32(-23.4))
    }
    
    func testBufferFromFunction() {
        let buf = AudioBuffer(count: 11) { (index)  in
            return index>0 ? 1.0/Float32(index) : 0.0
        }
        XCTAssertEqual(buf[2], Float32(0.5))
        XCTAssertEqual(buf[5], Float32(0.2))
        XCTAssertEqual(buf[10], Float32(0.1))
    }

    func testAudioBufferSamples() {
        let buf = AudioBuffer([Float32(3.0), -1.0, 0.5, 0.0, -23.4])
        let s: AudioBuffer.Samples<Float32> = buf.samples()
        XCTAssertEqual(s.map { $0 }, [3.0, -1.0, 0.5, 0, -23.4])
        XCTAssertEqual(s.last(where: { $0 > 0 }), 0.5)
    }
}
