import 'package:flutter/foundation.dart';
import "../../veri/database/veritabani.dart";
import "../../servisler/yazdirma_servisi.dart";
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saglayicilar/riverpod/cari_provider.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/ts_kart.dart';
// lib/ekranlar/cari/tahsilat_odeme_ekrani.dart
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../../modeller/cari_model.dart";
import "../../modeller/cari_hareket_model.dart";
import "../../depolar/cari_deposu.dart";
import "../../depolar/kasa_deposu.dart";
import "../../depolar/banka_hesap_deposu.dart";
import "../../depolar/banka_hareket_deposu.dart";
import "../../depolar/kredi_karti_deposu.dart";
import "../../modeller/kasa_hareket_model.dart";
import "../../modeller/banka_hareket_model.dart";
import "../../modeller/banka_hesap_model.dart";
import "../../modeller/kredi_karti_model.dart";
import "../../servisler/auth_servisi.dart";
import "../../servisler/bildirim_servisi.dart";
import "../../servisler/bulut/bulut_manager.dart";
import "../../cekirdek/utils/para_utils.dart";

class TahsilatOdemeEkrani extends ConsumerStatefulWidget {
  final int cariId;
  const TahsilatOdemeEkrani({super.key, required this.cariId});
  @override
  ConsumerState<TahsilatOdemeEkrani> createState() =>
      _TahsilatOdemeEkraniState();
}

class _TahsilatOdemeEkraniState extends ConsumerState<TahsilatOdemeEkrani> {
  final CariDeposu _depo = CariDeposu();
  CariModel? _cari;
  bool _yukleniyor = true, _islem = false;
  final _tutarCtrl = TextEditingController();
  final _aciklamaCtrl = TextEditingController();
  String _islemTipi = 'Tahsilat';
  String _odemeTuru = 'Nakit';
  // 🔴 DÜZELTME (kullanıcı bulgusu): "Banka"/"Kredi Kartı" seçilebiliyordu
  // ama HANGİ banka hesabı / HANGİ kart olduğu hiç sorulmuyordu, ve bu
  // seçimler gerçek bir banka/kart hareketi de OLUŞTURMUYORDU — sadece
  // cari bakiyesi değişiyor, şirketin gerçek banka/kart durumu hiç
  // etkilenmiyordu (para "kayboluyordu"). BorcOdemeIslemServisi'ndeki
  // AYNI, doğru çalışan desen buraya da taşındı.
  List<BankaHesapModel> _bankaHesaplari = [];
  List<KrediKartiModel> _krediKartlari = [];
  BankaHesapModel? _secilenHesap;
  KrediKartiModel? _secilenKart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  String _bakiyeYazisi() {
    if (_cari == null) return '';
    final bakiye = _cari!.bakiye;
    final musteri = _cari!.cariTipi == 'Müşteri' ||
        _cari!.cariTipi == 'Hem Müşteri Hem Tedarikçi';
    if (musteri) {
      if (bakiye > 0) return 'Alacağımız: ${ParaUtils.formatla(bakiye)}';
      if (bakiye < 0) return 'Fazla Ödedi: ${ParaUtils.formatla(bakiye.abs())}';
      return 'Dengede';
    } else {
      if (bakiye < 0) return 'Borcumuz: ${ParaUtils.formatla(bakiye.abs())}';
      if (bakiye > 0) return 'Fazla Ödedik: ${ParaUtils.formatla(bakiye)}';
      return 'Dengede';
    }
  }

