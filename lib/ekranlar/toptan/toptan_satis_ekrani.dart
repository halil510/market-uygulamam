// lib/ekranlar/toptan/toptan_satis_ekrani.dart
//
// Kullanıcı isteği: "toptan satış — Ülker gibi firmaların kullandığı
// profesyonel sistem, Logo gibi yazılımlar gibi görsel olsun, e-Fatura/
// e-Arşiv ile entegre olsun." Bu ekran mevcut satış altyapısını
// (SatisDeposu, StokDeposu, CariDeposu) ve mevcut faturalandırma
// zincirini (FaturalandirmaServisi — satış detay ekranıyla AYNI,
// kanıtlanmış akış) kullanıyor; üstüne fiyat grubu/kademe/koli-adet-kg
// hesaplama katmanı ve "Logo tarzı" fatura-önizleme görünümlü sepet
// ekliyor.
import 'package:flutter/material.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';
import '../../modeller/urun_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/satis_model.dart';
import '../../modeller/satis_kalem_model.dart';
import '../../modeller/fatura_model.dart';
import '../../depolar/urun_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../veri/database/veritabani.dart';
import '../../servisler/fiyat_hesaplama_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/auth_servisi.dart';
import '../../servisler/aktif_sube_servisi.dart';
import '../../servisler/onay_merkezi_servisi.dart';
import '../../servisler/toptan_satis_islem_servisi.dart';

class _SepetKalemi {
  final UrunModel urun;
  double miktar;
  String birim; // 'adet' | 'koli' | 'kg'
  FiyatSonucu fiyatSonucu;
  _SepetKalemi(
      {required this.urun,
      required this.miktar,
      required this.birim,
      required this.fiyatSonucu});

  double get kdvOran => double.tryParse(urun.kdvOran) ?? 18;
  // 🔴 DÜZELTME: Önceki hâli "birim fiyat KDV DAHİL" varsayıp ters
  // çıkarma yapıyordu — bu, ekranda gösterilen özet ile gerçekte
  // satışa/faturaya kaydedilen tutarların UYUŞMAMASINA yol açıyordu.
  // Projenin kurulu kuralı (bkz. sepet_model.dart): toplamTutar =
  // müşteriden tahsil edilen tutarın ta kendisi; kdvTutar bundan
  // ÇARPILARAK (raporlama amaçlı) türetilir.
  double get toplamTutar => miktar * fiyatSonucu.birimFiyat;
  double get kdvTutari => toplamTutar * (kdvOran / 100);
  // Stoktan gerçekte düşülecek miktar (koli ise adede çevrilir).
  double get stokMiktari => (birim == 'koli' && urun.koliIciMiktar > 0)
      ? miktar * urun.koliIciMiktar
      : miktar;
}

class ToptanSatisEkrani extends StatefulWidget {
  // Kullanıcı isteği: "cariye girip satış dedik mi o bayi seçili
  // gelsin" + "çoğalt dedik mi eski siparişin kalemleri gelsin."
  final CariModel? baslangicBayi;
  final int?
      tekrarSatisId; // "Çoğalt" — bu satışın kalemleri fiyatlar TAZE hesaplanarak yeniden eklenir
  const ToptanSatisEkrani({super.key, this.baslangicBayi, this.tekrarSatisId});

  @override
  State<ToptanSatisEkrani> createState() => _ToptanSatisEkraniState();
}

class _ToptanSatisEkraniState extends State<ToptanSatisEkrani> {
  final _cariDepo = CariDeposu();
  final _urunDepo = UrunDeposu();
  final _fiyatServisi = FiyatHesaplamaServisi();

  CariModel? _secilenBayi;
  final List<_SepetKalemi> _sepet = [];
  final _aramaCtrl = TextEditingController();
  List<UrunModel> _aramaSonuclari = [];
  bool _kaydediliyor = false;

  double get _kdvToplam => _sepet.fold(0.0, (s, k) => s + k.kdvTutari);
  double get _genelToplam => _sepet.fold(0.0, (s, k) => s + k.toplamTutar);

