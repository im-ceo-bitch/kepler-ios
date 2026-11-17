import Foundation
@main struct Tests { static func main() {
    let a: [UInt8] = Array(repeating: [UInt8(100), 50, 200, 255], count: 256).flatMap { $0 }
    let b: [UInt8] = Array(repeating: [UInt8(103), 52, 198, 240], count: 256).flatMap { $0 }
    let c: [UInt8] = Array(repeating: [UInt8(220), 120, 70, 255], count: 256).flatMap { $0 }
    precondition(IumrahHotelPhotoSignature.similar(a,a)); precondition(IumrahHotelPhotoSignature.similar(a,b)); precondition(!IumrahHotelPhotoSignature.similar(a,c)); precondition(!IumrahHotelPhotoSignature.similar([],[])); precondition(!IumrahHotelPhotoSignature.similar([1],[1])); print("Photo fingerprint: 5/5 PASS")
} }
