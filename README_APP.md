# 📱 Hopa Gate Control - Aplicație Mobilă

## 🤖 Android APK

### Locație APK
```
hopa_final/build/app/outputs/flutter-apk/app-release.apk
```

### Dimensiune: ~22.3 MB

### Instalare Android
1. Transferă `app-release.apk` pe telefon
2. Activează "Surse necunoscute" în Setări > Securitate
3. Deschide APK-ul și instalează
4. La prima pornire, introdu codul de activare primit de la installer

## 🍎 iOS (iPhone/iPad)

### Pentru a construi pentru iOS:

**Cerințe:**
- Mac cu macOS
- Xcode instalat
- Apple Developer Account ($99/an)

**Comenzi:**
```bash
# Pe Mac
cd hopa_final
flutter build ios --release

# Sau pentru TestFlight
flutter build ipa
```

### Alternativă fără Mac - Codemagic CI/CD:

1. **Creează cont pe codemagic.io** (gratuit pentru 500 minute/lună)
2. **Conectează repository-ul**
3. **Configurează build-ul:**
   ```yaml
   # codemagic.yaml
   workflows:
     ios-workflow:
       name: iOS Workflow
       environment:
         flutter: stable
         xcode: latest
       scripts:
         - cd hopa_final
         - flutter packages pub get
         - flutter build ios --release --no-codesign
   ```

## 📋 Funcționalități Aplicație

### ✅ Implementate:
1. **Autentificare cu cod activare**
2. **Control poartă** (deschide/închide)
3. **Contact Installer** cu calendar pentru programări
4. **Setări sistem automatizare** (BFT, FAAC, Nice, etc.)
5. **Schimbare nume dispozitiv**
6. **Notificări SOS**
7. **Tema dark/light**

### ❌ De implementat:
1. **Push notifications** (necesită Firebase)
2. **Istoric deschideri în app**
3. **Control vocal** (Hey Siri/OK Google)
4. **Widget-uri** pentru acces rapid
5. **Apple Watch / WearOS support**

## 🔧 Configurare pentru Producție

### 1. Schimbă API URL în `lib/config/api_config.dart`:
```dart
class ApiConfig {
  static const String baseUrl = 'https://api.hopagate.ro'; // În loc de localhost
  static const String apiVersion = '/api/v1';
}
```

### 2. Configurează Firebase (pentru push notifications):
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

### 3. Actualizează versiunea în `pubspec.yaml`:
```yaml
version: 1.0.0+1  # Schimbă la 1.0.1+2, etc.
```

## 📦 Publicare în Store-uri

### Google Play Store
1. Creează cont developer ($25 o singură dată)
2. Pregătește:
   - Screenshots (min. 2)
   - Icon 512x512
   - Feature graphic 1024x500
   - Descriere în română
3. Upload APK/AAB
4. Completează formularele
5. Așteaptă review (2-3 ore)

### Apple App Store
1. Apple Developer Account ($99/an)
2. Pregătește:
   - Screenshots pentru toate dimensiunile
   - Icon 1024x1024
   - Descriere și keywords
3. Upload prin Xcode/Transporter
4. Așteaptă review (24-48 ore)

## 🛠️ Comenzi Utile

```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Run în debug mode
flutter run

# Build APK
flutter build apk --release

# Build App Bundle (pentru Play Store)
flutter build appbundle --release

# Build iOS (doar pe Mac)
flutter build ios --release

# Analizează codul
flutter analyze

# Testează
flutter test
```

## 📱 Testare

### Android
- APK disponibil: `app-release.apk`
- Testează pe diferite versiuni Android (7.0+)
- Verifică pe telefoane cu notch/punch-hole

### iOS
- Folosește TestFlight pentru beta testing
- Testează pe iPhone și iPad
- Verifică Dark Mode

## 🐛 Probleme Cunoscute

1. **NDK Warning** - Nu afectează funcționalitatea
2. **Keyboard overlap** - Rezolvat cu `resizeToAvoidBottomInset`
3. **iOS build** - Necesită Mac sau CI/CD service

## 📞 Suport

Pentru probleme cu aplicația:
- Email: support@hopagate.ro
- Tel: 0721 XXX XXX 