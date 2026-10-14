import AppKit
import CoreGraphics
import Foundation
import RaicodePetCore

enum PetAnimation: String, CaseIterable {
    case idle, stretch, lookAround, working, waiting, done, failed
    /// One-shots played on top of the state loop.
    case celebrate, wave
    /// Looped while the pet is being dragged.
    case walkRight, walkLeft
}

/// Anything that can supply frames for the pet: the built-in pixel dog or a Codex pet.
protocol PetArt {
    var id: String { get }
    /// The pet's name, shown in its speech bubble.
    var displayName: String { get }
    /// How the pet is listed in the menu.
    var menuTitle: String { get }
    /// Point size the pet is drawn at.
    var displaySize: CGSize { get }
    /// Pixel art wants nearest-neighbour; illustrations want smooth scaling.
    var smoothScaling: Bool { get }
    func frames(_ animation: PetAnimation) -> [CGImage]
    func frameDuration(_ animation: PetAnimation, index: Int) -> TimeInterval
    /// The pose facing look direction `index` (0 = up, clockwise, 16 steps), if the pet has them.
    func lookFrame(_ index: Int) -> CGImage?
}

extension PetArt {
    func lookFrame(_ index: Int) -> CGImage? { nil }
    var canLook: Bool { lookFrame(0) != nil }
    var canWalk: Bool { !frames(.walkRight).isEmpty }
}

// MARK: - Built-in pixel pets

final class PixelArt: PetArt {
    let character: PixelCharacter
    var id: String { character.id }
    var displayName: String { character.displayName }
    var menuTitle: String { "\(character.displayName) — \(character.species)" }
    let displaySize = CGSize(width: 128, height: 128)  // 32px × 4, keeps pixels crisp
    let smoothScaling = false

    private var cache: [String: [CGImage]] = [:]

    init(_ character: PixelCharacter) {
        self.character = character
    }

    func frames(_ animation: PetAnimation) -> [CGImage] {
        let key: String
        switch animation {
        case .celebrate: key = "done"
        case .wave: key = "waiting"
        case .lookAround: key = character.frames["look"] == nil ? "stretch" : "look"
        default: key = animation.rawValue
        }
        if let cached = cache[key] { return cached }
        let images = (character.frames[key] ?? []).compactMap { render($0) }
        cache[key] = images
        return images
    }

    func frameDuration(_ animation: PetAnimation, index: Int) -> TimeInterval {
        switch animation {
        case .idle, .walkRight, .walkLeft: return 1.1
        case .stretch: return 0.7
        case .lookAround: return 0.45
        case .working: return 0.3
        case .waiting, .wave: return 0.35
        case .done, .celebrate: return 0.18
        case .failed: return 0.9
        }
    }

    private func render(_ rows: [String]) -> CGImage? {
        let h = rows.count
        let w = rows.first?.count ?? 0
        guard w > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where x < w {
                guard let (r, g, b) = character.palette[ch] else { continue }
                let i = (y * w + x) * 4
                bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
            }
        }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

// MARK: - Codex pets

/// A Codex-format pet: `pet.json` + an 8-column spritesheet of 192×208 cells.
/// Rows, frame counts and timings follow Codex's V2 spec (hatch-pet `animation-rows.md`).
final class CodexPetArt: PetArt {
    static let cell = CGSize(width: 192, height: 208)
    static let columns = 8

    /// Standard rows in atlas order, with Codex's per-frame durations in ms.
    /// The duration count is also the row's frame count.
    static let rows: [(name: String, ms: [Int])] = [
        ("idle", [280, 110, 110, 140, 140, 320]),
        ("running-right", Array(repeating: 120, count: 7) + [220]),
        ("running-left", Array(repeating: 120, count: 7) + [220]),
        ("waving", Array(repeating: 140, count: 3) + [280]),
        ("jumping", Array(repeating: 140, count: 4) + [280]),
        ("failed", Array(repeating: 140, count: 7) + [240]),
        ("waiting", Array(repeating: 150, count: 5) + [260]),
        ("running", Array(repeating: 120, count: 5) + [220]),
        ("review", Array(repeating: 150, count: 5) + [280]),
    ]
    /// V2 sheets add two rows of 8 look poses each: 0°…157.5°, then 180°…337.5°.
    static let lookRowStart = 9

    private struct Sequence {
        var frames: [CGImage] = []
        var ms: [Int] = []
    }

    let id: String
    let displayName: String
    var menuTitle: String { "\(displayName) — Codex pet" }
    let displaySize = CGSize(width: 144, height: 156)
    let smoothScaling = true

    private var sequences: [String: Sequence] = [:]
    private var looks: [CGImage] = []
    private var glance = Sequence()

    init?(folder: URL) {
        struct Manifest: Decodable {
            var id: String?
            var displayName: String?
            var spritesheetPath: String?
        }
        let manifestURL = folder.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        let sheetURL = folder.appendingPathComponent(manifest.spritesheetPath ?? "spritesheet.webp")
        guard let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        id = manifest.id ?? folder.lastPathComponent
        displayName = manifest.displayName ?? id
        guard let sliced = Self.slice(atlas), let idle = sliced.rows["idle"], !idle.isEmpty else { return nil }
        for (name, ms) in Self.rows {
            let frames = sliced.rows[name] ?? []
            sequences[name] = Sequence(frames: frames, ms: Array(ms.prefix(frames.count)))
        }
        if sliced.looks.count == LookDirection.count {
            looks = sliced.looks
            glance = Self.glance(idle: idle[0], looks: looks)
        }
    }

