//
//  MarkdownEditorAttributeKeys.swift
//

// Custom NSAttributedString keys for tracking markdown semantics in attributed strings.

import AppKit

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
  static let markdownHeadingLevel = NSAttributedString.Key("sceal.headingLevel")
  static let markdownListType = NSAttributedString.Key("sceal.listType")
  static let markdownBold = NSAttributedString.Key("sceal.bold")
  static let markdownItalic = NSAttributedString.Key("sceal.italic")
  static let markdownStrikethrough = NSAttributedString.Key("sceal.strikethrough")
  static let markdownLinkURL = NSAttributedString.Key("sceal.linkURL")
  static let markdownCodeFence = NSAttributedString.Key("sceal.codeFence")
  static let markdownCodeBlock = NSAttributedString.Key("sceal.codeBlock")
  static let markdownPromptBoundary = NSAttributedString.Key("sceal.promptBoundary")
  static let markdownPromptBoundaryKind = NSAttributedString.Key("sceal.promptBoundaryKind")
  static let markdownPromptBlock = NSAttributedString.Key("sceal.promptBlock")
  static let markdownImageBlock = NSAttributedString.Key("sceal.imageBlock")
  static let markdownImagePath = NSAttributedString.Key("sceal.imagePath")
  static let markdownImageTitle = NSAttributedString.Key("sceal.imageTitle")
  static let markdownImageWidth = NSAttributedString.Key("sceal.imageWidth")
  static let markdownSectionDivider = NSAttributedString.Key("sceal.sectionDivider")
  static let markdownHorizontalRule = NSAttributedString.Key("sceal.horizontalRule")
  static let markdownInlineCode = NSAttributedString.Key("sceal.inlineCode")
  static let markdownHeadingColor = NSAttributedString.Key("sceal.headingColor")
  static let markdownBlockquote = NSAttributedString.Key("sceal.blockquote")
  static let markdownIndentLevel = NSAttributedString.Key("sceal.indentLevel")
  static let markdownSectionHeadingColor = NSAttributedString.Key("sceal.sectionHeadingColor")
  static let markdownSectionBulletColor = NSAttributedString.Key("sceal.sectionBulletColor")
  static let markdownSectionUseSectionColor = NSAttributedString.Key(
    "sceal.sectionUseSectionColor")
}

enum MarkdownListType: String {
  case bullet
  case numbered
  case checkboxUnchecked
  case checkboxChecked
}
