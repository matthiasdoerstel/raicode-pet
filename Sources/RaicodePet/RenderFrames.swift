import AppKit
import Foundation

enum RenderFrames {
    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for pet in PetLibrary.available() {
            for animation in PetAnimation.allCases {
                for (i, frame) in pet.frames(animation).enumerated() {
                    let rep = NSBitmapImageRep(cgImage: frame)
                    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                    let url = dir.appendingPathComponent("\(pet.id)-\(animation.rawValue)-\(i).png")
                    try? png.write(to: url)
                }
                print(pet.id, animation.rawValue, pet.frames(animation).count)
            }
            for i in 0..<16 {
                guard let frame = pet.lookFrame(i),
                      let png = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: dir.appendingPathComponent("\(pet.id)-look-\(i).png"))
            }
        }
    }
}
