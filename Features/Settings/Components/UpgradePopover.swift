//
//  UpgradePopover.swift
//

// Shared paid-feature lock affordances for settings controls.

import SwiftUI

struct UpgradeLockIndicator: View {
  let capability: AppCapability
  let title: String
  let message: String

  @State private var isPopoverPresented = false

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      Image(systemName: "lock.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.orange)
        .frame(width: 24, height: 24)
        .background(.orange.opacity(0.14), in: Circle())
        .overlay(
          Circle()
            .strokeBorder(.orange.opacity(0.22), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .help("Upgrade to Paid")
    .accessibilityLabel("\(capability.displayName) requires Paid")
    .onHover { isHovering in
      guard isHovering else { return }
      isPopoverPresented = true
    }
    .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
      UpgradePopoverContent(
        capability: capability,
        title: title,
        message: message
      )
    }
  }
}

struct UpgradeLockedStatus: View {
  let text: String
  let capability: AppCapability
  let title: String
  let message: String

  var body: some View {
    HStack(spacing: 8) {
      UpgradeLockIndicator(capability: capability, title: title, message: message)

      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

struct UpgradeLockedBanner: View {
  let capability: AppCapability
  let title: String
  let message: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      UpgradeLockIndicator(capability: capability, title: title, message: message)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.subheadline.weight(.semibold))

        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.orange.opacity(0.20), lineWidth: 1)
    )
  }
}

private struct UpgradePopoverContent: View {
  let capability: AppCapability
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Image(systemName: "lock.fill")
          .foregroundStyle(.orange)

        Text("Paid Feature")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.headline)

        Text(message)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("Paid also includes")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(AppCapability.allCases) { paidCapability in
          Label(
            paidCapability.displayName,
            systemImage: paidCapability == capability ? "checkmark.circle.fill" : "circle"
          )
          .font(.caption)
          .foregroundStyle(paidCapability == capability ? .primary : .secondary)
        }
      }

      Button {
        // TODO: Connect this to the StoreKit purchase flow before Mac App Store release.
      } label: {
        Label("Upgrade", systemImage: "arrow.up.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    }
    .padding(14)
    .frame(width: 300, alignment: .leading)
  }
}
