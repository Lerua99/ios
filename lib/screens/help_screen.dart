import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajutor & Întrebări Frecvente'),
        backgroundColor: Colors.deepPurple,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader('🚀 Primii Pași'),
          _buildFAQ(
            '❓ Cum primesc codul de activare?',
            'Codul de activare îl primești prin EMAIL de la instalatorul tău imediat după finalizarea instalării. Verifică și folderul Spam/Junk.',
          ),
          _buildFAQ(
            '❓ Cum activez contul?',
            'La prima deschidere a aplicației, introdu codul de activare primit prin email (6 cifre). Nu e nevoie de parolă - te autentifici doar cu acest cod.',
          ),
          
          const Divider(height: 32),
          _buildHeader('🚪 Control Poartă'),
          _buildFAQ(
            '❓ Cum deschid/închid poarta?',
            'Apasă pe butonul mare din centrul ecranului principal. Poarta se va deschide/închide automat în funcție de starea curentă.',
          ),
          _buildFAQ(
            '❓ Ce înseamnă "LIBER" și "OCUPAT"?',
            '• LIBER (verde) - poarta poate fi acționată\n• OCUPAT (roșu) - poarta este în mișcare, așteaptă finalizarea',
          ),
          _buildFAQ(
            '❓ Am mai multe porți (principală, pietonală, garaj). Cum aleg?',
            'Dacă ai mai multe porți configurate, vei vedea butoane de navigare în partea de jos a ecranului. Apasă pe ele pentru a schimba între porți.',
          ),
          
          const Divider(height: 32),
          _buildHeader('👥 Invitații Oaspeți'),
          _buildFAQ(
            '❓ Cum invit un oaspete?',
            '1. Apasă pe iconița MOV (persoane) din bara de jos\n2. Apasă "Creare Nouă"\n3. Completează: Nume, Data de început/sfârșit, Număr acționări\n4. Apasă "Creează Invitația"\n5. Apasă "Partajează Invitația" și alege WhatsApp/Email/SMS',
          ),
          _buildFAQ(
            '❓ Ce înseamnă "acționări"?',
            'O acționare = o apăsare pe buton (deschis SAU închis)\nO vizită completă = 2 acționări:\n• 1 acționare când vine (deschide)\n• 1 acționare când pleacă (închide)\n\nExemplu: 10 acționări = 5 vizite complete',
          ),
          _buildFAQ(
            '❓ Pot retrimite invitația aceluiași oaspete?',
            'Da! Mergi la "Invitații Active", găsește invitația și apasă butonul "Partajează" pentru a trimite din nou linkul.',
          ),
          
          const Divider(height: 32),
          _buildHeader('🔔 Notificări'),
          _buildFAQ(
            '❓ Cum activez notificările?',
            'Apasă pe iconița GALBENĂ (clopotel) din bara de jos și activează tipurile de notificări dorite:\n• Notificări Familie - când un membru deschide poarta\n• Push Notificări - master switch pentru toate\n• Probleme Tehnice - alertă când e o defecțiune\n• Service Necesar - după numărul de cicluri setat',
          ),
          _buildFAQ(
            '❓ De ce nu primesc notificări?',
            '1. Verifică dacă notificările sunt activate în aplicație (iconița clopotel)\n2. Verifică setările telefonului: Setări → Aplicații → HOPA → Notificări → ON\n3. Dacă ai economizor de baterie, adaugă HOPA la excepții',
          ),
          
          const Divider(height: 32),
          _buildHeader('📊 Statistici & Istoric'),
          _buildFAQ(
            '❓ Unde văd istoricul deschiderilor?',
            'Apasă pe iconița VERDE (ceas/history) din bara de jos. Vei vedea:\n• Grafice cu activitatea zilnică/lunară\n• Istoric detaliat (cine, când, de unde)\n• Statistici pe surse (APK, oaspeți, etc.)',
          ),
          
          const Divider(height: 32),
          _buildHeader('🆘 SOS & Probleme'),
          _buildFAQ(
            '❓ Cum raportez o problemă tehnică?',
            '1. Apasă pe iconița ROȘIE (SOS) din bara de jos\n2. Selectează tipul problemei\n3. Descrie problema\n4. Instalatorul va primi notificarea instant',
          ),
          _buildFAQ(
            '❓ Unde văd răspunsurile la problemele raportate?',
            'Apasă pe iconița CYAN (listă) din bara de jos - aici vezi toate mesajele și răspunsurile de la instalator.',
          ),
          
          const Divider(height: 32),
          _buildHeader('⚙️ Setări & Cont'),
          _buildFAQ(
            '❓ Cum schimb tema aplicației (Light/Dark)?',
            'Mergi la Setări → Temă → Alege Light/Dark/System',
          ),
          _buildFAQ(
            '❓ Cum văd informațiile despre cont?',
            'Mergi la Setări → vezi:\n• Numele tău\n• Email-ul\n• Codul de activare\n• FCM Token (pentru notificări)\n• Versiunea aplicației',
          ),
          _buildFAQ(
            '❓ Ce este abonamentul PRO?',
            'PRO oferă:\n• Statistici avansate\n• Invitații oaspeți\n• Notificări personalizate\n• Acces prioritar la noi funcții\n\nPoți activa trial gratuit de 15 zile din aplicație!',
          ),
          
          const Divider(height: 32),
          _buildHeader('📞 Contact & Suport'),
          _buildFAQ(
            '❓ Cum contactez instalatorul?',
            'Apasă pe iconița "Contact Instalator" din Settings sau din meniul principal.',
          ),
          _buildFAQ(
            '❓ Suport tehnic HOPA?',
            'Email: support@hopa.tritech.ro\nTelefon: [NUMĂR SUPORT]\nProgram: Luni-Vineri 9:00-18:00',
          ),
          
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Icon(Icons.lightbulb_outline, size: 48, color: Colors.amber),
                SizedBox(height: 8),
                Text(
                  'Nu ai găsit răspunsul?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Link către suport sau contact instalator
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Contactează instalatorul pentru asistență'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                  icon: Icon(Icons.support_agent),
                  label: Text('Contactează Suportul'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildFAQ(String question, String answer) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(
          question,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}




