  @override
  void initState() {
    super.initState();
    _secilenBayi = widget.baslangicBayi;
    if (widget.tekrarSatisId != null) {
      // "Çoğalt" — eski build tamamlanana kadar bekleyip sepeti doldur.
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _eskiSiparisiCogalt(widget.tekrarSatisId!));
    }
  }

  /// Kullanıcı isteği: "Çoğalt dedik mi eski siparişin kalemleri
  /// gelsin." Eski satışın kalemlerini okuyup, HER BİRİ İÇİN fiyatı
  /// YENİDEN (güncel fiyat/kademe/kredi durumuna göre) hesaplayarak
  /// sepete ekler — eski, artık geçersiz olabilecek bir fiyatı körü
  /// körüne kopyalamak yerine bilinçli olarak TAZE fiyat kullanılır.
  Future<void> _eskiSiparisiCogalt(int satisId) async {
    try {
      final db = await Veritabani().db;
      final kalemler = await db
          .query('satis_kalem', where: 'satis_id = ?', whereArgs: [satisId]);
      for (final k in kalemler) {
        final urunId = k['urun_id'] as int?;
        if (urunId == null) continue;
        final urun = await _urunDepo.idileGetir(urunId);
        if (urun == null) continue;
        final miktar = (k['miktar'] as num?)?.toDouble() ?? 1;
        final fiyatSonucu = await _fiyatServisi.hesapla(
          urun: urun,
          cari: _secilenBayi,
          miktar: miktar,
          birim: 'adet',
        );
        if (!mounted) return;
        setState(() {
          _sepet.add(_SepetKalemi(
              urun: urun,
              miktar: miktar,
              birim: 'adet',
              fiyatSonucu: fiyatSonucu));
        });
      }
      if (mounted && kalemler.isNotEmpty) {
        BildirimServisi.basari(
            context, 'Önceki sipariş kalemleri güncel fiyatlarla eklendi');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Sipariş çoğaltılamadı: $e');
    }
  }

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _bayiSec() async {
    final tumCariler = await _cariDepo.tumunuGetir();
    // 🔴 DÜZELTME (kullanıcı bulgusu — "bayi/müşteri/tedarikçi doğru
    // mu"): Aynı düzeltme (bkz. toptan_dashboard_ekrani.dart) — saf
    // bir tedarikçi, musteriTipi yanlışlıkla "Bayi"/"Toptan" ise bu
    // satış listesinde görünmemeli.
    final bayiler = tumCariler
        .where((c) =>
            c.cariTipi.contains('Müşteri') &&
            (c.musteriTipi == 'Bayi' || c.musteriTipi == 'Toptan'))
        .toList();
    if (!mounted) return;
    if (bayiler.isEmpty) {
      BildirimServisi.hata(
          context,
          'Henüz "Bayi" veya "Toptan" tipinde cari yok. Cari kartından '
          'müşteri tipini "Bayi/Toptan" yapın.');
      return;
    }
    final secilen = await showModalBottomSheet<CariModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (c, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: TsRenk.arkaplan(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(TsRadius.xl)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(TsBosluk.lg),
              child: Text('Bayi / Toptan Müşteri Seç',
                  style: TsMetin.baslikM
                      .copyWith(color: TsRenk.metinBirincil(context))),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
                itemCount: bayiler.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TsBosluk.sm),
                itemBuilder: (c, i) {
                  final b = bayiler[i];
                  return TsKart.liste(
                    baslik: b.unvan,
                    altBaslik:
                        '${b.musteriTipi} · Bakiye: ${ParaUtils.formatla(b.bakiye)}',
                    ikon: CircleAvatar(
                      backgroundColor: TsRenk.zemin(TsRenk.primary),
                      child: Text(
                          b.unvan.isNotEmpty ? b.unvan[0].toUpperCase() : '?',
                          style: TextStyle(
                              color: TsRenk.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                    onTap: () => Navigator.pop(c, b),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (secilen != null) {
      setState(() {
        _secilenBayi = secilen;
        _sepet.clear();
      });
    }
  }

  Future<void> _urunAra(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _aramaSonuclari = []);
      return;
    }
    final sonuc = await _urunDepo.ara(q.trim());
    if (mounted) setState(() => _aramaSonuclari = sonuc);
  }

  Future<void> _urunEkle(UrunModel urun) async {
    _aramaCtrl.clear();
    setState(() => _aramaSonuclari = []);

    String birim = urun.satisBirimiTipi == 'kg' ? 'kg' : 'adet';
    double miktar = 1;

    final sonuc = await showDialog<(double, String)>(
      context: context,
      builder: (c) => _MiktarBirimDialog(
          urun: urun, baslangicBirim: birim, baslangicMiktar: miktar),
    );
    if (sonuc == null) return;
    miktar = sonuc.$1;
    birim = sonuc.$2;
    if (miktar <= 0) return;

    final fiyatSonucu = await _fiyatServisi.hesapla(
      urun: urun,
      cari: _secilenBayi,
      miktar: miktar,
      birim: birim,
    );

    setState(() {
      final mevcutIdx =
          _sepet.indexWhere((k) => k.urun.id == urun.id && k.birim == birim);
      if (mevcutIdx >= 0) {
        _sepet[mevcutIdx].miktar += miktar;
      } else {
        _sepet.add(_SepetKalemi(
            urun: urun,
            miktar: miktar,
            birim: birim,
            fiyatSonucu: fiyatSonucu));
      }
    });
  }

  void _kalemSil(int index) => setState(() => _sepet.removeAt(index));

  String _birimEtiket(String birim) => switch (birim) {
        'koli' => 'Koli',
        'kg' => 'Kg',
        _ => 'Adet',
      };

  /// Fatura ızgarası başlık hücresi (ÜRÜN/MİKTAR/TUTAR gibi).
  Widget _gridBaslikHucre(String metin,
          {required int flex, bool ortala = false, bool sagaYasla = false}) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Text(metin,
              textAlign: ortala
                  ? TextAlign.center
                  : (sagaYasla ? TextAlign.right : TextAlign.left),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: TsRenk.metinIkincil(context))),
        ),
      );

  /// Fatura ızgarası veri hücresi — rakamlar hizalı (FontFeature.tabularFigures).
  Widget _gridHucre(String metin,
          {required int flex,
          bool ortala = false,
          bool sagaYasla = false,
          bool kalin = false,
          bool sonuk = false}) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(metin,
              textAlign: ortala
                  ? TextAlign.center
                  : (sagaYasla ? TextAlign.right : TextAlign.left),
              style: TextStyle(
                fontSize: 12,
                fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
                color: sonuk
                    ? TsRenk.metinIkincil(context)
                    : TsRenk.metinBirincil(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );

  Future<void> _satisiTamamla() async {
    if (_secilenBayi == null || _sepet.isEmpty || _kaydediliyor) return;
    // 🔴 Derin analizde bulundu: guard bayrağı (_kaydediliyor) önceden
    // buradaki iki await'ten (limitKontrolEt + olası onay dialog'u)
    // SONRA true yapılıyordu — o sırada buton hâlâ etkin kalıyordu. Hızlı
    // bir çift dokunma, ikinci çağrının da guard'ı hâlâ false görmesine
    // ve aynı toptan satışın STOK ve CARİ BORCU İKİ KEZ işlenerek
    // mükerrer kaydedilmesine yol açabilirdi (diğer ekranlar — alim_ekrani,
    // bayi_siparis_al_ekrani — bayrağı doğru şekilde ilk await'ten önce
    // set ediyor). Artık en baştan, herhangi bir await'ten önce set
    // ediliyor.
    setState(() => _kaydediliyor = true);
    ({double tutar, double esik, String aciklama})? riskOnayBilgisi;
    try {
      final limitSonuc =
          await _cariDepo.limitKontrolEt(_secilenBayi!.id!, _genelToplam);
      if (limitSonuc.asildi && mounted) {
        final devam = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
              SizedBox(width: 8),
              Text('Kredi Limiti Aşılıyor'),
            ]),
            content: Text(
              '${_secilenBayi!.unvan} için tanımlı kredi limiti: '
              '${ParaUtils.formatla(limitSonuc.limit)}\n'
              'Mevcut bakiye: ${ParaUtils.formatla(limitSonuc.mevcutBakiye)}\n'
              'Bu satışla birlikte: ${ParaUtils.formatla(limitSonuc.mevcutBakiye + _genelToplam)}\n\n'
              'Limit ${ParaUtils.formatla(limitSonuc.asimTutari)} kadar aşılacak. '
              'Yine de devam etmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: TsRenk.uyari),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Yine de Devam Et'),
              ),
            ],
          ),
        );
        if (devam != true) return;
        // FAZ 9 — Onay Merkezi (bildirim tipi): satış ENGELLENMEDİ,
        // kullanıcı zaten "Yine de Devam Et" dedi. Kayıt burada HEMEN
        // düşürülMÜYOR — 🔴 DÜZELTME (derin analizde bulundu): önceden
        // buradan düşürülüyordu, yani satış transaction'ı SONRADAN
        // (stok yetersizliği/exception ile) başarısız olsa bile Onay
        // Merkezi'nde hiç gerçekleşmemiş bir satış için yanlış-pozitif
        // bir "risk aşımı" kaydı kalıyordu. Artık sadece bilgi
        // saklanıyor; gerçek kayıt aşağıda transaction BAŞARIYLA
        // bittikten sonra düşürülüyor (diğer 6 onay hook'uyla aynı desen).
        riskOnayBilgisi = (
          tutar: limitSonuc.mevcutBakiye + _genelToplam,
          esik: limitSonuc.limit,
          aciklama: '${_secilenBayi!.unvan}: limit ${ParaUtils.formatla(limitSonuc.limit)}, '
              'aşım ${ParaUtils.formatla(limitSonuc.asimTutari)}',
        );
      }

      final kullanici = AuthServisi().aktifKullanici;
      final tarih = DateTime.now();
      final fisNo = await Veritabani()
          .fisNoUret('cari_satis', subeId: AktifSubeServisi().subeId ?? 1);

      final satisKalemler = _sepet.map((k) {
        final kdvOran = double.tryParse(k.urun.kdvOran) ?? 18;
        // 🔴 DÜZELTME: Projenin kurulu KDV kuralı (bkz. sepet_model.dart
        // içindeki açık dokümantasyon): 'toplamTutar' MÜŞTERİDEN TAHSİL
        // EDİLEN tutarın ta kendisidir (üzerine ayrıca KDV eklenmez) —
        // kdvTutar, bu tutardan SADECE raporlama/fatura kırılımı için
        // ÇARPILARAK hesaplanır (ters çıkarma DEĞİL).
        final kdvTutar = k.toplamTutar * (kdvOran / 100);
        final birimFiyatStokBazli = k.fiyatSonucu.birimFiyat /
            (k.birim == 'koli' && k.urun.koliIciMiktar > 0
                ? k.urun.koliIciMiktar
                : 1);
        return SatisKalemModel(
          satisId: 0,
          urunId: k.urun.id!,
          urunAdi: '${k.urun.urunAdi} (${_birimEtiket(k.birim)})',
          barkod: k.urun.barkod,
          miktar: k.stokMiktari, // stok her zaman ADET/KG cinsinden tutulur
          birimFiyat: birimFiyatStokBazli,
          toplamTutar: k.toplamTutar,
          iskontoOran: 0,
          iskontoTutar: 0,
          kdvOran: kdvOran,
          kdvTutar: kdvTutar,
          netFiyat:
              birimFiyatStokBazli, // KDV hariç net birim fiyat (iskonto yok)
          alisFiyat: k.urun.alisFiyat,
          alisFiyatKdv: k.urun.alisFiyatKdvDahil,
        );
      }).toList();

      final satis = SatisModel(
        fisNo: fisNo,
        tarih: tarih,
        cariId: _secilenBayi!.id,
        cariAdi: _secilenBayi!.unvan,
        toplamTutar: _genelToplam,
        genelToplam: _genelToplam,
        odenenTutar: 0,
        odemeYontemi: 'Cari',
        fisTipi: 'Toptan Satış',
        kasiyerId: kullanici?.id,
        kullaniciId: kullanici?.id,
      );

      // Satış + stok (FEFO) + cari hareketi artık ToptanSatisIslemServisi
      // içinde TEK transaction'da atomik olarak yürütülüyor (uygulama
      // ortada kapanırsa satış kaydedilip stok düşülmemiş, bayinin
      // carisine borç yazılmamış olabiliyordu — bkz. o servisin doc
      // yorumu), davranış birebir korundu.
      final satisId = await ToptanSatisIslemServisi().satisKaydet(
        satis: satis,
        kalemler: satisKalemler,
        stokKalemleri: _sepet
            .map((k) => ToptanStokKalemi(
                urunId: k.urun.id!, stokMiktari: k.stokMiktari))
            .toList(),
        cariId: _secilenBayi!.id!,
        fisNo: fisNo,
        genelToplam: _genelToplam,
        kullaniciId: kullanici?.id,
        kullaniciAdi: kullanici?.adSoyad,
      );

      // ══════════════════════════════════════════════════════════════
      // 🔴 KRİTİK DÜZELTME (kullanıcı bulgusu — "toptan satış sonrası
      // Cari'de detay gözükmüyor")
      //
      // Bu ekran ConsumerState DEĞİL — düz State. Cari hareketi yukarıda
      // doğru yazılıyor (bakiye de doğru güncelleniyor), ama Genel Cari
      // modülündeki detay ekranı (cari_detay_ekrani.dart) bu veriyi
      // `cariDetayProvider` adlı bir Riverpod cache'inden okuyor.
      //
      // Uygulamadaki HER DİĞER cari-yazan ekran (iade x4, masa, cari
      // hareket, tahsilat/ödeme) yazdıktan hemen sonra
      // `ref.invalidate(cariDetayProvider(cariId))` çağırıyor. Bu ekran
      // ConsumerState olmadığı için o çağrıyı hiç yapmıyordu.
      //
      // Sonuç: kullanıcı toptan satışı bitirip Cari modülünden aynı
      // cariye bakınca (özellikle sekme/IndexedStack ile o ekran daha
      // önce açılıp bellekte kalmışsa) YENİ satış görünmüyordu — cache
      // bayatlamıştı. Tarayıcıyı/uygulamayı kapatıp açınca ya da o
      // ekranı zorla yeniden açınca fark edilmiyordu; asıl belirti,
      // ekranı kapatmadan tekrar bakınca eski veri görünmesiydi.
      //
      // ÇÖZÜM: `ProviderScope.containerOf` — bu ekranın ConsumerState'e
      // çevrilmesini gerektirmeyen, projede zaten kullanılan (bkz.
      // uygulama.dart) güvenli bir yöntem.
      // ══════════════════════════════════════════════════════════════
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .invalidate(cariDetayProvider(_secilenBayi!.id!));
      }

      // Tüm veritabanı yazmaları bitti — buradan sonrası arayüz.
      // FAZ 9 — Onay Merkezi (bildirim tipi): satış artık GERÇEKTEN
      // kalıcı olduğu için (transaction başarıyla bitti) risk aşımı
      // kaydı burada, satisId referansıyla düşürülüyor.
      if (riskOnayBilgisi != null) {
        OnayMerkeziServisi().kaydet(
          tur: OnayTuru.riskAsimi,
          tutar: riskOnayBilgisi.tutar,
          esikTutar: riskOnayBilgisi.esik,
          referansTuru: 'satis',
          referansId: satisId,
          aciklama: riskOnayBilgisi.aciklama,
        );
      }
      if (!mounted) return;

      // 🔴 DÜZELTME: aşağıdaki setState `_secilenBayi`'yi null yapıyor,
      // ama fatura kesme adımı (birkaç satır aşağıda) onu kullanıyordu.
      // Sonuç: kasiyer "Fatura Kes"e basınca _faturalandir() içindeki
      // `if (bayiSnapshot?.id == null) return;` sessizce çalışıyor,
      // hiçbir şey olmuyor, hata da gösterilmiyordu.
      // Parametrenin adı zaten `bayiSnapshot` — niyet kopya almaktı,
      // ama kopya hiç alınmamıştı. Artık alınıyor.
      final bayiSnapshot = _secilenBayi;
      final bayiUnvan = bayiSnapshot!.unvan;
      setState(() {
        _sepet.clear();
        _secilenBayi = null;
      });

      // Kullanıcı isteği: "e-Fatura/e-Arşiv ile entegre olsun." Satış
      // tamamlanınca, mevcut (kanıtlanmış) faturalandırma zincirine
      // (satış detay ekranıyla AYNI akış) hemen geçiş sunuluyor.
      if (!mounted) return;
      final faturaKes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: TsRenk.basarili),
            SizedBox(width: 8),
            Text('Satış Tamamlandı'),
          ]),
          content: Text('$bayiUnvan için $fisNo numaralı toptan satış '
              'kaydedildi.\n\nŞimdi bu satış için fatura kesmek ister misiniz?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Şimdi Değil')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Fatura Kes')),
          ],
        ),
      );
      if (faturaKes == true) {
        await _faturalandir(satisId, bayiSnapshot, tarih, satisKalemler);
      } else if (mounted) {
        BildirimServisi.basari(context, 'Toptan satış tamamlandı: $fisNo');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Satış kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  /// Mevcut satış → fatura zincirini (satis_detay_ekrani.dart ile AYNI,
  /// kanıtlanmış FaturalandirmaServisi akışı) kullanarak fatura oluşturur.
  Future<void> _faturalandir(int satisId, CariModel? bayiSnapshot,
      DateTime tarih, List<SatisKalemModel> satisKalemler) async {
    if (bayiSnapshot?.id == null) return;
    try {
      final kontrol = await FaturalandirmaServisi.kontrolEt(bayiSnapshot!.id!);
      if (kontrol == null) {
        if (mounted) BildirimServisi.hata(context, 'Cari bulunamadı.');
        return;
      }
      if (!kontrol.hazir) {
        if (!mounted) return;
        final git = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TsRadius.xl)),
            title: Row(children: [
              Icon(Icons.warning_amber_rounded, color: TsRenk.uyari),
              const SizedBox(width: 8),
              const Text('Eksik Cari Bilgisi'),
            ]),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${kontrol.cari.unvan} için fatura kesilebilmesi için '
                      'aşağıdaki bilgiler eksik:'),
                  const SizedBox(height: 10),
                  ...kontrol.eksikAlanlar.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Icon(Icons.circle, size: 6, color: TsRenk.uyari),
                          const SizedBox(width: 8),
                          Text(e),
                        ]),
                      )),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cari Düzenle')),
            ],
          ),
        );
        if (git == true && mounted)
          await context.push('/cari/ekle', extra: kontrol.cari);
        return;
      }

      final detaylar = satisKalemler
          .map((k) => FaturaDetayModel(
                urunId: k.urunId,
                urunAdi: k.urunAdi,
                barkod: k.barkod,
                miktar: k.miktar,
                birimFiyat: k.birimFiyat,
                iskontoOrani: k.iskontoOran,
                iskontoTutari: k.iskontoTutar,
                kdvOrani: k.kdvOran,
                kdvTutari: k.kdvTutar,
                araToplam: k.miktar * k.birimFiyat,
                toplamTutar: k.toplamTutar,
              ))
          .toList();

      final yeniId = await FaturalandirmaServisi.faturaOlustur(
        kontrol: kontrol,
        kalemler: detaylar,
        faturaTipi: 'Satis',
        satisId: satisId,
        tarih: tarih,
        odenenTutar: 0,
      );

      if (!mounted) return;
      BildirimServisi.basari(context, 'Fatura oluşturuldu ✓');
      context.push('/fatura/detay/$yeniId');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Faturalandırma hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Toptan Satış',
        altBaslik: _secilenBayi?.unvan,
        gradyanli: true,
      ),
      body: Column(children: [
        // ── Bayi Bilgi Kartı (Logo-tarzı: bakiye + limit görsel özet) ──
        Container(
          margin: const EdgeInsets.all(TsBosluk.md),
          child: InkWell(
            onTap: _bayiSec,
            borderRadius: BorderRadius.circular(TsRadius.lg),
            child: Container(
              padding: const EdgeInsets.all(TsBosluk.lg),
              decoration: BoxDecoration(
                gradient: _secilenBayi == null
                    ? null
                    : LinearGradient(
                        colors: [
                          TsRenk.zemin(TsRenk.primary, opaklik: 0.10),
                          TsRenk.zemin(TsRenk.primary, opaklik: 0.03)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: _secilenBayi == null ? TsRenk.kart(context) : null,
                borderRadius: BorderRadius.circular(TsRadius.lg),
                border: Border.all(
                    color: _secilenBayi == null
                        ? TsRenk.zemin(TsRenk.uyari, opaklik: 0.4)
                        : TsRenk.primary,
                    width: 1.5),
                boxShadow: TsGolge.yumusak,
              ),
              child: _secilenBayi == null
                  ? Row(children: [
                      Icon(Icons.storefront, color: TsRenk.uyari),
                      const SizedBox(width: TsBosluk.sm),
                      Expanded(
                          child: Text('Bayi/Toptan Müşteri Seçin',
                              style: TsMetin.govdeVurgu.copyWith(
                                  color: TsRenk.metinBirincil(context)))),
                      const Icon(Icons.chevron_right),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: TsRenk.primary,
                              child: Text(
                                  _secilenBayi!.unvan.isNotEmpty
                                      ? _secilenBayi!.unvan[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: TsBosluk.md),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_secilenBayi!.unvan,
                                        style: TsMetin.baslikM.copyWith(
                                            color:
                                                TsRenk.metinBirincil(context))),
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: TsRenk.zemin(TsRenk.primary),
                                          borderRadius: BorderRadius.circular(
                                              TsRadius.sm)),
                                      child: Text(_secilenBayi!.musteriTipi,
                                          style: TsMetin.kucuk.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: TsRenk.primary)),
                                    ),
                                  ]),
                            ),
                            IconButton(
                                icon: const Icon(Icons.swap_horiz),
                                tooltip: 'Bayi Değiştir',
                                onPressed: _bayiSec),
                          ]),
                          const SizedBox(height: TsBosluk.sm),
                          Row(children: [
                            Expanded(
                                child: _MiniIstatistik(
                                    baslik: 'Bakiye',
                                    deger: ParaUtils.formatla(
                                        _secilenBayi!.bakiye),
                                    renk: _secilenBayi!.bakiye > 0
                                        ? TsRenk.uyari
                                        : TsRenk.basarili)),
                            if (_secilenBayi!.limitTutari > 0)
                              Expanded(
                                  child: _MiniIstatistik(
                                      baslik: 'Kredi Limiti',
                                      deger: ParaUtils.formatla(
                                          _secilenBayi!.limitTutari),
                                      renk: TsRenk.primary)),
                          ]),
                        ]),
            ),
          ),
        ),

        if (_secilenBayi != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Ürün ara (ad, barkod, kod)...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: TsRenk.zemin(TsRenk.notr, opaklik: 0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TsRadius.md),
                    borderSide: BorderSide.none),
              ),
              onChanged: _urunAra,
            ),
          ),
          if (_aramaSonuclari.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(TsBosluk.md, 4, TsBosluk.md, 0),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                  color: TsRenk.kart(context),
                  borderRadius: BorderRadius.circular(TsRadius.lg),
                  border: Border.all(color: TsRenk.ayirac(context)),
                  boxShadow: TsGolge.yumusak),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(TsBosluk.sm),
                itemCount: _aramaSonuclari.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TsBosluk.xs),
                itemBuilder: (c, i) {
                  final u = _aramaSonuclari[i];
                  return TsKart.liste(
                    baslik: u.urunAdi,
                    altBaslik:
                        'Stok: ${u.stok.toStringAsFixed(0)} ${u.birimAdi}'
                        '${u.koliIciMiktar > 0 ? " · 1 ${u.koliBirimAdi} = ${u.koliIciMiktar.toStringAsFixed(0)} ${u.birimAdi}" : ""}',
                    ikon: const Icon(Icons.inventory_2_outlined),
                    sagAksiyon: Icon(Icons.add_circle_rounded,
                        color: TsRenk.basarili, size: 24),
                    onTap: () => _urunEkle(u),
                  );
                },
              ),
            ),
          const SizedBox(height: TsBosluk.sm),

          // ── Sepet: GERÇEK fatura kalemi ızgarası (Logo/Netsis tarzı) ──
          // Kart listesi DEĞİL — ince kenarlıklı, zebra çizgili, sıra
          // numaralı, hizalı rakamlı klasik muhasebe tablosu. Bu, tam
          // olarak istenen "profesyonel ERP" görünümü — sadece renk/
          // boşluk tokenleri modernize edildi, düzeni korundu.
          if (_sepet.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: TsBosluk.md),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.primary, opaklik: 0.05),
                border: Border.all(color: TsRenk.ayirac(context)),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(TsRadius.sm)),
              ),
              child: Row(children: [
                _gridBaslikHucre('#', flex: 1, ortala: true),
                _gridBaslikHucre('ÜRÜN', flex: 6),
                _gridBaslikHucre('MİKTAR', flex: 3, ortala: true),
                _gridBaslikHucre('B.FİYAT', flex: 3, sagaYasla: true),
                _gridBaslikHucre('KDV%', flex: 2, ortala: true),
                _gridBaslikHucre('TUTAR', flex: 3, sagaYasla: true),
                const SizedBox(width: 32),
              ]),
            ),
          Expanded(
            child: _sepet.isEmpty
                ? TsBosDurum(
                    ikon: Icons.shopping_cart_outlined,
                    baslik: 'Sepet boş',
                    altyazi: 'Ürün arayıp ekleyin',
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(
                        TsBosluk.md, 0, TsBosluk.md, 0),
                    decoration: BoxDecoration(
                      color: TsRenk.kart(context),
                      border: Border(
                        left: BorderSide(color: TsRenk.ayirac(context)),
                        right: BorderSide(color: TsRenk.ayirac(context)),
                        bottom: BorderSide(color: TsRenk.ayirac(context)),
                      ),
                      boxShadow: TsGolge.yumusak,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _sepet.length,
                      itemBuilder: (c, i) {
                        final k = _sepet[i];
                        final kdvOran = double.tryParse(k.urun.kdvOran) ?? 18;
                        final ciftMi = i.isEven;
                        return Column(children: [
                          Container(
                            color: ciftMi
                                ? TsRenk.zemin(TsRenk.notr, opaklik: 0.04)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _gridHucre('${i + 1}',
                                      flex: 1, ortala: true, sonuk: true),
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(k.urun.urunAdi,
                                                style: TsMetin.govdeVurgu
                                                    .copyWith(
                                                        fontSize: 12.5,
                                                        color: TsRenk
                                                            .metinBirincil(
                                                                context)),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            Text(k.fiyatSonucu.aciklama,
                                                style: TsMetin.kucuk.copyWith(
                                                    color: TsRenk.basarili,
                                                    fontStyle:
                                                        FontStyle.italic),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ]),
                                    ),
                                  ),
                                  _gridHucre(
                                      '${k.miktar.toStringAsFixed(k.miktar == k.miktar.roundToDouble() ? 0 : 1)}\n${_birimEtiket(k.birim)}',
                                      flex: 3,
                                      ortala: true),
                                  _gridHucre(
                                      ParaUtils.formatla(
                                          k.fiyatSonucu.birimFiyat),
                                      flex: 3,
                                      sagaYasla: true),
                                  _gridHucre('%${kdvOran.toStringAsFixed(0)}',
                                      flex: 2, ortala: true, sonuk: true),
                                  _gridHucre(ParaUtils.formatla(k.toplamTutar),
                                      flex: 3, sagaYasla: true, kalin: true),
                                  SizedBox(
                                    width: 32,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: Icon(Icons.close,
                                          size: 15, color: TsRenk.hata),
                                      onPressed: () => _kalemSil(i),
                                    ),
                                  ),
                                ]),
                          ),
                          if (i < _sepet.length - 1)
                            Divider(height: 1, color: TsRenk.ayirac(context)),
                        ]);
                      },
                    ),
                  ),
          ),

          // ── Fatura-tarzı özet paneli: Ara Toplam / KDV / Genel Toplam ──
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              boxShadow: TsGolge.yumusak,
            ),
            child: SafeArea(
              top: false,
              child: Column(children: [
                _OzetSatiri(baslik: 'Ürün Toplamı', deger: _genelToplam),
                _OzetSatiri(
                    baslik: 'Fiyata Dahil KDV (bilgi amaçlı)',
                    deger: _kdvToplam,
                    vurgusuz: true),
                const Divider(height: 16),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GENEL TOPLAM',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(ParaUtils.formatla(_genelToplam),
                          style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: TsRenk.primary)),
                    ]),
                const SizedBox(height: TsBosluk.md),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: TsRenk.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(TsRadius.md))),
                    onPressed: (_sepet.isEmpty || _kaydediliyor)
                        ? null
                        : _satisiTamamla,
                    icon: _kaydediliyor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_kaydediliyor
                        ? 'Kaydediliyor...'
                        : 'Satışı Tamamla (Veresiye)'),
                  ),
                ),
              ]),
            ),
          ),
        ] else
          Expanded(
              child: TsBosDurum(
            ikon: Icons.storefront_outlined,
            baslik: 'Bayi seçilmedi',
            altyazi: 'Devam etmek için bir bayi/toptan müşteri seçin',
          )),
      ]),
    );
  }
}

