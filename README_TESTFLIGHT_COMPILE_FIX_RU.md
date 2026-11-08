# iumrah — исправление падения TestFlight 08.11.2026

## Причина
В логе `logs_115056464826.zip`, шаг Archive, `Sources/Views/Package/IumrahNuiteeJourneyFlow.swift:251`:
`error: no exact matches in call to instance method 'background'`.

Этот файл входил в старое 16-файловое обновление и остался в репозитории после применения объединённого 32+16 патча: последний не содержит инструкций на удаление старых файлов, а распаковщик только перезаписывает существующие пути.

## Исправление
- Устаревший `IumrahNuiteeJourneyFlow.swift` заменён тонким совместимым переходником к **NuiteeJourneyHotelsView**.
- Старая точка входа `FlightFirstPackageFlowView.swift` также перенаправлена к актуальному Nuitee journey.
- Удалены устаревшие ViewBuilder-экраны, один из которых вызвал ошибку Swift, а также дублирующий расчёт стоимости и устаревшая перезагрузка тарифов.
- Не меняются текущие UI, высота чёрного хедера, новая зелёная карточка, native Liquid Glass, расчёт стоимости, серверная интеграция, workflow, bundle ID и настройки подписи.

## Как применить
Загрузите ZIP в корень **main**, НЕ распаковывая вручную. Существующий `Apply iumrah Beta ZIP update` заменит эти два файла и удалит ZIP.
После успешного применения повторно запустите существующий TestFlight workflow.

## Проверено
- Содержимое ZIP корректно и включает ровно два Swift-файла с совместимыми типами.
- Swift syntax parse обоих изменённых файлов; повторный parse общей объединённой кодовой базы.
- Ссылки `NuiteeJourneyHotelsView` разрешаются новым файлом `Sources/Views/Hotels/NuiteeJourneyHotelsView.swift` из объединённого патча.
- Полная компиляция SwiftUI/Xcode недоступна в Linux; результат TestFlight необходимо проверить CI.
