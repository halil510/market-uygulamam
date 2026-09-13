// lib/ekranlar/tedarik/satin_alma_onerileri_ekrani.dart
//
// FAZ 6 (Satın Alma) — kritik stoktaki ürünler için sipariş ÖNERİSİ.
// Madde 16: bu ekran doğrudan sipariş OLUŞTURMAZ, sadece tedarikçi seçimi
// ve miktar onayından sonra kullanıcıyı SiparisOlusturEkrani'na (mevcut
// 'beklemede' sipariş akışı) önerilen kalemlerle yönlendirir. Stok/kasa/cari
// bu ekranda hiçbir şekilde ETKİLENMEZ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'siparis_olustur_ekrani.dart' show OnerilenSiparisKalemi;

class SatinAlmaOnerileriEkrani extends ConsumerStatefulWidget {
  const SatinAlmaOnerileriEkrani({super.key});
  @override
  ConsumerState<SatinAlmaOnerileriEkrani> createState() => _SatinAlmaOnerileriEkraniState();
}

class _SatinAlmaOnerileriEkraniState extends ConsumerState<SatinAlmaOnerileriEkrani> {
  final _urunDepo = UrunDeposu();
  final _cariDepo = CariDeposu();
  List<UrunModel> _urunler = [];
  final Map<int, double> _miktarlar = {};
  final Set<int> _secili = {};
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  double _onerilenMiktar(UrunModel u) {
    final eksik = u.minimumStok - u.stok;
    return eksik > 0 ? eksik : 1;
  }

  Future<void> _yukle() async {
    _yukleniyor = true;
    if (mounted) setState(() {});
    try {
      final liste = await _urunDepo.kritikStoklar(limit: 500);
      _urunler = liste;
      _miktarlar
        ..clear()
        ..addEntries(liste.map((u) => MapEntry(u.id!, _onerilenMiktar(u))));
      _secili
        ..clear()
        ..addAll(liste.map((u) => u.id!));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Yüklenemedi: $e');
    } finally {
      _yukleniyor = false;
      if (mounted) setState(() {});
    }
  }

  Future<CariModel?> _tedarikciSec() async {
    final cariler = await _cariDepo.tumunuGetir(tip: 'Tedarikçi');
    if (!mounted) return null;
    if (cariler.isEmpty) {
      BildirimServisi.uyari(context, 'Kayıtlı tedarikçi yok');
      return null;
    }
    return showModalBottomSheet<CariModel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => ListView.separated(
          controller: ctrl,
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: cariler.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = cariler[i];
            return ListTile(
              title: Text(c.unvan),
              subtitle: c.telefon != null ? Text(c.telefon!) : null,
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
    );
  }

  Future<void> _oneriyiSiparisEDonustur() async {
    if (_secili.isEmpty) {
      BildirimServisi.uyari(context, 'Ürün seçilmedi');
      return;
    }
    final tedarikci = await _tedarikciSec();
    if (tedarikci == null || !mounted) return;
    final kalemler = _urunler
        .where((u) => _secili.contains(u.id))
        .map((u) => OnerilenSiparisKalemi(urun: u, miktar: _miktarlar[u.id!] ?? 1))
        .toList();
    final kaydedildi = await context.push<bool>('/tedarik/siparis-olustur', extra: {
      'tedarikci': tedarikci,
      'onerilenKalemler': kalemler,
    });
    if (kaydedildi == true && mounted) await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final secilenAdet = _secili.length;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Satın Alma Önerileri',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: TsRenk.primary))
          : _urunler.isEmpty
              ? const BosEkran(
                  ikon: Icons.check_circle_outline,
                  baslik: 'Kritik stokta ürün yok',
                  aciklama: 'Minimum stok seviyesinin altına düşen ürün bulunmuyor.',
                )
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: _urunler.length,
                    itemBuilder: (_, i) {
                      final u = _urunler[i];
                      final secili = _secili.contains(u.id);
                      final miktar = _miktarlar[u.id!] ?? _onerilenMiktar(u);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: TsKart(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(children: [
                            Checkbox(
                              value: secili,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _secili.add(u.id!);
                                } else {
                                  _secili.remove(u.id);
                                }
                              }),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(u.urunAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  'Stok: ${u.stok.toStringAsFixed(0)} / Min: ${u.minimumStok.toStringAsFixed(0)} ${u.birimAdi}',
                                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                                ),
                              ]),
                            ),
                            SizedBox(
                              width: 84,
                              child: TextFormField(
                                enabled: secili,
                                initialValue: miktar % 1 == 0 ? miktar.toStringAsFixed(0) : miktar.toStringAsFixed(3),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  labelText: 'Miktar',
                                ),
                                onChanged: (v) {
                                  final m = double.tryParse(v);
                                  if (m != null && m > 0) _miktarlar[u.id!] = m;
                                },
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: _urunler.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: secilenAdet == 0 ? null : _oneriyiSiparisEDonustur,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text('Tedarikçi Seç ve Sipariş Oluştur ($secilenAdet)'),
                ),
              ),
            ),
    );
  }
}
