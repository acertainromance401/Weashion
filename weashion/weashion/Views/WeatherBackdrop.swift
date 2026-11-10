import SwiftUI

extension WeatherMood {
    /// Rain turns the cover into a dark edition: slate sky, paper-coloured masthead and captions.
    var prefersInvertedCover: Bool { self == .rain }
}

struct WeatherBackdrop: View {
    let mood: WeatherMood
    var dark = false

    private var sky: [Color] {
        if dark { return [Color(red: 0.08, green: 0.17, blue: 0.21), Color(red: 0.31, green: 0.40, blue: 0.42)] }
        switch mood {
        case .clear: return [Color(red: 0.60, green: 0.75, blue: 0.87), Color(red: 0.84, green: 0.89, blue: 0.91), Editorial.paper]
        case .cloud: return [Color(red: 0.76, green: 0.79, blue: 0.80), Color(red: 0.89, green: 0.90, blue: 0.89), Editorial.paper]
        case .rain: return [Color(red: 0.15, green: 0.20, blue: 0.24), Color(red: 0.34, green: 0.40, blue: 0.44), Editorial.paper]
        case .snow: return [Color(red: 0.90, green: 0.92, blue: 0.93), Color(red: 0.96, green: 0.96, blue: 0.95), Editorial.paper]
        }
    }

    private var cloudOpacity: Double {
        if dark { return 0.08 }
        switch mood {
        case .clear: return 0.22
        case .cloud: return 0.34
        case .rain: return 0.07
        case .snow: return 0.4
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
                if mood == .clear {
                    // A small, definite sun; overcast skies get none.
                    Circle()
                        .fill(Color(red: 1, green: 0.95, blue: 0.80).opacity(dark ? 0.3 : 0.8))
                        .frame(width: geometry.size.width * 0.17)
                        .blur(radius: 2)
                        .position(x: geometry.size.width * 0.76, y: geometry.size.height * 0.2)
                }
                Canvas { context, size in
                    for index in 0..<8 {
                        let seed = Double(index)
                        let x = (seed * 0.31).truncatingRemainder(dividingBy: 1) * size.width
                        let y = (0.12 + (seed * 0.17).truncatingRemainder(dividingBy: 0.5)) * size.height
                        let rect = CGRect(x: x - size.width * 0.2, y: y,
                                          width: size.width * (mood == .cloud ? 0.42 : 0.3) + seed * 6,
                                          height: (mood == .cloud ? 44 : 32) + seed * 4)
                        context.addFilter(.blur(radius: mood == .cloud ? 24 : 17))
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(cloudOpacity)))
                    }
                }
                if mood == .rain {
                    Canvas { context, size in
                        for index in 0..<70 {
                            let x = CGFloat((index * 37) % 101) / 101 * size.width
                            let y = CGFloat((index * 61) % 103) / 103 * size.height * 0.8
                            var line = Path()
                            line.move(to: CGPoint(x: x, y: y))
                            line.addLine(to: CGPoint(x: x - 3, y: y + 22))
                            context.stroke(line, with: .color(Editorial.paper.opacity(0.28)), lineWidth: 0.6)
                        }
                    }
                }
                if mood == .snow {
                    // Sparse flakes of different sizes, a few softened, rather than a uniform speckle.
                    Canvas { context, size in
                        for index in 0..<26 {
                            let x = CGFloat((index * 53) % 97) / 97 * size.width
                            let y = CGFloat((index * 29) % 89) / 89 * size.height * 0.85
                            let diameter = CGFloat(4 + (index * 7) % 6)
                            var flake = context
                            if index % 3 == 0 { flake.addFilter(.blur(radius: 1.5)) }
                            flake.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                                       with: .color(.white.opacity(0.92)))
                        }
                    }
                }
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, (dark ? Color.black : Editorial.paper).opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: geometry.size.height * 0.32)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
