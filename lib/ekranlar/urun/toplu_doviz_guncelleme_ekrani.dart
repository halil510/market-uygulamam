// lib/ekranlar/urun/toplu_doviz_guncelleme_ekrani.dart
//
// Kullanıcı sorusu: "kur değişti o zaman nasıl olacak?" — bu ekran tam
// olarak buna cevap veriyor. Ürün Ekle'de "döviz bazında takip et"
// işaretlenen ürünler burada listelenir; güncel TCMB kuru ile TL
// fiyatlarının nasıl değişeceği ÖNİZLENİR, onaylanırsa TEK SEFERDE hepsi
// güncellenir. Profesyonel muhasebe programlarındaki "kur farkı /
// yeniden fiyatlandırma" akışının karşılığı.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/doviz_model.dart';
import '../../servisler/tcmb_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';

class TopluDovizGuncellemeEkrani extends StatefulWidget {
  const TopluDovizGuncellemeEkrani({super.key});

  @override
  State<TopluDovizGuncellemeEkrani> createState() => _TopluDovizGuncellemeEkraniState();
}

class _TopluDovizGuncellemeEkraniState extends State<TopluDovizGuncellemeEkrani> {
  bool _yukleniyor = true;
  bool _guncelleniyor = false;
  List<UrunModel> _urunler = [];
  Map<String, DovizModel> _kurlar = {};
  final Set<int> _secili = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final urunler = await UrunDeposu().dovizBazliUrunleriGetir();
      final tcmbKurlari = await TcmbServisi().guncelKurlariGetir();
      final kurMap = {for (final k in tcmbKurlari) k.kod: k};

      // Güncel TCMB kurlarını, ekranda hesaplama için DovizModel benzeri
      // bir yapıya çeviriyoruz (gerçek kayıtlı kur listesine dokunmadan
      // sadece ÖNİZLEME amaçlı).
      final kurlar = <String, DovizModel>{};
      for (final u in urunler) {
        if (u.dovizKodu == null) continue;
        final tcmb = kurMap[u.dovizKodu];
        if (tcmb != null) {
          kurlar[u.dovizKodu!] = DovizModel(
            kod: tcmb.kod, ad: tcmb.ad, sembol: tcmb.kod,
            satisKuru: tcmb.birimForexSatis,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _urunler = urunler;
        _kurlar = kurlar;
        _secili
          ..clear()
          ..addAll(urunler.where((u) => u.id != null).map((u) => u.id!));
        _yukleniyor = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _yukleniyor = false);
      BildirimServisi.hata(context, 'TCMB\'den güncel kur alınamadı: $e');
    }
  }

  double? _yeniFiyat(UrunModel u) {
    final kur = _kurlar[u.dovizKodu];
    if (kur == null || u.dovizTutari == null) return null;
    return u.dovizTutari! * kur.satisKuru;
  }

