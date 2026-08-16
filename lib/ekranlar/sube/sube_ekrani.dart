// lib/ekranlar/sube/sube_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../veri/database/veritabani.dart';
import 'package:uuid/uuid.dart';

class SubeEkrani extends ConsumerStatefulWidget {
  const SubeEkrani({super.key});
  @override
  ConsumerState<SubeEkrani> createState() => _SubeEkraniState();
}

class _SubeEkraniState extends ConsumerState<SubeEkrani> {
  List<Map<String, dynamic>> _subeler = [];
  int _aktifSubeId = 1;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    _yukleniyor = true;
    if (mounted) setState(() {});
    try {
      final db = await Veritabani().db;
      final rows = await db.query('subeler', orderBy: 'sube_adi');
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _subeler = rows;
      _aktifSubeId = prefs.getInt('aktif_sube_id') ?? 1;
      _yukleniyor = false;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _aktifYap(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('aktif_sube_id', id);
      if (!mounted) return;
      _aktifSubeId = id;
      if (mounted) setState(() {});
      BildirimServisi.basari(context, 'Aktif şube değiştirildi ✓');
    } catch (e) {
      if (kDebugMode) debugPrint('Hata: $e');
    }
  }

  Future<void> _dialog({Map<String, dynamic>? s}) async {
    final koduC = TextEditingController(text: s?['sube_kodu']?.toString() ?? '');
    final adiC = TextEditingController(text: s?['sube_adi']?.toString() ?? '');
    final adrC = TextEditingController(text: s?['adres']?.toString() ?? '');
    final telC = TextEditingController(text: s?['telefon']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TsRadius.lg)),
        title: Text(s == null ? 'Yeni Şube' : 'Şubeyi Düzenle'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TsInput(etiket: 'Şube Kodu', controller: koduC, oncilIkon: Icons.tag),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Şube Adı *', controller: adiC, oncilIkon: Icons.store),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Adres', controller: adrC, oncilIkon: Icons.location_on, maksSatir: 2),
          const SizedBox(height: TsBosluk.md),
          TsInput(etiket: 'Telefon', controller: telC, oncilIkon: Icons.phone),
        ])),
        actions: [
          TsButon(tur: TsButonTuru.metin, metin: 'İptal', onPressed: () => Navigator.pop(ctx, false)),
          TsButon(metin: 'Kaydet', onPressed: () {
            if (adiC.text.trim().isNotEmpty) Navigator.pop(ctx, true);
          }),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final db = await Veritabani().db;
      final now = DateTime.now().toIso8601String();
      final data = {
        'sube_kodu': koduC.text.trim().isEmpty ? 'S${DateTime.now().millisecondsSinceEpoch}' : koduC.text.trim(),
        'sube_adi': adiC.text.trim(),
        'adres': adrC.text.trim(),
        'telefon': telC.text.trim(),
        'aktif': 1,
        'updated_at': now,
        'last_updated': now,
      };
      int subeId;
      if (s == null) {
        // 🔴🔴 Derin analizde bulundu: global_id atanmıyordu, ayrıca
        // senkron sisteminin beklediği 'last_updated' hiç yoktu
        // (sadece 'updated_at' vardı) — şubeler (çok şubeli
        // işletmelerde en temel veri) hiç senkronize olmuyordu.
        data['global_id'] = const Uuid().v4();
        subeId = await db.insert('subeler', data);
      } else {
        subeId = s['id'] as int;
        await db.update('subeler', data, where: 'id=?', whereArgs: [subeId]);
      }
      final satir = await db.query('subeler', where: 'id = ?', whereArgs: [subeId], limit: 1);
      if (satir.isNotEmpty) BulutManager().upsert('subeler', Map<String, dynamic>.from(satir.first));
      await _yukle();
      if (!mounted) return;
      BildirimServisi.basari(context, s == null ? 'Şube eklendi ✓' : 'Şube güncellendi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Şube Yönetimi',
        gradyanli: true,
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.add_business, color: Colors.white), onPressed: () => _dialog(), tooltip: 'Yeni Şube'),
        ],
      ),
      body: TsListe<Map<String, dynamic>>(
        yukleniyor: _yukleniyor,
        ogeler: _subeler,
        aramaMetniAl: (s) => s['sube_adi']?.toString() ?? '',
        bosBaslik: 'Henüz şube yok',
        bosIkon: Icons.store_outlined,
        yenile: _yukle,
        kartOlustur: (context, row, i) {
          final aktif = row['id'] == _aktifSubeId;
          final altSatirlar = [
            if ((row['sube_kodu']?.toString() ?? '').isNotEmpty) 'Kod: ${row['sube_kodu']}',
            if ((row['adres']?.toString() ?? '').isNotEmpty) row['adres'].toString(),
            if ((row['telefon']?.toString() ?? '').isNotEmpty) row['telefon'].toString(),
          ];
          return TsKart.liste(
            secili: aktif,
            baslik: row['sube_adi']?.toString() ?? '',
            altBaslik: altSatirlar.join(' • '),
            ikon: const Icon(Icons.store),
            etiketler: aktif ? [const TsBadge(metin: 'AKTİF', tur: TsBadgeTuru.basarili)] : null,
            sagAksiyon: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'aktif') _aktifYap(row['id'] as int);
                if (v == 'duzenle') _dialog(s: row);
              },
              itemBuilder: (_) => [
                if (!aktif)
                  const PopupMenuItem(
                      value: 'aktif',
                      child: ListTile(dense: true, leading: Icon(Icons.check_circle_outline, size: 18, color: TsRenk.primary), title: Text('Aktif Yap'))),
                const PopupMenuItem(
                    value: 'duzenle',
                    child: ListTile(dense: true, leading: Icon(Icons.edit, size: 18, color: TsRenk.primary), title: Text('Düzenle'))),
              ],
            ),
            onTap: () => _aktifYap(row['id'] as int),
          );
        },
      ),
    );
  }
}
