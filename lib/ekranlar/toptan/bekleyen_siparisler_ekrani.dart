// lib/ekranlar/toptan/bekleyen_siparisler_ekrani.dart
//
// Kullanıcı isteği: "Sipariş önce Bekleyen Sipariş olarak kaydedilsin,
// sonra ayrı bir ekrandan onaylanıp faturaya/irsaliyeye dönüştürülsün."
// Onay adımı, ToptanSatisEkrani'ndeki AYNI kanıtlanmış faturalandırma
// zincirini kullanır.
import 'package:flutter/material.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/bekleyen_siparis_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';

class BekleyenSiparislerEkrani extends StatefulWidget {
  /// Belirli bir bayi için filtrelenmiş liste (cari detayından
  /// açılınca) — null ise tüm bekleyen siparişler gösterilir (genel
  /// "Bekleyen Siparişler" giriş noktası).
  final CariModel? bayi;
  const BekleyenSiparislerEkrani({super.key, this.bayi});

  @override
  State<BekleyenSiparislerEkrani> createState() => _BekleyenSiparislerEkraniState();
}

class _BekleyenSiparislerEkraniState extends State<BekleyenSiparislerEkrani> {
  final _depo = BekleyenSiparisDeposu();
  final _cariDepo = CariDeposu();
  List<Map<String, dynamic>> _siparisler = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final liste = await _depo.bekleyenSiparisleriGetir(cariId: widget.bayi?.id);
      if (!mounted) return;
      setState(() { _siparisler = liste; _yukleniyor = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _yukleniyor = false);
      BildirimServisi.hata(context, 'Bekleyen siparişler yüklenemedi: $e');
    }
  }

  Future<void> _detayAc(Map<String, dynamic> siparis) async {
    final degisti = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => _SiparisDetayEkrani(siparis: siparis, depo: _depo, cariDepo: _cariDepo),
    ));
    if (degisti == true) _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Bekleyen Siparişler',
        altBaslik: widget.bayi != null ? widget.bayi!.unvan : '${_siparisler.length} sipariş',
        gradyanli: true,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _siparisler.isEmpty
              ? TsBosDurum(
                  ikon: Icons.inventory_2_outlined,
                  baslik: 'Bekleyen sipariş yok',
                  altyazi: 'Bayi Sipariş Al ekranından yeni sipariş oluşturabilirsiniz',
                )
              : RefreshIndicator(
                  onRefresh: _yukle,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(TsBosluk.lg),
                    itemCount: _siparisler.length,
                    separatorBuilder: (_, __) => const SizedBox(height: TsBosluk.sm),
                    itemBuilder: (ctx, i) {
                      final s = _siparisler[i];
                      final tarih = DateTime.tryParse(s['tarih']?.toString() ?? '');
                      return TsKart.liste(
                        baslik: s['cari_unvan']?.toString() ?? '—',
                        altBaslik: tarih != null
                            ? '${tarih.day.toString().padLeft(2, '0')}.${tarih.month.toString().padLeft(2, '0')}.${tarih.year} ${tarih.hour.toString().padLeft(2, '0')}:${tarih.minute.toString().padLeft(2, '0')}'
                            : null,
                        ikon: const Icon(Icons.pending_actions_outlined),
                        deger: ParaUtils.formatla((s['genel_toplam'] as num?)?.toDouble() ?? 0),
                        onTap: () => _detayAc(s),
                      );
                    },
                  ),
                ),
    );
  }
}

class _SiparisDetayEkrani extends StatefulWidget {
  final Map<String, dynamic> siparis;
  final BekleyenSiparisDeposu depo;
  final CariDeposu cariDepo;
  const _SiparisDetayEkrani({required this.siparis, required this.depo, required this.cariDepo});

  @override
  State<_SiparisDetayEkrani> createState() => _SiparisDetayEkraniState();
}