/// Bayi kartındaki küçük istatistik (bakiye/limit) gösterimi.
class _MiniIstatistik extends StatelessWidget {
  final String baslik;
  final String deger;
  final Color renk;
  const _MiniIstatistik(
      {required this.baslik, required this.deger, required this.renk});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(baslik.toUpperCase(),
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: TsRenk.metinIkincil(context),
                letterSpacing: 0.5)),
        Text(deger,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: renk)),
      ]);
}

/// Fatura-önizleme tarzı özet satırı (Ürün Toplamı / KDV bilgisi gibi).
class _OzetSatiri extends StatelessWidget {
  final String baslik;
  final double deger;
  final bool vurgusuz; // true ise daha soluk/bilgilendirme amaçlı gösterilir
  const _OzetSatiri(
      {required this.baslik, required this.deger, this.vurgusuz = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(baslik,
              style: TextStyle(
                  fontSize: vurgusuz ? 11.5 : 13,
                  color: vurgusuz
                      ? TsRenk.metinIkincil(context)
                      : TsRenk.metinIkincil(context),
                  fontStyle: vurgusuz ? FontStyle.italic : FontStyle.normal)),
          Text(ParaUtils.formatla(deger),
              style: TextStyle(
                  fontSize: vurgusuz ? 11.5 : 13,
                  fontWeight: vurgusuz ? FontWeight.w400 : FontWeight.w600,
                  color: vurgusuz
                      ? TsRenk.metinIkincil(context)
                      : TsRenk.metinBirincil(context))),
        ]),
      );
}

