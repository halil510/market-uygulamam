// lib/ekranlar/gider/gider_ekle_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../depolar/gider_deposu.dart';
import '../../depolar/banka_hesap_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../modeller/gider_model.dart';
import '../../modeller/banka_hesap_model.dart';
import '../../modeller/kredi_karti_model.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class GiderEkleEkrani extends ConsumerStatefulWidget {
  // 🔴 DÜZELTME (derin analizde bulundu): Bu ekran SADECE yeni gider
  // ekleyebiliyordu — mevcut bir gideri düzeltmenin (tutar/kategori/
  // açıklama hatası gibi) hiçbir yolu yoktu, kullanıcı silip yeniden
  // eklemek zorundaydı (bu da orijinal oluşturulma bilgisini kaybeder).
  final GiderModel? duzenlenecek;
  const GiderEkleEkrani({super.key, this.duzenlenecek});
  @override
  ConsumerState<GiderEkleEkrani> createState() => _GiderEkleEkraniState();
}

class _GiderEkleEkraniState extends ConsumerState<GiderEkleEkrani> {
  final GiderDeposu _depo = GiderDeposu();
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  final _belgeCtrl = TextEditingController();
  List<Map<String, dynamic>> _kategoriler = [];
  int? _seciliKategori;
  String _odemeYontemi = 'Nakit';
  bool _kayit = false;
  bool _yukleniyor = true;

  // 🔴🔴 KRİTİK DÜZELTME (paralel fork denetimi, 2026-09-22): 'Banka'/
  // 'Kredi Kartı' seçilebiliyordu ama HANGİ banka hesabı/HANGİ kart
  // olduğu hiç sorulmuyordu — bu yüzden GiderDeposu gerçek bir banka/
  // kart hareketi hiç oluşturamıyordu, para sessizce "kayboluyordu".
  // TahsilatOdemeEkrani'ndeki AYNI, doğru çalışan desen buraya da taşındı.
  List<BankaHesapModel> _bankaHesaplari = [];
  List<KrediKartiModel> _krediKartlari = [];
  BankaHesapModel? _secilenHesap;
  KrediKartiModel? _secilenKart;

  final List<String> _yontemler = const ['Nakit', 'Banka', 'Kredi Kartı', 'Çek'];

  bool get _bankaSecimiGerekli => _odemeYontemi == 'Banka';
  bool get _kartSecimiGerekli => _odemeYontemi == 'Kredi Kartı';

  @override
  void initState() {
    super.initState();
    final d = widget.duzenlenecek;
    if (d != null) {
      _tutarCtrl.text = d.tutar.toString();
      _aciklamaCtrl.text = d.aciklama ?? '';
      _belgeCtrl.text = d.belgeNo ?? '';
      _odemeYontemi = d.odemeYontemi;
      _seciliKategori = d.kategoriId;
    }
    _kategoriYukle();
    _hesapKartYukle();
  }

