import AppKit
import SwiftUI

enum OverlayMetrics {
    static let rightMargin: CGFloat = 14
    static let pinSize: CGFloat = 18
    static let pin: CGFloat = pinSize
    static let slimBar: CGFloat = 34
    static let slimWidth: CGFloat = pin + slimBar + 10
    /// Left column for the live time when expanded. Collapsed stays `pin`.
    static let timeGutter: CGFloat = 68
    static let expandedWidth: CGFloat = timeGutter + 276
    /// Room for the chrome shadow to fade to zero without clipping.
    static let shadowPadLeading: CGFloat = 36
    static let shadowPadTrailing: CGFloat = 16
    static let shadowPadVertical: CGFloat = 36
    static let lineThickness: CGFloat = 6
    static let gutterLineThickness: CGFloat = 1
    static let tapeHeightFraction: CGFloat = 0.72
    static let axisInset: CGFloat = 14
    /// Expanded side gutter.
    static let pillInset: CGFloat = 10
    /// Collapsed side gutter. A touch tighter than `axisInset` so the slim pills read a bit wider.
    static let collapsedPillInset: CGFloat = 12
    /// Collapsed playhead: head sits in `pin`, line stops at the pill's right edge.
    static let collapsedLineWidth: CGFloat = slimWidth - pin - collapsedPillInset

    static func pillInset(progress: CGFloat) -> CGFloat {
        collapsedPillInset + (pillInset - collapsedPillInset) * progress
    }

    static func shellLeading(progress: CGFloat) -> CGFloat {
        pin + (timeGutter - pin) * progress
    }

    static var panelExtraWidth: CGFloat { shadowPadLeading + shadowPadTrailing }
    static var panelExtraHeight: CGFloat { shadowPadVertical * 2 }
    static let grabberWidth: CGFloat = 22
    static let grabberHeight: CGFloat = 56
    static let shellRadius: CGFloat = 18
    static let pillRadius: CGFloat = 11
    /// Collapsed corners stay a bar, not a circle, on short blocks.
    static let collapsedPillRadius: CGFloat = 6
    static let pillGap: CGFloat = 4
    /// Expanded floor: one 13pt line plus padding.
    static let expandedMinHeight: CGFloat = 36
    /// Collapsed floor: 2× radius plus 2pt. Any higher flattens duration.
    static let compactMinHeight: CGFloat = collapsedPillRadius * 2 + 2

    static func pillRadius(progress: CGFloat) -> CGFloat {
        collapsedPillRadius + (pillRadius - collapsedPillRadius) * progress
    }
    /// Stacked title + time needs about this much pill height.
    static let stackedLabelHeight: CGFloat = 52
    static let compactDuration: TimeInterval = 45 * 60

    static func expandProgress(width: CGFloat) -> CGFloat {
        let span = expandedWidth - slimWidth
        guard span > 1 else { return 1 }
        return min(1, max(0, (width - slimWidth) / span))
    }
}

private struct TapeTheme {
    let light: Bool

    var shell: Color {
        light
            ? Color(red: 0.96, green: 0.96, blue: 0.97)
            : Color(red: 0.07, green: 0.07, blue: 0.09)
    }

    static let playhead = Color(hex: "FF3B30")

}

/// Blurred copies of the chrome so the shadow's alpha reaches zero
/// instead of a clipped drop-shadow ring.
private struct ElevatedChrome<S: Shape>: View {
    let shape: S
    let fill: Color

    var body: some View {
        ZStack {
            shape
                .fill(Color.black.opacity(0.06))
                .blur(radius: 2)
                .offset(y: 1)
                .allowsHitTesting(false)
            shape
                .fill(Color.black.opacity(0.12))
                .blur(radius: 18)
                .offset(y: 8)
                .allowsHitTesting(false)
            shape
                .fill(fill)
                .contentShape(shape)
        }
    }
}

struct OverlayView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Group {
            if !state.signedIn {
                signInChip
            } else if state.overlayHidden {
                HideGrabber(theme: TapeTheme(light: state.settings.lightMode))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventTape(state: state, theme: TapeTheme(light: state.settings.lightMode))
            }
        }
    }

    private var signInChip: some View {
        let theme = TapeTheme(light: state.settings.lightMode)
        return VStack(spacing: 8) {
            Text("Todaytape")
                .font(.system(size: 12, weight: .semibold))
            Button(state.phase == .connecting ? "Waiting for Google…" : "Set up") {
                OverlayController.shared.openSettings()
            }
            .controlSize(.small)
        }
        .foregroundStyle(theme.light ? Color.primary : Color.white)
        .padding(12)
        .background {
            ElevatedChrome(
                shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                fill: theme.shell
            )
        }
        .padding(.leading, OverlayMetrics.pin + OverlayMetrics.shadowPadLeading)
        .padding(.trailing, OverlayMetrics.shadowPadTrailing)
        .padding(.vertical, OverlayMetrics.shadowPadVertical)
    }
}

