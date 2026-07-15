import SwiftUI
import AppKit

// MARK: - Settings › Shortcuts (list + describe + rebind)

struct ShortcutsSettingsView: View {
    @ObservedObject private var store = ShortcutStore.shared
    @State private var recordingId: String? = nil
    @State private var monitor: Any? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Click a shortcut to record a new key combination. Press Esc to cancel.")
                    .font(AnnFont.voice(13)).foregroundColor(DS.ink40)
                    .padding(.top, 10).padding(.bottom, 4)

                ForEach(ShortcutRegistry.categories, id: \.self) { cat in
                    section(cat)
                }

                HStack {
                    Spacer()
                    Button(action: { store.resetAll() }) {
                        Text("RESET ALL TO DEFAULTS").font(AnnFont.label(10)).tracking(0.5).foregroundColor(DS.ink60)
                            .padding(.vertical, 8).padding(.horizontal, 16)
                            .background(DS.paperRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.borderChip, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 32).padding(.bottom, 26)
        }
        .onDisappear { stopRecording() }
    }

    private func section(_ cat: String) -> some View {
        let defs = ShortcutRegistry.all.filter { $0.category == cat }
        return VStack(alignment: .leading, spacing: 0) {
            Text(cat.uppercased()).font(AnnFont.label(10)).tracking(0.8).foregroundColor(DS.ink40)
                .padding(.top, 20).padding(.bottom, 4)
            ForEach(Array(defs.enumerated()), id: \.element.id) { i, def in
                row(def)
                if i < defs.count - 1 { Rectangle().fill(DS.hairline).frame(height: 1) }
            }
        }
    }

    private func row(_ def: ShortcutDef) -> some View {
        let chord = store.chord(def.id)
        let recording = recordingId == def.id
        let conflict = store.conflict(for: def.id, chord: chord)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(def.name).font(AnnFont.serif(15, .medium)).foregroundColor(DS.ink)
                if let conflict, !recording {
                    Text("Also used by \(conflict.name)")
                        .font(AnnFont.mono(9.5)).foregroundColor(DS.redAccent)
                } else {
                    Text(def.detail).font(AnnFont.voice(12)).foregroundColor(DS.ink40)
                }
            }
            Spacer(minLength: 12)

            if store.isCustomized(def.id) {
                Button(action: { store.reset(def.id) }) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.ink40).frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Reset to default")
            }

            Button(action: { toggleRecord(def.id) }) {
                Text(recording ? "Press keys…" : chord.display)
                    .font(AnnFont.mono(12, bold: true))
                    .foregroundColor(recording ? DS.redAccent : DS.ink)
                    .frame(minWidth: 74)
                    .padding(.vertical, 7).padding(.horizontal, 12)
                    .background((recording ? DS.redAccent.opacity(0.10) : DS.paperRaised),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recording ? DS.redAccent : DS.borderChip, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Recording

    private func toggleRecord(_ id: String) {
        if recordingId == id { stopRecording(); return }
        stopRecording()
        recordingId = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil }   // Esc cancels
            if let chord = Chord.from(event: event) {
                store.setChord(id, chord)
                stopRecording()
            }
            return nil   // swallow every key while recording
        }
    }

    private func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recordingId = nil
    }
}