  Future<void> _hesapKartYukle() async {
    try {
      final hesaplar = await BankaHesapDeposu().tumunuGetir();
      final kartlar = await KrediKartiDeposu().tumunuGetir();
      if (!mounted) return;
      final d = widget.duzenlenecek;
      BankaHesapModel? eslesenHesap;
      if (d?.bankaHesapId != null) {
        for (final h in hesaplar) {
          if (h.id == d!.bankaHesapId) { eslesenHesap = h; break; }
        }
      }
      KrediKartiModel? eslesenKart;
      if (d?.krediKartiId != null) {
        for (final k in kartlar) {
          if (k.id == d!.krediKartiId) { eslesenKart = k; break; }
        }
      }
      setState(() {
        _bankaHesaplari = hesaplar;
        _krediKartlari = kartlar;
        _secilenHesap = eslesenHesap ?? (hesaplar.isNotEmpty ? hesaplar.first : null);
        _secilenKart = eslesenKart ?? (kartlar.isNotEmpty ? kartlar.first : null);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Banka/kart yükleme hatası: $e');
    }
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    _belgeCtrl.dispose();
    super.dispose();
  }

  Future<void> _kategoriYukle() async {
    try {
      final k = await _depo.kategorileriGetir();
      if (!mounted) return;
      setState(() {
        _kategoriler = k.cast<Map<String, dynamic>>();
        // Düzenleme modunda zaten dolu olan seçili kategoriyi EZME.
        if (_seciliKategori == null && k.isNotEmpty) _seciliKategori = k.first['id'] as int;
        _yukleniyor = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Gider kategorisi yükleme hatası: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    if (_seciliKategori == null) {
      BildirimServisi.uyari(context, 'Kategori seçin');
      return;
    }
    final tutar = double.tryParse(_tutarCtrl.text.replaceAll(',', '.'));
    if (tutar == null || tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli bir tutar girin');
      return;
    }
    if (_bankaSecimiGerekli && _secilenHesap == null) {
      BildirimServisi.uyari(context, 'Banka hesabı seçiniz');
      return;
    }
    if (_kartSecimiGerekli && _secilenKart == null) {
      BildirimServisi.uyari(context, 'Kredi kartı seçiniz');
      return;
    }

    // ÖNCEDEN BURADA HATA VARDI: setState() olmadan _kayit değiştiriliyordu,
    // bu yüzden yükleniyor göstergesi hiç görünmüyor ve çift tıklama
    // koruması gerçekte çalışmıyordu (buton görsel olarak pasif olmuyordu).
    setState(() => _kayit = true);
    try {
      final duzenleniyor = widget.duzenlenecek != null;
      if (duzenleniyor) {
        await _depo.guncelle(widget.duzenlenecek!.copyWith(
          kategoriId: _seciliKategori!,
          tutar: tutar,
          aciklama: _aciklamaCtrl.text.trim().isEmpty ? null : _aciklamaCtrl.text.trim(),
          belgeNo: _belgeCtrl.text.trim().isEmpty ? null : _belgeCtrl.text.trim(),
          odemeYontemi: _odemeYontemi,
          bankaHesapId: _secilenHesap?.id,
          krediKartiId: _secilenKart?.id,
        ));
      } else {
        final yeniId = await _depo.ekle(GiderModel(
          kategoriId: _seciliKategori!,
          tutar: tutar,
          aciklama: _aciklamaCtrl.text.trim().isEmpty ? null : _aciklamaCtrl.text.trim(),
          tarih: DateTime.now(),
          belgeNo: _belgeCtrl.text.trim().isEmpty ? null : _belgeCtrl.text.trim(),
          odemeYontemi: _odemeYontemi,
          kullaniciId: AuthServisi().aktifKullanici?.id,
          bankaHesapId: _secilenHesap?.id,
          krediKartiId: _secilenKart?.id,
        ));
        // FAZ 9 — Onay Merkezi (bildirim tipi): gider ENGELLENMEDİ,
        // zaten kaydedildi — sadece eşik aşımı sonradan incelenebilsin
        // diye kayda düşülüyor.
        OnayMerkeziServisi().kaydet(
          tur: OnayTuru.yuksekGider,
          tutar: tutar,
          esikTutar: OnayEsikleri.yuksekGiderTutari,
          referansTuru: 'gider',
          referansId: yeniId,
          aciklama: _aciklamaCtrl.text.trim().isEmpty ? null : _aciklamaCtrl.text.trim(),
        );
      }
      if (mounted) {
        BildirimServisi.basari(context, duzenleniyor ? 'Gider güncellendi ✓' : 'Gider kaydedildi ✓');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kayit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(baslik: widget.duzenlenecek != null ? 'Gideri Düzenle' : 'Gider Ekle', gradyanli: true),
      body: _yukleniyor
          ? const TsYukleniyor(iskelet: true)
          : ListView(
              padding: const EdgeInsets.all(TsBosluk.lg),
              children: [
                TsKart(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Kategori', style: TsMetin.etiket.copyWith(color: TsRenk.metinIkincil(context))),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _seciliKategori,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: TsRenk.arkaplan(context),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _kategoriler
                          .map((k) => DropdownMenuItem<int>(
                              value: k['id'] as int, child: Text(k['ad'] as String)))
                          .toList(),
                      onChanged: (v) => setState(() => _seciliKategori = v),
                    ),
                  ]),
                ),
                const SizedBox(height: TsBosluk.md),

                TsInput(
                  etiket: 'Tutar (₺)',
                  controller: _tutarCtrl,
                  klavyeTuru: const TextInputType.numberWithOptions(decimal: true),
                  oncilIkon: Icons.attach_money,
                ),
                const SizedBox(height: TsBosluk.md),

                TsKart(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Ödeme Yöntemi', style: TsMetin.etiket.copyWith(color: TsRenk.metinIkincil(context))),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: _yontemler.map((y) {
                      final secili = y == _odemeYontemi;
                      return ChoiceChip(
                        label: Text(y),
                        selected: secili,
                        onSelected: (_) => setState(() => _odemeYontemi = y),
                        selectedColor: TsRenk.zemin(TsRenk.primary),
                        labelStyle: TextStyle(
                          color: secili ? TsRenk.primary : TsRenk.metinIkincil(context),
                          fontWeight: secili ? FontWeight.w700 : FontWeight.w500,
                        ),
                      );
                    }).toList()),
                    if (_bankaSecimiGerekli) ...[
                      const SizedBox(height: 12),
                      if (_bankaHesaplari.isNotEmpty)
                        DropdownButtonFormField<BankaHesapModel>(
                          value: _secilenHesap,
                          decoration: const InputDecoration(
                              labelText: 'Hangi Hesaptan?', border: OutlineInputBorder()),
                          items: _bankaHesaplari
                              .map((h) => DropdownMenuItem(
                                  value: h,
                                  child: Text(h.hesapAdi, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _secilenHesap = v),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: TsRenk.zemin(TsRenk.uyari),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(
                              'Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                        ),
                    ],
                    if (_kartSecimiGerekli) ...[
                      const SizedBox(height: 12),
                      if (_krediKartlari.isNotEmpty)
                        DropdownButtonFormField<KrediKartiModel>(
                          value: _secilenKart,
                          decoration: const InputDecoration(
                              labelText: 'Hangi Kart?', border: OutlineInputBorder()),
                          items: _krediKartlari
                              .map((k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(k.kartAdi, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) => setState(() => _secilenKart = v),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: TsRenk.zemin(TsRenk.uyari),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(
                              'Kredi kartı bulunamadı. Önce bir kart ekleyin veya başka yöntem seçin.',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                        ),
                    ],
                  ]),
                ),
                const SizedBox(height: TsBosluk.md),

                TsInput(
                  etiket: 'Açıklama (opsiyonel)',
                  controller: _aciklamaCtrl,
                  oncilIkon: Icons.notes,
                ),
                const SizedBox(height: TsBosluk.md),

                TsInput(
                  etiket: 'Belge No (opsiyonel)',
                  controller: _belgeCtrl,
                  oncilIkon: Icons.receipt_long_outlined,
                ),
                const SizedBox(height: TsBosluk.xl),

                SizedBox(
                  height: 54,
                  child: TsButon(
                    metin: widget.duzenlenecek != null ? 'Güncelle' : 'Kaydet',
                    ikon: Icons.save_outlined,
                    tamGenislik: true,
                    yukleniyor: _kayit,
                    onPressed: _kayit ? null : _kaydet,
                  ),
                ),
              ],
            ),
    );
  }
}
