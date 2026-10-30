# iumrah Hotels — Xcode compiler hotfix V6 (30.10.2026)

Источник ошибки: `logs_111195993054.zip`, Xcode 26.6, `Sources/Views/Tabs/HotelsHomeView.swift:188:19`, «compiler is unable to type-check this expression in reasonable time».

База: применять ПОСЛЕ `iumrah-beta-update-20261030-layout-recovery-v5.zip` или к репозиторию, где `HotelsHomeView.swift` совпадает с V5 (исходный SHA-256 указан в PATCH_MANIFEST.json).

Содержит ТОЛЬКО `Sources/Views/Tabs/HotelsHomeView.swift`. Огромное SwiftUI-выражение body декомпозировано на отдельно типизируемые computed views (презентации, state observers, lifecycle, GeometryReader, закреплённый хедер, scroll, содержимое текущего этапа, кнопка следующего этапа). Обработка скролла, переключения этапов, навигации, Nuitee, корзины и refresh не переписана.

Локальная валидация: 281 Swift-файл успешно прошёл `swiftc -frontend -parse`, 11 структурных проверок пройдены, ZIP CRC проверен. Это НЕ full Xcode build, потому что macOS/Xcode нет. Проверка может не обнаружить следующую ошибку компиляции. Обязательно сначала запустить build-only CI на GitHub и лишь после зелёного результата TestFlight; запуск на iPhone для UI всё равно нужен.

`.github/workflows`, ключи Cloudflare, номера сборок и версия приложения не изменяются.
