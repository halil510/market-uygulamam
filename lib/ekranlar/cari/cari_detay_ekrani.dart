// lib/ekranlar/cari/cari_detay_ekrani.dart
import 'package:flutter/foundation.dart';
import 'fis_detay_ekrani.dart';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/cari_hareket_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/satis_deposu.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/gib_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/cari_deposu.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/musteri_360_servisi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../modeller/kullanici_model.dart';
import '../../cekirdek/utils/sifre_hash.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../widgetlar/ortak/yonetici_sifre_dialogu.dart';
import '../../servisler/yazdirma_servisi.dart';
import '../../widgetlar/ortak/fis_fiyat_guncelle_akisi.dart';
import '../../cekirdek/utils/hata_utils.dart';
part 'cari_detay_ekrani_islemler.dart';
part 'cari_detay_ekrani_sekmeler.dart';

/// Karma ödemeli bir satışta hem Cari hem Cari-dışı (Nakit/Kart/Havale)
/// payı varsa, SatisTamamlamaServisi.tamamla() AYNI satış (fis_id) için
/// 2 ayrı cari_hareket satırı yazar: gerçek Cari borcu (borc>0, alacak=0)
/// + bakiyeyi etkilemeyen bilgi amaçlı satır (borc=alacak, self-
/// cancelling — o payın Nakit/Kart/Havale ile ANINDA ödendiğini
/// kaydeder). Kullanıcı bulgusu (2026-09-20): bu, Cari Hareketler
/// listesinde AYNI satışın 2 ayrı "Satış" kartı gibi görünmesine yol
/// açıyordu — kafa karıştırıcı.
///
/// Bu SAF fonksiyon, aynı fis_id + fis_tipi='Satış' satırlarını TEK bir
/// karta birleştirir. borc/alacak toplanır — bu, net bakiye etkisini
/// DOĞRU tutar (self-cancelling satırın borc=alacak'ı zaten birbirini
/// götürür), ama HAM toplamları (100 borç + 50 alacak gibi) DEĞİL,
/// sadece NET etkiyi (borç YA DA alacak, ikisi asla aynı anda değil)
/// gösterir — iki ayrı tutarın aynı kartta görünmesi kafa karıştırırdı.
/// Tam ödeme dağılımı (50 Nakit + 50 Cari gibi) artık Satış Detayı
/// ekranında gösteriliyor — bu liste sadece NET etkiyi özetler.
/// 'Satış' olmayan hareketler (Tahsilat, Ödeme, Toptan Satış vb.) ve
/// tek satırlı 'Satış' kayıtları DEĞİŞTİRİLMEDEN geçer.
/// Satış-aile fiş tipleri: bir satıştan otomatik türeyen ve o satış
/// silindiğinde (SatisDeposu.sil()) oluşan orijinal + ters-kayıt tipleri.
const _satisAileTipleri = {
  'Satış', 'Toptan Satış', 'Satış İptali', 'Toptan Satış İptali', 'Tahsilat İptali',
};

/// Alım-aile fiş tipleri: bir tedarikçi alımından türeyen ve o alım
/// silindiğinde (AlimIslemServisi.sil(), 2026-09-22) oluşan orijinal +
/// ters-kayıt tipleri. Satış ailesinden AYRI tutuluyor çünkü 'fis_id',
/// Satış için satislar.id, Alım için tedarikci_siparisler.id'dir — bu
/// iki id UZAYI ÇAKIŞABİLİR (ikisi de 1'den başlar), aynı fis_id'ye
/// sahip bir Satış ile bir Alım'ı TEK grupta birleştirmek net hesabını
/// bozardı (bkz. aşağıdaki _fisAilesi/anahtar mantığı).
const _alimAileTipleri = {
  'Alım', 'Alım İptali',
};

/// [h] hangi aileye ait (varsa) — 's' (Satış) / 'a' (Alım) / null
/// (aile-dışı, ör. Tahsilat/Ödeme).
String? _fisAilesi(CariHareketModel h) {
  if (_satisAileTipleri.contains(h.fisTipi)) return 's';
  if (_alimAileTipleri.contains(h.fisTipi)) return 'a';
  return null;
}

