# 🧪 Instrucțiuni Testare APK → Shelly

## ✅ **Ce am modificat:**

1. **ApiConfig** - URL-ul serverului local: `http://192.168.1.132:8000/api/v1`
2. **ApiService** - Endpoint nou unificat pentru control poartă
3. **GateControlScreen** - Folosește API în loc de conexiune directă

## 📱 **Pentru testare pe telefon:**

### **1. Pregătire:**
- ✅ Serverul Laravel rulează pe `192.168.1.132:8000`
- ✅ Telefonul și PC-ul sunt pe aceeași rețea WiFi
- ✅ Ai un client de test cu codul: `TEST12`

### **2. Rulare aplicație:**
```bash
cd hopa_final
flutter run
```

### **3. Test rapid API (opțional):**
```bash
dart test_api_connection.dart
```

## 🔧 **Flux de testare:**

1. **Login în aplicație:**
   - Introdu codul: `TEST12`
   - Ar trebui să te autentifice cu succes

2. **Control poartă:**
   - Apasă pe butonul mare de control
   - Verifică în consolă:
     - `🔵 Trimit comandă de control către backend`
     - `✅ Comandă executată cu succes prin local/cloud!`

3. **Verifică în serverul Laravel:**
   - Ar trebui să vezi request-uri la:
     - `/api/v1/login-code`
     - `/api/v1/gate/control`

## 🚨 **Troubleshooting:**

### **"Eroare de conexiune"**
- Verifică IP-ul PC-ului: `ipconfig` (Windows)
- Actualizează în `api_service.dart` dacă e diferit

### **"Nu aveți un dispozitiv configurat"**
- Verifică în baza de date că clientul TEST12 are `shelly_device_id`
- Sau că există înregistrare în `shelly_devices`

### **"Dispozitivul nu are configurată nici conexiune locală, nici cloud"**
- Adaugă în baza de date:
  - `shelly_auth_key` pentru cloud
  - SAU `shelly_ip_address` pentru local

## 📊 **Monitorizare:**

În consola Flutter vei vedea:
- Request-uri API cu status codes
- Metoda folosită (local/cloud)
- Mesaje de succes/eroare

În Laravel logs:
- `storage/logs/laravel.log` - toate încercările de control
- Local vs Cloud fallback logic

## 🎯 **Rezultat așteptat:**

1. **Conexiune locală rapidă** dacă Shelly e pe aceeași rețea
2. **Fallback automat la cloud** dacă local nu merge
3. **Mesaje clare de eroare** pentru debugging

---

**Happy Testing!** 🚀 