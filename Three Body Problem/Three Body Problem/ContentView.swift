//
//  ContentView.swift
//  Three Body Problem
//
//  Created by Java on 28/12/2025.
//

import SwiftUI

// MARK: - 2D Vector

struct Vec2: Hashable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    static func + (l: Vec2, r: Vec2) -> Vec2 { .init(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: Vec2, r: Vec2) -> Vec2 { .init(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: Vec2, r: Double) -> Vec2 { .init(x: l.x * r, y: l.y * r) }
    static func / (l: Vec2, r: Double) -> Vec2 { .init(x: l.x / r, y: l.y / r) }

    func length() -> Double { (x*x + y*y).squareRoot() }
}

// MARK: - Body

struct Body: Identifiable {
    let id = UUID()
    var name: String
    var mass: Double
    var pos: Vec2
    var vel: Vec2
    var radius: Double // purely visual (pixels)
}

// MARK: - Simulator (Velocity Verlet)

final class GravitySim: ObservableObject {
    enum Mode: Int, CaseIterable, Identifiable {
        case two = 2
        case three = 3
        var id: Int { rawValue }
        var label: String { rawValue == 2 ? "2 bodies" : "3 bodies" }
    }

    @Published var bodies: [Body] = []
    @Published var paused: Bool = false
    @Published var mode: Mode = .three

    // Tuneables (screen-friendly units)
    @Published var G: Double = 500.0
    @Published var softening: Double = 8.0
    @Published var dt: Double = 1.0 / 240.0
    @Published var stepsPerFrame: Int = 3

    private var acc: [UUID: Vec2] = [:]

    init() {
        setMode(.three)
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        paused = false
        switch newMode {
        case .two:
            resetTwoBody()
        case .three:
            resetThreeBody()
        }
        acc = [:]
        recomputeAllAccelerations()
    }

    // A clean 2-body circular-orbit setup (equal masses)
    private func resetTwoBody() {
        let m = 200.0
        let a = 150.0                 // each body’s orbit radius around COM
        let r = 2.0 * a               // separation between bodies
        // circular speed for equal masses about COM:
        // v^2 = G*m / (4a)
        let v = (G * m / (4.0 * a)).squareRoot()

        bodies = [
            Body(name: "A", mass: m, pos: .init(x: -a, y: 0), vel: .init(x: 0, y: -v), radius: 8),
            Body(name: "B", mass: m, pos: .init(x:  a, y: 0), vel: .init(x: 0, y:  v), radius: 8)
        ]
        _ = r // (kept for clarity)
    }

    // A “binary + intruder” style 3-body setup (often chaotic)
    private func resetThreeBody() {
        bodies = [
            Body(name: "A", mass: 200, pos: .init(x: -150, y: 0),   vel: .init(x: 0,  y: -8.0), radius: 8),
            Body(name: "B", mass: 200, pos: .init(x:  150, y: 0),   vel: .init(x: 0,  y:  8.0), radius: 8),
            Body(name: "C", mass:  20, pos: .init(x:    0, y: 230), vel: .init(x: 9.0, y:  0.0), radius: 5)
        ]
    }

    func tick() {
        guard !paused, bodies.count >= 2 else { return }
        for _ in 0..<stepsPerFrame {
            stepVelocityVerlet()
        }
    }

    private func acceleration(for index: Int) -> Vec2 {
        let bi = bodies[index]
        var a = Vec2.zero

        for j in bodies.indices where j != index {
            let bj = bodies[j]
            let r = bj.pos - bi.pos
            let dist2 = r.x*r.x + r.y*r.y + softening*softening
            let invDist = 1.0 / dist2.squareRoot()
            let invDist3 = invDist * invDist * invDist
            a = a + (r * (G * bj.mass * invDist3))
        }
        return a
    }

    private func recomputeAllAccelerations() {
        for i in bodies.indices {
            acc[bodies[i].id] = acceleration(for: i)
        }
    }

