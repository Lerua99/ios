import 'dart:async';

void main() async {
  print('🚀 Test logică poartă - 5 cicluri deschis/închis');
  print('=' * 50);
  
  bool isGateOpen = true; // Pornim cu poarta deschisă
  
  for (int ciclu = 1; ciclu <= 5; ciclu++) {
    print('\n📍 CICLU $ciclu/5');
    print('-' * 30);
    
    // Simulăm apăsarea butonului
    print('🔘 Apăs butonul...');
    print('📊 Stare curentă: Poarta e ${isGateOpen ? "DESCHISĂ" : "ÎNCHISĂ"}');
    
    if (isGateOpen) {
      // Poarta e deschisă, o închidem (2 comenzi)
      print('🔵 Poarta e DESCHISĂ - Trimit 2 comenzi pentru ÎNCHIDERE');
      
      print('  🔸 [1/2] Trimit prima comandă către Shelly...');
      await Future.delayed(Duration(milliseconds: 100)); // Simulăm request HTTP
      print('  ✅ [1/2] Prima comandă trimisă cu succes!');
      
      print('  ⏳ Aștept 500ms între comenzi...');
      await Future.delayed(Duration(milliseconds: 500));
      
      print('  🔸 [2/2] Trimit a doua comandă către Shelly...');
      await Future.delayed(Duration(milliseconds: 100)); // Simulăm request HTTP
      print('  ✅ [2/2] A doua comandă trimisă cu succes!');
      
      isGateOpen = false;
      print('🔒 REZULTAT: Poarta a fost ÎNCHISĂ cu succes!');
      
    } else {
      // Poarta e închisă, o deschidem (1 comandă)
      print('🔵 Poarta e ÎNCHISĂ - Trimit 1 comandă pentru DESCHIDERE');
      
      print('  🔸 Trimit comandă către Shelly...');
      await Future.delayed(Duration(milliseconds: 100)); // Simulăm request HTTP
      print('  ✅ Comandă trimisă cu succes!');
      
      isGateOpen = true;
      print('🔓 REZULTAT: Poarta a fost DESCHISĂ cu succes!');
    }
    
    // Pauză între cicluri
    if (ciclu < 5) {
      print('\n⏰ Aștept 2 secunde până la următorul ciclu...');
      await Future.delayed(Duration(seconds: 2));
    }
  }
  
  print('\n' + '=' * 50);
  print('✅ Test complet! 5 cicluri finalizate cu succes.');
  print('📊 Stare finală: Poarta e ${isGateOpen ? "DESCHISĂ" : "ÎNCHISĂ"}');
  
  // Rezumat comenzi
  print('\n📈 REZUMAT COMENZI:');
  print('  • Total cicluri: 5');
  print('  • Operații de închidere: 3 (6 comenzi HTTP)');
  print('  • Operații de deschidere: 2 (2 comenzi HTTP)');
  print('  • Total comenzi HTTP: 8');
} 