import Foundation

@main
struct IumrahPerformanceV3Smoke {
    static func main() {
        let gb: UInt64 = 1024 * 1024 * 1024
        func profile(_ machine: String, _ memory: UInt64, low: Bool = false, thermal: Bool = false) -> IumrahPerformanceProfile {
            .resolve(machine: machine, memoryBytes: memory * gb, lowPower: low, thermalLimited: thermal)
        }
        precondition(profile("iPhone11,8", 3) == .efficiency) // XR
        precondition(profile("iPhone12,1", 4) == .efficiency) // 11
        precondition(profile("iPhone14,4", 4) == .balanced)   // 13 mini
        precondition(profile("iPhone15,2", 6) == .balanced)
        precondition(profile("iPhone17,1", 8) == .performance)
        precondition(profile("iPhone17,1", 8, low: true) == .efficiency)
        precondition(profile("iPhone17,1", 8, thermal: true) == .efficiency)
        precondition(profile("iPad", 4) == .efficiency)
        precondition(IumrahPerformanceProfile.efficiency.decorativeFPS == 15)
        precondition(IumrahPerformanceProfile.balanced.decorativeFPS == 24)
        precondition(IumrahPerformanceProfile.performance.decorativeFPS == 30)
        precondition(IumrahPerformanceProfile.efficiency.imageMemoryLimit == 24 * Int(gb / 1024))
        precondition(IumrahPerformanceProfile.performance.imageMemoryLimit == 48 * Int(gb / 1024))
        precondition(IumrahPerformanceProfile.efficiency.staticBackgrounds)
        precondition(!IumrahPerformanceProfile.balanced.staticBackgrounds)
        print("PASS: 15 adaptive-profile and image-budget checks")
    }
}