    private func stepVelocityVerlet() {
        // 1) position update using a(t)
        for i in bodies.indices {
            let id = bodies[i].id
            let a0 = acc[id] ?? acceleration(for: i)
            bodies[i].pos = bodies[i].pos + bodies[i].vel * dt + a0 * (0.5 * dt * dt)
        }

        // 2) compute a(t+dt)
        var aNew: [UUID: Vec2] = [:]
        for i in bodies.indices {
            aNew[bodies[i].id] = acceleration(for: i)
        }

        // 3) velocity update using average acceleration
        for i in bodies.indices {
            let id = bodies[i].id
            let a0 = acc[id] ?? .zero
            let a1 = aNew[id] ?? .zero
            bodies[i].vel = bodies[i].vel + (a0 + a1) * (0.5 * dt)
        }

        acc = aNew
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var sim = GravitySim()

    private let trailCount = 220
    @State private var trails: [UUID: [Vec2]] = [:]

    var body: some View {
        VStack(spacing: 12) {

            // Switch between 2 and 3 bodies
            Picker("", selection: $sim.mode) {
                ForEach(GravitySim.Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: sim.mode) { _, newMode in
                trails = [:]
                sim.setMode(newMode)
            }

            Canvas { context, size in
                let center = Vec2(x: Double(size.width) / 2.0, y: Double(size.height) / 2.0)

                // Trails
                for b in sim.bodies {
                    guard let arr = trails[b.id], arr.count >= 2 else { continue }
                    var path = Path()
                    path.move(to: toScreen(arr[0], center: center))
                    for p in arr.dropFirst() {
                        path.addLine(to: toScreen(p, center: center))
                    }
                    context.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 1)
                }

                // Bodies
                for b in sim.bodies {
                    let p = toScreen(b.pos, center: center)
                    let r = b.radius
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                    context.draw(
                        Text(b.name).font(.system(size: 12, weight: .bold)).foregroundColor(.white),
                        at: CGPoint(x: p.x, y: p.y - r - 10)
                    )
                }

                // Border
                context.stroke(Path(CGRect(origin: .zero, size: size)),
                               with: .color(.white.opacity(0.2)),
                               lineWidth: 1)
            }
            .background(Color.black)
            .frame(height: 520)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            controls
        }
        .padding()
        .onReceive(Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()) { _ in
            sim.tick()
            updateTrails()
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(sim.paused ? "Play" : "Pause") { sim.paused.toggle() }
                Button("Reset") {
                    trails = [:]
                    sim.setMode(sim.mode)
                }
            }

            HStack {
                Text("G")
                Slider(value: $sim.G, in: 50...2000)
                Text(String(format: "%.0f", sim.G)).frame(width: 70, alignment: .trailing)
            }

            HStack {
                Text("Softening")
                Slider(value: $sim.softening, in: 0...30)
                Text(String(format: "%.1f", sim.softening)).frame(width: 70, alignment: .trailing)
            }

            HStack {
                Text("Speed")
                Slider(
                    value: Binding(
                        get: { Double(sim.stepsPerFrame) },
                        set: { sim.stepsPerFrame = max(1, Int($0.rounded())) }
                    ),
                    in: 1...12,
                    step: 1
                )
                Text("\(sim.stepsPerFrame)x").frame(width: 70, alignment: .trailing)
            }

            Text("Tip: if it blows up, lower G, increase softening, or lower Speed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func updateTrails() {
        for b in sim.bodies {
            var arr = trails[b.id, default: []]
            arr.append(b.pos)
            if arr.count > trailCount { arr.removeFirst(arr.count - trailCount) }
            trails[b.id] = arr
        }
        // Remove trails for bodies that no longer exist (after switching mode)
        let ids = Set(sim.bodies.map { $0.id })
        trails.keys.filter { !ids.contains($0) }.forEach { trails.removeValue(forKey: $0) }
    }

    private func toScreen(_ p: Vec2, center: Vec2) -> CGPoint {
        CGPoint(x: center.x + p.x, y: center.y + p.y)
    }
}
