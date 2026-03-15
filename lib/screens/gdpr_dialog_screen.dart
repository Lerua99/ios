import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GdprDialogScreen extends StatelessWidget {
  final VoidCallback? onAccepted;

  const GdprDialogScreen({Key? key, this.onAccepted}) : super(key: key);

  Future<void> _accept(BuildContext context) async {
    if (onAccepted != null) {
      onAccepted!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false, // Header-ul gestionează singur padding-ul de sus
        child: Column(
          children: [
            // Header gradient ca în screenshot
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 20, right: 20, bottom: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: const [
                  Icon(Icons.shield_outlined, color: Colors.white, size: 26),
                  SizedBox(width: 10),
                  Text('🔒 Politica de\nConfidențialitate',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF065F46), width: 1),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TritechGroup S.R.L.\nUltima actualizare: octombrie 2025',
                              style: TextStyle(color: Colors.grey[200], height: 1.4, fontSize: 16)),
                          const SizedBox(height: 16),
                          _section('1. Cine suntem noi',
                              'TritechGroup S.R.L. este o companie românească specializată în soluții de automatizare pentru porți și sisteme inteligente de control al accesului.\nWebsite: https://hopa.tritech.ro\nE-mail de contact: contact@hopa.tritech.ro'),
                          _section('2. Ce acoperă această Politică de Confidențialitate',
                              'Explică ce date colectăm, cum le folosim, în ce scop și care sunt drepturile dumneavoastră. Se aplică aplicației Hopa și site-ului hopa.tritech.ro.'),
                          _section('3. Ce sunt datele personale',
                              'Informații care pot duce la identificarea unei persoane (nume, e-mail, telefon, IP, date despre dispozitiv, locație).'),
                          _section('4. De ce colectăm datele',
                              'Funcționarea aplicației și a dispozitivelor; administrarea conturilor; comunicări de întreținere; suport tehnic; îmbunătățiri și securitate; marketing doar cu consimțământ.'),
                          _section('5. Ce date colectăm și cum',
                              'Site: IP, browser, sistem de operare.\nAplicație: nume, e-mail, telefon, token Firebase, loguri la cerere, locație doar dacă este activată deschiderea automată.'),
                          _section('6. Consimțământ notificări și marketing',
                              'Poți accepta/refuza notificările push și promoțiile. Opțiunile pot fi modificate ulterior din Setări.'),
                          _section('7. Cui dezvăluim datele',
                              'Doar furnizori IT și parteneri autorizați pentru funcționalitate sau suport. Nu vindem date.'),
                          _section('8. Durata de stocare',
                              'Cât este necesar pentru serviciu sau conform legii. Logurile accesate la cerere se șterg după finalizarea suportului.'),
                          _section('9. Drepturile dumneavoastră (GDPR)',
                              'Acces, rectificare, ștergere, restricționare, opoziție la marketing, portabilitate, retragere consimțământ. Solicitați la contact@hopa.tritech.ro.'),
                          _section('10. Securitatea datelor',
                              'Măsuri tehnice și organizatorice: criptare, autentificare sigură, control acces.'),
                          _section('11. Modificări',
                              'Politica poate fi actualizată; versiunea actualizată va fi publicată în aplicație și pe site.'),
                          _section('12. Contact',
                              'TritechGroup S.R.L.\n📧 contact@hopa.tritech.ro\n🌐 https://hopa.tritech.ro'),
                          const SizedBox(height: 12),
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.south, color: Colors.orange),
                                const SizedBox(width: 6),
                                Text('Vă rugăm să citiți până la final',
                                    style: TextStyle(color: Colors.orange[300], fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom bar cu butoane mari
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();

                        // Șterge toate cheile GDPR (legacy + per-user).
                        for (final key in prefs.getKeys()) {
                          if (key == 'gdpr_accepted' || key.startsWith('gdpr_accepted_')) {
                            await prefs.remove(key);
                          }
                        }
                        
                        Future.delayed(const Duration(milliseconds: 50), () => Navigator.of(context).pushAndRemoveUntil(
                              PageRouteBuilder(pageBuilder: (_, __, ___) => const _ExitScreen()),
                              (r) => false,
                            ));
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('REFUZ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _accept(context),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('ACCEPT'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExitScreen extends StatelessWidget {
  const _ExitScreen();
  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(milliseconds: 100), () => Navigator.of(context).pop());
    return const Scaffold(backgroundColor: Colors.black);
  }
}

Widget _section(String title, String body) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF14B8A6), fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body, style: TextStyle(color: Colors.grey[200], height: 1.4, fontSize: 14)),
      ],
    ),
  );
}