  Future<void> _yukle() async {
    try {
      final c = await _depo.idileGetir(widget.cariId);
      final hesaplar = await BankaHesapDeposu().tumunuGetir();
      final kartlar = await KrediKartiDeposu().tumunuGetir();
      if (!mounted) return;
      setState(() {
        _cari = c;
        _bankaHesaplari = hesaplar;
        _krediKartlari = kartlar;
        if (hesaplar.isNotEmpty) _secilenHesap = hesaplar.first;
        if (kartlar.isNotEmpty) _secilenKart = kartlar.first;
        _yukleniyor = false;
      });
    } catch (e) {
      // 🔴 DÜZELTME: Hata durumunda _yukleniyor hiç false yapılmıyordu
      // — cari çekilemezse ekran SONSUZA KADAR "yükleniyor" durumunda
      // kalıyordu, kullanıcıya hiçbir geri bildirim/çıkış yolu yoktu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) {
        setState(() => _yukleniyor = false);
        BildirimServisi.hata(context, 'Cari bilgisi yüklenemedi: $e');
      }
    }
  }

  Widget _segmentButton() {
    final tedarikci = _cari?.cariTipi == 'Tedarikci';
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(
          value: 'Tahsilat',
          label: Text(tedarikci ? 'Ödeme Yaptım' : 'Tahsilat'),
          icon: const Icon(Icons.add_circle_outline),
        ),
        ButtonSegment(
          value: 'Odeme',
          label: Text(tedarikci ? 'Borç Ekle' : 'İade/Ödeme'),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ],
      selected: {_islemTipi},
      onSelectionChanged: (s) => setState(() => _islemTipi = s.first),
    );
  }

  // 🔴 YENİ: Bu ekran hem müşteri hem tedarikçi için kullanıldığından,
  // "para gerçekten hareket ediyor mu" ve "hangi yönde" ayrı ayrı
  // belirlenmeli:
  //   - Tedarikçi + "Ödeme Yaptım" (Tahsilat)  → PARA ÇIKAR (gerçek ödeme)
  //   - Tedarikçi + "Borç Ekle" (Odeme)        → para hareketi YOK (sadece
  //     veresiye borç kaydı — henüz ödeme yapılmadı)
  //   - Müşteri + "Tahsilat"                   → PARA GİRER
  //   - Müşteri + "İade/Ödeme" (Odeme)         → PARA ÇIKAR (iade)
  bool get _tedarikci => _cari?.cariTipi == 'Tedarikci';

  bool get _paraHareketEdiyor {
    if (_tedarikci && _islemTipi == 'Odeme') return false; // sadece borç kaydı
    return true;
  }

  bool get _paraCikiyor {
    if (_tedarikci && _islemTipi == 'Tahsilat') return true; // Ödeme Yaptım
    if (!_tedarikci && _islemTipi == 'Odeme') return true; // İade/Ödeme
    return false; // müşteri tahsilatı = para girer
  }

  bool get _bankaSecimiGerekli =>
      _paraHareketEdiyor && (_odemeTuru == 'Banka' || _odemeTuru == 'Havale');
  bool get _kartSecimiGerekli =>
      _paraHareketEdiyor && _odemeTuru == 'Kredi Kartı';

  Future<void> _kaydet() async {
    if (_islem) return; // en başta — onay diyaloğu açıkken tekrar tetiklenmesin
    final tutar = ParaUtils.sayiCoz(_tutarCtrl.text);
    if (tutar == null || tutar <= 0) {
      BildirimServisi.uyari(context, 'Geçerli tutar girin');
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
    // 🔴 YENİ (kullanıcı bulgusu — "yanlış ödeme ve tahsilat
    // girmesin"): Saf bir müşteride "İade/Ödeme" (para ÇIKIŞI) veya
    // saf bir tedarikçide "Ödeme Yaptım" YERİNE aslında "Tahsilat"
    // (para GİRİŞİ, yani tedarikçiden para topladığınızı) kaydetmek
    // her zaman GEÇERSİZ değildir (iade gibi durumlar olabilir) ama
    // GENELDE bir yazım/seçim hatasıdır — bu yüzden tamamen
    // ENGELLEMEK yerine, kullanıcıya AÇIK bir onay soruyoruz.
    final cariTipi = _cari?.cariTipi ?? '';
    final safMusteri = cariTipi == 'Müşteri';
    final safTedarikci = cariTipi == 'Tedarikci' || cariTipi == 'Tedarikçi';
    final olagandisi = (safMusteri && _islemTipi == 'Odeme') ||
        (safTedarikci && _islemTipi == 'Tahsilat');
    if (olagandisi) {
      final devamEt = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Emin misiniz?'),
          ]),
          content: Text(safMusteri
              ? 'Bu cari bir MÜŞTERİ. Normalde müşteriden "Tahsilat" yapılır. '
                  'Şimdi ona "Ödeme/İade" kaydetmek üzeresiniz — bu genelde '
                  'bir iade durumudur, yanlışlıkla seçtiyseniz İptal\'e basın.'
              : 'Bu cari bir TEDARİKÇİ. Normalde tedarikçiye "Ödeme" '
                  'yapılır. Şimdi ondan "Tahsilat" kaydetmek üzeresiniz — bu '
                  'genelde bir iade/düzeltme durumudur, yanlışlıkla '
                  'seçtiyseniz İptal\'e basın.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Evet, Devam Et'),
            ),
          ],
        ),
      );
      if (devamEt != true) return;
    }
    setState(() => _islem = true);
    try {
      final kasiyer = AuthServisi().aktifAd;

      // ══════════════════════════════════════════════════════════════════
      // 🆕 MAKBUZ İÇİN: bakiyeyi işlemden ÖNCE yakala.
      // hareketEkle() bakiyeyi yeniden hesaplayıp güncelliyor; sonradan
      // okursak "eski bakiye"yi kaybederiz.
      // ══════════════════════════════════════════════════════════════════
      final oncekiBakiye = _cari?.bakiye ?? 0;

      // 🔴🔴 DÜZELTME (derin analizde bulundu): Cari hareket ve gerçek para
      // hareketi (kasa/banka/kart) önceden İKİ AYRI, transaction'sız çağrı
      // idi — ikincisi herhangi bir nedenle başarısız olursa cari bakiyesi
      // güncellenmiş ama kasaya/bankaya hiç para girmemiş/çıkmamış gibi
      // görünüyordu (kasa sayımı ile sistem bakiyesi tutmaz hale gelirdi).
      // Artık BorcOdemeIslemServisi'ndeki desenle aynı şekilde TEK bir
      // db.transaction() içinde atomik olarak yürütülüyor.
      final db = await Veritabani().db;
      String? cariHareketGlobalId;
      int? kasaHareketId;
      int? bankaHareketId;
      int? krediHareketId;

      await db.transaction((txn) async {
        cariHareketGlobalId = await _depo.hareketEkleTxn(
            txn,
            CariHareketModel(
              cariId: widget.cariId,
              tarih: DateTime.now(),
              fisTipi: _islemTipi,
              aciklama: _aciklamaCtrl.text.trim().isEmpty
                  ? '$_islemTipi - $_odemeTuru'
                  : _aciklamaCtrl.text.trim(),
              borc: _islemTipi == 'Odeme' ? tutar : 0,
              alacak: _islemTipi == 'Tahsilat' ? tutar : 0,
              odemeTuru: _odemeTuru,
              kullanici: kasiyer,
            ));
        // 🔴🔴 FAZ 1 madde 5 (kullanıcı onayıyla): bu cari_hareket'in
        // YEREL id'sini alıp, oluşturacağımız kasa hareketine referans
        // olarak veriyoruz — cari_hareket_ekrani.dart artık bu iptal
        // edildiğinde bağlı kasa hareketini GÜVENİLİR şekilde bulup
        // otomatik tersine çevirebiliyor (kasa_hareketleri zaten
        // referans_id/referans_turu taşıyordu, yeni sütun gerekmedi).
        int? cariHareketLocalId;
        if (cariHareketGlobalId != null) {
          final satir = await txn.query('cari_hareket',
              columns: ['id'],
              where: 'global_id = ?',
              whereArgs: [cariHareketGlobalId],
              limit: 1);
          if (satir.isNotEmpty) cariHareketLocalId = satir.first['id'] as int;
        }
        // 🔴 DÜZELTME (kullanıcı bulgusu): "Banka"/"Kredi Kartı" seçilse
        // bile önceden HİÇBİR gerçek hareket oluşturulmuyordu — sadece
        // cari bakiyesi değişiyor, şirketin gerçek banka bakiyesi/kart
        // limiti hiç etkilenmiyordu. Artık BorcOdemeIslemServisi'ndeki
        // AYNI, doğru desen uygulanıyor. "Borç Ekle" (tedarikçi, veresiye
        // kayıt) için hiçbir para hareketi oluşturulmaz — bu doğru,
        // çünkü henüz gerçek bir ödeme yapılmamıştır.
        if (_paraHareketEdiyor) {
          if (_odemeTuru == 'Nakit') {
            kasaHareketId = await KasaDeposu().hareketEkleTxn(
                txn,
                KasaHareketModel(
                  hareketTipi: _islemTipi == 'Tahsilat' ? 'Tahsilat' : 'Ödeme',
                  tutar: tutar,
                  tarih: DateTime.now(),
                  referansId: cariHareketLocalId,
                  referansTuru: 'cari_hareket',
                  aciklama: '${_cari?.unvan ?? 'Cari'} - $_islemTipi',
                ));
          } else if (_odemeTuru == 'Banka' || _odemeTuru == 'Havale') {
            bankaHareketId = await BankaHareketDeposu().ekleTxn(
                txn,
                BankaHareketModel(
                  bankaHesapId: _secilenHesap!.id!,
                  islemTipi: _paraCikiyor ? 'Giden' : 'Gelen',
                  tutar: tutar,
                  aciklama: '${_cari?.unvan ?? 'Cari'} - $_islemTipi',
                  tarih: DateTime.now(),
                ));
          } else if (_odemeTuru == 'Kredi Kartı') {
            // Kredi kartı sadece PARA ÇIKIŞI (ödeme) senaryosunda anlamlıdır
            // — bir müşteriden kredi kartıyla "tahsilat" bu ekranın kapsamı
            // dışında (o zaten Satış ekranından yapılır).
            krediHareketId = await KrediKartiDeposu().limitDegistirTxn(
                txn, _secilenKart!.id!, tutar,
                aciklama: '${_cari?.unvan ?? 'Cari'} - $_islemTipi');
          }
        }
      });

      // Transaction kalıcı oldu — bulut senkronunu şimdi tetikle (bkz.
      // KasaDeposu.hareketEkleTxn'deki aynı gerekçe: commit'ten önce
      // senkronlamak, geri alınırsa buluta var olmayan satır gönderirdi).
      Future<void> sync(String tablo, dynamic id) async {
        if (id == null) return;
        final satir =
            await db.query(tablo, where: 'id = ?', whereArgs: [id], limit: 1);
        if (satir.isNotEmpty)
          BulutManager().upsert(tablo, Map<String, dynamic>.from(satir.first));
      }

      if (cariHareketGlobalId != null) {
        final satir = await db.query('cari_hareket',
            where: 'global_id = ?', whereArgs: [cariHareketGlobalId], limit: 1);
        if (satir.isNotEmpty)
          BulutManager()
              .upsert('cari_hareket', Map<String, dynamic>.from(satir.first));
      }
      final cariSatir = await db.query('cari',
          where: 'id = ?', whereArgs: [widget.cariId], limit: 1);
      if (cariSatir.isNotEmpty)
        BulutManager()
            .upsert('cari', Map<String, dynamic>.from(cariSatir.first));
      await sync('kasa_hareketleri', kasaHareketId);
      if (bankaHareketId != null) {
        await sync('banka_hareketler', bankaHareketId);
        final hesapSatir = await db.query('banka_hesaplar',
            where: 'id = ?', whereArgs: [_secilenHesap!.id], limit: 1);
        if (hesapSatir.isNotEmpty)
          BulutManager().upsert(
              'banka_hesaplar', Map<String, dynamic>.from(hesapSatir.first));
      }
      if (krediHareketId != null) {
        await sync('kredi_karti_hareket', krediHareketId);
        final kartSatir = await db.query('kredi_kartlari',
            where: 'id = ?', whereArgs: [_secilenKart!.id], limit: 1);
        if (kartSatir.isNotEmpty)
          BulutManager().upsert(
              'kredi_kartlari', Map<String, dynamic>.from(kartSatir.first));
      }
      // ══════════════════════════════════════════════════════════════════
      // 🆕 TAHSİLAT / TEDİYE MAKBUZU YAZDIRMA
      //
      // Yazdırma HATASI işlemi geri almamalı — para hareketi zaten
      // veritabanına yazıldı. Kullanıcı görünür bir uyarı alır ve
      // isterse tekrar dener (hizli_satis_ekrani'ndeki aynı desen).
      //
      // "Borç Ekle" (tedarikçiye veresiye kayıt) için makbuz BASILMAZ —
      // ortada gerçek bir para hareketi yok, makbuz sadece parayı
      // belgeler.
      // ══════════════════════════════════════════════════════════════════
      if (_paraHareketEdiyor) {
        try {
          final guncelCari = await _depo.idileGetir(widget.cariId);
          final makbuzNo = await Veritabani()
              .fisNoUret(_islemTipi == 'Tahsilat' ? 'tahsilat' : 'tediye');
          await YazdirmaServisi().makbuzYazdir(
            makbuzNo: makbuzNo,
            tarih: DateTime.now(),
            cariUnvan: _cari?.unvan ?? 'Cari',
            tutar: tutar,
            odemeTuru: _odemeTuru,
            islemTipi: _islemTipi,
            aciklama: _aciklamaCtrl.text.trim().isEmpty
                ? null
                : _aciklamaCtrl.text.trim(),
            kesenKisi: kasiyer,
            oncekiBakiye: oncekiBakiye,
            sonBakiye: guncelCari?.bakiye,
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('⚠️ Makbuz yazdırılamadı: $e\n'
                  'İşlem kaydedildi, makbuzu Cari Detay ekranından tekrar basabilirsiniz.'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 6),
            ));
          }
        }
      }

      if (mounted) {
        // ÖNCEDEN BURADA hiçbir provider geçersiz kılınmıyordu — ekran
        // sadece geri dönüyordu, ama Cari Detay/Liste ekranları hâlâ
        // ÖNBELLEĞE ALINMIŞ (eski) bakiyeyi gösteriyordu. Kullanıcının
        // "tahsilat/ödeme yaptığımda bakiyeler hemen yenilenmiyor,
        // çıkıp tekrar girmem gerekiyor" şikayeti tam olarak buydu.
        // cari_detay_ekrani.dart'ın KENDİSİ başka yerlerde zaten bu
        // deseni kullanıyor — aynısı burada da uygulanıyor.
        ref.invalidate(cariDetayProvider(widget.cariId));
        ref.read(carilerProvider.notifier).yukle();
        BildirimServisi.basari(context, '$_islemTipi kaydedildi');
        context.pop();
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _islem = false);
    }
  }

  @override
  void dispose() {
    _tutarCtrl.dispose();
    _aciklamaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_yukleniyor)
      return Scaffold(
          backgroundColor: context.scaffoldBg, body: const AppYukleniyor());
    if (_cari == null)
      return Scaffold(
          appBar: TsAppBar(
            gradyanli: false,
          ),
          body:
              const BosEkran(ikon: Icons.inbox_outlined, baslik: 'Bulunamadı'));
    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: TsAppBar(
        baslik: '${_cari!.unvan} - Tahsilat/Ödeme',
        gradyanli: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TsKart(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bakiye:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(ParaUtils.formatla(_cari!.bakiye.abs()),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _cari!.bakiye > 0 ? Colors.red : Colors.green)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _segmentButton(),
          const SizedBox(height: 16),
          TextField(
            controller: _tutarCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
                labelText: 'Tutar',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _odemeTuru,
            decoration: const InputDecoration(
                labelText: 'Ödeme Şekli', border: OutlineInputBorder()),
            items: ['Nakit', 'Banka', 'Kredi Kartı', 'Çek', 'Havale']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _odemeTuru = v!),
          ),
          const SizedBox(height: 12),
          if (_bankaSecimiGerekli) ...[
            if (_bankaHesaplari.isNotEmpty)
              DropdownButtonFormField<BankaHesapModel>(
                value: _secilenHesap,
                decoration: const InputDecoration(
                    labelText: 'Hangi Hesaptan?', border: OutlineInputBorder()),
                items: _bankaHesaplari
                    .map((h) => DropdownMenuItem(
                        value: h,
                        child:
                            Text(h.hesapAdi, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _secilenHesap = v),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    'Banka hesabı bulunamadı. Önce bir hesap ekleyin veya "Nakit" seçin.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ),
            const SizedBox(height: 12),
          ],
          if (_kartSecimiGerekli) ...[
            if (_krediKartlari.isNotEmpty)
              DropdownButtonFormField<KrediKartiModel>(
                value: _secilenKart,
                decoration: const InputDecoration(
                    labelText: 'Hangi Kart?', border: OutlineInputBorder()),
                items: _krediKartlari
                    .map((k) => DropdownMenuItem(
                        value: k,
                        child:
                            Text(k.kartAdi, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _secilenKart = v),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    'Kredi kartı bulunamadı. Önce bir kart ekleyin veya başka yöntem seçin.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800)),
              ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _aciklamaCtrl,
            decoration: const InputDecoration(
                labelText: 'Açıklama (opsiyonel)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _islem ? null : _kaydet,
              child: _islem
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('$_islemTipi Kaydet',
                      style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
