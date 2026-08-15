// lib/saglayicilar/riverpod/irsaliye_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/sepet_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../veri/database/veritabani.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import 'package:uuid/uuid.dart';
import '../../servisler/aktif_sube_servisi.dart';

part 'irsaliye_provider.g.dart';

class IrsaliyeDurum {
  final List<SepetKalem> kalemler;
  final List<UrunModel>  aramaSonuclari;
  final bool             kayitIsleniyor;
  final String           tip, cariAdi;
  final int?             cariId;
  final String?          hata;

  const IrsaliyeDurum({
    this.kalemler       = const [],
    this.aramaSonuclari = const [],
    this.kayitIsleniyor = false,
    this.tip            = 'Çıkış',
    this.cariAdi        = '',
    this.cariId,
    this.hata,
  });

  bool   get sepetBos => kalemler.isEmpty;
  double get toplam   => kalemler.fold(0.0, (s, k) => s + k.toplamTutar);

  IrsaliyeDurum copyWith({
    List<SepetKalem>?   kalemler,
    List<UrunModel>?    aramaSonuclari,
    bool?               kayitIsleniyor,
    String?             tip, cariAdi,
    int? Function()?    cariId,
    String? Function()? hata,
  }) => IrsaliyeDurum(
    kalemler:       kalemler       ?? this.kalemler,
    aramaSonuclari: aramaSonuclari ?? this.aramaSonuclari,
    kayitIsleniyor: kayitIsleniyor ?? this.kayitIsleniyor,
    tip:            tip            ?? this.tip,
    cariAdi:        cariAdi        ?? this.cariAdi,
    cariId:         cariId         != null ? cariId()  : this.cariId,
    hata:           hata           != null ? hata()    : this.hata,
  );
}

@riverpod
Future<List<Map<String, dynamic>>> irsaliyeListesi(IrsaliyeListesiRef ref) async {
  final db = await Veritabani().db;
  return db.rawQuery('''
    SELECT i.*, c.unvan as cari_adi FROM irsaliyeler i
    LEFT JOIN cari c ON i.cari_id = c.id
    ORDER BY i.tarih DESC LIMIT 100
  ''');
}

@riverpod
class Irsaliye extends _$Irsaliye {
  final _urunDepo = UrunDeposu();
  Timer? _debounce;

  @override
  IrsaliyeDurum build() => const IrsaliyeDurum();

  void araDebounce(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { state = state.copyWith(aramaSonuclari: []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final s = await _urunDepo.ara(q.trim(), limit: 12);
      state = state.copyWith(aramaSonuclari: s);
    });
  }

  void urunEkle(UrunModel u) {
    final liste = List<SepetKalem>.from(state.kalemler);
    final idx   = liste.indexWhere((k) => k.urun.id == u.id);
    if (idx >= 0) liste[idx] = liste[idx].copyWith(miktar: liste[idx].miktar + 1);
    else liste.add(SepetKalem(urun: u, birimFiyat: u.satisFiyati));
    state = state.copyWith(kalemler: liste, aramaSonuclari: []);
  }

  void miktarDegistir(int i, double miktar) {
    final liste = List<SepetKalem>.from(state.kalemler);
    if (miktar <= 0) liste.removeAt(i); else liste[i] = liste[i].copyWith(miktar: miktar);
    state = state.copyWith(kalemler: liste);
  }

  void sil(int i) => state = state.copyWith(
      kalemler: List<SepetKalem>.from(state.kalemler)..removeAt(i));
  void tipAyarla(String t) => state = state.copyWith(tip: t);
  void cariSec(int? id, String ad) => state = state.copyWith(cariId: () => id, cariAdi: ad);
  void temizle() => state = const IrsaliyeDurum();