    /// An idle "look around": glance right, back, glance left, back — built from the look poses.
    private static func glance(idle: CGImage, looks: [CGImage]) -> Sequence {
        // Look indices: 4 = right (90°), 12 = left (270°); neighbours ease in and out.
        let steps: [(CGImage, Int)] = [
            (looks[5], 150), (looks[4], 900), (looks[5], 150), (idle, 400),
            (looks[11], 150), (looks[12], 900), (looks[11], 150), (idle, 300),
        ]
        return Sequence(frames: steps.map(\.0), ms: steps.map(\.1))
    }

    private func sequence(_ animation: PetAnimation) -> Sequence {
        if animation == .lookAround, !glance.frames.isEmpty { return glance }
        let candidates: [String]
        switch animation {
        case .idle: candidates = ["idle"]
        case .stretch, .lookAround, .wave: candidates = ["waving"]
        case .working: candidates = ["running"]
        case .waiting: candidates = ["waiting"]
        case .done: candidates = ["review"]
        case .failed: candidates = ["failed"]
        case .celebrate: candidates = ["jumping"]
        case .walkRight: candidates = ["running-right"]
        case .walkLeft: candidates = ["running-left", "running-right"]
        }
        for name in candidates {
            if let s = sequences[name], !s.frames.isEmpty { return s }
        }
        return sequences["idle"] ?? Sequence()
    }

    func frames(_ animation: PetAnimation) -> [CGImage] {
        sequence(animation).frames
    }

    func frameDuration(_ animation: PetAnimation, index: Int) -> TimeInterval {
        let ms = sequence(animation).ms
        guard !ms.isEmpty else { return 0.15 }
        return Double(ms[min(index, ms.count - 1)]) / 1000
    }

    func lookFrame(_ index: Int) -> CGImage? {
        looks.isEmpty ? nil : looks[index % looks.count]
    }

    /// Cuts the atlas into standard rows (each capped at its spec length and ending at its
    /// first fully transparent cell) plus the 16 look poses, when present.
    static func slice(_ atlas: CGImage) -> (rows: [String: [CGImage]], looks: [CGImage])? {
        let w = atlas.width, h = atlas.height
        // Some sheets are exported at a different scale — derive the cell from the column count.
        let cellW = w / columns
        let cellH = Int((Double(cellW) * Double(cell.height) / Double(cell.width)).rounded())
        guard cellW > 0, cellH > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(atlas, in: CGRect(x: 0, y: 0, width: w, height: h))

        func cellIsEmpty(col: Int, row: Int) -> Bool {
            // CGContext memory is top-down for the drawn image, matching cropping coordinates.
            let x0 = col * cellW, y0 = row * cellH
            var y = y0
            while y < min(y0 + cellH, h) {
                var x = x0
                while x < min(x0 + cellW, w) {
                    if pixels[(y * w + x) * 4 + 3] > 8 { return false }
                    x += 3
                }
                y += 3
            }
            return true
        }

        func crop(col: Int, row: Int) -> CGImage? {
            atlas.cropping(to: CGRect(x: col * cellW, y: row * cellH, width: cellW, height: cellH))
        }

        let rowCount = h / cellH
        var rows: [String: [CGImage]] = [:]
        for (row, spec) in Self.rows.enumerated() where row < rowCount {
            var frames: [CGImage] = []
            for col in 0..<min(columns, spec.ms.count) {
                if cellIsEmpty(col: col, row: row) { break }
                if let img = crop(col: col, row: row) { frames.append(img) }
            }
            rows[spec.name] = frames
        }

        var looks: [CGImage] = []
        if rowCount >= lookRowStart + 2 {
            for row in lookRowStart..<lookRowStart + 2 {
                for col in 0..<columns {
                    if let img = crop(col: col, row: row) { looks.append(img) }
                }
            }
        }
        return (rows, looks)
    }
}

// MARK: - Library

enum PetLibrary {
    static let selectionKey = "selectedPet"

    static var folders: [URL] {
        if let override = ProcessInfo.processInfo.environment["RAICODE_PET_DIRS"] {
            return override.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".raicode-pet/pets"),
                home.appendingPathComponent(".codex/pets")]
    }

    /// Built-in pixel pets first, then installed Codex pets (deduplicated by id).
    static func available() -> [PetArt] {
        var pets: [PetArt] = PixelSprites.characters.map(PixelArt.init)
        var seen = Set(pets.map(\.id))
        for root in folders {
            let dirs = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let pet = CodexPetArt(folder: dir), seen.insert(pet.id).inserted else { continue }
                pets.append(pet)
            }
        }
        return pets
    }

    static func selected(from pets: [PetArt]) -> PetArt {
        let saved = UserDefaults.standard.string(forKey: selectionKey)
        return pets.first { $0.id == saved } ?? pets[0]
    }
}
