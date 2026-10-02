import SwiftUI
import AppKit

enum Theme {
    // Nordlicht Blau: ruhig, privat und klar genug für datenreiche Ansichten.
    static let accent = dynamic(light: "#176FC1", dark: "#466C82")
    static let accentStrong = dynamic(light: "#0B4F91", dark: "#86A1B1")
    static let accentSoft = dynamic(light: "#E2F0FB", dark: "#223039")
    static let stage = dynamic(light: "#DCEAF5", dark: "#090E12")
    static let workspace = dynamic(light: "#FBFCFE", dark: "#11171C")
    static let canvas = dynamic(light: "#F4F8FB", dark: "#0D1317")
    static let surface = dynamic(light: "#FFFFFF", dark: "#182026")
    static let surfaceShell = dynamic(light: "#EAF2F8", dark: "#202A31")
    static let mist = dynamic(light: "#BFD5E8", dark: "#566873")
    static let border = dynamic(light: "#D7E4EE", dark: "#303A41")
    static let textPrimary = dynamic(light: "#102233", dark: "#E8EDF0")
    static let textSecondary = dynamic(light: "#607487", dark: "#98A5AD")
    static let controlSurface = dynamic(light: "#F3F7FA", dark: "#1C242A")
    static let controlHover = dynamic(light: "#E8F1F7", dark: "#273138")
    static let chartIncome = dynamic(light: "#4D927E", dark: "#6E9486")
    static let chartExpense = dynamic(light: "#C86C68", dark: "#AD7B78")
    static let chartTransfer = dynamic(light: "#6D87A0", dark: "#748893")

    /// Typography scale — see DESIGN.md. No raw font sizes outside this list.
    static func pageTitle(_ text: String) -> Text {
        Text(text).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(textPrimary).tracking(-0.7)
    }

    static let heroFigure = Font.system(size: 62, weight: .bold, design: .rounded)
    static let sectionHeader = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 12)
    static let micro = Font.system(size: 11, weight: .medium)

    /// Spacing scale — see DESIGN.md. Only these six values.
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 18
        static let cardShell: CGFloat = 23
        static let hero: CGFloat = 24
        static let heroShell: CGFloat = 30
        static let workspace: CGFloat = 30
        static let badge: CGFloat = 36
    }

    /// Animation timing per interaction class — see DESIGN.md.
    enum Motion {
        static let hover = Animation.spring(response: 0.2, dampingFraction: 0.7)
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.65)
        static let value = Animation.spring(response: 0.35, dampingFraction: 0.8)
        static let selection = Animation.spring(response: 0.3, dampingFraction: 0.82)
    }

    static let paleGreenBackground = dynamic(light: "#EAF5F1", dark: "#1C332D")
    static let paleGreenText = dynamic(light: "#23715E", dark: "#79A997")
    static let paleYellowBackground = dynamic(light: "#FBF3DB", dark: "#332B15")
    static let paleYellowText = dynamic(light: "#956400", dark: "#E3B75B")
    static let paleRedBackground = dynamic(light: "#FDEBEC", dark: "#33191A")
    static let paleRedText = dynamic(light: "#9F2F2D", dark: "#C78B88")
    static let paleBlueBackground = accentSoft
    static let paleBlueText = accentStrong

    static func dynamic(light: String, dark: String) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 6 { value.append("FF") }
        var rgba: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgba)
        let red = CGFloat((rgba & 0xFF00_0000) >> 24) / 255
        let green = CGFloat((rgba & 0x00FF_0000) >> 16) / 255
        let blue = CGFloat((rgba & 0x0000_FF00) >> 8) / 255
        let alpha = CGFloat(rgba & 0x0000_00FF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

struct StatusTag: View {
    let text: String
    let background: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(Theme.micro)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

/// Elevation is expressed differently per appearance — see DESIGN.md:
/// light mode reads depth from a soft shadow, dark mode from a lighter fill tone
/// plus a hairline white-opacity border instead (shadows barely read on dark
/// backgrounds, so we don't fake one there).
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.lg + 2)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.9), lineWidth: 1)
            )
            .padding(5)
            .background(Theme.surfaceShell)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardShell, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.cardShell, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.06) : Theme.border.opacity(0.7), lineWidth: 0.8)
            )
            .shadow(color: Theme.accentStrong.opacity(colorScheme == .dark ? 0 : 0.065), radius: 10, x: 0, y: 4)
    }
}

