IUMRAH SWIFT COMPILATION HOTFIX — 2026-10-27

ЗАЧЕМ
Исправляет единственную явную ошибку в приложенном TestFlight-логе:
Sources/Umrah Flow/Views/UmrahStartView.swift:12:29
incorrect argument labels in call — UmrahVoiceStepScreen(...)

ИСПРАВЛЕНИЕ
recordingKey: "tawaf_start" перемещён ПОСЛЕ counterText,
как требует порядок параметров автоматически созданного Swift memberwise init.
Значение audioKey/recordingKey и все действия пользователя сохранены.

ПРИМЕНЕНИЕ
Этот ZIP является минимальным накопительным патчем.
Загрузить в корень kepler-ios, выполнить текущий Apply beta update.
После успешного Apply запустить TestFlight Intel повторно.
Не загружайте ещё раз предыдущий большой ZIP.

ПРОВЕРКА
- Точный Swift compile error найден в архиве logs_109759772692.zip.
- Проверен порядок аргументов всех 4 вызовов UmrahVoiceStepScreen.
- Swift parser прошёл все 279 Swift-файлов в восстановленном проекте.
- Полный Xcode/SwiftUI typecheck в Linux недоступен: следующий билд может обнаружить независимые ошибки.
- Workflow/TestFlight version/build number/Cloudflare/Nuitee не изменены.
