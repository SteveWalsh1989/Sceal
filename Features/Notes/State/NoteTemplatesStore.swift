//
//  NoteTemplatesStore.swift
//

// Feature store for user-managed slash-command templates.

import Combine
import Foundation

@MainActor
final class NoteTemplatesStore: ObservableObject {
  @Published private(set) var templates: [NoteTemplate]

  private let settingsRepository: SettingsRepository

  init(settingsRepository: SettingsRepository) {
    self.settingsRepository = settingsRepository
    self.templates = settingsRepository.loadNoteTemplates()
  }

  var sortedTemplates: [NoteTemplate] {
    sorted(templates)
  }

  // Creates a new editable template and selects a unique generated command.
  @discardableResult
  func createTemplate() -> NoteTemplate.ID {
    let title = "New Template"
    let command = uniqueGeneratedTemplateCommand(for: title)
    let template = NoteTemplate(title: title, command: command)
    templates.append(template)
    sortTemplates()
    return template.id
  }

  // Deletes a template without affecting any note files.
  func deleteTemplate(id: NoteTemplate.ID) {
    templates.removeAll { $0.id == id }
  }

  // Imports templates by command, replacing local templates that use the same command.
  func mergeImportedTemplates(_ importedTemplates: [NoteTemplate]) {
    guard !importedTemplates.isEmpty else { return }

    var mergedTemplates = templates
    for importedTemplate in importedTemplates {
      let normalizedCommand = NoteTemplateCommandRules.normalizedManualInput(
        importedTemplate.command
      )
      guard !normalizedCommand.isEmpty else { continue }
      var template = importedTemplate.normalizedForCurrentVersion()
      template.command = normalizedCommand

      if let existingIndex = mergedTemplates.firstIndex(where: { $0.command == normalizedCommand })
      {
        mergedTemplates[existingIndex] = template
      } else {
        mergedTemplates.append(template)
      }
    }

    templates = sorted(mergedTemplates)
  }

  // Replaces all templates after a full-library restore.
  func replaceTemplates(_ restoredTemplates: [NoteTemplate]) {
    templates = sorted(restoredTemplates.map { $0.normalizedForCurrentVersion() })
  }

  func accessibleTemplates(limit: Int?) -> [NoteTemplate] {
    guard let limit else {
      return sortedTemplates
    }

    return Array(sortedTemplates.prefix(limit))
  }

  func template(withID templateID: NoteTemplate.ID) -> NoteTemplate? {
    templates.first { $0.id == templateID }
  }

  // Returns enabled, valid templates for slash command lookup.
  func enabledSlashCommandTemplates(
    limit: Int?,
    excluding excludedID: NoteTemplate.ID? = nil
  ) -> [NoteTemplate] {
    accessibleTemplates(limit: limit).filter { template in
      template.id != excludedID
        && template.isEnabled
        && commandValidationMessage(for: template.id) == nil
    }
  }

  // Returns the first validation message for the current command field.
  func commandValidationMessage(for templateID: NoteTemplate.ID) -> String? {
    guard let template = template(withID: templateID) else { return nil }
    let command = template.command.trimmingCharacters(in: .whitespacesAndNewlines)

    if command.isEmpty {
      return "Enter a command."
    }

    if !NoteTemplateCommandRules.isValidFormat(command) {
      return "Use lowercase letters, numbers, and hyphens only."
    }

    if EditorSlashCommandHandler.reservedCommandNames.contains(command) {
      return "This command is reserved by Scéal."
    }

    let duplicateCount = templates.filter { $0.command == command }.count
    if duplicateCount > 1 {
      return "This command is already used by another template."
    }

    return nil
  }

  @discardableResult
  func mutateTemplate(id: NoteTemplate.ID, mutate: (inout NoteTemplate) -> Void) -> Bool {
    var updatedTemplates = templates
    guard let index = updatedTemplates.firstIndex(where: { $0.id == id }) else { return false }
    mutate(&updatedTemplates[index])
    templates = sorted(updatedTemplates)
    return true
  }

  func uniqueGeneratedTemplateCommand(
    for title: String,
    excluding excludedID: NoteTemplate.ID? = nil
  ) -> String {
    let base = NoteTemplateCommandRules.suggestedCommand(for: title)
    var candidate = base
    var suffix = 2

    while EditorSlashCommandHandler.reservedCommandNames.contains(candidate)
      || templates.contains(where: { $0.id != excludedID && $0.command == candidate })
    {
      candidate = "\(base)-\(suffix)"
      suffix += 1
    }

    return candidate
  }

  // Persists templates with the existing UserDefaults key and payload shape.
  func persistTemplates() throws {
    try settingsRepository.saveNoteTemplates(templates)
  }

  private func sortTemplates() {
    templates = sorted(templates)
  }

  private func sorted(_ templates: [NoteTemplate]) -> [NoteTemplate] {
    templates.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }
}
