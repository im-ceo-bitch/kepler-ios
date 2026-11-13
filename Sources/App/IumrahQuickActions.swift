import SwiftUI
import UIKit

@MainActor
final class IumrahQuickActionCenter: ObservableObject {
    static let shared = IumrahQuickActionCenter()

    enum Action: String {
        case newTrip = "com.iumrah.shortcut.newTrip"
        case bookings = "com.iumrah.shortcut.bookings"
        case flights = "com.iumrah.shortcut.flights"
        case supportBeforeDelete = "com.iumrah.shortcut.supportBeforeDelete"
    }

    struct PresentationRequest: Identifiable, Equatable {
        let id = UUID()
        let action: Action
    }

    @Published private(set) var pendingRequest: PresentationRequest?

    let supportPhoneNumber = "+998508898845"

    private init() {}

    func queue(_ action: Action) {
        pendingRequest = PresentationRequest(action: action)
    }

    func queue(shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = Action(rawValue: shortcutItem.type) else { return false }
        queue(action)
        return true
    }

    func consume() {
        pendingRequest = nil
    }

    func refreshShortcutItems(language: AppSettingsStore.Language, activeBooking: StoredBookingSession?) {
        UIApplication.shared.shortcutItems = [
            buildNewTripItem(language: language),
            buildBookingsItem(language: language, activeBooking: activeBooking),
            buildFlightsItem(language: language),
            buildSupportItem(language: language)
        ]
    }

    private func buildNewTripItem(language: AppSettingsStore.Language) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: Action.newTrip.rawValue,
            localizedTitle: localize(language, ru: "Создать умру", en: "Create Umrah", uz: "Umra yaratish", uzCyrl: "Умра яратиш"),
            localizedSubtitle: localize(language, ru: "Собрать индивидуальную поездку", en: "Build your private trip", uz: "Shaxsiy sayohatingizni yig‘ing", uzCyrl: "Шахсий саёҳатингизни йиғинг"),
            icon: UIApplicationShortcutIcon(systemImageName: "plus.circle")
        )
    }

    private func buildBookingsItem(language: AppSettingsStore.Language, activeBooking: StoredBookingSession?) -> UIApplicationShortcutItem {
        let title: String
        let subtitle: String
        if let activeBooking {
            title = activeBooking.displayBookingNumber
            subtitle = localize(language, ru: "Последняя поездка", en: "Latest trip", uz: "So‘nggi safar", uzCyrl: "Сўнгги сафар")
        } else {
            title = localize(language, ru: "Мои бронирования", en: "My bookings", uz: "Bronlarim", uzCyrl: "Бронларим")
            subtitle = localize(language, ru: "Статус вашей поездки", en: "Trip status", uz: "Safaringiz holati", uzCyrl: "Сафарингиз ҳолати")
        }
        return UIApplicationShortcutItem(
            type: Action.bookings.rawValue,
            localizedTitle: title,
            localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: "suitcase")
        )
    }

    private func buildFlightsItem(language: AppSettingsStore.Language) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: Action.flights.rawValue,
            localizedTitle: localize(language, ru: "Найти авиабилеты", en: "Find flights", uz: "Aviabilet topish", uzCyrl: "Авиабилет топиш"),
            localizedSubtitle: localize(language, ru: "Поиск рейсов", en: "Flight search", uz: "Reys qidirish", uzCyrl: "Рейс қидириш"),
            icon: UIApplicationShortcutIcon(systemImageName: "airplane")
        )
    }

    private func buildSupportItem(language: AppSettingsStore.Language) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: Action.supportBeforeDelete.rawValue,
            localizedTitle: localize(language, ru: "Хотите удалить?", en: "Thinking of deleting?", uz: "O‘chirib tashlamoqchimisiz?", uzCyrl: "Ўчириб ташламоқчимисиз?"),
            localizedSubtitle: localize(language, ru: "Мы точно можем помочь. Позвоните нам", en: "We can help. Call us", uz: "Yordam bera olamiz. Bizga qo‘ng‘iroq qiling", uzCyrl: "Ёрдам бера оламиз. Бизга қўнғироқ қилинг"),
            icon: UIApplicationShortcutIcon(systemImageName: "phone.fill")
        )
    }

    private func localize(
        _ language: AppSettingsStore.Language,
        ru: String,
        en: String,
        uz: String,
        uzCyrl: String
    ) -> String {
        switch language {
        case .russian:
            return ru
        case .english:
            return en
        case .uzbek:
            return uz
        case .uzbekCyrillic:
            return uzCyrl
        case .arabic:
            return en
        case .turkish:
            return en
        case .indonesian:
            return en
        case .malay:
            return en
        }
    }
}
