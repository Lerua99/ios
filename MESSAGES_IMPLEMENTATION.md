# 💬 IMPLEMENTARE MESAJE & PUSH INSTALATOR

## ✅ CE AM IMPLEMENTAT

### 📱 **APK Flutter (hopa_final):**

1. **InstallerMessagesScreen** - Ecran centralizat cu 3 tab-uri:
   - 🚨 SOS Alerts (clickabile pentru detalii)
   - 🆕 Cereri Instalare (clickabile pentru accept/reject)
   - 📢 Mesaje Admin (clickabile pentru citire)

2. **InstallerSOSDetailScreen** - Detalii SOS:
   - Informații client (nume, telefon, adresă)
   - Problema raportată
   - Buton "Sună Clientul"
   - Buton "Marchează ca Preluat" (acknowledge)
   - Buton "Programează Vizită" (schedule)
   - Buton "Marchează ca Rezolvat" (resolve)

3. **InstallerRequestDetailScreen** - Detalii cerere instalare:
   - Informații client
   - Adresă instalare
   - Tip serviciu solicitat
   - Deadline (ore rămase)
   - Buton "Sună Clientul"
   - Buton "Accept Cererea"

4. **API Service** - Metode noi:
   - `acknowledgeInstallerSOS(sosId)`
   - `scheduleInstallerSOS(sosId, date, time, notes)`
   - `getInstallationRequests()`
   - `acceptInstallationRequest(requestId)`
   - `getAdminNotifications()`
   - `markAdminNotificationRead(notificationId)`

5. **Dashboard** - Buton "💬 Mesaje" cu badge pentru necitite

### 🔧 **Backend Laravel (X:/):**

1. **API Routes** (`routes/api.php`):
   - `GET /api/v1/installer/sos/{id}/schedule` - programează vizită SOS
   - `GET /api/v1/installer/notifications` - listă notificări admin
   - `POST /api/v1/installer/notifications/{id}/read` - marchează ca citită

2. **Controllers:**
   - **InstallationRequestController** - Push FCM când vine cerere nouă
   - **Admin\NotificationController** - Push FCM când admin trimite notificare
   - **Api\Installer\NotificationController** (NOU) - API notificări admin
   - **Api\Installer\SOSController** - Adăugat metoda `schedule()`

3. **Push Notifications:**
   - 🆕 Push pentru instalări noi → instalator
   - 📢 Push pentru mesaje admin → instalatori (specific sau broadcast)
   - 🚨 Push pentru SOS → instalator (deja exista)

## 🧪 TESTARE

### **1. Test SOS:**
a) Din APK client, trimite SOS
b) Verifică că instalatorul primește push
c) În APK instalator, deschide "💬 Mesaje" → tab "SOS"
d) Click pe card SOS → se deschide detalii
e) Testează: Sună, Acknowledge, Schedule, Resolve

### **2. Test Cereri Instalare:**
a) Din web (hopa.tritech.ro/solicita-instalare), completează formular
b) Selectează un instalator
c) Verifică că instalatorul primește push
d) În APK instalator, deschide "💬 Mesaje" → tab "Cereri"
e) Click pe card cerere → se deschide detalii
f) Testează: Sună, Accept

### **3. Test Mesaje Admin:**
a) Din admin panel (hopa.tritech.ro/admin), secțiunea Notificări
b) Click "Trimite Notificare" → "Doar Instalatori" sau "Toți Instalatorii"
c) Completează: titlu, mesaj, tip (info/success/warning/danger)
d) Verifică că instalatorul primește push
e) În APK instalator, deschide "💬 Mesaje" → tab "Admin"
f) Click pe mesaj → se deschide dialog cu mesaj complet

### **4. Test Push Multi-Device:**
a) Deschide APK pe 2 telefoane cu același instalator
b) Verifică că apar 2 token-uri FCM:
   ```bash
   php artisan tinker --execute='$u=App\Models\User::where("role","installer")->first(); echo App\Models\UserFcmToken::where("user_id",$u->id)->count();'
   ```
c) Trimite un test (SOS, cerere sau mesaj admin)
d) Verifică că ambele telefoane primesc push

## 🔄 REBUILD APK

Pentru a testa în APK:

```bash
cd D:\Ampps\www\nou\hopa_final
flutter clean
flutter pub get
flutter build apk --release
```

APK-ul va fi în: `build/app/outputs/flutter-apk/app-release.apk`

## 📊 FLUXURI COMPLETE

### **Flux SOS:**
1. Client trimite SOS din APK
2. Backend trimite push către instalator
3. Instalator primește notificare push
4. Instalator deschide APK → Mesaje → tab SOS
5. Click pe card SOS → detalii complete
6. Acknowledge → Schedule → Resolve

### **Flux Instalare Nouă:**
1. Client completează formular pe web
2. Selectează instalator din județ
3. Backend trimite push către instalator
4. Instalator primește notificare push
5. Instalator deschide APK → Mesaje → tab Cereri
6. Click pe card cerere → detalii complete
7. Accept cererea → contactează clientul

### **Flux Mesaj Admin:**
1. Admin creează notificare în panel
2. Selectează destinatar (un instalator sau toți)
3. Backend trimite push către instalator(i)
4. Instalator primește notificare push
5. Instalator deschide APK → Mesaje → tab Admin
6. Click pe mesaj → citește mesajul complet
7. Mesajul e marcat automat ca citit

## ⚙️ CONFIGURARE NECESARĂ

Asigură-te că pe server:
1. Rute actualizate: `php artisan route:clear && php artisan route:cache`
2. Config actualizat: `php artisan config:clear && php artisan config:cache`
3. Firebase service account configurat: `storage/app/firebase-service-account.json`

## 🐛 TROUBLESHOOTING

**Push-ul nu ajunge:**
- Verifică că instalatorul a deschis APK (reînnoiește FCM token)
- Verifică numărul de token-uri: trebuie câte 1 per device
- Verifică log-urile: `tail -f storage/logs/laravel.log | grep -i "push\|fcm"`

**Mesajele nu apar în APK:**
- Verifică răspunsul API: `GET /api/v1/installer/notifications`
- Verifică autentificarea: token Bearer valid
- Verifică log-urile în APK (debug mode)

**Erori FCM UNREGISTERED:**
- Token-uri vechi/expirate
- Rulează cleanup: `php artisan tinker --execute='App\Models\UserFcmToken::cleanupOldTokens();'`
- Deschide APK pentru token nou

---
**Data implementării**: 21 Octombrie 2024
**Versiune**: 2.0




































