# Budgie Flutter

Budgie Flutter is a personal finance planner for tracking salary, expenses, goals, and monthly savings progress.

## Features

- Monthly salary and expense tracking
- Goal creation with priority and optional fixed percent allocation
- Allocation engine behavior:
	- applies fixed percentages first
	- scales fixed percentages when total exceeds 100%
	- distributes remaining pool by priority weights (high=3, medium=2, low=1)
- Month processing to move allocations into goals
- Goal purchase flow with savings checks
- Purchase history and event log analytics
- Local persistence with shared_preferences
- Optional Firebase Google sign-in and Firestore sync

## Tech Stack

- Flutter and Dart
- flutter_bloc for state management
- shared_preferences for local persistence
- Firebase Auth and Cloud Firestore (optional)
- FlutterFire CLI for Firebase platform wiring

## Project Structure

```text
lib/
	main.dart
	app/
		bootstrap/
	core/
		constants/
		theme/
		utils/
	features/
		planner/
			application/
			domain/
			presentation/
test/
```

## Getting Started

```bash
cd budgie_flutter
flutter pub get
flutter run
```

## Optional Firebase Setup

Configure Firebase using the Firebase CLI (without FlutterFire):

```bash
npx -y firebase-tools@latest login
npx -y firebase-tools@latest use --add <PROJECT_ID>
npx -y firebase-tools@latest apps:list
```

Then download platform config files from Firebase:

```bash
npx -y firebase-tools@latest apps:sdkconfig ANDROID <ANDROID_APP_ID> > android/app/google-services.json
npx -y firebase-tools@latest apps:sdkconfig IOS <IOS_APP_ID> > ios/Runner/GoogleService-Info.plist
npx -y firebase-tools@latest apps:sdkconfig IOS <MACOS_APP_ID> > macos/Runner/GoogleService-Info.plist
```

If you prefer environment-based config, fetch your app config values and run with dart-defines:

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

Important:

- Firebase config artifacts are intentionally ignored in git.
- Do not commit firebase.json, lib/firebase_options.dart, or platform Google service files.

## Local-Only Mode

If Firebase is not configured or initialization is unavailable, the app continues in local-only mode using on-device storage.

## Quality Checks

```bash
flutter analyze
flutter test
```

## Contributing 

- Keep changes focused and well-scoped.
- Run analyze and tests before opening a PR.
- Follow existing project structure and naming conventions.
