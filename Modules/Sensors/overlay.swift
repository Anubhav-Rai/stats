//
//  overlay.swift
//  Sensors
//
//  Created by Anubhav Rai on 29/10/2026
//  Using Swift 5.0
//  Running on macOS 27.2
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Overlay: NSPanel {
    private let visibleAlpha: CGFloat = 0.94
    private let margin: CGFloat = 10
    private let radius: CGFloat = 16

    private let background: NSVisualEffectView = NSVisualEffectView()
    private let container: NSStackView = NSStackView()
    private var gauges: [String: GaugeView] = [:]
    private var keys: [String] = []
    private var isShown: Bool = false

    init() {
        super.init(
            contentRect: NSRect.zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.ignoresMouseEvents = true
        self.isOpaque = false
        self.hasShadow = true
        self.backgroundColor = .clear
        self.appearance = NSAppearance(named: .darkAqua)
        self.alphaValue = 0

        self.background.material = .hudWindow
        self.background.blendingMode = .behindWindow
        self.background.state = .active
        self.background.maskImage = self.roundedMask()

        let tint = TintView(radius: self.radius)
        tint.translatesAutoresizingMaskIntoConstraints = false

        self.container.orientation = .horizontal
        self.container.alignment = .top
        self.container.spacing = 4
        self.container.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 8, right: 10)
        self.container.translatesAutoresizingMaskIntoConstraints = false

        self.background.addSubview(tint)
        self.background.addSubview(self.container)
        NSLayoutConstraint.activate([
            self.container.topAnchor.constraint(equalTo: self.background.topAnchor),
            self.container.bottomAnchor.constraint(equalTo: self.background.bottomAnchor),
            self.container.leadingAnchor.constraint(equalTo: self.background.leadingAnchor),
            self.container.trailingAnchor.constraint(equalTo: self.background.trailingAnchor),
            tint.topAnchor.constraint(equalTo: self.background.topAnchor),
            tint.bottomAnchor.constraint(equalTo: self.background.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: self.background.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: self.background.trailingAnchor)
        ])
        self.contentView = self.background

        NotificationCenter.default.addObserver(self, selector: #selector(self.listenForModuleToggle), name: .toggleModule, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.listenForPause), name: .pause, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func setValues(_ sensors: [Sensor_p]) {
        guard !sensors.isEmpty else {
            self.fadeOut()
            return
        }

        let keys = sensors.map({ $0.key })
        if keys != self.keys {
            self.rebuild(sensors)
        }

        sensors.forEach { (s: Sensor_p) in
            guard let gauge = self.gauges[s.key] else { return }
            if let f = s as? Fan {
                let level = Double(f.percentage)/100
                gauge.update(value: "\(f.percentage)%", level: level, color: Self.color(level, zones: (0.4, 0.7, 0.9)))
            } else if s.type == .temperature {
                let level = s.value/100
                gauge.update(value: s.formattedMiniValue, level: level, color: Self.color(level, zones: (0.6, 0.75, 0.9)))
            } else {
                gauge.update(value: s.formattedMiniValue, level: 0, color: .white)
            }
        }

        self.reposition()
        self.fadeIn()
    }

    private func rebuild(_ sensors: [Sensor_p]) {
        self.container.arrangedSubviews.forEach({ $0.removeFromSuperview() })
        self.gauges = [:]
        self.keys = sensors.map({ $0.key })

        let fans = sensors.filter({ $0 is Fan })
        sensors.forEach { (s: Sensor_p) in
            var label: String
            if s is Fan {
                label = fans.count > 1 ? "FAN \((fans.firstIndex(where: { $0.key == s.key }) ?? 0) + 1)" : "FAN"
            } else if s.group == .CPU || s.group == .GPU {
                label = s.group.rawValue
            } else {
                label = localizedString(s.name).uppercased()
            }

            let gauge = GaugeView(label: label)
            self.container.addArrangedSubview(gauge)
            self.gauges[s.key] = gauge
        }
    }

    // green → yellow → orange → red, using the dark appearance system tints
    private static func color(_ level: Double, zones: (yellow: Double, orange: Double, red: Double)) -> NSColor {
        switch level {
        case zones.red...:
            return NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)
        case zones.orange...:
            return NSColor(srgbRed: 1.0, green: 0.624, blue: 0.039, alpha: 1)
        case zones.yellow...:
            return NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: 1)
        default:
            return NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1)
        }
    }

    private func roundedMask() -> NSImage {
        let edge = self.radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: self.radius, yRadius: self.radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: self.radius, left: self.radius, bottom: self.radius, right: self.radius)
        image.resizingMode = .stretch
        return image
    }

    private func reposition() {
        // the screen with the menu bar, so the overlay doesn't jump between displays with focus
        guard let screen = NSScreen.screens.first else { return }
        self.background.layoutSubtreeIfNeeded()
        let size = self.container.fittingSize
        let frame = screen.visibleFrame
        let newFrame = NSRect(
            x: frame.maxX - size.width - self.margin,
            y: frame.maxY - size.height - self.margin,
            width: size.width,
            height: size.height
        )
        if self.frame != newFrame {
            self.setFrame(newFrame, display: true)
            self.invalidateShadow()
        }
    }

    private func fadeIn() {
        guard !self.isShown else { return }
        self.isShown = true
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = self.visibleAlpha
        }
    }

    public func fadeOut() {
        guard self.isShown else { return }
        self.isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.orderOut(nil)
        })
    }

    @objc private func listenForModuleToggle(_ notification: Notification) {
        guard let name = notification.userInfo?["module"] as? String, name == ModuleType.sensors.stringValue,
              let state = notification.userInfo?["state"] as? Bool, !state else { return }
        self.fadeOut()
    }

    @objc private func listenForPause(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? Bool, state else { return }
        self.fadeOut()
    }
}

