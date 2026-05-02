# greenhouse

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## SCADA Environment Profiles

This app supports two env profiles:

- `.env.physical` for real STM32 device (`192.168.50.20:502` by default)
- `.env.emulated` for local mock device (`127.0.0.1:1502` by default)

Run with profile:

```bash
flutter run --dart-define=SCADA_ENV=physical
```

```bash
flutter run --dart-define=SCADA_ENV=emulated
```