  Future<bool> kaydet() async {
    if (state.kalemler.isEmpty) return false;
    state = state.copyWith(kayitIsleniyor: true, hata: () => null);
    try {
      final db          = await Veritabani().db;
      final kullaniciId = AuthServisi().aktifKullanici?.id;
      // ÖNCEDEN burada da (irsaliye_ekrani.dart'ta bulduğum aynı
      // desende) zaman damgası tabanlı numara üretiliyordu — aynı
      // çakışma riskini taşıyordu. Zaten var olan, sağlam, kalıcı
      // sayaç tabanlı fonksiyona yönlendirildi.
      final no  = await Veritabani().fisNoUret('irsaliye', subeId: AktifSubeServisi().subeId ?? 1);
      final now = DateTime.now().toIso8601String();
      // 🔴 Derin analizde bulundu (şu an kullanılmıyor ama gelecekte
      // aktifleşirse aynı hatayı taşımasın diye düzeltildi): hiçbir
      // tabloya global_id/last_updated atanmıyordu, BulutManager hiç
      // çağrılmıyordu.
      final irsaliyeGid = const Uuid().v4();
      final id          = await db.insert(DbSabitler.irsaliyeler, {
        'global_id': irsaliyeGid,
        'irsaliye_no': no, 'cari_id': state.cariId,
        'tarih': now, 'tip': state.tip,
        'toplam_tutar': state.toplam, 'durum': 'Tamamlandı',
        'kullanici_id': kullaniciId,
        'created_at': now, 'last_updated': now,
      });
      final irsSatir = await db.query(DbSabitler.irsaliyeler, where: 'id = ?', whereArgs: [id], limit: 1);
      if (irsSatir.isNotEmpty) BulutManager().upsert(DbSabitler.irsaliyeler, Map<String, dynamic>.from(irsSatir.first));

      for (final k in state.kalemler) {
        final kalemGid = const Uuid().v4();
        await db.insert(DbSabitler.irsaliyeKalem, {
          'global_id': kalemGid,
          'irsaliye_id': id, 'urun_id': k.urun.id,
          'urun_adi': k.urun.urunAdi, 'miktar': k.miktar,
          'birim_fiyat': k.birimFiyat, 'toplam_tutar': k.toplamTutar,
          'last_updated': now,
        });
        final kalemSatir = await db.query(DbSabitler.irsaliyeKalem, where: 'global_id = ?', whereArgs: [kalemGid], limit: 1);
        if (kalemSatir.isNotEmpty) BulutManager().upsert(DbSabitler.irsaliyeKalem, Map<String, dynamic>.from(kalemSatir.first));

        // ÖNCEDEN BURADA da (satis/iade_ekrani.dart'ta bulduğum aynı
        // desende) stok_hareket hiç oluşturulmuyordu.
        final hareketMiktar = state.tip == 'Çıkış' ? -k.miktar : k.miktar;
        final urunRows = await db.query('urunler',
            columns: ['stok'], where: 'id = ?', whereArgs: [k.urun.id]);
        if (urunRows.isNotEmpty) {
          final onceki = (urunRows.first['stok'] as num).toDouble();
          final sonraki = onceki + hareketMiktar;
          await db.update('urunler', {'stok': sonraki, 'last_updated': now}, where: 'id = ?', whereArgs: [k.urun.id]);
          final urunSatir = await db.query('urunler', where: 'id = ?', whereArgs: [k.urun.id], limit: 1);
          if (urunSatir.isNotEmpty) BulutManager().upsert('urunler', Map<String, dynamic>.from(urunSatir.first));

          final stokGid = const Uuid().v4();
          await db.insert('stok_hareket', {
            'global_id': stokGid,
            'urun_id': k.urun.id,
            'hareket_turu': 'İrsaliye ${state.tip}',
            'miktar': k.miktar,
            'onceki_stok': onceki,
            'sonraki_stok': sonraki,
            'tarih': now,
            'last_updated': now,
            'referans_id': id,
            'referans_turu': 'irsaliye',
          });
          final stokSatir = await db.query('stok_hareket', where: 'global_id = ?', whereArgs: [stokGid], limit: 1);
          if (stokSatir.isNotEmpty) BulutManager().upsert('stok_hareket', Map<String, dynamic>.from(stokSatir.first));
        }
      }
      ref.invalidate(irsaliyeListesiProvider);
      state = const IrsaliyeDurum();
      return true;
    } catch (e) {
      state = state.copyWith(kayitIsleniyor: false, hata: () => e.toString());
      return false;
    }
  }
}
