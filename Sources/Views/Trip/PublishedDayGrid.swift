import SwiftUI

/// Published civil dates are provider day keys, independent of the phone's time zone.
struct PublishedDayGrid: View {
    let days: [String]
    @Binding var selection: String
    @State private var shownMonth = ""
    @Environment(\.locale) private var locale

    var body: some View {
        let available = Set(days)
        let months = Set(days.map { String($0.prefix(7)) }).sorted()
        let month = months.contains(shownMonth) ? shownMonth : (months.first ?? "")
        let formatter = dayFormatter
        if let first = formatter.date(from: month + "-01"), let index = months.firstIndex(of: month) {
            let calendar = civilCalendar
            let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
            let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
            VStack {
                HStack {
                    Button { shownMonth = months[max(0,index-1)] } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                    Spacer()
                    Text(monthTitle(first))
                    Spacer()
                    Button { shownMonth = months[min(months.count-1,index+1)] } label: { Image(systemName: "chevron.right") }.disabled(index+1 == months.count)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday-1+i)%7]).font(.caption2)
                    }
                    ForEach(0..<(count+offset), id: \.self) { i in
                        if i < offset { Color.clear.frame(height: 38) }
                        else {
                            let day = i-offset+1
                            let key = String(format: "%@-%02d", month, day)
                            Button { selection = key } label: {
                                Text(String(day)).frame(maxWidth: .infinity, minHeight: 38)
                                    .background(selection == key ? Color.primary.opacity(0.14) : .clear, in: Circle())
                            }.disabled(!available.contains(key)).accessibilityLabel(key)
                        }
                    }
                }
            }.iumrahCard()
        }
    }

    private var civilCalendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = locale
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = civilCalendar
        formatter.timeZone = civilCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = civilCalendar
        formatter.timeZone = civilCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }
}
