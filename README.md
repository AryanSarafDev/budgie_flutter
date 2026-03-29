# Budgie Flutter

Flutter equivalent of the Budgie React planner.

## Included Features

- Monthly salary and expense tracking
- Goal creation with priority and optional fixed % allocation
- Same allocation engine behavior as React app:
	- applies fixed percentages first
	- scales fixed percentages when total exceeds 100%
	- distributes remaining pool by priority weights (high=3, medium=2, low=1)
- Month processing to move allocated savings into goals
- Goal purchase flow with savings checks
- Purchase history + event log analytics tab
- Local persistence via `shared_preferences`
- Optional Firebase Google sign-in + Firestore sync to `budgieUsers/{uid}`

## Run

```bash
cd budgie_flutter
flutter pub get
flutter run
```

## Optional Firebase Setup

This app intentionally uses `--dart-define` Firebase config so it can run without FlutterFire codegen.

Example:

```bash
flutter run \
	--dart-define=FIREBASE_API_KEY=... \
	--dart-define=FIREBASE_APP_ID=... \
	--dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
	--dart-define=FIREBASE_PROJECT_ID=... \
	--dart-define=FIREBASE_AUTH_DOMAIN=... \
	--dart-define=FIREBASE_STORAGE_BUCKET=... \
	--dart-define=FIREBASE_MEASUREMENT_ID=...
```

If Firebase config is missing, app behavior falls back to local-only mode.

## Validation

```bash
flutter analyze
flutter test
```