/// The one deliberately bold moment in the app: the "heute frei verfügbar" figure.
/// Everything else stays quiet by comparison — spend boldness in one place, not
/// repeated across every card. The only material in the content area, no gradient,
/// no colored glow — see DESIGN.md.
struct HeroCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.09) : Color.white, lineWidth: 1)
            )
            .padding(6)
            .background(Theme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.heroShell, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.heroShell, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 1)
            )
            .shadow(color: Theme.accentStrong.opacity(colorScheme == .dark ? 0.12 : 0.16), radius: 24, x: 0, y: 12)
    }
}

/// Circular, accent-tinted icon marker for stat cards — accent at reduced opacity
/// as the fill, icon in full accent color. See DESIGN.md.
struct IconBadge: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Theme.Radius.badge, height: Theme.Radius.badge)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.22), radius: 8, y: 4)
    }
}

/// A single stat tile: icon badge top-trailing, label-over-number stack leading —
/// the "small caption above a big bold figure" hierarchy from DESIGN.md, reused
/// wherever a card boils down to one headline number.
struct StatCard<Content: View>: View {
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    content
                }
                Spacer(minLength: Theme.Space.sm)
                IconBadge(systemName: icon)
            }
        }
    }
}

/// Tactile press feedback for primary actions — motion that answers a person's
/// action, not decoration that plays on every hover.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

extension View {
    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }
}

/// Ring progress indicator with a centered value — accent stroke over a quiet
/// track, animates on value change per DESIGN.md's `.value` timing.
struct DonutRing: View {
    let progress: Double
    let centerText: String
    var tint: Color = Theme.accent
    var track: Color = Theme.accentSoft

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.value, value: progress)
            Text(centerText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 72, height: 72)
    }
}

/// Hover feedback for list rows that carry real actions (edit/delete) — signals
/// interactivity before the pointer reaches the small action buttons inside.
/// Not applied to purely informational cards; see DESIGN.md's anti-"card kit" rule.
struct InteractiveRow: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.accent.opacity(isHovering ? 0.05 : 0))
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func interactiveRow() -> some View {
        modifier(InteractiveRow())
    }

    /// Keeps scrolling available while hiding AppKit's scroller chrome even when
    /// macOS is configured to always show scroll bars.
    func financeScrollIndicatorsHidden() -> some View {
        scrollIndicators(.hidden)
            .background(ScrollIndicatorHider())
    }
}

private struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollIndicatorHiderView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollIndicatorHiderView)?.hideEnclosingScrollerIfNeeded()
    }
}

private final class ScrollIndicatorHiderView: NSView {
    private weak var configuredScrollView: NSScrollView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configuredScrollView = nil
        hideEnclosingScrollerIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configuredScrollView = nil
        hideEnclosingScrollerIfNeeded()
    }

    func hideEnclosingScrollerIfNeeded() {
        if let configuredScrollView {
            hideScrollers(on: configuredScrollView)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, configuredScrollView == nil else { return }
            guard let contentView = window?.contentView else { return }
            let targetFrame = convert(bounds, to: nil)
            guard let scrollView = allScrollViews(in: contentView).min(by: {
                frameDistance($0.convert($0.bounds, to: nil), targetFrame)
                    < frameDistance($1.convert($1.bounds, to: nil), targetFrame)
            }), frameDistance(scrollView.convert(scrollView.bounds, to: nil), targetFrame) < 12 else { return }

            hideScrollers(on: scrollView)
            configuredScrollView = scrollView
        }
    }

    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(allScrollViews)
    }

    private func frameDistance(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        abs(lhs.minX - rhs.minX)
            + abs(lhs.minY - rhs.minY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func hideScrollers(on scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
    }
}

/// Compact, app-native choice control used for chart periods. It avoids the
/// heavy system segmented-control chrome while keeping full keyboard semantics.
struct ChoiceTabs<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    init(options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) {
        self.options = options
        _selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(Theme.micro)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(selection == option ? Color.white : Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 30)
                        .background(selection == option ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .pressable()
            }
        }
        .padding(3)
        .background(Theme.controlSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
