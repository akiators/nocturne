import SwiftUI

// MARK: - Palette (тёмная база в духе Mimose)

enum Palette {
    static let background = Color(hex: "#050507")
    static let surface = Color(hex: "#101014")
    static let surfaceElevated = Color(hex: "#17171E")
    static let stroke = Color.white.opacity(0.08)
    static let textPrimary = Color(hex: "#F2F2F7")
    static let textSecondary = Color(hex: "#8E8E93")
    static let accent = Color(hex: "#B66DFF")
    static let accentSecondary = Color(hex: "#FF4D9E")
    static let accentTertiary = Color(hex: "#4DD8FF")

    static var waveGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary, accentTertiary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Metrics {
    static let cornerS: CGFloat = 10
    static let cornerM: CGFloat = 14
    static let cornerL: CGFloat = 20
    static let coverSmall: CGFloat = 44
    static let coverRow: CGFloat = 56
    static let coverLarge: CGFloat = 264
    static let hPadding: CGFloat = 18
    static let miniPlayerHeight: CGFloat = 58
    static let tabBarHeight: CGFloat = 56
}

// MARK: - Typography

extension Font {
    static func display(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func title(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body() -> Font { .system(size: 15, weight: .regular) }
    static func secondary() -> Font { .system(size: 13, weight: .regular) }
    static func caption() -> Font { .system(size: 11, weight: .medium) }
    static func numeric(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
}

// MARK: - Wave background (аналог волнового градиента Mimose)

struct WaveBackground: View {
    var intensity: Double = 1.0
    @State private var animate = false

    var body: some View {
        ZStack {
            Color(Palette.background)
            Ellipse()
                .fill(Palette.accent.opacity(0.35 * intensity))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: animate ? 90 : -120, y: animate ? -160 : -60)
            Ellipse()
                .fill(Palette.accentSecondary.opacity(0.28 * intensity))
                .frame(width: 380, height: 380)
                .blur(radius: 100)
                .offset(x: animate ? -140 : 110, y: animate ? 120 : 200)
            Ellipse()
                .fill(Palette.accentTertiary.opacity(0.18 * intensity))
                .frame(width: 320, height: 320)
                .blur(radius: 110)
                .offset(x: animate ? 40 : 160, y: animate ? 260 : 40)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Glass card (матовый «стеклянный» стиль, iOS 15+)

struct GlassCard: ViewModifier {
    var radius: CGFloat = Metrics.cornerM

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Palette.stroke, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = Metrics.cornerM) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

// MARK: - Shimmer (skeleton loading)

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.10), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.7)
                        .offset(x: phase * geo.size.width)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Reusable components

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title(19))
                .foregroundColor(Palette.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.secondary())
                    .foregroundColor(Palette.accent)
            }
        }
        .padding(.horizontal, Metrics.hPadding)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Palette.textSecondary.opacity(0.6))
                .padding(.bottom, 4)
            Text(title)
                .font(.title(17))
                .foregroundColor(Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var filled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled
                        ? AnyShapeStyle(Palette.waveGradient)
                        : AnyShapeStyle(Palette.surfaceElevated))
            .foregroundColor(filled ? .white : Palette.textPrimary)
            .cornerRadius(Metrics.cornerM)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Cover image (ленивая загрузка + кэш)

final class ImageCache: NSCache<NSString, UIImage> {
    static let shared = ImageCache()
}

/// Фоновая загрузка изображений (обложки для now playing и prefetch).
final class ImageLoader {
    static let shared = ImageLoader()

    func prefetch(url: URL) async {
        let key = url.absoluteString as NSString
        guard ImageCache.shared.object(forKey: key) == nil else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ImageCache.shared.setObject(image, forKey: key)
            }
        } catch {
            // Плейсхолдер остаётся.
        }
    }
}

struct CoverImage: View {
    let url: URL?
    var size: CGFloat
    var radius: CGFloat = Metrics.cornerS

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(colors: [Palette.surfaceElevated, Palette.surface],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3))
                    .foregroundColor(Palette.textSecondary.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(radius)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        let key = url.absoluteString as NSString
        if let cached = ImageCache.shared.object(forKey: key) {
            image = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.setObject(img, forKey: key)
                image = img
            }
        } catch {
            // Пустая обложка остаётся плейсхолдером.
        }
    }
}

// MARK: - Text field style

extension View {
    /// Единый стиль полей ввода (аналог TextFieldStyle, совместим со всеми SDK).
    func styledField() -> some View {
        self
            .padding(12)
            .background(Palette.surface)
            .cornerRadius(Metrics.cornerM)
            .foregroundColor(Palette.textPrimary)
            .font(.body())
    }
}
