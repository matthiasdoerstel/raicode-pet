import AppKit
import CoreGraphics
import Foundation

enum PetAnimation: String, CaseIterable {
    case idle, stretch, lookAround, working, waiting, done, failed
    /// One-shots played on top of the state loop.
    case celebrate, wave
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
    func frameDuration(_ animation: PetAnimation) -> TimeInterval
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

    func frameDuration(_ animation: PetAnimation) -> TimeInterval {
        switch animation {
        case .idle: return 1.1
        case .stretch: return 0.7
        case .lookAround: return 0.45
        case .working: return 0.16
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
final class CodexPetArt: PetArt {
    static let cell = CGSize(width: 192, height: 208)
    static let columns = 8
    static let rowNames = ["idle", "running-right", "running-left", "waving", "jumping",
                           "failed", "waiting", "running", "review", "stretching", "looking-around"]

    let id: String
    let displayName: String
    var menuTitle: String { "\(displayName) — Codex pet" }
    let displaySize = CGSize(width: 144, height: 156)
    let smoothScaling = true

    private var rows: [String: [CGImage]] = [:]

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
        rows = Self.slice(atlas)
        guard rows["idle"]?.isEmpty == false else { return nil }
    }

    func frames(_ animation: PetAnimation) -> [CGImage] {
        let candidates: [String]
        switch animation {
        case .idle: candidates = ["idle"]
        case .stretch: candidates = ["stretching", "looking-around"]
        case .lookAround: candidates = ["looking-around", "stretching"]
        case .working: candidates = ["running", "running-right"]
        case .waiting: candidates = ["waiting"]
        case .done: candidates = ["review"]
        case .failed: candidates = ["failed"]
        case .celebrate: candidates = ["jumping"]
        case .wave: candidates = ["waving"]
        }
        for name in candidates {
            if let f = rows[name], !f.isEmpty { return f }
        }
        return rows["idle"] ?? []
    }

    func frameDuration(_ animation: PetAnimation) -> TimeInterval {
        switch animation {
        case .idle, .stretch, .lookAround: return 0.16
        case .failed: return 0.18
        default: return 0.11
        }
    }

    /// Cuts the atlas into rows; each row ends at its first fully transparent cell.
    static func slice(_ atlas: CGImage) -> [String: [CGImage]] {
        let w = atlas.width, h = atlas.height
        // Some sheets are exported at a different scale — derive the cell from the column count.
        let cellW = w / columns
        let cellH = Int((Double(cellW) * Double(cell.height) / Double(cell.width)).rounded())
        guard cellW > 0, cellH > 0 else { return [:] }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [:] }
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

        var result: [String: [CGImage]] = [:]
        let rowCount = min(h / cellH, rowNames.count)
        for row in 0..<rowCount {
            var frames: [CGImage] = []
            for col in 0..<columns {
                if cellIsEmpty(col: col, row: row) { break }
                let rect = CGRect(x: col * cellW, y: row * cellH, width: cellW, height: cellH)
                if let img = atlas.cropping(to: rect) { frames.append(img) }
            }
            result[rowNames[row]] = frames
        }
        return result
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