/// Bir satış silindiğinde SatisDeposu.sil() (bir alım silindiğinde
/// AlimIslemServisi.sil()) orijinal "Satış"/"Alım" cari_hareket kaydını
/// SİLMEZ (audit için is_deleted=0 kalır) — sadece net etkisini
/// sıfırlayan bir "... İptali" ters kaydı EKLER. Kullanıcı isteği
/// (2026-09-21, Alım'a genişletildi 2026-09-22): iptal edilmiş bir
/// satışın/alımın izi (audit) veritabanında kalsın ama müşteri
/// ekstresinde "... İptali" yazan kafa karıştırıcı satırlar GÖRÜNMESİN —
/// silinen fiş sanki hiç olmamış gibi. Bu fonksiyon AYNI aileden VE AYNI
/// fis_id'ye ait satırların NET etkisi sıfırsa (gerçekten tam iptal
/// edilmişse) o grubu listeden tamamen çıkarır; net sıfır değilse
/// (kısmi/karma durum, emin olunamayan bir senaryo) hiçbir şeye
/// dokunmaz — güvenli taraf hep "göster" yönündedir.
List<CariHareketModel> _iptalEdilmisSatislariGizle(
    List<CariHareketModel> ham) {
  final gruplar = <String, List<CariHareketModel>>{};
  for (final h in ham) {
    final aile = _fisAilesi(h);
    if (h.fisId == null || aile == null) continue;
    (gruplar['$aile:${h.fisId}'] ??= []).add(h);
  }
  final gizlenecekAnahtarlar = <String>{};
  gruplar.forEach((anahtar, grup) {
    final asliVarMi = grup.any((g) =>
        g.fisTipi == 'Satış' || g.fisTipi == 'Toptan Satış' || g.fisTipi == 'Alım');
    final iptalVarMi = grup.any((g) => g.fisTipi.endsWith('İptali'));
    if (!asliVarMi || !iptalVarMi) return;
    final net = grup.fold(0.0, (s, g) => s + g.borc - g.alacak);
    if (net.abs() < 0.01) gizlenecekAnahtarlar.add(anahtar);
  });
  if (gizlenecekAnahtarlar.isEmpty) return ham;
  return ham.where((h) {
    final aile = _fisAilesi(h);
    if (h.fisId == null || aile == null) return true;
    return !gizlenecekAnahtarlar.contains('$aile:${h.fisId}');
  }).toList();
}

/// CariDeposu.hareketIptalEt() bir Tahsilat/Ödeme iptal edildiğinde
/// ORİJİNAL kaydı is_deleted=1 yapar (hareketleriniGetir() zaten
/// is_deleted=0 filtreler, o satır hiç gelmez) ve yanına salt-audit,
/// borc=0/alacak=0 bir "... İptali" damga satırı ekler (bakiyeyi
/// etkilemesin diye bilinçli olarak sıfır). Sonuç: müşteri ekstresinde
/// üstünde hiçbir şey görünmeyen, ₺0,00 tutarlı, tek başına asılı kalan
/// bir "Tahsilat İptali" satırı — kullanıcı bulgusu (2026-09-22): "silme
/// işlemi olmaz mı" (yani bu iz de satış iptalinde olduğu gibi hiç
/// görünmesin). Orijinali zaten görünmediğinden bu damga satırı hiçbir
/// bakiye bilgisi taşımıyor — DB'de audit için kalmaya devam eder, sadece
/// ekrandan gizlenir.
List<CariHareketModel> _sifirTutarliIptalDamgalariniGizle(
    List<CariHareketModel> ham) {
  return ham
      .where((h) =>
          !(h.fisTipi.endsWith('İptali') && h.borc == 0 && h.alacak == 0))
      .toList();
}

