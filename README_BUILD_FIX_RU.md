# iumrah: Configurator + Unified Headers — Build Fix V3

Исправлены именно ошибки компиляции из `logs_110704905981.zip`, 29.10.2026:

1. `HomeDashboardView.swift:215` — `prayerTimesTitle` заменён на существующий локализованный `prayerEntryTitle`.
2. `HomeDashboardView.swift:216` — `weatherTitle` заменён на существующий локализованный `weatherEntryTitle`.
3. `IumrahConfiguratorVisualDraft.swift:410` — сложная конкатенация внутри SwiftUI `Text` выделена в отдельно типизированное вычисляемое свойство `cartSummaryText`.

Это полный повторный патч «2 в 1» с исправлениями, не только два файла. Повторно загружать прежние архивы не нужно.

В патче нет `.github/workflows`, сертификатов, номера сборки и серверных API ключей.

Проверены структура ZIP, контрольные суммы, исходные места ошибок и синтаксис Swift. Полная компиляция Xcode доступна только на macOS и здесь **НЕ выполнялась**. Не считать тестирование на устройстве или успешную сборку подтверждёнными до запуска TestFlight Intel.
