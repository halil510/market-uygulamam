import 'package:flutter/foundation.dart';
// lib/ekranlar/satis/bekleyen_fisler_ekrani.dart
// Askıya alınan satışlar - SharedPreferences'te saklanır, geri yüklenebilir

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/sepet_model.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../servisler/bildirim_servisi.dart';

// Askıya alınan satış yapısı
class _AskiSatis {
  final String id;
  final DateTime tarih;
  final List<Map<String, dynamic>> kalemler; // SepetKalem JSON
  final Map<String, dynamic>? cari;
  final String not_;

  _AskiSatis({required this.id, required this.tarih, required this.kalemler, this.cari, this.not_ = ''});

  double get toplam => kalemler.fold(0.0, (s, k) =>
      s + (k['miktar'] as double) * (k['birimFiyat'] as double));

  Map<String, dynamic> toJson() => {
    'id': id, 'tarih': tarih.toIso8601String(),
    'kalemler': kalemler, 'cari': cari, 'not': not_,
  };

  factory _AskiSatis.fromJson(Map<String, dynamic> j) => _AskiSatis(
    id: j['id'], tarih: DateTime.parse(j['tarih']),
    kalemler: List<Map<String, dynamic>>.from(j['kalemler'] ?? []),
    cari: j['cari'], not_: j['not'] ?? '',
  );
}

class BekleyenFislerEkrani extends ConsumerStatefulWidget {
  const BekleyenFislerEkrani({super.key});
  @override
  ConsumerState<BekleyenFislerEkrani> createState() => _BekleyenFislerEkraniState();


  static Future<void> askiyaAl({
    required List<SepetKalem> sepet,
    CariModel? musteri,
    String not_ = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json  = prefs.getString('askidaki_satislar');
    final list  = json != null ? List<Map<String, dynamic>>.from(jsonDecode(json)) : <Map<String, dynamic>>[];

    final yeni = _AskiSatis(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      tarih: DateTime.now(),
      kalemler: sepet.map((k) => {
        'urunId': k.urun.id,
        'urunAdi': k.urun.urunAdi,
        'miktar': k.miktar,
        'birimFiyat': k.birimFiyat,
        'iskontoOran': k.iskontoOran,
        'birimAdi': k.urun.birimAdi,
      }).toList(),
      cari: musteri != null ? {'id': musteri.id, 'unvan': musteri.unvan} : null,
      not_: not_,
    );
    list.add(yeni.toJson());
    await prefs.setString('askidaki_satislar', jsonEncode(list));
  }

  static Future<int> bekleyenSayi() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('askidaki_satislar');
    if (json == null) return 0;
    return List.from(jsonDecode(json)).length;
  }
}


class _BekleyenFislerEkraniState extends ConsumerState<BekleyenFislerEkrani> {
  List<_AskiSatis> _fisler = [];
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _yukle()); }

  Future<void> _yukle() async {
    try {  
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('askidaki_satislar');
      if (!mounted) return;
      if (json == null) { setState(() => _fisler = []); return; }
      final list = List<Map<String, dynamic>>.from(jsonDecode(json));
      if (!mounted) return;
      setState(() => _fisler = list.map(_AskiSatis.fromJson).toList());
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _kaydet() async {
    try {  
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('askidaki_satislar', jsonEncode(_fisler.map((f) => f.toJson()).toList()));
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _sil(String id) async {
    try {  
      if (!mounted) return;
      setState(() => _fisler.removeWhere((f) => f.id == id));
      await _kaydet();
      if (mounted) BildirimServisi.uyari(context, 'Askıdaki fiş silindi');
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  // Static: Hızlı satıştan çağrılır
  
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(baslik: 'Askıdaki Satışlar (${_fisler.length})'),
      body: TsListe<_AskiSatis>(
        ogeler: _fisler,
        bosBaslik: 'Askıda bekleyen satış yok',
        bosAltyazi: 'Hızlı satışta ⏸ butonuna basarak satışı askıya alabilirsiniz',
        bosIkon: Icons.pause_circle_outline,
        kartOlustur: (context, f, i) => TsKart.liste(
          ikon: const Icon(Icons.pause_circle, color: Colors.orange),
          baslik: f.cari != null ? f.cari!['unvan'] as String : 'Perakende',
          altBaslik: '${f.kalemler.length} kalem · ${_fmt.format(f.tarih)}',
          deger: ParaUtils.formatla(f.toplam),
          sagAksiyon: IconButton(
            icon: const Icon(Icons.delete_outline, color: TsRenk.hata, size: 20),
            onPressed: () => _sil(f.id),
          ),
          onTap: () async {
            if (mounted) Navigator.pop(context, f);
          },
        ),
      ),
    );
  }
}
