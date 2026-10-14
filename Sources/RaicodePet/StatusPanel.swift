import RaicodePetCore
import SwiftUI

/// The dropdown behind the menu bar item, laid out like the system's own (Weather, Control Center):
/// content straight on the glass, groups split by dividers, no cards. Settings stay in the right-click menu.
struct StatusPanel: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject var pet: PetController
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            if !store.sessions.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(store.sessions, id: \.sessionId) { s in
                        SessionRow(session: s, now: app.now) { app.select(s) }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let frame = pet.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(pet.art.smoothScaling ? .high : .none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pet.art.name).font(.headline)
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var summary: String {
        let focus = store.sessions.first { $0.state == store.state }
        return StatusPill.content(for: focus, now: app.now).text ?? "All quiet"
    }
}

/// One session, like a Weather location row: symbol and name left, status right,
/// then what was asked and what came back.
private struct SessionRow: View {
    let session: SessionRecord
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let pill = StatusPill.content(for: session, now: now)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Image(systemName: pill.symbol)
                        .frame(width: 18)
                    Text(session.project)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(pill.text ?? "idle")
                        .foregroundStyle(.secondary)
                }
                summary
                    .padding(.leading, 28)  // under the project name, past the symbol
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)  // keep the text aligned with the header; the hover fill bleeds out
        .onHover { hovering = $0 }
        .help("Jump to this session")
    }

    @ViewBuilder private var summary: some View {
        if session.prompt != nil || session.result != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let prompt = session.prompt {
                    wrapping(Text(prompt).fontWeight(.medium))
                }
                if let result = session.result {
                    wrapping(Text(result).foregroundStyle(.secondary))
                }
            }
            .font(.callout)
        }
    }

    /// Full width, wrapped in full (TaskText already caps the length).
    private func wrapping(_ text: some View) -> some View {
        text
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