List<CariHareketModel> cariHareketleriniGrupla(List<CariHareketModel> hamGiris) {
  final ham = _sifirTutarliIptalDamgalariniGizle(
      _iptalEdilmisSatislariGizle(hamGiris));
  final gruplar = <int, List<CariHareketModel>>{};
  for (final h in ham) {
    if (h.fisTipi == 'Satış' && h.fisId != null) {
      (gruplar[h.fisId!] ??= []).add(h);
    }
  }

  final sonuc = <CariHareketModel>[];
  final islenmisFisIdler = <int>{};
  for (final h in ham) {
    if (h.fisTipi != 'Satış' || h.fisId == null) {
      sonuc.add(h);
      continue;
    }
    final fisId = h.fisId!;
    if (islenmisFisIdler.contains(fisId)) continue;
    islenmisFisIdler.add(fisId);

    final grup = gruplar[fisId]!;
    if (grup.length == 1) {
      sonuc.add(h);
      continue;
    }

    final borcToplam = ParaUtils.yuvarla(grup.fold(0.0, (s, g) => s + g.borc));
    final alacakToplam = ParaUtils.yuvarla(grup.fold(0.0, (s, g) => s + g.alacak));
    final net = borcToplam - alacakToplam;
    sonuc.add(CariHareketModel(
      id: h.id,
      cariId: h.cariId,
      tarih: h.tarih,
      fisTipi: h.fisTipi,
      fisId: fisId,
      fisNo: h.fisNo,
      // 🔴 DÜZELTME (Cari/Fiş denetimi, 2026-09-20): metin ÖNCEDEN "ödeme
      // dağılımı için dokunun" diyordu ama bu karta dokunmak (satisMi ==
      // true dalı, aşağıda _hareketFaturalandir) HER ZAMAN faturalama
      // akışını başlatıyordu — ödeme dağılımı hiç gösterilmiyordu (o
      // sadece Satış Detayı ekranında var). Metin artık gerçek davranışı
      // yansıtıyor.
      aciklama: 'Karma Satış: ${h.fisNo ?? fisId} (fatura oluşturmak için dokunun)',
      borc: net > 0 ? net : 0,
      alacak: net < 0 ? -net : 0,
      odemeTuru: 'Karma',
      kullanici: h.kullanici,
    ));
  }
  return sonuc;
}

class CariDetayEkrani extends ConsumerWidget {
  final int cariId;
  const CariDetayEkrani({super.key, required this.cariId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cariDetayProvider(cariId));
    return async.when(
      loading: () => const Scaffold(body: Center(child: AppYukleniyor())),
      error: (e, _) => Scaffold(
        appBar: const TsAppBar(
        baslik: 'Hata',
        gradyanli: false,
      ),
        body: BosEkran(ikon: Icons.inbox_outlined, baslik: bildirimMetniniSadelestir(e.toString()))),
      data: (cari) {
        if (cari == null) return const Scaffold(
          appBar: TsAppBar(
        baslik: 'Bulunamadı',
        gradyanli: false,
      ),
          body: BosEkran(ikon: Icons.inbox_outlined, baslik: 'Cari bulunamadı'));
        return _CariDetayIcerik(cari: cari);
      },
    );
  }
}

class _CariDetayIcerik extends ConsumerStatefulWidget {
  final CariModel cari;
  const _CariDetayIcerik({required this.cari});
  @override
  ConsumerState<_CariDetayIcerik> createState() => _CariDetayIcerikState();
}

