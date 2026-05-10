//
//  NotesStore+Templates.swift
//

// NotesStore extension for custom slash-command template management.

import Foundation
import SwiftUI

extension NotesStore {
  var sortedNoteTemplates: [NoteTemplate] {
    noteTemplates.sorted {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  var accessibleNoteTemplates: [NoteTemplate] {
    guard let templateLimit = featureAccess.templateLimit else {
      return sortedNoteTemplates
    }

    return Array(sortedNoteTemplates.prefix(templateLimit))
  }

  var canCreateNoteTemplate: Bool {
    featureAccess.canCreateTemplate(currentTemplateCount: noteTemplates.count)
  }

  // Creates a new editable template and selects a unique generated command.
  @discardableResult
  func createNoteTemplate() -> NoteTemplate.ID {
    let title = "New Template"
    let command = uniqueGeneratedTemplateCommand(for: title)
    let template = NoteTemplate(title: title, command: command)
    noteTemplates.append(template)
    sortTemplates()
    persistNoteTemplates()
    return template.id
  }

  // Creates a template from UI actions only when the active plan allows it.
  @discardableResult
  func createNoteTemplateIfAllowed() -> NoteTemplate.ID? {
    guard canCreateNoteTemplate else {
      userMessage = (text: "Paid is required to create more templates.", kind: .info)
      return nil
    }

    return createNoteTemplate()
  }

  // Returns whether the template is present but outside the active plan's template limit.
  func isNoteTemplateLockedByPlan(_ templateID: NoteTemplate.ID) -> Bool {
    guard let templateLimit = featureAccess.templateLimit else { return false }
    guard let index = sortedNoteTemplates.firstIndex(where: { $0.id == templateID }) else {
      return false
    }
    return index >= templateLimit
  }

  // Deletes the template and persists the updated template list.
  func deleteNoteTemplate(id: NoteTemplate.ID) {
    noteTemplates.removeAll { $0.id == id }
    persistNoteTemplates()
    resetNewNoteDefaultIfTemplateMissing()
  }

  // Imports templates by command, replacing local templates that use the same command.
  func mergeImportedNoteTemplates(_ importedTemplates: [NoteTemplate]) {
    guard !importedTemplates.isEmpty else { return }

    var merged = noteTemplates
    for importedTemplate in importedTemplates {
      let normalizedCommand = NoteTemplateCommandRules.normalizedManualInput(
        importedTemplate.command
      )
      guard !normalizedCommand.isEmpty else { continue }
      var template = importedTemplate.normalizedForCurrentVersion()
      template.command = normalizedCommand

      if let existingIndex = merged.firstIndex(where: { $0.command == normalizedCommand }) {
        merged[existingIndex] = template
      } else {
        merged.append(template)
      }
    }

    noteTemplates = merged
    sortTemplates()
    persistNoteTemplates()
    resetNewNoteDefaultIfTemplateMissing()
  }

  // Replaces all templates after a full-library restore.
  func replaceNoteTemplates(_ templates: [NoteTemplate]) {
    noteTemplates = templates.map { $0.normalizedForCurrentVersion() }
    sortTemplates()
    persistNoteTemplates()
    resetNewNoteDefaultIfTemplateMissing()
  }

  // Returns enabled, valid templates for slash command lookup.
  func enabledSlashCommandTemplates(excluding excludedID: NoteTemplate.ID? = nil)
    -> [NoteTemplate]
  {
    accessibleNoteTemplates.filter { template in
      template.id != excludedID
        && template.isEnabled
        && templateCommandValidationMessage(for: template.id) == nil
    }
  }

  func templateTitleBinding(for templateID: NoteTemplate.ID) -> Binding<String> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.title ?? "" },
      set: { self.updateTemplateTitle(id: templateID, title: $0) }
    )
  }

  func templateCommandBinding(for templateID: NoteTemplate.ID) -> Binding<String> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.command ?? "" },
      set: { self.updateTemplateCommand(id: templateID, command: $0) }
    )
  }

  func templateDescriptionBinding(for templateID: NoteTemplate.ID) -> Binding<String> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.menuDescription ?? "" },
      set: { self.updateNoteTemplate(id: templateID) { $0.menuDescription = $1 }($0) }
    )
  }

  func templateBodyBinding(for templateID: NoteTemplate.ID) -> Binding<String> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.body ?? "" },
      set: { body in
        self.mutateNoteTemplate(id: templateID) { template in
          template.body = body
          normalizeEdgeDividersIntoOptions(for: &template)
        }
      }
    )
  }

  func templateEnabledBinding(for templateID: NoteTemplate.ID) -> Binding<Bool> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.isEnabled ?? true },
      set: { enabled in
        self.mutateNoteTemplate(id: templateID) { $0.isEnabled = enabled }
      }
    )
  }

  func templateCursorPlacementBinding(for templateID: NoteTemplate.ID)
    -> Binding<NoteTemplateCursorPlacement>
  {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.cursorPlacement ?? .automatic },
      set: { placement in
        self.mutateNoteTemplate(id: templateID) { $0.cursorPlacement = placement }
      }
    )
  }

  func templateSectionColorBinding(for templateID: NoteTemplate.ID) -> Binding<String?> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.sectionColorName },
      set: { colorName in
        self.mutateNoteTemplate(id: templateID) { template in
          template.sectionColorName = colorName
        }
      }
    )
  }

  func templateStartsWithDividerBinding(for templateID: NoteTemplate.ID) -> Binding<Bool> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.startsWithDivider ?? false },
      set: { startsWithDivider in
        self.mutateNoteTemplate(id: templateID) { template in
          template.startsWithDivider = startsWithDivider
          if startsWithDivider {
            template.body = NoteTemplateMarkdown.removingLeadingSectionDivider(from: template.body)
          }
        }
      }
    )
  }

  func templateEndsWithDividerBinding(for templateID: NoteTemplate.ID) -> Binding<Bool> {
    Binding(
      get: { self.noteTemplate(withID: templateID)?.endsWithDivider ?? false },
      set: { endsWithDivider in
        self.mutateNoteTemplate(id: templateID) { template in
          template.endsWithDivider = endsWithDivider
          if endsWithDivider {
            template.body = NoteTemplateMarkdown.removingTrailingSectionDivider(from: template.body)
          }
        }
      }
    )
  }

  func noteTemplate(withID templateID: NoteTemplate.ID) -> NoteTemplate? {
    noteTemplates.first { $0.id == templateID }
  }

  // Returns the first validation message for the current command field.
  func templateCommandValidationMessage(for templateID: NoteTemplate.ID) -> String? {
    guard let template = noteTemplate(withID: templateID) else { return nil }
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

    let duplicateCount = noteTemplates.filter { $0.command == command }.count
    if duplicateCount > 1 {
      return "This command is already used by another template."
    }

    return nil
  }

  // Encodes custom templates to UserDefaults so they are restored on launch.
  func persistNoteTemplates() {
    do {
      try settingsRepository.saveNoteTemplates(noteTemplates)
    } catch {
      report(error, context: "Saving templates failed")
    }
  }

  private func updateTemplateTitle(id: NoteTemplate.ID, title: String) {
    mutateNoteTemplate(id: id) { template in
      template.title = title
      if template.usesGeneratedCommand {
        template.command = uniqueGeneratedTemplateCommand(for: title, excluding: id)
      }
    }
  }

  private func updateTemplateCommand(id: NoteTemplate.ID, command: String) {
    mutateNoteTemplate(id: id) { template in
      template.command = NoteTemplateCommandRules.normalizedManualInput(command)
      template.usesGeneratedCommand = false
    }
  }

  private func updateNoteTemplate(
    id: NoteTemplate.ID,
    mutate: @escaping (inout NoteTemplate, String) -> Void
  ) -> (String) -> Void {
    return { [weak self] value in
      self?.mutateNoteTemplate(id: id) { template in
        mutate(&template, value)
      }
    }
  }

  private func mutateNoteTemplate(id: NoteTemplate.ID, mutate: (inout NoteTemplate) -> Void) {
    var updatedTemplates = noteTemplates
    guard let index = updatedTemplates.firstIndex(where: { $0.id == id }) else { return }
    mutate(&updatedTemplates[index])
    noteTemplates = updatedTemplates
    sortTemplates()
    persistNoteTemplates()
  }

  private func uniqueGeneratedTemplateCommand(
    for title: String,
    excluding excludedID: NoteTemplate.ID? = nil
  ) -> String {
    let base = NoteTemplateCommandRules.suggestedCommand(for: title)
    var candidate = base
    var suffix = 2

    while EditorSlashCommandHandler.reservedCommandNames.contains(candidate)
      || noteTemplates.contains(where: { $0.id != excludedID && $0.command == candidate })
    {
      candidate = "\(base)-\(suffix)"
      suffix += 1
    }

    return candidate
  }

  private func sortTemplates() {
    noteTemplates.sort {
      $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  private func resetNewNoteDefaultIfTemplateMissing() {
    if case .template(let templateID) = newNoteDefault,
      noteTemplate(withID: templateID) == nil
    {
      updateNewNoteDefault(.blank)
    }
  }
}

// Pulls edge divider markers out of editable content and into explicit template toggles.
private func normalizeEdgeDividersIntoOptions(for template: inout NoteTemplate) {
  if NoteTemplateMarkdown.hasLeadingSectionDivider(in: template.body) {
    template.body = NoteTemplateMarkdown.removingLeadingSectionDivider(from: template.body)
    template.startsWithDivider = true
  }

  if NoteTemplateMarkdown.hasTrailingSectionDivider(in: template.body) {
    template.body = NoteTemplateMarkdown.removingTrailingSectionDivider(from: template.body)
    template.endsWithDivider = true
  }
}
