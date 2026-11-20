# IUMRAH iOS — Public Trip Share · GitHub Actions permission hotfix V3

Причина ошибки: в предыдущем ZIP содержался `.github/workflows/deploy-package-engine.yml`. GitHub отказал `git push`, потому что токен установщика ZIP не имеет разрешения `workflows`.

Данный архив **не содержит файлов `.github/workflows/`** и полностью сохраняет необходимые изменения Swift + локального PackageEngine из V2. Не содержит устаревший `Backend/UnifiedDeploySnapshot` overlay, так как публичный API уже перенесён в действующий Business `Backend/IumrahBackend` отдельным патчем V3.

Инструкция:
1. Не используйте старый `iumrah-beta-update-20261120-unified-shares-v2.zip` повторно.
2. Загрузите **только этот ZIP** в корень `kepler-ios` (main), закоммитьте.
3. Дождитесь успешного `Apply iumrah Beta ZIP update` и проверьте, что `Commit applied files` зелёный.
4. В Business отдельно примените `iumrah-business-update-20261120-public-shares-v3.zip` и запустите `Deploy iumrah backend`, если это ещё не сделано.
5. Проверьте в приложении создание/отзыв ссылки владельцем, публичный просмотр и 404 после отзыва.

Этот ZIP не обновляет деплой workflow iOS и не заменяет Business backend. Сборка Xcode и деплой Cloudflare требуют проверки в CI. Статус успешного деплоя не следует выводить из локальной проверки архива.
