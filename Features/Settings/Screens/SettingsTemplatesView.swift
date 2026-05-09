//
//  SettingsTemplatesView.swift
//

// Settings panel for creating and editing custom slash-command templates.

import SwiftUI

struct SettingsTemplatesView: View {
  @ObservedObject var store: NotesStore
  @State private var selectedTemplateID: NoteTemplate.ID?
  @AppStorage("settings.templates.listWidth") private var templateListWidth = 180.0
  @AppStorage("settings.templates.isListCollapsed") private var isTemplateListCollapsed = false
  @State private var templateListDragStartWidth: CGFloat?

  private let collapsedTemplateListWidth: CGFloat = 44
  private let defaultTemplateListWidth: CGFloat = 180
  private let minimumTemplateListWidth: CGFloat = 150
  private let maximumTemplateListWidth: CGFloat = 420
  private let minimumTemplateDetailWidth: CGFloat = 360
  private let templateListResizeHandleWidth: CGFloat = 6

  private var selectedTemplate: NoteTemplate? {
    selectedTemplateID.flatMap { store.noteTemplate(withID: $0) }
  }

  var body: some View {
    GeometryReader { proxy in
      HStack(spacing: 0) {
        if isTemplateListCollapsed {
          collapsedTemplateList
            .frame(width: collapsedTemplateListWidth)
        } else {
          templateList
            .frame(width: resolvedTemplateListWidth(totalWidth: proxy.size.width))

          templateListResizeHandle(totalWidth: proxy.size.width)
        }

        templateDetail
          .frame(minWidth: minimumTemplateDetailWidth, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear(perform: selectInitialTemplateIfNeeded)
    .onChange(of: store.noteTemplates) { _, _ in
      selectInitialTemplateIfNeeded()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var templateList: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text("Templates")
          .font(.headline)

        Spacer()

        Button {
          isTemplateListCollapsed = true
        } label: {
          Image(systemName: "sidebar.leading")
        }
        .help("Collapse template list")
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)

      List(selection: $selectedTemplateID) {
        ForEach(store.sortedNoteTemplates) { template in
          TemplateListRow(template: template)
            .tag(template.id)
        }
      }
      .listStyle(.sidebar)

      Divider()

      HStack {
        Button {
          selectedTemplateID = store.createNoteTemplate()
        } label: {
          Image(systemName: "plus")
        }
        .help("Add template")

        Button {
          deleteSelectedTemplate()
        } label: {
          Image(systemName: "trash")
        }
        .help("Delete template")
        .disabled(selectedTemplateID == nil)

        Spacer()
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
  }

  private var collapsedTemplateList: some View {
    VStack(spacing: 12) {
      Button {
        isTemplateListCollapsed = false
      } label: {
        Image(systemName: "sidebar.trailing")
      }
      .help("Show template list")

      Button {
        selectedTemplateID = store.createNoteTemplate()
        isTemplateListCollapsed = false
      } label: {
        Image(systemName: "plus")
      }
      .help("Add template")

      Spacer()
    }
    .buttonStyle(.borderless)
    .padding(.top, 10)
  }

  @ViewBuilder
  private var templateDetail: some View {
    if let template = selectedTemplate {
      TemplateDetailView(store: store, template: template)
        .id(template.id)
    } else {
      ContentUnavailableView("No Template Selected", systemImage: "text.badge.plus")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func selectInitialTemplateIfNeeded() {
    if let selectedTemplateID, store.noteTemplate(withID: selectedTemplateID) != nil {
      return
    }
    selectedTemplateID = store.sortedNoteTemplates.first?.id
  }

  private func deleteSelectedTemplate() {
    guard let selectedTemplateID else { return }
    store.deleteNoteTemplate(id: selectedTemplateID)
    self.selectedTemplateID = store.sortedNoteTemplates.first?.id
  }

  private func resolvedTemplateListWidth(totalWidth: CGFloat) -> CGFloat {
    clampedTemplateListWidth(CGFloat(templateListWidth), totalWidth: totalWidth)
  }

  private func clampedTemplateListWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let availableWidth = totalWidth - minimumTemplateDetailWidth - templateListResizeHandleWidth
    let maximumWidth = min(maximumTemplateListWidth, max(minimumTemplateListWidth, availableWidth))
    return min(max(proposedWidth, minimumTemplateListWidth), maximumWidth)
  }

  private func templateListResizeHandle(totalWidth: CGFloat) -> some View {
    Rectangle()
      .fill(Color.primary.opacity(0.001))
      .frame(width: templateListResizeHandleWidth)
      .overlay {
        Rectangle()
          .fill(Color.primary.opacity(0.14))
          .frame(width: 1)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let startWidth =
              templateListDragStartWidth ?? resolvedTemplateListWidth(totalWidth: totalWidth)
            templateListDragStartWidth = startWidth
            templateListWidth = Double(
              clampedTemplateListWidth(startWidth + value.translation.width, totalWidth: totalWidth)
            )
          }
          .onEnded { _ in
            templateListDragStartWidth = nil
          }
      )
      .help("Resize template list")
  }
}

private struct TemplateListRow: View {
  let template: NoteTemplate

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(template.title.isEmpty ? "Untitled Template" : template.title)
        .lineLimit(1)

      Text(template.slashCommand)
        .font(.caption)
        .foregroundStyle(template.isEnabled ? .secondary : .tertiary)
        .lineLimit(1)
    }
    .opacity(template.isEnabled ? 1 : 0.55)
  }
}

private struct TemplateDetailView: View {
  @ObservedObject var store: NotesStore
  let template: NoteTemplate
  private let minimumContentWidth: CGFloat = 640

  private var bodyBinding: Binding<String> {
    store.templateBodyBinding(for: template.id)
  }

  var body: some View {
    GeometryReader { proxy in
      ScrollView([.horizontal, .vertical]) {
        VStack(alignment: .leading, spacing: 18) {
          Form {
            Section("Template") {
              TextField("Title", text: store.templateTitleBinding(for: template.id))

              LabeledContent("Command") {
                HStack(spacing: 0) {
                  Text("/")
                    .foregroundStyle(.secondary)
                  TextField("", text: store.templateCommandBinding(for: template.id))
                    .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
              }

              if let validationMessage = store.templateCommandValidationMessage(for: template.id) {
                Text(validationMessage)
                  .font(.caption)
                  .foregroundStyle(.red)
              }

              TextField(
                "Menu description",
                text: store.templateDescriptionBinding(for: template.id)
              )

              Toggle("Enabled", isOn: store.templateEnabledBinding(for: template.id))

              Picker(
                "Cursor",
                selection: store.templateCursorPlacementBinding(for: template.id)
              ) {
                ForEach(NoteTemplateCursorPlacement.allCases, id: \.self) { placement in
                  Text(placement.displayName).tag(placement)
                }
              }
              .pickerStyle(.menu)
            }

            Section("Divider") {
              Toggle(
                "End with divider",
                isOn: store.templateEndsWithDividerBinding(for: template.id)
              )

              ColorSwatchRow(
                title: "Color",
                selectedColorName: store.templateSectionColorBinding(for: template.id)
              )
            }
          }
          .formStyle(.grouped)

          VStack(alignment: .leading, spacing: 10) {
            Text("Content")
              .font(.headline)

            ZStack(alignment: .topLeading) {
              if template.body.isEmpty {
                Text("Start writing...")
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 34)
                  .padding(.vertical, 30)
                  .allowsHitTesting(false)
              }

              MarkdownEditorView(
                noteID: "template-\(template.id)",
                text: bodyBinding,
                appearanceSettings: store.appearanceSettings,
                continuousSpellCheckingEnabled: store.continuousSpellCheckingEnabled,
                customSlashTemplates: store.enabledSlashCommandTemplates(excluding: template.id),
                allowsImageAttachments: false,
                allowsSectionColorEditing: false,
                appliesTemplateSectionColorOverride: true,
                templateSectionColorName: template.sectionColorName
              )
            }
            .frame(minHeight: 420)
          }
          .padding(.horizontal, 14)
          .padding(.bottom, 24)
        }
        .frame(width: max(proxy.size.width, minimumContentWidth), alignment: .topLeading)
      }
      .scrollIndicators(.visible)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ColorSwatchRow: View {
  let title: String
  @Binding var selectedColorName: String?

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 56, alignment: .leading)

      Button {
        selectedColorName = nil
      } label: {
        Text("None")
          .font(.caption)
          .frame(width: 42, height: 20)
      }
      .buttonStyle(.plain)
      .background(
        Capsule()
          .strokeBorder(selectedColorName == nil ? Color.primary : Color.primary.opacity(0.18))
      )

      ForEach(ThemePalette.colors, id: \.name) { entry in
        Button {
          selectedColorName = entry.name
        } label: {
          Circle()
            .fill(Color(nsColor: entry.color))
            .frame(width: 18, height: 18)
            .overlay(
              Circle()
                .strokeBorder(
                  selectedColorName == entry.name ? Color.primary : Color.primary.opacity(0.18),
                  lineWidth: selectedColorName == entry.name ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .help(entry.name.capitalized)
      }
    }
  }
}