class _SiparisDetayEkraniState extends State<_SiparisDetayEkrani> {
  List<Map<String, dynamic>> _kalemler = [];
  bool _yukleniyor = true;
  bool _islemde = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final liste = await widget.depo.siparisKalemleriGetir(widget.siparis['id'] as int);
      if (!mounted) return;
      setState(() { _kalemler = liste; _yukleniyor = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _yukleniyor = false);
      BildirimServisi.hata(context, 'Sipariş kalemleri yüklenemedi: $e');
    }
  }

  Future<void> _iptalEt() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Siparişi İptal Et'),
        content: const Text('Bu bekleyen sipariş iptal edilsin mi? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (onay != true) return;
    setState(() => _islemde = true);
    try {
      await widget.depo.iptalEt(widget.siparis['id'] as int);
      if (mounted) {
        BildirimServisi.basari(context, 'Sipariş iptal edildi');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'İptal edilemedi: $e');
    } finally {
      if (mounted) setState(() => _islemde = false);
    }
  }

  Future<void> _onayla() async {
    setState(() => _islemde = true);
    try {
      final cariId = widget.siparis['cari_id'] as int;
      final cari = await widget.cariDepo.idileGetir(cariId);
      if (cari == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı');
        return;
      }
      final kullanici = AuthServisi().aktifKullanici;
      final satisId = await widget.depo.onaylaVeSatisaCevir(
        siparisId: widget.siparis['id'] as int,
        cari: cari,
        kullaniciId: kullanici?.id,
      );

      // ══════════════════════════════════════════════════════════════
      // 🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "bekleyen siparişi
      // onaylıyorum, Cari'de detay gözükmüyor")
      //
      // onaylaVeSatisaCevir() içinde CariDeposu().hareketEkle() ile
      // hareket doğru yazılıyor, bakiye doğru güncelleniyor (bunlar
      // önceki bir turda ayrıca doğrulandı). Ama bu ekran ConsumerState
      // değil; Genel Cari modülü (cari_detay_ekrani.dart) veriyi
      // `cariDetayProvider` adlı Riverpod cache'inden okuyor ve o
      // cache burada hiç invalidate edilmiyordu.
      //
      // Aynı hata toptan_satis_ekrani.dart'ta da vardı (anlık toptan
      // satış) — ikisi de düzeltildi, aynı yöntemle.
      // ══════════════════════════════════════════════════════════════
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .invalidate(cariDetayProvider(cari.id!));
      }

      if (!mounted) return;

      // Kullanıcı isteği: "sonradan faturalandırma sevk yani" — satış
      // oluştuktan sonra fatura/irsaliye adımları SUNULUR, zorunlu
      // tutulmaz (ToptanSatisEkrani ile AYNI, kanıtlanmış davranış).
      final secim = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Sipariş Onaylandı'),
          ]),
          content: const Text('Satış oluşturuldu. Şimdi ne yapmak istersiniz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, 'kapat'), child: const Text('Şimdi Değil')),
            TextButton(onPressed: () => Navigator.pop(c, 'irsaliye'), child: const Text('İrsaliye Oluştur')),
            FilledButton(onPressed: () => Navigator.pop(c, 'fatura'), child: const Text('Fatura Kes')),
          ],
        ),
      );

      if (secim == 'fatura') {
        await _faturalandir(satisId, cari);
      } else if (secim == 'irsaliye') {
        await _irsaliyeOlustur(cari, satisId);
      } else if (mounted) {
        BildirimServisi.basari(context, 'Satış oluşturuldu');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Onaylanamadı: $e');
    } finally {
      if (mounted) setState(() => _islemde = false);
    }
  }

  /// ToptanSatisEkrani._faturalandir() ile AYNI, kanıtlanmış zincir.
  Future<void> _faturalandir(int satisId, CariModel cari) async {
    try {
      final kontrol = await FaturalandirmaServisi.kontrolEt(cari.id!);
      if (kontrol == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı.');
        return;
      }
      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${kontrol.cari.unvan} için fatura kesilebilmesi için aşağıdaki bilgiler eksik:'),
              const SizedBox(height: 10),
              ...kontrol.eksikAlanlar.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(e),
                    ]),
                  )),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted) await context.push('/cari/ekle', extra: kontrol.cari);
        return;
      }

      final detaylar = _kalemler.map((k) {
        final toplamMiktar = (k['toplam_miktar'] as num).toDouble();
        final toplamTutar = (k['toplam_tutar'] as num).toDouble();
        final kdvOran = (k['kdv_oran'] as num).toDouble();
        final birimFiyat = toplamMiktar > 0 ? toplamTutar / toplamMiktar : 0.0;
        return FaturaDetayModel(
          urunId: k['urun_id'] as int,
          urunAdi: '${k['urun_adi']} (${k['birim_adi']})',
          miktar: toplamMiktar,
          birimFiyat: birimFiyat,
          iskontoOrani: (k['iskonto_oran'] as num).toDouble(),
          iskontoTutari: (k['iskonto_tutar'] as num).toDouble(),
          kdvOrani: kdvOran,
          kdvTutari: toplamTutar * (kdvOran / 100),
          araToplam: toplamMiktar * birimFiyat,
          toplamTutar: toplamTutar,
        );
      }).toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Satis',
        satisId: satisId,
        tarih: DateTime.now(),
        odenenTutar: 0,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu ✓');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    }
  }

  /// 🔴 NOT: Bu irsaliye, satış zaten oluşturulduktan SONRA çağrılıyor
  /// — satış oluşturma sırasında stok ZATEN düşürülmüştü (bkz.
  /// BekleyenSiparisDeposu.onaylaVeSatisaCevir). Bu yüzden burada
  /// STOK TEKRAR DÜŞÜRÜLMÜYOR — sadece sevk belgesi (kayıt amaçlı)
  /// oluşturuluyor. irsaliye_ekrani.dart'taki STANDALONE oluşturma
  /// akışı stok da düşürür; o akışla KARIŞTIRILMAMALI.
  Future<void> _irsaliyeOlustur(CariModel cari, int satisId) async {
    try {
      final db = await Veritabani().db;
      final no = await Veritabani().fisNoUret('irsaliye', subeId: AktifSubeServisi().subeId ?? 1);
      final now = DateTime.now().toIso8601String();
      final toplam = _kalemler.fold(0.0, (s, k) => s + (k['toplam_tutar'] as num).toDouble());
      late int irsaliyeId;
      await db.transaction((txn) async {
        irsaliyeId = await txn.insert('irsaliyeler', {
          'global_id': const Uuid().v4(),
          'irsaliye_no': no,
          'cari_id': cari.id,
          'tarih': now,
          'tip': 'Çıkış',
          'toplam_tutar': toplam,
          'durum': 'Hazırlanıyor',
          'kullanici_id': AuthServisi().aktifId,
          'created_at': now,
          'last_updated': now,
        });
        for (final k in _kalemler) {
          await txn.insert('irsaliye_kalem', {
            'global_id': const Uuid().v4(),
            'irsaliye_id': irsaliyeId,
            'urun_id': k['urun_id'],
            'urun_adi': '${k['urun_adi']} (${k['birim_adi']})',
            'miktar': k['toplam_miktar'],
            'birim_fiyat': (k['toplam_miktar'] as num) > 0
                ? (k['toplam_tutar'] as num).toDouble() / (k['toplam_miktar'] as num).toDouble()
                : 0.0,
            'toplam_tutar': k['toplam_tutar'],
            'last_updated': now,
          });
        }
      });
      if (!mounted) return;
      BildirimServisi.basari(context, 'İrsaliye oluşturuldu: $no ✓');
      context.push('/irsaliye/detay/$irsaliyeId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'İrsaliye oluşturulamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.siparis;
    final onaylandi = s['durum'] == 'onaylandi';
    final iptal = s['durum'] == 'iptal';
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Sipariş Detayı',
        altBaslik: s['cari_unvan']?.toString(),
        gradyanli: true,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(
              padding: const EdgeInsets.all(TsBosluk.lg),
              children: [
                if (onaylandi || iptal)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TsBosluk.md),
                    child: TsBadge(
                      metin: onaylandi ? 'ONAYLANDI' : 'İPTAL EDİLDİ',
                      tur: onaylandi ? TsBadgeTuru.basarili : TsBadgeTuru.hata,
                    ),
                  ),
                if (s['not_'] != null && s['not_'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TsBosluk.md),
                    child: TsKart(
                      child: Row(children: [
                        Icon(Icons.notes, size: 18, color: TsRenk.metinIkincil(context)),
                        const SizedBox(width: TsBosluk.sm),
                        Expanded(child: Text(s['not_'].toString())),
                      ]),
                    ),
                  ),
                ..._kalemler.map((k) => Padding(
                      padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                      child: TsKart.liste(
                        baslik: k['urun_adi']?.toString() ?? '',
                        altBaslik: '${(k['miktar'] as num).toStringAsFixed(0)} ${k['birim_adi']}'
                            ' (${(k['toplam_miktar'] as num).toStringAsFixed(0)} Adet)'
                            '${(k['iskonto_oran'] as num) > 0 ? " · %${(k['iskonto_oran'] as num).toStringAsFixed(0)} iskonto" : ""}',
                        deger: ParaUtils.formatla((k['toplam_tutar'] as num).toDouble()),
                      ),
                    )),
                const SizedBox(height: TsBosluk.md),
                TsKart(
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Maliyet Toplamı', style: TsMetin.govde.copyWith(color: TsRenk.metinIkincil(context))),
                      Text(ParaUtils.formatla((s['alis_toplam'] as num?)?.toDouble() ?? 0)),
                    ]),
                    const SizedBox(height: TsBosluk.xs),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('GENEL TOPLAM', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text(ParaUtils.formatla((s['genel_toplam'] as num?)?.toDouble() ?? 0),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: TsRenk.primary)),
                    ]),
                  ]),
                ),
              ],
            ),
      bottomNavigationBar: (!onaylandi && !iptal)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(TsBosluk.lg),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _islemde ? null : _iptalEt,
                      style: OutlinedButton.styleFrom(foregroundColor: TsRenk.hata),
                      child: const Text('İptal Et'),
                    ),
                  ),
                  const SizedBox(width: TsBosluk.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _islemde ? null : _onayla,
                      style: FilledButton.styleFrom(backgroundColor: TsRenk.primary),
                      child: _islemde
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Onayla ve Satışa Dönüştür'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
    );
  }
}