class _CariDetayIcerikState extends ConsumerState<_CariDetayIcerik>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<CariHareketModel> _hareketler = [];
  bool _yukl = false;
  final _fmt = DateFormat('dd.MM.yyyy HH:mm');

  // 🆕 Uzun basıp seçip yazdırma (kullanıcı isteği 2026-09-22): hızlı
  // satıştaki manuel yazdırma butonuyla AYNI fikir — bir fiş/tahsilat/
  // ödeme satırına uzun basılınca seçilir (vurgulanır), app bar'da beliren
  // yazıcı ikonuna basınca O satır yazdırılır. Sadece gerçek bir belgesi
  // olan tipler seçilebilir (Satış/Toptan Satış → fiş, Tahsilat/Odeme →
  // makbuz) — "...İptali" gibi salt-audit satırların basılacak bir belgesi
  // yok.
  static const _yazdirilabilirTipler = {
    'Satış', 'Toptan Satış', 'Tahsilat', 'Odeme',
  };
  // Çoklu seçim (2026-10-01): uzun basarak birden fazla fiş seçilebilir —
  // tek seçimde yazdır, seçili Satış fişlerinde "Son fiyata göre güncelle".
  final Set<CariHareketModel> _secimler = {};
  CariHareketModel? get _seciliHareket =>
      _secimler.length == 1 ? _secimler.first : null;
  set _seciliHareket(CariHareketModel? v) {
    _secimler.clear();
    if (v != null) _secimler.add(v);
  }
  bool _yazdiriliyor = false;

  MusteriIstatistik? _istatistik;
  MusteriSegmenti? _segment;
  bool _analizYukl = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (_secimler.isNotEmpty) setState(() => _secimler.clear());
    });
    _hareketYukle();
    if (widget.cari.cariTipi.contains('Müşteri')) _analizYukle();
  }

  // 🔴 DÜZELTME (derin analizde bulundu): "Düzenle"/"Tahsilat-Ödeme"
  // sonrası dışarıdan (CariDetayEkrani.build) cariDetayProvider
  // invalidate edilip YENİ bir `cari` bu State'e widget.cari olarak
  // geliyordu, ama _analizYukle() SADECE initState()'te çağrıldığı için
  // (Flutter aynı State nesnesini koruyor) 360° sekmesi tahsilat/
  // düzenleme sonrası ESKİ risk oranını/segmenti göstermeye devam
  // ediyordu — ör. bir tahsilat müşteriyi "Riskli"den çıkarsa bile.
  @override
  void didUpdateWidget(covariant _CariDetayIcerik oldWidget) {
    super.didUpdateWidget(oldWidget);
    final degisti = oldWidget.cari.bakiye != widget.cari.bakiye ||
        oldWidget.cari.limitTutari != widget.cari.limitTutari ||
        oldWidget.cari.cariTipi != widget.cari.cariTipi;
    if (degisti && widget.cari.cariTipi.contains('Müşteri')) _analizYukle();
  }

  Future<void> _analizYukle() async {
    if (!mounted) return;
    setState(() => _analizYukl = true);
    try {
      final servis = Musteri360Servisi();
      final c = widget.cari;
      final istat = await servis.istatistikGetir(c.id!);
      final segment = await servis.segmentGetir(c.id!,
          istatistik: istat, bakiye: c.bakiye, limitTutari: c.limitTutari);
      if (mounted) {
        setState(() {
          _istatistik = istat;
          _segment = segment;
          _analizYukl = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CariDetay analizYukle hata: $e');
      if (mounted) setState(() => _analizYukl = false);
    }
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _hareketYukle() async {
    if (!mounted) return;
    setState(() => _yukl = true);
    try {
      final h = await CariDeposu().hareketleriniGetir(widget.cari.id!);
      // 🔴 DÜZELTME (kullanıcı bulgusu, 2026-09-20): Karma ödemeli bir
      // satışta hem Cari hem Cari-dışı (Nakit/Kart/Havale) payı varsa,
      // SatisTamamlamaServisi.tamamla() AYNI satış için 2 ayrı
      // cari_hareket satırı yazıyor (gerçek Cari borcu + bakiyeyi
      // etkilemeyen bilgi amaçlı satır — bkz. o dosyanın yorumu). Bu,
      // burada AYNI satışın 2 ayrı "Satış" kartı gibi görünmesine yol
      // açıyordu — kullanıcı: "listeye bakınca 2 tane fiş görünce kafa
      // karışıklığı oluyor". cariHareketleriniGrupla() aynı fis_id'ye
      // sahip 'Satış' satırlarını TEK karta birleştirir (net bakiye
      // etkisi korunur); tam ödeme dağılımı artık Satış Detayı'nda
      // gösteriliyor (bkz. satis_detay_ekrani.dart).
      if (mounted) setState(() { _hareketler = cariHareketleriniGrupla(h); _yukl = false; });
    } catch (e) {
      if (kDebugMode) debugPrint('CariDetay hareketYukle hata: $e');
      if (mounted) setState(() => _yukl = false);
    }
  }

  Color get _bakiyeRenk {
    final c = widget.cari;
    if (c.bakiye == 0) return context.textSecondary;
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? Colors.green.shade700 : Colors.blue.shade700;
    return c.bakiye < 0 ? Colors.red.shade700 : Colors.blue.shade700;
  }

  String get _bakiyeEtiket {
    final c = widget.cari;
    if (c.bakiye == 0) return 'Dengede';
    final musteri = c.cariTipi.contains('Müşteri');
    if (musteri) return c.bakiye > 0 ? 'Alacağımız' : 'Fazla Ödedi';
    return c.bakiye < 0 ? 'Borcumuz' : 'Fazla Ödedik';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cari;
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslikWidget: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(c.unvan, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          _eFaturaRozeti(c),
        ]),
        aksiyonlar: [
          if (_secimler.isNotEmpty) ...[
            if (_seciliHareket != null)
            IconButton(
              icon: _yazdiriliyor
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_outlined, color: Colors.white),
              tooltip: 'Seçili fişi/makbuzu yazdır',
              onPressed: _yazdiriliyor ? null : _seciliYazdir,
            ),
            if (ref.read(authProvider).isMudur)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'Seçili fişler için işlemler',
                onSelected: (v) {
                  if (v == 'fiyat') _seciliFisleriFiyatGuncelle();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'fiyat',
                    child: Text('Son fiyata göre güncelle'),
                  ),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Seçimi iptal et',
              onPressed: () => setState(() => _secimler.clear()),
            ),
          ],
          if (c.cariTipi.contains('Müşteri'))
            IconButton(
              icon: const Icon(Icons.stars_outlined, color: Colors.amber),
              tooltip: 'Puanlar',
              onPressed: () => context.push('/cari/puan/${c.id}',
                  extra: {'unvan': c.unvan}),
            ),
          if (c.musteriTipi == 'Bayi' && ref.read(authProvider).isMudur)
            IconButton(
              icon: const Icon(Icons.badge_outlined, color: Colors.white),
              tooltip: 'Bayi Girişi',
              onPressed: () => _bayiGirisiYonet(context, c),
            ),
          if (c.cariTipi.contains('Müşteri') && c.bakiye > 0 && ref.read(authProvider).isMudur)
            IconButton(
              icon: const Icon(Icons.money_off, color: Colors.white),
              tooltip: 'Borç Sil',
              onPressed: () => _borcSil(context, c),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Düzenle',
            onPressed: () => context.push('/cari/ekle', extra: c).then((_) {
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
            }),
          ),
        ],
        alt: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Bilgi'),
            Tab(text: 'Hareketler'),
            Tab(text: '360°'),
          ],
        ),
      ),
      body: TabBarView(controller: _tab, children: [
        _bilgiTab(context, c),
        _hareketTab(),
        _analizTab(context, c),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'hareket',
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/cari/hareket/${c.id}'),
            tooltip: 'Hareket Ekle',
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
        elevation: 6,
            heroTag: 'tahsilat',
            backgroundColor: AppRenkler.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Tahsilat/Ödeme'),
            onPressed: () async {
              await context.push('/cari/tahsilat/${c.id}');
              // Kullanıcı bu arada başka ekrana geçtiyse bu ekran kapanmıştır.
              if (!mounted) return;
              ref.invalidate(cariDetayProvider(c.id!));
              ref.read(carilerProvider.notifier).yukle();
              _hareketYukle();
            },
          ),
        ],
      ),
    );
  }

  bool _mukellefSorguluyor = false;

}