/// Miktar ve birim (adet/koli/kg) seçim dialogu.
class _MiktarBirimDialog extends StatefulWidget {
  final UrunModel urun;
  final String baslangicBirim;
  final double baslangicMiktar;
  const _MiktarBirimDialog(
      {required this.urun,
      required this.baslangicBirim,
      required this.baslangicMiktar});

  @override
  State<_MiktarBirimDialog> createState() => _MiktarBirimDialogState();
}

class _MiktarBirimDialogState extends State<_MiktarBirimDialog> {
  late String _birim;
  final _miktarCtrl = TextEditingController();
  String? _hata;

  @override
  void initState() {
    super.initState();
    _birim = widget.baslangicBirim;
    _miktarCtrl.text = widget.baslangicMiktar.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _miktarCtrl.dispose();
    super.dispose();
  }

  /// Girilen miktarı ürünün TEMEL birimine (adet/kg) çevirir — koli
  /// seçiliyse koli içi adede göre büyütür. Asgari sipariş miktarı hep
  /// temel birim üzerinden tanımlı olduğu için karşılaştırma bununla
  /// yapılmalı, ekrandaki ham miktarla değil.
  double _temelBirimMiktar(double miktar) =>
      (_birim == 'koli' && widget.urun.koliIciMiktar > 0)
          ? miktar * widget.urun.koliIciMiktar
          : miktar;

