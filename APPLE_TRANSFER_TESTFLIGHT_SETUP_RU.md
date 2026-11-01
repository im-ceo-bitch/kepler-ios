# iumrah — перенос Apple Team и новый TestFlight CI (01.11.2026)

БАЗА: загруженный `kepler-ios-main 2.zip`. Это конфигурационный PATCH к текущему репозиторию, **не подтверждённый Xcode build**. Требуется реальный прогон GitHub Actions.

## 0. ВАЖНО: автоматический распаковщик репозитория

`.github/workflows/apply-beta-update.yml` из исходного ZIP **игнорирует любые изменения `.github/workflows/`**, кроме `deploy-package-engine.yml`.

**Поэтому простая загрузка ZIP `iumrah-beta-update-*.zip` в корень GitHub НЕ обновит TestFlight workflows!**

Установи новые YAML вручную, выбрав в GitHub: `.github/workflows` → Add file → Upload files (загрузи извлечённые файлы). Либо распакуй ZIP и внеси файлы через git push. После этого ZIP PATCH в корне GitHub обновит исходники и скрипты, но его workflow-файлы автоматический распаковщик пропустит. Выдаваемый ZIP является переносимым patch overlay — пути файлов внутри **без** вложенной папки `kepler-ios-main/`.

## 1. Что изменено

- Новый владелец Apple Developer Individual: Team ID `HVT4U96286`.
- App ID/Bundle IDs сохранены: `6759577859`, `com.iumrah.app`, `com.iumrah.app.widgets`.
- `project.yml`: версия `2.1.0`, сборка `200` по умолчанию; Signing = Automatic для app+Widget; не задеваются GoogleSignIn resource bundle targets.
- Entitlements и Swift WidgetStore: новая общая Keychain Sharing группа `HVT4U96286.com.iumrah.shared`.
- `Backend/PackageEngine/src/storefront.ts`: оба AASA appIDs (`HVT4U96286...` и прежний для установленных ранее клиентов). **Новое AASA начнёт работать только после отдельного развёртывания Backend/PackageEngine в Cloudflare.**
- `.github/workflows/iumrah-build-only.yml`: проверка без Apple Secrets, Intel, Xcode26+, unsigned iOS compilation.
- `.github/workflows/testflight-intel.yml`: автономный ручной workflow — build-only gate, затем archive/export с `-allowProvisioningUpdates` + новым App Store Connect API, загрузка через `apple-actions/upload-testflight-build@v5`.
- Три устаревших workflow `testflight.yml`, `testflight-signing.yml`, `testflight-mac.yml` заменены безопасными предупреждениями (исходные использовали старые ключи и профили).
- TestFlight номер сборки берётся через API нового владельца для конкретной версии; новая 2.1.0 стартует с 200, последующие 201, 202... Прошлые номера 30000 в ДРУГОЙ версии не переносятся в новую нумерацию. Если у новой версии номер достиг 5000, Workflow останавливается.
- Старые файлы `Signing/distribution-private-key.enc`, `Signing/*.mobileprovision` и `Resources/Provisioning/*.mobileprovision` **не используются новым Workflow**. Они остаются в исходном репозитории, поскольку ZIP-распаковщик не удаляет файлы и защищает `Signing/`. После удачного нового CI их следует удалить из GitHub и проверить историю/права доступа (private signing material).

## 2. GitHub Secrets — менять только у РЕПОЗИТОРИЯ iumrah iOS

GitHub → repo → Settings → Secrets and variables → Actions → **Repository secrets** (карандаш Edit).

| Secret | Действие | Значение |
|:--|:--|:--|
| `APPLE_TEAM_ID` | ОБНОВИТЬ | `HVT4U96286` |
| `ASC_KEY_ID` | ОБНОВИТЬ | Key ID, полученный в **новом** Aziz Kodirov App Store Connect (не старый ключ Kodirali) |
| `ASC_ISSUER_ID` | ОБНОВИТЬ | Issuer ID **нового** Aziz Kodirov App Store Connect |
| `ASC_API_KEY_P8` | ОБНОВИТЬ | **весь PEM-текст** из нового `AuthKey_<keyid>.p8`, включая BEGIN/END PRIVATE KEY, без base64 |
| `IOS_SIGNING_KEY_PASSWORD` | Больше не нужен НОВОМУ iOS TestFlight Workflow | Не пытаться использовать со старым `Signing/distribution-private-key.enc`. Удалить только после вывода из эксплуатации старых CI. |
| `APPLE_ID_EMAIL` | Только если где-то ещё используется | Новый Apple email; для нового TestFlight CI не нужен |
| `APPLE_APP_SPECIFIC_PASSWORD` | Не нужен новому CI | Используется только в устаревших схемах авторизации |

**Остальные secrets** Cloudflare, Ignav, AeroDataBox, SMS, Travelpayouts не меняются из-за App Transfer. `IOS_SIGNING_KEY_PASSWORD` от прежнего владельца не будет работать с новым профилем. Новому CI не нужен `.p12` и не нужны заранее скачанные `.mobileprovision`: Xcode получает подпись через App Store Connect API (Apple WWDC21 cloud signing). Но нужна достаточная роль API-ключа и разрешение на создание/обновление signing assets; при ошибке авторизации проверь Account Holder/Admin или попроси Apple Developer Support.

**Безопасность:** приватный `.p8` никогда не коммитить в репозиторий, не присылать в чат и не печатать в Actions logs. Старый API ключ после переноса приложения технически относится к другой команде и должен быть заменён.

