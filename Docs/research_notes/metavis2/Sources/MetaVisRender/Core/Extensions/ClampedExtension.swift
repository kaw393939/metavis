// ClampedExtension.swift
// MetaVisRender
//
// Utility extension for clamping values to a range

import Foundation

// MARK: - Clamped Extension

public extension Comparable {
    /// Clamp value to a closed range
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
