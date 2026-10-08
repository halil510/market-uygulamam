// lib/ekranlar/irsaliye/irsaliye_ekle_ekrani.dart
//
// Yeni irsaliye oluşturma ekranı — irsaliye_ekrani.dart'tan ayrıldı
// (2026-10-07 refactor).
import '../../cekirdek/utils/hata_utils.dart';
import 'dart:async';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../servisler/belge_no_servisi.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../depolar/irsaliye_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';

class IrsaliyeEkleEkrani extends ConsumerStatefulWidget {
  const IrsaliyeEkleEkrani({super.key});

  @override
  ConsumerState<IrsaliyeEkleEkrani> createState() => _IrsaliyeEkleEkraniState();
}

class _IrsaliyeEkleEkraniState extends ConsumerState<IrsaliyeEkleEkrani> {
  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  final _araCtrl  = TextEditingController();
  Timer? _debounce;

  CariModel? _seciliCari;
  final List<_IrsKalem> _kalemler = [];
  List<UrunModel> _aramaSonuclari = [];
  bool _kayit = false;
  final DateTime _tarih = DateTime.now();
  String _tip = 'Çıkış';

  @override
  void dispose() {
    _araCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _aramaChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _aramaSonuclari = []);
        return;
      }
      final s = await _urunDepo.ara(q.trim(), limit: 10);
      if (mounted) setState(() => _aramaSonuclari = s);
    });
  }

  void _urunEkle(UrunModel u) {
    final mevcut = _kalemler.indexWhere((k) => k.urunId == u.id!);
    setState(() {
      if (mevcut >= 0) {
        _kalemler[mevcut] = _IrsKalem(
          urunId:     u.id!,
          urunAdi:    u.urunAdi,
          barkod:     u.barkod,
          miktar:     _kalemler[mevcut].miktar + 1,
          birimAdi:   u.birimAdi,
          birimFiyat: u.satisFiyati,
        );
      } else {
        _kalemler.add(_IrsKalem(
          urunId:     u.id!,
          urunAdi:    u.urunAdi,
          barkod:     u.barkod,
          miktar:     1,
          birimAdi:   u.birimAdi,
          birimFiyat: u.satisFiyati,
        ));
      }
      _aramaSonuclari = [];
      _araCtrl.clear();
    });
  }

  Future<void> _cariSec() async {
    final cariler = await _cariDepo.tumunuGetir(tip: 'Müşteri');
    if (!mounted) return;
    final secilen = await showDialog<CariModel>(
      context: context,
      builder: (bCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        
        title: const Text('Müşteri Seç'),
        content: SizedBox(
          // 🔴 DÜZELTME (komple derin analizde bulundu): sabit width:360
          // küçük ekranlarda (320-360px) dialog taşmasına/overflow'a yol
          // açabiliyordu. Artık ekran genişliğine göre üst sınırlanıyor.
          width: MediaQuery.of(bCtx).size.width < 400
              ? MediaQuery.of(bCtx).size.width * 0.85
              : 360,
          height: 400,
          child: ListView.builder(
            itemCount: cariler.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(
                backgroundColor: TsRenk.zemin(Colors.teal),
                child: Text(cariler[i].unvan.isNotEmpty
                    ? cariler[i].unvan[0].toUpperCase() : '?',
                    style: TextStyle(color: Colors.teal.shade700,
                        fontWeight: FontWeight.w700)),
              ),
              title: Text(cariler[i].unvan),
              subtitle: cariler[i].telefon != null
                  ? Text(cariler[i].telefon!) : null,
              onTap: () => Navigator.pop(bCtx, cariler[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(bCtx),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
    if (secilen != null) setState(() => _seciliCari = secilen);
  }

  Future<void> _kaydet() async {
    if (!mounted) return;
    if (_kayit) return; // 🔴 DÜZELTME: çift tıklama koruması hiç yoktu —
    // hızlı çift tıklamada aynı irsaliye iki kez oluşturulabiliyordu.
    if (_kalemler.isEmpty) {
      BildirimServisi.uyari(context, 'En az 1 ürün ekleyin');
      return;
    }
    setState(() => _kayit = true);
    try {
      // ÖNCEDEN burada zaman damgası tabanlı ("IRS" + yıl + zaman
      // damgasının son haneleri) bir numara üretiliyordu — bu, fatura/
      // cari numarasında bulup düzelttiğim AYNI çakışma riskini
      // taşıyordu. Meğer doğru, GİB-standardı, kalıcı sayaç tabanlı
      // fonksiyon (fisNoUret) ZATEN varmış, sadece kullanılmıyormuş.
      final no     = await BelgeNoServisi().uret('irsaliye');

      // Tüm transaction + bulut senkron mantığı artık
      // IrsaliyeDeposu.olustur'da — bkz. o metodun doc yorumu, davranış
      // birebir korundu (irsaliye + kalemler + stok hareketi TEK
      // transaction içinde).
      await IrsaliyeDeposu().olustur(
        kalemler: _kalemler
            .map((k) => IrsaliyeKalemGirdi(
                urunId: k.urunId,
                urunAdi: k.urunAdi,
                miktar: k.miktar,
                birimFiyat: k.birimFiyat))
            .toList(),
        cariId: _seciliCari?.id,
        tarih: _tarih,
        tip: _tip,
        irsaliyeNo: no,
        kullaniciId: AuthServisi().aktifId,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'İrsaliye oluşturuldu ✓');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: ${bildirimMetniniSadelestir(e.toString())}');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  double get _toplam =>
      _kalemler.fold(0, (s, k) => s + k.miktar * k.birimFiyat);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TsAppBar(
        baslik: 'Yeni İrsaliye',
        aksiyonlar: [
          if (!_kayit)
            TextButton(
              onPressed: _kayit ? null : _kaydet,
              child: const Text('Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_kayit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary),
                ),
              ),
            ),
        ],
        gradyanli: false,
      ),
      body: Column(children: [
        // Üst bilgiler
        Container(
          padding: const EdgeInsets.all(14),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _tip,
                isDense: true,
                decoration: const InputDecoration(
                    labelText: 'Tip', border: OutlineInputBorder()),
                items: ['Çıkış', 'Giriş', 'Transfer']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) { if (v != null) setState(() => _tip = v); },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cariSec,
                icon: const Icon(Icons.person_search, size: 16),
                label: Text(
                  _seciliCari?.unvan ?? 'Müşteri Seç',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ]),
        ),

        // Ürün arama
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _araCtrl,
            decoration: const InputDecoration(
              hintText: 'Ürün ara ve ekle...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: _aramaChanged,
          ),
        ),

        if (_aramaSonuclari.isNotEmpty)
          SizedBox(
            height: 160,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.cardBg,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              // Şeffaf Material: sonuçlara dokunma dalgası görünsün.
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                  itemCount: _aramaSonuclari.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(_aramaSonuclari[i].urunAdi),
                    subtitle: Text(ParaUtils.formatla(_aramaSonuclari[i].satisFiyati)),
                    trailing: Text('${_aramaSonuclari[i].stok.toStringAsFixed(0)} stok',
                        style: TextStyle(
                            fontSize: 11,
                            color: _aramaSonuclari[i].stok > 0
                                ? Colors.green : Colors.red)),
                    onTap: () => _urunEkle(_aramaSonuclari[i]),
                  ),
                ),
              ),
            ),
          ),

        // Kalem listesi
        Expanded(
          child: _kalemler.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: context.textSecondary),
                      const SizedBox(height: 8),
                      Text('Ürün ekleyin',
                          style: TextStyle(color: context.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _kalemler.length,
                  itemBuilder: (_, i) {
                    final k = _kalemler[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                        dense: true,
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: TsRenk.zemin(Colors.teal),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Colors.teal, size: 18),
                        ),
                        title: Text(k.urunAdi,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                            '${k.birimAdi} • ${ParaUtils.formatla(k.birimFiyat)}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20, color: Colors.red),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                if (k.miktar <= 1) {
                                  _kalemler.removeAt(i);
                                } else {
                                  _kalemler[i] = _IrsKalem(
                                    urunId:     k.urunId,
                                    urunAdi:    k.urunAdi,
                                    barkod:     k.barkod,
                                    miktar:     k.miktar - 1,
                                    birimAdi:   k.birimAdi,
                                    birimFiyat: k.birimFiyat,
                                  );
                                }
                              });
                            },
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              k.miktar.toStringAsFixed(
                                  k.miktar % 1 == 0 ? 0 : 2),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                size: 20, color: Colors.green),
                            padding: EdgeInsets.zero,
                            constraints:
                                const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                _kalemler[i] = _IrsKalem(
                                  urunId:     k.urunId,
                                  urunAdi:    k.urunAdi,
                                  barkod:     k.barkod,
                                  miktar:     k.miktar + 1,
                                  birimAdi:   k.birimAdi,
                                  birimFiyat: k.birimFiyat,
                                );
                              });
                            },
                          ),
                        ]),
                      ),
                      ),
                    );
                  },
                ),
        ),

        // Toplam bar
        if (_kalemler.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Text('${_kalemler.length} kalem',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(
                ParaUtils.formatla(_toplam),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _IrsKalem {
  final int    urunId;
  final String urunAdi;
  final String? barkod;
  final double miktar;
  final String birimAdi;
  final double birimFiyat;

  const _IrsKalem({
    required this.urunId,
    required this.urunAdi,
    this.barkod,
    required this.miktar,
    required this.birimAdi,
    required this.birimFiyat,
  });
}
