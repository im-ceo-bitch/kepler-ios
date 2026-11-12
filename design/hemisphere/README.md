# iumrah · Native Hemisphere Map

Изолированный SwiftUI-компонент для iOS 17+ и Mac Catalyst. Не изменяет ни одного существующего экрана, backend или workflow. XcodeGen уже включает весь `Sources`, поэтому менять project.yml не требуется.

## Подключение

Полный глобус, адаптация к системной теме:

```swift
IumrahHemisphereMap()
    .frame(width: 300, height: 300)
```

Верхняя часть сферы для авиационного hero, без перехвата жестов:

```swift
IumrahHemisphereMap(
    projection: .init(latitude: 25, longitude: 48),
    presentation: .horizon,
    palette: .dark,
    cycleDuration: 12,
    lightIntensity: 0.8,
    mapOpacity: 0.85
)
.frame(height: 145)
```

`palette: .light` / `.dark` принудительно задаёт монохромный стиль, `.automatic` следует colorScheme. `isAnimating: false` отключает движение света. `lightIntensity` и `mapOpacity` ограничены диапазоном 0...1. Период ограничен 6...60 секундами. Центр полушария произвольный, по умолчанию Аравия и Центральная Азия. География не вращается. Анимация выключается вне активной сцены, после исчезновения компонента и при Reduce Motion. Для проверки внешнего вида предусмотрены два изолированных Xcode Preview.

## Дальнейшая интеграция с рейсами

`IumrahHemisphereProjection.point(latitude:longitude:)` возвращает нормализованные координаты 0...1 для видимой стороны сферы или nil для обратной стороны. Масштабирование и смещение должны соответствовать полному кругу, в режиме horizon — до его обрезки. Реальные координаты и статусы AeroDataBox добавляются отдельным overlay позднее. Сам компонент не делает запросов, не симулирует статус полёта и не использует цветовые акценты.

## Географические данные

Natural Earth, low-resolution 1:110m country polygons (public domain, https://www.naturalearthdata.com/about/terms-of-use/). Границы стран объединены в контуры суши; сетка триангулирована и закодирована в Swift. 16 905 треугольников, координаты с точностью хранения 0,01°. Это обзорная география, не навигационная карта. Никаких внешних пакетов, сетевых тайлов или изображений карты в приложении.

## Проверки

Из корня репозитория:

```sh
swiftc -O Sources/Core/Components/IumrahHemisphereProjection.swift \
  Sources/Core/Components/IumrahHemisphereLandData.swift \
  design/hemisphere/main.swift -o /tmp/iumrah-hemisphere-check
/tmp/iumrah-hemisphere-check
```

Проверены декодирование, координаты, отсечение горизонта и четыре центра проекции. Все три Swift-файла прошли синтаксический parse. SwiftUI/Xcode build и FPS на iPhone необходимо проверить на macOS: в Linux отсутствует Apple SDK. Внешнее анимированное превью — визуализация той же геометрии и формул освещения, не запись из запущенного iOS-приложения.