  @override
  Widget build(BuildContext context) {
    final koliVar = widget.urun.koliIciMiktar > 0;
    final kgUrunu = widget.urun.satisBirimiTipi == 'kg';
    final asgari = widget.urun.asgariSiparisMiktari;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.urun.urunAdi),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _miktarCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Miktar',
            border: const OutlineInputBorder(),
            errorText: _hata,
          ),
          onChanged: (_) {
            if (_hata != null) setState(() => _hata = null);
          },
        ),
        const SizedBox(height: 12),
        if (!kgUrunu)
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'adet', label: Text('Adet')),
              if (koliVar)
                ButtonSegment(
                    value: 'koli', label: Text(widget.urun.koliBirimAdi)),
            ],
            selected: {_birim == 'kg' ? 'adet' : _birim},
            onSelectionChanged: (s) => setState(() {
              _birim = s.first;
              _hata = null;
            }),
          )
        else
          Text('Bu ürün Kg bazında satılıyor',
              style:
                  TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
        if (koliVar && _birim == 'koli')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '1 ${widget.urun.koliBirimAdi} = ${widget.urun.koliIciMiktar.toStringAsFixed(0)} ${widget.urun.birimAdi}',
                style: TextStyle(
                    fontSize: 11, color: TsRenk.metinIkincil(context))),
          ),
        // Profesyonel B2B kuralı: asgari sipariş miktarı (MOQ) tanımlıysa
        // kullanıcıya baştan göster — sürpriz hata yerine önceden bilgi.
        if (asgari > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: 14, color: TsRenk.metinIkincil(context)),
              const SizedBox(width: 4),
              Text(
                  'Asgari sipariş: ${asgari.toStringAsFixed(asgari == asgari.roundToDouble() ? 0 : 1)} ${widget.urun.birimAdi}',
                  style: TextStyle(
                      fontSize: 11.5, color: TsRenk.metinIkincil(context))),
            ]),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final miktar =
                double.tryParse(_miktarCtrl.text.replaceAll(',', '.')) ?? 0;
            if (miktar <= 0) {
              setState(() => _hata = 'Geçerli bir miktar girin');
              return;
            }
            final temelMiktar = _temelBirimMiktar(miktar);
            if (asgari > 0 && temelMiktar < asgari) {
              setState(() => _hata =
                  'Asgari sipariş miktarı ${asgari.toStringAsFixed(asgari == asgari.roundToDouble() ? 0 : 1)} ${widget.urun.birimAdi}');
              return;
            }
            Navigator.pop(context, (miktar, kgUrunu ? 'kg' : _birim));
          },
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
