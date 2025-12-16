import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class MessagesScreen extends StatefulWidget {
  final VoidCallback? onRead;
  const MessagesScreen({Key? key, this.onRead}) : super(key: key);

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  Future<List<dynamic>>? _sosRequestsFuture;
  Future<List<dynamic>>? _pushNotificationsFuture;
  Future<List<dynamic>>? _marketingOffersFuture;
  String _selectedTab = 'instalator'; // 'instalator' | 'generale' | 'oferte'
  int _sosCount = 0;
  int _generalCount = 0; // exclude marketing
  int _marketingCount = 0;

  @override
  void initState() {
    super.initState();
    _sosRequestsFuture = ApiService.getSosRequestsForClient();
    _pushNotificationsFuture = ApiService.getPushNotificationHistory();
    _marketingOffersFuture = ApiService.getMarketingOffers();
    _loadMessageCounts();
  }

  Future<void> _loadMessageCounts() async {
    try {
      final results = await Future.wait([
        _sosRequestsFuture ?? Future.value([]),
        _pushNotificationsFuture ?? Future.value([]),
        _marketingOffersFuture ?? Future.value([]),
      ]);
      
      setState(() {
        // Numără doar mesajele SOS nerezolvate
        _sosCount = results[0].where((s) => s['status'] != 'resolved').length;
        // Mesajele generale (doar din push notifications)
        final List<dynamic> allPush = List<dynamic>.from(results[1]);
        _generalCount = allPush.length;
        // Ofertele marketing (din endpoint-ul dedicat)
        _marketingCount = results[2].length;
      });
    } catch (e) {
      // Ignore errors for count
    }
  }

  Future<void> _refreshMessages() async { // Renamed method
    setState(() {
      _sosRequestsFuture = ApiService.getSosRequestsForClient();
      _pushNotificationsFuture = ApiService.getPushNotificationHistory();
      _marketingOffersFuture = ApiService.getMarketingOffers();
    });
    _loadMessageCounts();
  }

  Future<void> _confirmAppointment(String sosId) async {
    try {
      await ApiService.confirmSosAppointment(sosId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Programare confirmată cu succes!'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshMessages(); // Reîncarcă lista după confirmare
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la confirmarea programării: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showReplyDialog(String sosNotificationId, String installerName) async {
    final TextEditingController _messageController = TextEditingController();
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button to close dialog
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            'Răspunde instalatorului $installerName',
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextFormField(
                  controller: _messageController,
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Scrie mesajul tău aici...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    filled: true,
                    fillColor: Colors.grey[700],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Anulează', style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan.shade400, // Matching the new button color
              ),
              onPressed: () async {
                if (_messageController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mesajul nu poate fi gol.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                try {
                  await ApiService.replyToInstaller(sosNotificationId, _messageController.text);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mesajul a fost trimis cu succes!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.of(context).pop();
                    _refreshMessages(); // Reîncarcă lista pentru a vedea eventuale actualizări
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Eroare la trimiterea mesajului: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Trimite', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openCalendarForReschedule(String sosId) async {
    // Deschide un date picker pentru a selecta noua dată
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.grey,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      // Deschide un time picker pentru a selecta ora
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: 9, minute: 0),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.teal,
                onPrimary: Colors.white,
                surface: Colors.grey,
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        // Confirmă reprogramarea
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.grey[850],
              title: const Text(
                'Confirmă reprogramarea',
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                'Dorești să reprogramezi pentru:\n'
                '${DateFormat('dd MMMM yyyy', 'ro').format(pickedDate)}\n'
                'Ora: ${pickedTime.format(context)}?',
                style: TextStyle(color: Colors.grey[300]),
              ),
              actions: [
                TextButton(
                  child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('Confirmă'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        if (confirm == true) {
          try {
            // TODO: Trimite noua dată și oră către API
            await ApiService.rescheduleSosAppointment(
              sosId, 
              pickedDate, 
              pickedTime.format(context)
            );
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cerere de reprogramare trimisă!'),
                  backgroundColor: Colors.orange,
                ),
              );
              _refreshMessages();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Eroare: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    }
  }

  Future<void> _cancelAppointment(String sosId, bool reschedule) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(
            reschedule ? 'Reprogramare' : 'Anulare comandă',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            reschedule 
                ? 'Dorești să reprogramezi această intervenție? Instalatorul va fi notificat și te va contacta pentru o nouă programare.'
                : 'Ești sigur că vrei să anulezi această comandă? Acțiunea este ireversibilă.',
            style: TextStyle(color: Colors.grey[300]),
          ),
          actions: [
            TextButton(
              child: const Text('Nu', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: reschedule ? Colors.orange : Colors.red,
              ),
              child: Text(reschedule ? 'Reprogramează' : 'Anulează'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        // TODO: Implementează API call pentru anulare/reprogramare
        await ApiService.cancelSosAppointment(sosId, reschedule);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reschedule ? 'Cerere de reprogramare trimisă!' : 'Comandă anulată!'),
              backgroundColor: reschedule ? Colors.orange : Colors.red,
            ),
          );
          _refreshMessages();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Eroare: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteMessage(String messageId, String type) async {
    try {
      if (type == 'sos') {
        // Pentru mesaje SOS
        await ApiService.deleteSosMessage(messageId);
      } else if (type == 'offer') {
        // Pentru oferte marketing
        await ApiService.deleteMarketingOffer(int.parse(messageId));
      } else {
        // Pentru notificări generale
        await ApiService.deletePushNotification(messageId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mesaj șters!'),
            backgroundColor: Colors.green,
          ),
        );
        _refreshMessages();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la ștergere: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteAllMessages() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text(
            'Șterge toate mesajele',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            _selectedTab == 'instalator' 
                ? 'Ești sigur că vrei să ștergi toate mesajele de la instalator?'
                : _selectedTab == 'generale'
                    ? 'Ești sigur că vrei să ștergi toate mesajele generale?'
                    : 'Ești sigur că vrei să ștergi toate ofertele promoționale?',
            style: TextStyle(color: Colors.grey[300]),
          ),
          actions: [
            TextButton(
              child: const Text('Anulează', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Șterge toate'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        if (_selectedTab == 'instalator') {
          // Ștergere mesaje SOS/instalator
          await ApiService.deleteAllSosMessages();
        } else if (_selectedTab == 'generale') {
          // Ștergere DOAR mesaje generale
          await ApiService.deleteAllPushNotifications(type: 'general');
        } else if (_selectedTab == 'oferte') {
          // Ștergere DOAR oferte marketing
          await ApiService.deleteAllMarketingOffers();
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesajele oferte au fost șterse!'),
              backgroundColor: Colors.green,
            ),
          );
          _refreshMessages();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Eroare: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Mesajele Mele',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if ((_selectedTab == 'instalator' && _sosCount > 0) || 
              (_selectedTab == 'generale' && _generalCount > 0) ||
              (_selectedTab == 'oferte' && _marketingCount > 0))
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              onPressed: _deleteAllMessages,
              tooltip: 'Șterge toate',
            ),
        ],
      ),
      body: Column(
        children: [
          // Tab-uri pentru filtrare
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTab = 'instalator';
                      });
                      widget.onRead?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTab == 'instalator' 
                            ? Colors.blue 
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.build,
                                  size: 18,
                                  color: _selectedTab == 'instalator' ? Colors.white : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Instalator',
                                  style: TextStyle(
                                    color: _selectedTab == 'instalator' ? Colors.white : Colors.black87,
                                    fontWeight: _selectedTab == 'instalator' 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_sosCount > 0)
                            Positioned(
                              right: 10,
                              top: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_sosCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTab = 'generale';
                      });
                      widget.onRead?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTab == 'generale' 
                            ? Colors.blue 
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications,
                                  size: 18,
                                  color: _selectedTab == 'generale' ? Colors.white : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Generale',
                                  style: TextStyle(
                                    color: _selectedTab == 'generale' ? Colors.white : Colors.black87,
                                    fontWeight: _selectedTab == 'generale' 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_generalCount > 0)
                            Positioned(
                              right: 10,
                              top: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_generalCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTab = 'oferte';
                      });
                      widget.onRead?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _selectedTab == 'oferte' 
                            ? Colors.blue 
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_offer,
                                  size: 18,
                                  color: _selectedTab == 'oferte' ? Colors.white : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Oferte',
                                  style: TextStyle(
                                    color: _selectedTab == 'oferte' ? Colors.white : Colors.black87,
                                    fontWeight: _selectedTab == 'oferte' 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_marketingCount > 0)
                            Positioned(
                              right: 10,
                              top: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_marketingCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Lista de mesaje
          Expanded(
            child: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          _sosRequestsFuture ?? Future.value([]),
          _pushNotificationsFuture ?? Future.value([]),
          _marketingOffersFuture ?? Future.value([]),
        ]).then((lists) {
          List<dynamic> messages = [];
          
          if (_selectedTab == 'instalator') {
            // Doar mesajele SOS de la instalator
            messages = lists[0];
          } else if (_selectedTab == 'generale') {
            // Doar mesajele generale (din push notifications)
            messages = lists[1];
          } else {
            // Oferte marketing (din endpoint-ul dedicat /marketing/offers)
            messages = lists[2];
          }
          
          // Sortează după dată (câmp 'created_at' sau 'sent_at') dacă există
          messages.sort((a, b) {
            final String dateA = a['created_at'] ?? a['sent_at'] ?? '';
            final String dateB = b['created_at'] ?? b['sent_at'] ?? '';
            return dateB.compareTo(dateA); // descrescător
          });
          return messages;
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.blue));
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Eroare: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedTab == 'instalator' 
                      ? Icons.build_outlined 
                      : _selectedTab == 'oferte' 
                        ? Icons.local_offer_outlined 
                        : Icons.notifications_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedTab == 'instalator' 
                        ? 'Nu ai cereri de service.'
                        : _selectedTab == 'oferte'
                          ? 'Nu ai oferte.'
                          : 'Nu ai mesaje generale.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          } else {
            final messages = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final item = messages[index];

                final bool isSos = item.containsKey('gate_name');

                if (isSos) {
                  // === EXISTING CARD (SOS) ===
                  final request = item;
                  // Verifică dacă există obiectul "appointment" în răspuns
                  final Map<String, dynamic>? appointment = request['appointment'];

                  final bool hasAppointment = appointment != null;

                  // Confirmarea programării este trimisă din backend în câmpul "confirmed" din obiectul appointment
                  final bool isConfirmed = appointment != null ? (appointment['confirmed'] ?? false) : false;
                  final String installerName = request['installer']?['name'] ?? 'Instalator Necunoscut';

                  String statusText = '';
                  Color statusColor = Colors.grey;

                  switch (request['status']) {
                    case 'pending':
                      statusText = 'În așteptare';
                      statusColor = Colors.orange;
                      break;
                    case 'acknowledged':
                      statusText = 'Prezentată';
                      statusColor = Colors.blue;
                      break;
                    case 'resolved':
                      statusText = 'Rezolvată';
                      statusColor = Colors.green;
                      break;
                    default:
                      statusText = 'Necunoscut';
                      statusColor = Colors.grey;
                  }

                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.build_circle, color: statusColor, size: 28),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Poartă: ${request['gate_name']}',
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              statusText,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${request['problem_description']}',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${request['created_at']}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                if (installerName != 'Instalator Necunoscut') ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.person, color: Colors.grey[600], size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        installerName,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (hasAppointment) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.blue, width: 1.5),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.calendar_today, color: Colors.blue, size: 20),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Programare Vizită',
                                              style: TextStyle(
                                                color: Colors.blue,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '📅 ${appointment != null ? appointment['date'] : ''} la ${appointment != null ? appointment['time'] : ''}',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (appointment != null && appointment['notes'] != null && (appointment['notes'] as String).isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            '💬 ${appointment['notes']}',
                                            style: TextStyle(color: Colors.grey[700], fontSize: 14),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (isConfirmed)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.green, width: 1.5),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, color: Colors.green, size: 22),
                                          const SizedBox(width: 10),
                                          const Text(
                                            'Programare confirmată!',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (request['status'] == 'acknowledged' && hasAppointment)
                                    Builder(
                                      builder: (context) {
                                        // Verifică dacă data programării a trecut
                                        bool isPastDate = false;
                                        if (appointment != null && appointment['date'] != null && appointment['time'] != null) {
                                          try {
                                            final appointmentDateTime = DateTime.parse('${appointment['date']} ${appointment['time']}');
                                            isPastDate = appointmentDateTime.isBefore(DateTime.now());
                                          } catch (e) {
                                            // În caz de eroare la parsare, considerăm că nu a trecut
                                          }
                                        }
                                        
                                        return Column(
                                          children: [
                                            if (isPastDate) ...[
                                              Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(12),
                                                margin: const EdgeInsets.only(bottom: 12),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange[50],
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: Colors.orange, width: 1.5),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.warning, color: Colors.orange, size: 22),
                                                    const SizedBox(width: 10),
                                                    const Expanded(
                                                      child: Text(
                                                        'Data programării a trecut! Poți reprograma.',
                                                        style: TextStyle(
                                                          color: Colors.orange,
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            // Butoane principale: Confirmă, Anulează, Reprogramează
                                            Row(
                                              children: [
                                                // Afișează butonul Confirmă doar dacă data nu a trecut
                                                if (!isPastDate)
                                                  Expanded(
                                                    child: ElevatedButton(
                                                      onPressed: () => _confirmAppointment(request['id'].toString()),
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.check, color: Colors.white, size: 20),
                                                          SizedBox(height: 4),
                                                          Text('Confirmă', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                        ],
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.green,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(10),
                                                        ),
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                      ),
                                                    ),
                                                  ),
                                                if (!isPastDate) const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () => _cancelAppointment(request['id'].toString(), false),
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.cancel, color: Colors.white, size: 20),
                                                        SizedBox(height: 4),
                                                        Text('Anulează', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                      ],
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.red,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () => _openCalendarForReschedule(request['id'].toString()),
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.calendar_month, color: Colors.white, size: 20),
                                                        SizedBox(height: 4),
                                                        Text('Reprogramează', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                      ],
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.orange,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // Buton răspunde instalatorului
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: () => _showReplyDialog(request['id'].toString(), installerName),
                                                icon: const Icon(Icons.message, size: 20),
                                                label: const Text('Trimite Mesaj Instalatorului', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.blue,
                                                  side: const BorderSide(color: Colors.blue, width: 1.5),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                                // Afișăm mesaj pentru acknowledged fără programare
                                if (request['status'] == 'acknowledged' && !hasAppointment) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orange, width: 1.5),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info, color: Colors.orange, size: 22),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            'Instalatorul a primit cererea. Așteaptă programarea.',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showReplyDialog(request['id'].toString(), installerName),
                                      icon: const Icon(Icons.message, size: 20),
                                      label: const Text('Trimite Mesaj Instalatorului', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.blue,
                                        side: const BorderSide(color: Colors.blue, width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // Delete button in top right corner
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: Icon(Icons.close, color: Colors.grey[400], size: 22),
                                onPressed: () => _deleteMessage(request['id'].toString(), 'sos'),
                                tooltip: 'Șterge',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  // === PUSH NOTIFICATION GENERAL SAU OFERTĂ ===
                  final title = item['title'] ?? 'Notificare';
                  final body = item['body'] ?? item['description'] ?? '-';
                  final sentAt = item['sent_at'] ?? '';
                  // Determină tipul în funcție de tab
                  final String messageType = _selectedTab == 'oferte' ? 'offer' : 'general';

                  Color accent = Colors.blueAccent;

                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 16.0),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _selectedTab == 'oferte' ? Icons.local_offer : Icons.notifications, 
                                        color: Colors.blue, 
                                        size: 26
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    body,
                                    style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      sentAt,
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Delete button
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: Icon(Icons.close, color: Colors.grey[400], size: 22),
                                onPressed: () => _deleteMessage(item['id'].toString(), messageType),
                                tooltip: 'Șterge',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              },
            );
          }
        },
      ),
          ),
        ],
      ),
    );
  }
} 