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
        }
    }
}
