import SwiftUI

struct CalendarSettingsRow: View {
    @EnvironmentObject private var state: AppState
    let calendar: CalendarInfo
    @State private var showingColours = false

    private var selected: CalendarColor { state.settings.calendarColor(for: calendar.id) }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !state.settings.hidden.contains(calendar.id) },
                set: { _ in state.toggleCalendar(calendar.id) }
            )) {
                Text(calendar.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .help(calendar.title)
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            Button { showingColours.toggle() } label: {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected.color)
                        .frame(width: 22, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15)))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Colour for \(calendar.title)")
            .accessibilityValue(CalendarPalette.swatches.first { $0.hex == selected.hex }?.name ?? "Custom, #\(selected.hex)")
            .help("Change calendar colour")
            .popover(isPresented: $showingColours, arrowEdge: .trailing) {
                colourOptions
            }
        }
    }

    private var colourOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(calendar.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 8) {
                ForEach(CalendarPalette.swatches) { swatch in
                    Button {
                        state.setCalendarColor(swatch.value, for: calendar.id)
                    } label: {
                        Circle()
                            .fill(swatch.value.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if selected.hex == swatch.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(swatch.value.foreground)
                                }
                            }
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(selected.hex == swatch.hex ? [.isSelected] : [])
                    .help(swatch.name)
                }
            }
            HStack(spacing: 8) {
                colourPreview("Upcoming", colour: selected)
                colourPreview("Past", colour: selected.block(past: true))
            }

            ColorPicker("Custom colour", selection: Binding(
                get: { selected.color },
                set: { if let value = CalendarColor(color: $0) { state.setCalendarColor(value, for: calendar.id) } }
            ), supportsOpacity: false)
            .font(.system(size: 12))
            Text("Applies only in Todaytape.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 256)
    }

    private func colourPreview(_ title: String, colour: CalendarColor) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(colour.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(colour.color, in: RoundedRectangle(cornerRadius: 8))
    }
}
