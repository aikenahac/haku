import SwiftUI

/// Parses SVG path data (`d` attribute) into a SwiftUI `Path`, so the design's
/// exact vectors (glyph, icons, squiggles) can be reused verbatim.
/// Supports M L H V C S Q T A Z, absolute and relative.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var parser = Parser(d)
        return parser.run()
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "

        init(_ d: String) { chars = Array(d) }

        mutating func run() -> Path {
            var command: Character = " "
            while true {
                skipSeparators()
                guard i < chars.count else { break }
                if chars[i].isLetter {
                    command = chars[i]
                    i += 1
                } else if command == "M" {
                    command = "L"  // implicit lineto after moveto
                } else if command == "m" {
                    command = "l"
                }
                apply(command)
                lastCommand = command
            }
            return path
        }

        mutating func apply(_ c: Character) {
            let rel = c.isLowercase
            let base = rel ? current : .zero
            switch c.uppercased().first! {
            case "M":
                let p = point(base); path.move(to: p); current = p; start = p; lastControl = nil
            case "L":
                let p = point(base); path.addLine(to: p); current = p; lastControl = nil
            case "H":
                let x = number() + (rel ? current.x : 0)
                current = CGPoint(x: x, y: current.y); path.addLine(to: current); lastControl = nil
            case "V":
                let y = number() + (rel ? current.y : 0)
                current = CGPoint(x: current.x, y: y); path.addLine(to: current); lastControl = nil
            case "C":
                let c1 = point(base), c2 = point(base), p = point(base)
                path.addCurve(to: p, control1: c1, control2: c2); lastControl = c2; current = p
            case "S":
                let c1 = reflected(for: "CS")
                let c2 = point(base), p = point(base)
                path.addCurve(to: p, control1: c1, control2: c2); lastControl = c2; current = p
            case "Q":
                let c1 = point(base), p = point(base)
                path.addQuadCurve(to: p, control: c1); lastControl = c1; current = p
            case "T":
                let c1 = reflected(for: "QT")
                let p = point(base)
                path.addQuadCurve(to: p, control: c1); lastControl = c1; current = p
            case "A":
                let rx = number(), ry = number(), rot = number()
                let large = flag(), sweep = flag()
                let p = point(base)
                arc(to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = p; lastControl = nil
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
            default:
                i += 1
            }
        }

        func reflected(for kinds: String) -> CGPoint {
            guard let lc = lastControl, kinds.contains(lastCommand.uppercased().first!) else { return current }
            return CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
        }

        mutating func point(_ base: CGPoint) -> CGPoint {
            let x = number(), y = number()
            return CGPoint(x: x + base.x, y: y + base.y)
        }

        mutating func flag() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let v = chars[i] == "1"
            i += 1
            return v
        }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i].isNewline || chars[i] == "\t" { i += 1 }
        }

        mutating func number() -> CGFloat {
            skipSeparators()
            var s = ""
            var seenDot = false, seenExp = false
            while i < chars.count {
                let ch = chars[i]
                if ch == "-" || ch == "+" {
                    if !s.isEmpty, !(s.last == "e" || s.last == "E") { break }
                } else if ch == "." {
                    if seenDot || seenExp { break }
                    seenDot = true
                } else if ch == "e" || ch == "E" {
                    if seenExp { break }
                    seenExp = true
                } else if !ch.isNumber {
                    break
                }
                s.append(ch)
                i += 1
            }
            return CGFloat(Double(s) ?? 0)
        }

        /// Endpoint arc → cubic Béziers (SVG spec F.6).
        mutating func arc(to end: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
            var rx = abs(rxIn), ry = abs(ryIn)
            let p0 = current
            guard rx > 0, ry > 0, p0 != end else { path.addLine(to: end); return }
            let phi = rotation * .pi / 180
            let cosP = cos(phi), sinP = sin(phi)
            let dx = (p0.x - end.x) / 2, dy = (p0.y - end.y) / 2
            let x1 = cosP * dx + sinP * dy
            let y1 = -sinP * dx + cosP * dy
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
            let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
            var coef = sqrt(max(0, num / den))
            if large == sweep { coef = -coef }
            let cx1 = coef * rx * y1 / ry
            let cy1 = -coef * ry * x1 / rx
            let cx = cosP * cx1 - sinP * cy1 + (p0.x + end.x) / 2
            let cy = sinP * cx1 + cosP * cy1 + (p0.y + end.y) / 2
            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
                return a
            }
            let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
            var dTheta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
            if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
            if sweep && dTheta < 0 { dTheta += 2 * .pi }
            let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
            let delta = dTheta / CGFloat(segments)
            let t = 4.0 / 3.0 * tan(delta / 4)
            var th = theta1
            for _ in 0..<segments {
                let cos1 = cos(th), sin1 = sin(th)
                let cos2 = cos(th + delta), sin2 = sin(th + delta)
                func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: cx + rx * x * cosP - ry * y * sinP, y: cy + rx * x * sinP + ry * y * cosP)
                }
                let c1 = map(cos1 - t * sin1, sin1 + t * cos1)
                let c2 = map(cos2 + t * sin2, sin2 - t * cos2)
                let p = map(cos2, sin2)
                path.addCurve(to: p, control1: c1, control2: c2)
                th += delta
            }
        }
    }
}

/// A shape drawn from SVG path data in a fixed viewBox, scaled to fit its frame.
struct SVGShape: Shape {
    let path: Path
    let viewBox: CGRect

    init(_ d: String, viewBox: CGSize) {
        self.path = SVGPath.parse(d)
        self.viewBox = CGRect(origin: .zero, size: viewBox)
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox.width
        let sy = rect.height / viewBox.height
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: sx, y: sy))
    }
}
