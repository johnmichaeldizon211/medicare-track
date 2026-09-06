# Play Store Release Checklist

## Required Build Inputs

Build with JDK 21 or Android Studio's bundled JBR. The local system Java 25 can cause Gradle/Kotlin problems.

Before building from PowerShell, prefer:

```powershell
$env:JAVA_HOME="C:\Program Files\Android\Android Studio\jbr"
flutter build appbundle --release
```

The current Flutter app code does not reference `API_BASE_URL`, so no release `--dart-define` is currently required for that value.

## Firebase Status

- Firebase Android package is `com.lifehouse.medicaretrack`.
- `android/app/google-services.json` points to Firebase project `medicare-track-af1cf`.
- `.firebaserc` default project is also `medicare-track-af1cf`.
- Debug and release Google Services Gradle processing pass locally with Android Studio's bundled JBR:
  - `:app:processDebugGoogleServices`
  - `:app:processReleaseGoogleServices`
- Firestore rules and indexes are present in `firestore.rules` and `firestore.indexes.json`.

Before launch, deploy Firestore rules/indexes if the Firebase Console does not already have the latest version:

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

The backend uses Firebase Admin SDK credentials through `FIREBASE_SERVICE_ACCOUNT_JSON` or `GOOGLE_APPLICATION_CREDENTIALS`. Keep service account JSON files private and do not commit or upload them publicly.

If enabling Google Sign-In, Phone Auth, App Check, restricted API keys, or other certificate-bound Google APIs later, add the Play app signing SHA-1/SHA-256 fingerprints in Firebase Project settings and then refresh `google-services.json` if Firebase generates changes.

## Android Signing

Create a Play upload key, then copy `android/key.properties.example` to `android/key.properties` and fill in the real values:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=upload-keystore.jks
```

Place the keystore at `android/upload-keystore.jks`. Both files are ignored by git.

## Play Console Items

Before production rollout, complete these in Play Console:

- Confirm package name: `com.lifehouse.medicaretrack`. This cannot be changed after publishing the app under that package.
- Target SDK is already set to API 36 in `android/app/build.gradle.kts`.
- Privacy Policy URL and matching in-app/user-data disclosures.
- Data Safety form for account, contact, authentication, health/care, and message data.
- Health apps declaration, because the app supports resident care, medications, and care tasks.
- Account deletion web URL. The app includes in-app family account deletion, but Google Play also requires a web path for deletion requests.
- Store listing assets: app icon, feature graphic, screenshots, short description, full description, contact email, and app category.
- Closed/internal testing release before production rollout.