private class GaugeView: NSView {
    private let diameter: CGFloat = 42
    private let lineWidth: CGFloat = 4

    private let track: CAShapeLayer = CAShapeLayer()
    private let progress: CAShapeLayer = CAShapeLayer()
    private let valueField: NSTextField = NSTextField(labelWithString: "")
    private let labelField: NSTextField
    
    init(label: String) {
        self.labelField = NSTextField(labelWithString: label)
        super.init(frame: NSRect(x: 0, y: 0, width: 54, height: 62))
        self.wantsLayer = true
        self.translatesAutoresizingMaskIntoConstraints = false

        let ring = NSRect(x: (self.frame.width - self.diameter)/2, y: self.frame.height - self.diameter, width: self.diameter, height: self.diameter)
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: ring.midX, y: ring.midY),
            radius: (self.diameter - self.lineWidth)/2,
            startAngle: .pi/2,
            endAngle: .pi/2 - 2 * .pi,
            clockwise: true
        )

        self.track.path = path
        self.track.fillColor = nil
        self.track.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        self.track.lineWidth = self.lineWidth

        self.progress.path = path
        self.progress.fillColor = nil
        self.progress.lineWidth = self.lineWidth
        self.progress.lineCap = .round
        self.progress.strokeEnd = 0

        self.layer?.addSublayer(self.track)
        self.layer?.addSublayer(self.progress)

        self.valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        self.valueField.textColor = .white
        self.valueField.alignment = .center
        self.valueField.frame = NSRect(x: ring.minX, y: ring.midY - 8, width: ring.width, height: 16)

        self.labelField.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        self.labelField.textColor = NSColor.white.withAlphaComponent(0.55)
        self.labelField.alignment = .center
        self.labelField.lineBreakMode = .byTruncatingTail
        self.labelField.frame = NSRect(x: 0, y: 0, width: self.frame.width, height: 13)

        self.addSubview(self.valueField)
        self.addSubview(self.labelField)

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: self.frame.width),
            self.heightAnchor.constraint(equalToConstant: self.frame.height)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(value: String, level: Double, color: NSColor) {
        self.valueField.stringValue = value

        let newLevel = CGFloat(min(max(level, 0), 1))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.6)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        self.progress.strokeEnd = newLevel
        self.progress.strokeColor = color.cgColor
        CATransaction.commit()
    }
}

// darkens the blur so the white text keeps its contrast over light windows
private class TintView: NSView {
    private let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: NSRect.zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: self.radius, yRadius: self.radius)
        NSColor.black.withAlphaComponent(0.45).setFill()
        path.fill()
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.1).setStroke()
        path.stroke()
    }
}