private struct HideGrabber: View {
    @ObservedObject private var state = AppState.shared
    let theme: TapeTheme
    @State private var hovering = false

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
        Button {
            state.setOverlayHidden(false)
        } label: {
            ZStack {
                shape
                    .fill(theme.shell)
                    .opacity(hovering ? 0.4 : 0.075)
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.light ? Color.black : Color.white)
                    .opacity(hovering ? 0.4 : 0.16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.22), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show Todaytape")
    }
}

private struct TapeCornerMenu: View {
    @ObservedObject private var state = AppState.shared
    let theme: TapeTheme
    @State private var hovering = false
    @State private var open = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if open {
                menuCard
            }
            Button {
                open.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.light ? Color.black.opacity(0.55) : Color.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(theme.light ? Color.black.opacity(0.06) : Color.white.opacity(0.1))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering || open ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: hovering || open)
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var menuCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow("Dark", checked: !state.settings.lightMode) {
                state.setLightMode(false)
                open = false
            }
            menuRow("Light", checked: state.settings.lightMode) {
                state.setLightMode(true)
                open = false
            }
            Rectangle()
                .fill(theme.light ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            menuRow("Hide", checked: false) {
                open = false
                state.setOverlayHidden(true)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 128)
        .background(theme.shell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    private func menuRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(theme.light ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Slim and expanded are one view. Width of the panel drives the morph
/// (capsule → cards, labels fade in) so the now-pin stays put.
private struct EventTape: View {
    @ObservedObject var state: AppState
    @ObservedObject private var clock = AppClock.shared
    let theme: TapeTheme

    var body: some View {
        let (start, end) = state.dayWindow(on: clock.now)
        let span = max(end.timeIntervalSince(start), 1)
        let allDay = state.allDayEvents
        GeometryReader { geo in
            let tapeWidth = max(0, geo.size.width - OverlayMetrics.panelExtraWidth)
            let tapeHeight = max(0, geo.size.height - OverlayMetrics.panelExtraHeight)
            let progress = OverlayMetrics.expandProgress(width: tapeWidth)
            let axis = tapeHeight - OverlayMetrics.axisInset * 2 - allDayHeight(allDay)
            let tapeTop = allDayHeight(allDay)
            let events = state.timedEvents
            let frames = mixedFrames(events, start: start, span: span, axis: axis, progress: progress)
            let nowY = tapeTop + OverlayMetrics.axisInset + yOnFrames(
                clock.now, events: events, frames: frames, start: start, span: span, axis: axis
            )

            ZStack(alignment: .topLeading) {
                ElevatedChrome(
                    shape: RoundedRectangle(cornerRadius: OverlayMetrics.shellRadius, style: .continuous),
                    fill: theme.shell
                )
                .padding(.leading, OverlayMetrics.shellLeading(progress: progress))

                if !allDay.isEmpty {
                    allDayStrip(allDay, progress: progress)
                }

                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let frame = frames[index]
                    let y = tapeTop + OverlayMetrics.axisInset + frame.y
                    block(
                        event,
                        y: y,
                        height: min(frame.height, max(0, tapeTop + OverlayMetrics.axisInset + axis - y)),
                        progress: progress
                    )
                }

                NowPin(now: clock.now, progress: progress, width: tapeWidth)
                    .offset(y: nowY - OverlayMetrics.pinSize / 2)
                    .zIndex(1000)
            }
            .frame(width: tapeWidth, height: tapeHeight, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                if progress > 0.72 {
                    TapeCornerMenu(theme: theme)
                        .padding(.trailing, OverlayMetrics.pillInset + 4)
                        .padding(.bottom, 12)
                }
            }
            .padding(.leading, OverlayMetrics.shadowPadLeading)
            .padding(.trailing, OverlayMetrics.shadowPadTrailing)
            .padding(.vertical, OverlayMetrics.shadowPadVertical)
        }
    }

    private func allDayHeight(_ events: [DayEvent]) -> CGFloat {
        events.isEmpty ? 0 : CGFloat(events.count) * 30 + 12
    }

    private func allDayStrip(_ events: [DayEvent], progress: CGFloat) -> some View {
        VStack(spacing: 4) {
            ForEach(events) { event in
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(state.blockColor(for: event, at: clock.now).foreground)
                    .opacity(labelOpacity(progress))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(state.blockColor(for: event, at: clock.now).color)
                    )
            }
        }
        .padding(.leading, OverlayMetrics.shellLeading(progress: progress) + OverlayMetrics.pillInset(progress: progress))
        .padding(.trailing, OverlayMetrics.pillInset(progress: progress))
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func block(_ event: DayEvent, y: CGFloat, height: CGFloat, progress: CGFloat) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: OverlayMetrics.pillRadius(progress: progress),
            style: .continuous
        )
        let alignment: Alignment = ExpandedLabel.isCompact(event, height: height) ? .leading : .topLeading
        let inset = OverlayMetrics.pillInset(progress: progress)
        return Button {
            if let url = event.joinURL { NSWorkspace.shared.open(url) }
            else if let url = event.htmlLink { NSWorkspace.shared.open(url) }
        } label: {
            // Size the pill from the tape, not the label. Overlay text so collapsed
            // title+time rows cannot stretch the block to the window edge.
            shape
                .fill(state.blockColor(for: event, at: clock.now).color)
                .overlay {
                    ExpandedLabel(event: event, now: clock.now, height: height, foreground: state.blockColor(for: event, at: clock.now).foreground)
                        .opacity(labelOpacity(progress))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                }
                .clipShape(shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .padding(.leading, OverlayMetrics.shellLeading(progress: progress) + inset)
        .padding(.trailing, inset)
        .frame(maxWidth: .infinity, minHeight: 0)
        .frame(height: height)
        .offset(y: y)
    }

    private func labelOpacity(_ progress: CGFloat) -> CGFloat {
        let t = (progress - 0.28) / 0.45
        return min(1, max(0, t))
    }

    private func yPos(_ date: Date, start: Date, span: TimeInterval, height: CGFloat) -> CGFloat {
        CGFloat(min(max(0, date.timeIntervalSince(start) / span), 1)) * height
    }

    private func mixedFrames(
        _ events: [DayEvent],
        start: Date,
        span: TimeInterval,
        axis: CGFloat,
        progress: CGFloat
    ) -> [BlockFrame] {
        let collapsed = packedFrames(
            events, start: start, span: span, axis: axis,
            minHeight: OverlayMetrics.compactMinHeight, gap: 0
        )
        let expanded = packedFrames(
            events, start: start, span: span, axis: axis,
            minHeight: OverlayMetrics.expandedMinHeight, gap: OverlayMetrics.pillGap
        )
        return zip(collapsed, expanded).map { a, b in
            BlockFrame(
                y: a.y + (b.y - a.y) * progress,
                height: a.height + (b.height - a.height) * progress
            )
        }
    }

    private func frames(
        _ events: [DayEvent],
        start: Date,
        span: TimeInterval,
        axis: CGFloat,
        minHeight: CGFloat,
        gap: CGFloat
    ) -> [BlockFrame] {
        let last = events.count - 1
        return events.enumerated().map { i, event in
            let y = yPos(event.start, start: start, span: span, height: axis)
            let prop = CGFloat(event.duration / span) * axis
            let h = max(minHeight, prop - (i == last ? 0 : gap))
            return BlockFrame(y: y, height: h)
        }
    }

    /// Floor short events, push later blocks down, steal from empty gaps if we run off the tape.
    private func packedFrames(
        _ events: [DayEvent],
        start: Date,
        span: TimeInterval,
        axis: CGFloat,
        minHeight: CGFloat,
        gap: CGFloat
    ) -> [BlockFrame] {
        let n = events.count
        guard n > 0 else { return [] }
        var result = frames(events, start: start, span: span, axis: axis, minHeight: minHeight, gap: gap)
        for i in 1..<n {
            let floorY = result[i - 1].y + result[i - 1].height + gap
            if result[i].y < floorY {
                result[i].y = floorY
            }
        }
        let overflow = result[n - 1].y + result[n - 1].height - axis
        if overflow > 0.5 {
            result[n - 1].y = axis - result[n - 1].height
            for i in stride(from: n - 2, through: 0, by: -1) {
                let maxY = result[i + 1].y - result[i].height - gap
                if result[i].y > maxY {
                    result[i].y = maxY
                }
            }
            if result[0].y < 0 {
                let total = result.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(n - 1) * gap
                if total > axis, total > 0 {
                    let scale = axis / total
                    for i in 0..<n { result[i].height *= scale }
                }
                var cursor: CGFloat = 0
                for i in 0..<n {
                    result[i].y = cursor
                    cursor += result[i].height + gap
                }
            }
        }
        return result
    }

    private func yOnFrames(
        _ date: Date,
        events: [DayEvent],
        frames: [BlockFrame],
        start: Date,
        span: TimeInterval,
        axis: CGFloat
    ) -> CGFloat {
        guard !events.isEmpty, events.count == frames.count else {
            return yPos(date, start: start, span: span, height: axis)
        }
        if date <= events[0].start { return frames[0].y }
        let last = events.count - 1
        if date >= events[last].end { return frames[last].y + frames[last].height }
        for i in 0..<events.count {
            let event = events[i]
            if date < event.start {
                let prev = events[i - 1]
                let gapSpan = event.start.timeIntervalSince(prev.end)
                let y0 = frames[i - 1].y + frames[i - 1].height
                let y1 = frames[i].y
                guard gapSpan > 0.001 else { return y1 }
                let t = CGFloat(date.timeIntervalSince(prev.end) / gapSpan)
                return y0 + min(max(0, t), 1) * (y1 - y0)
            }
            if date < event.end {
                let dur = max(event.duration, 0.001)
                let t = CGFloat(date.timeIntervalSince(event.start) / dur)
                return frames[i].y + min(max(0, t), 1) * frames[i].height
            }
        }
        return axis
    }
}

private struct BlockFrame {
    var y: CGFloat
    var height: CGFloat
}

private struct ExpandedLabel: View {
    let event: DayEvent
    let now: Date
    let height: CGFloat
    let foreground: Color

    static func isCompact(_ event: DayEvent, height: CGFloat) -> Bool {
        event.duration < OverlayMetrics.compactDuration || height < OverlayMetrics.stackedLabelHeight
    }

    var body: some View {
        let current = event.contains(now)
        let titleWeight: Font.Weight = current ? .semibold : .medium
        let compact = Self.isCompact(event, height: height)
        Group {
            if height < 22 {
                Text(event.title)
                    .font(.system(size: 12, weight: titleWeight))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(event.title)
                        .font(.system(size: 13, weight: titleWeight))
                        .foregroundStyle(foreground)
                        .lineLimit(compact ? 1 : 2)
                        .frame(minWidth: 0)
                    Spacer(minLength: 4)
                    timeText
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 6 : 8)
    }

    private var timeText: some View {
        Text(Self.range(event.start, event.end))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .layoutPriority(1)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm"
        return f
    }()

    private static let period: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()

    static func range(_ start: Date, _ end: Date) -> String {
        let a = clock.string(from: start)
        let b = clock.string(from: end)
        let pa = period.string(from: start)
        let pb = period.string(from: end)
        if pa == pb {
            return "\(a)-\(b) \(pb)"
        }
        return "\(a) \(pa)-\(b) \(pb)"
    }
}

private struct NowPin: View {
    let now: Date
    let progress: CGFloat
    let width: CGFloat

    var body: some View {
        let t = progress
        let leading = OverlayMetrics.shellLeading(progress: t)
        let gap = OverlayMetrics.pillInset(progress: t) * t
        let thick = OverlayMetrics.lineThickness
            + (OverlayMetrics.gutterLineThickness - OverlayMetrics.lineThickness) * t
        let lineEnd = OverlayMetrics.slimWidth - OverlayMetrics.collapsedPillInset
            + (width - OverlayMetrics.pillInset(progress: t)
                - (OverlayMetrics.slimWidth - OverlayMetrics.collapsedPillInset)) * t
        let lineStart = leading + gap
        let lineWidth = max(0, lineEnd - lineStart)
        let color = TapeTheme.playhead

        HStack(spacing: gap) {
            ZStack(alignment: .trailing) {
                Circle()
                    .fill(color)
                    .frame(width: OverlayMetrics.pinSize, height: OverlayMetrics.pinSize)
                    .opacity(max(CGFloat(0), CGFloat(1) - t * 1.35))
                Text(Self.clock.string(from: now))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(color)
                    .opacity(max(CGFloat(0), (t - 0.22) / 0.45))
                    .padding(.trailing, 8)
                    .offset(x: gap)
            }
            .frame(width: leading, height: OverlayMetrics.pinSize)

            Rectangle()
                .fill(color)
                .frame(width: lineWidth, height: thick)
        }
        .allowsHitTesting(false)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f
    }()
}
