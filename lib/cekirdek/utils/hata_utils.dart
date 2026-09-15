// lib/cekirdek/utils/hata_utils.dart
//
// Kullanıcıya gösterilecek hata metni üretir. Dart'ın `Exception`
// sınıfı, iş mantığının bilinçli attığı ("Bu sipariş zaten teslim
// alınmış." gibi) kullanıcı-dostu mesajların önüne otomatik olarak
// "Exception: " ekler — bu ön ek geliştiriciye anlamlı, kasiyer/garson
// gibi son kullanıcıya ise teknik ve güven verici olmayan görünür.
String kullaniciyaHataMetni(Object hata) {
  final metin = hata.toString();
  const on = 'Exception: ';
  return metin.startsWith(on) ? metin.substring(on.length) : metin;
}
