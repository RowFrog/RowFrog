import UIKit

/// A route's pin as drawn on the lake map (split off LakeMapScreen.swift, 14 Nov 2026): the start a
/// blue dot; a turning point a numbered disc with a blue ring (owner's picks, 14 Nov 2026), white in
/// light mode and on satellite pictures, dark grey in dark mode; the selected one filled blue.
enum RoutePinImage {
    static func make(_ pin: RoutePin, dark: Bool = false) -> UIImage {
        // A touch bigger than it looks, so it is easier to hold and drag.
        let size: CGFloat = pin.isStart ? 22 : 24
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let rect = CGRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)
            let circle = UIBezierPath(ovalIn: rect)
            if pin.isStart {
                UIColor.systemBlue.setFill()
                circle.fill()
                UIColor(white: 0.15, alpha: 1).setStroke()
                circle.lineWidth = 2
                circle.stroke()
                return
            }
            // systemBlue resolved for the mode: the lighter blue in dark mode.
            let blue = UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
            let disc = dark ? UIColor(white: 0.17, alpha: 1) : UIColor.white
            (pin.isSelected ? blue : disc).setFill()
            circle.fill()
            (pin.isSelected ? disc : blue).setStroke()
            circle.lineWidth = 2
            circle.stroke()
            let number = NSAttributedString(string: "\(pin.index)", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: pin.isSelected ? disc : blue,
            ])
            let box = number.size()
            number.draw(at: CGPoint(x: (size - box.width) / 2, y: (size - box.height) / 2))
        }
    }
}
