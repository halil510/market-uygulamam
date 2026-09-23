// lib/servisler/fatura_seri/seri_mutabakat_servisi.dart
//
// Fatura Seri Mutabakatı — bu cihaza tahsis edilmiş her numara bloğu için
// kaç numaranın faturaya dönüştüğünü, hangi numaraların tüketilip de
// faturası BULUNMADIĞINI (boşluk — GİB'in "boşluksuz sıra" kuralı açısından
// incelenmesi gereken) ve blokta kaç numaranın kaldığını gösterir. Ayrıca
// hiçbir bloğa ait olmayan (eski sistem / elle girilmiş) faturaları sayar.
//
// Salt okunur — hiçbir veriyi değiştirmez.
import '../../veri/database/veritabani.dart';

class BlokMutabakati {
  final String seri;
  final int yil;
  final int baslangic;
  final int bitis;
  final int siradaki;
  final String durum;
  final String? tahsisZamani;

  /// Tüketilmiş ve faturası mevcut (silinmemiş) numara sayısı.
  final int kullanilan;

  /// Tüketilmiş, faturası var ama silinmiş (deleted_at dolu) numaralar.
  final List<int> silinmis;

  /// Tüketilmiş ama hiç faturası olmayan numaralar (kalıcı silinmiş vb.).
  final List<int> bosluklar;

  /// Blokta henüz tüketilmemiş numara sayısı.
  final int kalan;

  const BlokMutabakati({
    required this.seri,
    required this.yil,
    required this.baslangic,
    required this.bitis,
    required this.siradaki,
    required this.durum,
    required this.tahsisZamani,
    required this.kullanilan,
    required this.silinmis,
    required this.bosluklar,
    required this.kalan,
  });

  bool get sorunlu => bosluklar.isNotEmpty;
}

class SeriMutabakatRaporu {
  final List<BlokMutabakati> bloklar;

  /// Seri+yıl formatına uyan ama hiçbir bloğun aralığına düşmeyen
  /// faturalar (merkezi sistem öncesi ya da elle numara girilmiş).
  final List<String> blokDisiFaturalar;

  const SeriMutabakatRaporu(this.bloklar, this.blokDisiFaturalar);

  int get toplamBosluk => bloklar.fold(0, (t, b) => t + b.bosluklar.length);
}

/// Saf hesap — [bloklar] `yerel_fatura_blok` satırları, [faturalar]
/// `{fatura_no, deleted_at}` satırları.
SeriMutabakatRaporu seriMutabakatHesapla(
  List<Map<String, dynamic>> bloklar,
  List<Map<String, dynamic>> faturalar,
) {
  // (seri, yil, sira) → silinmiş mi
  final numaralar = <String, bool>{};
  final eslesmeyenler = <String>{};
  final seriYillar = {
    for (final b in bloklar) '${b['seri']}${b['yil']}',
  };

  for (final f in faturalar) {
    final no = f['fatura_no']?.toString();
    if (no == null) continue;
    for (final sy in seriYillar) {
      if (no.length == sy.length + 9 && no.startsWith(sy)) {
        final sira = int.tryParse(no.substring(sy.length));
        if (sira != null) {
          numaralar['$sy#$sira'] = f['deleted_at'] != null;
          eslesmeyenler.add(no);
        }
        break;
      }
    }
  }

  final sonuc = <BlokMutabakati>[];
  final blokIcindekiler = <String>{};
  for (final b in bloklar) {
    final seri = b['seri'] as String;
    final yil = b['yil'] as int;
    final bas = b['blok_baslangic'] as int;
    final bit = b['blok_bitis'] as int;
    final siradaki = b['siradaki'] as int;
    final sy = '$seri$yil';
    final tuketilenSon = (siradaki - 1).clamp(bas - 1, bit);

    var kullanilan = 0;
    final silinmis = <int>[];
    final bosluklar = <int>[];
    for (var n = bas; n <= bit; n++) {
      final anahtar = '$sy#$n';
      if (numaralar.containsKey(anahtar)) {
        blokIcindekiler.add('$sy${n.toString().padLeft(9, '0')}');
      }
      if (n > tuketilenSon) continue;
      final silindi = numaralar[anahtar];
      if (silindi == null) {
        bosluklar.add(n);
      } else if (silindi) {
        silinmis.add(n);
      } else {
        kullanilan++;
      }
    }
    final aktif = b['durum'] == 'aktif' && siradaki <= bit;
    sonuc.add(BlokMutabakati(
      seri: seri,
      yil: yil,
      baslangic: bas,
      bitis: bit,
      siradaki: siradaki,
      durum: b['durum']?.toString() ?? '',
      tahsisZamani: b['tahsis_zamani']?.toString(),
      kullanilan: kullanilan,
      silinmis: silinmis,
      bosluklar: bosluklar,
      kalan: aktif ? bit - siradaki + 1 : 0,
    ));
  }

  final blokDisi = eslesmeyenler.difference(blokIcindekiler).toList()..sort();
  return SeriMutabakatRaporu(sonuc, blokDisi);
}

class SeriMutabakatServisi {
  Future<SeriMutabakatRaporu> raporGetir() async {
    final db = await Veritabani().db;
    final bloklar = await db.query('yerel_fatura_blok',
        orderBy: 'seri ASC, yil DESC, blok_baslangic DESC');
    final faturalar = await db.query('faturalar',
        columns: ['fatura_no', 'deleted_at'], where: 'fatura_no IS NOT NULL');
    return seriMutabakatHesapla(bloklar, faturalar);
  }
}
