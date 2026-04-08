import SwiftUI

/// Renders a 2D pixel art array as a grid of squares.
/// 0 = transparent, 1 = pixelColor, 2 = accentColor
struct PixelArtView: View {
    let pixels: [[Int]]
    let pixelColor: Color
    let accentColor: Color
    var gap: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let rows = pixels.count
            let cols = pixels.first?.count ?? 0
            guard rows > 0, cols > 0 else { return AnyView(EmptyView()) }

            let pixelW = (geo.size.width  - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let pixelH = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

            return AnyView(
                Canvas { context, _ in
                    for row in 0..<rows {
                        for col in 0..<pixels[row].count {
                            let val = pixels[row][col]
                            guard val != 0 else { continue }

                            let color = val == 2 ? accentColor : pixelColor
                            let x = CGFloat(col) * (pixelW + gap)
                            let y = CGFloat(row) * (pixelH + gap)
                            let rect = CGRect(x: x, y: y, width: pixelW, height: pixelH)

                            context.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            )
        }
    }
}

// MARK: - Preview helper
#Preview {
    PixelArtView(
        pixels: AppProfile.briefcaseArt,
        pixelColor: .black,
        accentColor: .orange
    )
    .frame(width: 120, height: 120)
    .padding()
    .background(Color(hex: "#F5F0E8"))
}
