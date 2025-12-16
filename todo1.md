# TODO1 – Plan de finalizare ZYPGO (cap-coadă)

## 0. Bază și reguli
- [ ] Verifică `.env` pentru chei (Stripe, Firebase/FCM, Google Maps) și URL-urile API (local/prod).
- [ ] Rulează `php artisan config:clear && php artisan route:clear` după modificări de config/rute.

## 1. Admin / Super Admin – Management Șoferi
- [ ] Backend: endpoint listare șoferi cu filtre (status aprobat/în așteptare/suspendat, disponibilitate, doc lipsă, rating).
- [ ] Backend: endpoint detaliu șofer (profil, documente, vehicule, statistici comenzi/rating/anulări).
- [ ] Backend: acțiuni aprobă/suspendă/revocă, reset documente lipsă, schimbă rol/permisiune.
- [ ] Frontend: înlocuiește placeholder “Modul în dezvoltare” cu listă + filtre + acțiuni + modale detalii/documente/vehicule.
- [ ] Notificări: trimite push/email la aprobare/suspendare; log în audit.

## 2. Admin – Șoferi în Așteptare
- [ ] Listă dedicată pending + approve/reject cu motiv.
- [ ] Workflow verificare documente înainte de aprobare.

## 3. Admin – Bids/Users rating fix
- [ ] `resources/views/admin/bids/show.blade.php`: folosește `average_rating` (sau câmp real) și elimină TODO rating.
- [ ] Confirmă model/câmp rating în `users` și calculele de medie.

## 4. Transportator (Driver) – pagini placeholder
- [ ] `driver/bids/show.blade.php`: date reale ofertă + acțiuni (modifică sumă, anulează, vezi comandă).
- [ ] `driver/orders/show.blade.php`: date reale comandă + acțiuni (finalizează, raportează problemă, contactează client).
- [ ] `DriverController::subscriptionStats`: înlocuiește mock cu statistici reale din abonamente.

## 5. Comenzi & Plăți
- [ ] `Api/Driver/OrderController`:
  - [ ] Procesează plata la finalizare (Stripe/escrow) – TODO existent.
  - [ ] Trimite push la anulare către client (TODO existent).
- [ ] `NotificationHelper`/Push: verifică integrările folosite pentru comenzi.

## 6. Abonamente
- [ ] `Api/SubscriptionController`: implementează “Process payment” în subscribe / change plan / renew (înlocuiește success hardcodat).
- [ ] Actualizează status utilizator/abonament după plată, log erori.

## 7. Rating / Moderare
- [ ] `Api/RatingController`: la raportare rating → notifică adminii (push/email) + intrare în audit.

## 8. Chat / AI
- [ ] `Api/ChatController@handleAutoTranslation`: înlocuiește placeholder cu integrare reală (Google Translate) sau dezactivează controlat.
- [ ] Verifică endpoint-ul super-admin chatbot din `components/chatbot-widget.blade.php` (securizare + răspunsuri).

## 9. Dashboard metrics
- [ ] `DashboardController`: înlocuiește valorile placeholder pentru active/available drivers, ongoing trips etc. cu calcule reale.

## 10. Mobile / Chei / Store
- [ ] Setează `API_BASE_URL` corect (local/prod) în mobile apps.
- [ ] Înlocuiește chei reale pentru Maps/Firebase/Stripe.
- [ ] Store readiness: icon-uri, splash, descrieri, privacy/terms, teste pe device-uri.

## 11. QA / Livrare
- [ ] Teste end-to-end (aprobare șofer, comenzi, licitații, plăți, abonamente, rating).
- [ ] Teste push/FCM + fallback email.
- [ ] Load/security testing conform plan (TLS/SSL, rate-limit, webhook Stripe).
- [ ] Documentează pașii de deployment (SSL/CDN, domeniu).


