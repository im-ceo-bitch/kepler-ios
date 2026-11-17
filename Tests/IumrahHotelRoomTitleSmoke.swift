import Foundation
@main struct Tests {
 static func main() {
    let checks:[(String?,String?,String)] = [
        ("Double Room, Free WiFi, Air conditioning", nil, "Double Room"),
        ("Free WiFi, Air conditioning, Private bathroom", "Superior Twin Room", "Superior Twin Room"),
        ("Free WiFi, Air conditioning, Private bathroom", nil, "Room"),
        ("Deluxe King Room with City View", nil, "Deluxe King Room with City View"),
        ("Room service, Minibar, TV", nil, "Room"),
        ("Junior Suite · Minibar", nil, "Junior Suite"),
        ("Double Room Air conditioning", nil, "Double Room"),
        ("<b>Family Room</b>; towels", nil, "Family Room"),
        ("Двухместный номер, кондиционер", nil, "Двухместный номер"),
        ("", nil, "Room"),
        ("Premium", nil, "Premium"),
        ("King Room", "Free WiFi, TV", "King Room")]
    for (rate,room,expected) in checks { let actual=IumrahHotelRoomTitle.display(rate:rate,room:room); precondition(actual == expected, "\(rate ?? "nil"): \(actual) != \(expected)") }
    print("Room title: \(checks.count)/\(checks.count) PASS")
 }
}
