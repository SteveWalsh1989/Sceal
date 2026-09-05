//
//  StructuredNotesCutoverStatus.swift
//

// Persists whether the production library still needs its safety-backed structured conversion.

import Foundation

nonisolated enum StructuredNotesCutoverStatus: String, Codable, Equatable, Sendable {
  case notStarted
  case conversionRequired
  case completed
  case failedValidation
  case recoveryRequired
}
