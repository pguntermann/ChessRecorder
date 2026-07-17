//
//  EngineAnalysisDepthScheduleTests.swift
//  Chess RecorderTests
//

import XCTest
@testable import Chess_Recorder

final class EngineAnalysisDepthScheduleTests: XCTestCase {

    func testSequenceLandsOnConfiguredMaxDepth() {
        let target = 28
        var depth = EngineAnalysisDisplayBuilder.initialDepth(targetDepth: target, unlimited: false)
        var seen = [depth]

        while let next = EngineAnalysisDisplayBuilder.nextDepth(
            after: depth,
            targetDepth: target,
            unlimited: false
        ) {
            depth = next
            seen.append(depth)
        }

        XCTAssertEqual(seen, [6, 8, 10, 14, 18, 22, 28])
        XCTAssertEqual(seen.last, target)
    }

    func testNextDepthClampsFinalStepToTarget() {
        XCTAssertEqual(
            EngineAnalysisDisplayBuilder.nextDepth(after: 22, targetDepth: 28, unlimited: false),
            28
        )
        XCTAssertNil(
            EngineAnalysisDisplayBuilder.nextDepth(after: 28, targetDepth: 28, unlimited: false)
        )
    }

    func testDepthStatusIncludesNextStep() {
        XCTAssertEqual(
            EngineAnalysisDisplayBuilder.depthStatusMessage(
                currentDepth: 14,
                targetDepth: 28,
                unlimited: false,
                isFinal: false
            ),
            "Depth 14 of 28 (next 18)"
        )
        XCTAssertEqual(
            EngineAnalysisDisplayBuilder.depthStatusMessage(
                currentDepth: 28,
                targetDepth: 28,
                unlimited: false,
                isFinal: true
            ),
            "Depth 28"
        )
    }
}