  // 🔴 Derin analizde bulundu: bu ekran, seçili ürünlerin alış fiyatını
  // güncel kurla anında ve HİÇBİR onay istemeden uyguluyordu —
  // tutarsızlık için, komşu toplu işlem ekranları (toplu_islem_ekrani.dart,
  // toplu_fiyat_ekrani.dart) hep açık bir onay dialogu gösteriyor.
  Future<void> _uygula() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Toplu Döviz Güncelleme'),
        content: Text(
            '${_secili.length} ürünün alış fiyatı güncel kura göre yeniden '
            'hesaplanacak. Bu işlem geri alınamaz. Devam edilsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Uygula')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    setState(() => _guncelleniyor = true);
    try {
      // 🔴 DÜZELTME (Madde 4 — Transaction denetimi, 2026-09-16):
      // ÖNCEDEN her ürün ayrı ayrı alisFiyatiGuncelle() ile (N farklı
      // db.update() çağrısı, atomik DEĞİL) güncelleniyordu —
      // kullanıcıya "Bu işlem geri alınamaz!" denip atomik bir işlem
      // izlenimi veriliyordu, ama ortasında bir kesinti (uygulama
      // çökmesi/güç kesintisi) olsaydı KISMİ güncelleme kalır, geri
      // alınamazdı. Artık UrunDeposu.topluAlanGuncelle() ile TEK
      // transaction'da (ya hepsi ya hiçbiri) yazılıyor. alis_kdv_oran
      // her ürün için zaten bellekte olduğundan (u.alisKdvOran), eski
      // yoldaki gereksiz per-ürün SELECT de ayrıca ortadan kalktı.
      final now = DateTime.now().toIso8601String();
      final guncellemeler = <int, Map<String, dynamic>>{};
      for (final u in _urunler) {
        if (u.id == null || !_secili.contains(u.id)) continue;
        final yeni = _yeniFiyat(u);
        if (yeni == null) continue;
        final yeniKdvDahil = yeni * (1 + u.alisKdvOran / 100);
        guncellemeler[u.id!] = {
          'alis_fiyat': yeni,
          'alis_fiyat_kdv_dahil': yeniKdvDahil,
          'fiyat_guncelleme_tarih': now,
        };
      }
      final guncellenenIds = await UrunDeposu().topluAlanGuncelle(guncellemeler);
      if (!mounted) return;
      BildirimServisi.basari(context,
          '${guncellenenIds.length} ürünün fiyatı güncel kurla yeniden hesaplandı ✓');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Güncelleme başarısız: $e');
    } finally {
      if (mounted) setState(() => _guncelleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Toplu Döviz Güncelleme',
        aksiyonlar: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _yukle),
        ],
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : _urunler.isEmpty
              ? const TsBosDurum(
                  ikon: Icons.currency_exchange,
                  baslik: 'Döviz bazında takip edilen ürün yok',
                  altyazi: 'Ürün Ekle\'de "Dövizle Hesapla" ile ürün eklerken '
                      '"Bu ürünü döviz bazında takip et" seçeneğini işaretleyin',
                )
              : Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: TsRenk.kart(context),
                    child: Text(
                      'Aşağıdaki ürünler döviz bazında takip ediliyor. Güncel '
                      'TCMB kuruyla yeni fiyatları önizlendi — onayladığınız '
                      'ürünlerin TL alış fiyatı tek seferde güncellenecek.',
                      style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context)),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(TsBosluk.lg),
                      itemCount: _urunler.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _urunSatiri(_urunler[i]),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 54,
                        child: TsButon(
                          metin: '${_secili.length} Ürünü Güncelle',
                          ikon: Icons.sync,
                          tamGenislik: true,
                          yukleniyor: _guncelleniyor,
                          onPressed: (_guncelleniyor || _secili.isEmpty) ? null : _uygula,
                        ),
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _urunSatiri(UrunModel u) {
    final yeni = _yeniFiyat(u);
    final eski = u.alisFiyat;
    final fark = yeni != null ? yeni - eski : null;
    final secilimi = u.id != null && _secili.contains(u.id);

    return TsKart(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        // Kullanıcı isteği: "ürün üzerine tıklanınca ürün güncelle
        // sayfasına gitsin, orada satış fiyatını da güncelleyebiliriz" —
        // yeni hesaplanan alış fiyatı ÖNCEDEN DOLU olarak Ürün Güncelle
        // ekranına gidiliyor. O ekrandaki MEVCUT KDV hesaplama mantığı
        // (alış fiyat alanı değişince otomatik tetiklenen dinleyici)
        // KDV dahil fiyatı da doğru şekilde yeniden hesaplayacak — bu
        // yüzden burada KDV hesaplamasını tekrar YAZMAYA gerek yok,
        // aynı, zaten doğru çalışan mantık yeniden kullanılıyor.
        onTap: yeni == null ? null : () async {
          final guncellenmisModel = u.copyWith(alisFiyat: yeni);
          final sonuc = await context.push('/urun/ekle', extra: guncellenmisModel);
          if (sonuc == true && mounted) _yukle(); // kaydedildiyse listeyi tazele
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(children: [
          Checkbox(
            value: secilimi,
            onChanged: yeni == null ? null : (v) => setState(() {
              if (v == true) {
                _secili.add(u.id!);
              } else {
                _secili.remove(u.id);
              }
            }),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.urunAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${u.dovizTutari?.toStringAsFixed(2)} ${u.dovizKodu}',
                  style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
            ]),
          ),
          if (yeni != null) ...[
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(ParaUtils.formatla(yeni),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                      color: (fark ?? 0) > 0 ? Colors.red.shade600 : (fark ?? 0) < 0 ? Colors.green.shade600 : null)),
              Text('Eski: ${ParaUtils.formatla(eski)}',
                  style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
            ]),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, size: 16, color: TsRenk.metinIkincil(context)),
          ] else
            Text('Kur bulunamadı', style: TextStyle(fontSize: 11, color: TsRenk.hata)),
        ]),
      ),
    );
  }
}
