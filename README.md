# Local Party (Android)

Local Party — Flutter-приложение для локальной комнаты на 2 Android-устройства:

- одно устройство (DJ/Host) захватывает системный звук через `MediaProjection`;
- второе устройство воспроизводит поток с буфером и clock sync;
- можно передавать роль DJ в комнате.

## Что уже сделано

- Переименован пакет в `local_party`
- Android `applicationId`: `com.localparty.app`
- `minSdk = 29` (Android 10+)
- Добавлены разрешения и foreground service для `mediaProjection`
- Реализованы:
  - lobby/room UI
  - discovery/connect на Nearby
  - захват PCM через Kotlin service
  - воспроизведение PCM через `AudioTrack`
  - handover DJ роли

## Команды (как ты просил — сам запускаешь)

Из корня проекта:

```bash
flutter pub get
dart analyze lib test
flutter test
```

### Сборка debug APK

```bash
flutter build apk --debug
```

Если упадёт с ошибкой типа `zip END header not found` (битый Gradle wrapper cache), выполни:

```bash
rm -rf ~/.gradle/wrapper/dists/gradle-8.14-all
cd android
./gradlew --refresh-dependencies
cd ..
flutter build apk --debug
```

Если всё ещё падает:

```bash
flutter clean
rm -rf ~/.gradle/caches
rm -rf ~/.gradle/wrapper/dists
flutter pub get
flutter build apk --debug
```

## Запуск на 2 устройствах (smoke test)

1. На обоих телефонах включи Wi‑Fi и Bluetooth.
2. Запусти приложение на обоих:
   ```bash
   flutter run -d <device_id_1>
   flutter run -d <device_id_2>
   ```
3. На первом: `Создать комнату`.
4. На втором: `Найти комнату` → `Подключиться`.
5. На DJ устройстве нажми `Начать захват звука` и дай системное разрешение.
6. Включи музыку в другом приложении.
7. На втором проверь звук и задержку.
8. Нажми `Стать диджеем` на госте и проверь handover.

## Важные ограничения Android

- Не все приложения разрешают audio playback capture.
- Spotify / YouTube Music часто блокируют захват (это нормально, не баг приложения).
- При активном захвате всегда показывается системная foreground-нотификация.

# my_first

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