## 3. Настройки Apple Developer — единовременно

В НОВОМ аккаунте `developer.apple.com/account/resources/identifiers/list`:

1. Проверь ID приложения `com.iumrah.app` и наличие включённых Push Notifications, Sign in with Apple, Associated Domains, Keychain Sharing.
2. Проверь существование отдельного Bundle ID `com.iumrah.app.widgets`; если ID не перенёсся автоматически, зарегистрируй его под новой командой и включи разрешённую Keychain Sharing группу.
3. Проверь, что Keychain group `HVT4U96286.com.iumrah.shared` разрешена для **обоих** таргетов.
4. В App Store Connect нового владельца открой Users and Access → Integrations → App Store Connect API → Team Keys. Создай **новый** ключ с достаточными правами (для автоматического подписания нужен доступ к сертификатам/профилям), скачай `.p8` ОДИН раз. Если App Manager не может создать signing assets, используй Admin/Account Holder; не предоставляй ключ старому аккаунту.
5. Не удаляй старый Apple ID, пока не проверишь первый подписанный TestFlight build, вход пользователей и сервисы.

## 4. Порядок установки и запуска

1. **Вручную обнови файлы `.github/workflows/testflight-intel.yml`, `.github/workflows/iumrah-build-only.yml`, `.github/workflows/testflight.yml`, `.github/workflows/testflight-signing.yml`, `.github/workflows/testflight-mac.yml` в GitHub** (как в ZIP). При необходимости старые workflows можно вообще удалить, кроме `testflight-intel.yml` (он новый) и `iumrah-build-only.yml`.
2. Примени остальные пути из ZIP с помощью обычного git push или автоматического `iumrah-beta-update-*.zip` распаковщика (помни о блокировке workflow-путей).
3. Замени четыре обязательных secrets из таблицы выше.
4. GitHub Actions → **Iumrah | Build Only | Intel** → Run workflow. Процесс не требует Apple API, проверяет типы Swift на macOS и компиляцию в Xcode.
5. Только после зелёного Build Only → Actions → **Iumrah | TestFlight | Intel | New Team** → Run workflow → `2.1.0`.
6. В TestFlight workflow есть **свой build-only gate**, и `testflight_upload` запускается лишь после его успеха. Он использует новый Team, автоматически получает build number и IPA, затем отправляет в TestFlight. `Upload` означает, что Apple получила бинарник, но перед появлением в TestFlight он ещё проходит обработку.
7. После первого успешного Upload проверь на iPhone Sign in with Apple, push notifications, widget, universal links, booking, wallet pass.

## 5. НЕ забыть после App Transfer

- **Keychain Sharing**: Team ID меняется. У существующих пользователей часть секретов Keychain после обновления станет недоступной — требуется повторный вход. Не удаляй пользовательские данные на сервере; проверь миграцию сессий.
- **Sign in with Apple**: Apple выдаёт отдельные transfer identifiers / migration API. Если у тебя реальные пользователи Apple Login, требуется перенос идентификаторов в пределах установленного Apple срока; изменение Team ID само по себе это не делает. Проверь backend `APPLE_WEB_CLIENT_ID`, private keys и настройки Services IDs.
- **APNs**: токены/ключи команды и server credentials надо проверить и обновить для нового владельца, иначе push могут перестать доставляться.
- **Associated Domains**: нужен Backend/PackageEngine deploy, чтобы AASA `https://iumrah.app/.well-known/apple-app-site-association` содержал новый App ID. В patch добавлен также старый для старых установок.
- **Apple Wallet Pass**: `WALLET_TEAM_ID` и Workflow `deploy-package-engine.yml` **пока намеренно остаются со старым `2DQ678JTNG`**, так как Pass Type ID и приватный сертификат не перенесены/не заменены в этом обновлении. НЕ меняй `WALLET_TEAM_ID`, `WALLET_CERT_PEM`, `WALLET_KEY_PEM`, `WALLET_PASS_TYPE_ID` наугад. Для возобновления перевыпуска карт требуется отдельно выпустить/привязать Pass Type ID и Pass Signing Certificate у нового владельца; затем согласованно поменять backend, secrets и проверку deploy workflow.
- **Mac Catalyst**: iOS workflow не собирает macOS. Старый `testflight-mac.yml` отключён, поскольку старые Mac certificates/profiles не относятся к новой команде. Для macOS понадобится отдельное обновление и Mac App Store signing.
- **Старый репозиторий/сборки**: `ASC_API_KEY_P8` новой команды НЕ подходит к старым профилям в `Signing/`, старые `ios_distribution.cer` и `IOS_SIGNING_KEY_PASSWORD` использовать нельзя.

## 6. Что проверено / не проверено

Проверено локально (Linux): валидность YAML, синтаксис Python/Ruby, структурные проверки проекта/entitlements, `node --test` соответствующего AASA контракта, синтаксис shell steps, сохранение путей PATCH. **XcodeBuild, подпись сертификатами нового владельца и реальные серверные возможности Apple не выполнялись**; эти шаги обязательно исполняются GitHub Actions. Если Apple API key не имеет права создавать сертификаты, workflow безопасно завершится ошибкой, не загрузив неподписанное приложение.

Документы:
- https://developer.apple.com/videos/play/wwdc2021/10204/ — Xcode cloud signing with App Store Connect API keys
- https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
