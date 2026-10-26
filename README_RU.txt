iumrah — единый iOS hotfix: сеть (возможный SIGABRT) + native Liquid Glass tabs (2026-10-26)

Применить ZIP через существующий Apply iumrah Beta ZIP update.
Содержит РОВНО 4 Swift файла плюс эту инструкцию.
- IumrahConnectivityMonitor.swift: URLSession живёт до завершения процесса; отложенные сетевые задачи не используют инвалидированную сессию.
- IumrahApp.swift: системный UITabBar / Liquid Glass, чёрные иконки, 50% чёрный индикатор в светлой теме.
- AppNavigationContainer.swift: удалена кастомная нижняя панель.
- RootView.swift: сохранён родной TabView без его принудительного скрытия.

Не включает Nuitee Hotels или какие-либо другие предыдущие обновления. Они должны уже присутствовать в репозитории.
Не изменяет GitHub Actions, версию приложения, сборку и конфигурацию Cloudflare.
Исправление SIGABRT основано на вероятной причине; на iPhone не проверено.
Проверки: синтаксический разбор Swift файлов, целостность ZIP, контроль точного объединения.
Xcode build / TestFlight / iPhone launch: НЕ проводились.
