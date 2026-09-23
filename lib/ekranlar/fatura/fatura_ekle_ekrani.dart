// lib/ekranlar/fatura/fatura_ekle_ekrani.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/fatura_deposu.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/urun_deposu.dart';
import '../../modeller/fatura_model.dart';
import '../../modeller/cari_model.dart';
import '../../modeller/urun_model.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/faturalandirma_servisi.dart';
import '../../cekirdek/utils/para_utils.dart';

// Kalem modeli — controller'ları içinde tutar (memory leak önlenir)
class _Kalem {
  UrunModel? urun;
  final adCtrl   = TextEditingController();
  final miktCtrl = TextEditingController(text: '1');
  final fiyCtrl  = TextEditingController();
  final iskCtrl  = TextEditingController();
  String kdvOran;

  // ÖNCEDEN varsayılan KDV oranı sabit '18' idi — Ayarlar > Fatura
  // Ayarları'ndaki "Varsayılan KDV" ayarı hiç okunmuyordu. Artık
  // dışarıdan (yüklenen ayardan) verilebiliyor.
  _Kalem({String varsayilanKdv = '18'}) : kdvOran = varsayilanKdv;

  double get miktar      => double.tryParse(miktCtrl.text.replaceAll(',', '.')) ?? 1;
  double get birimFiyat  => double.tryParse(fiyCtrl.text.replaceAll(',', '.'))  ?? 0;
  double get iskontoOran => ParaUtils.sayiCoz(iskCtrl.text) ?? 0;
  double get araToplam   => birimFiyat * miktar;
  double get iskontoTut  => araToplam * (iskontoOran / 100);
  double get netTutar    => araToplam - iskontoTut;
  double get kdvTutar    => netTutar * ((double.tryParse(kdvOran) ?? 18) / 100);
  double get toplam      => netTutar + kdvTutar;

  void dispose() {
    adCtrl.dispose(); miktCtrl.dispose();
    fiyCtrl.dispose(); iskCtrl.dispose();
  }
}

class FaturaEkleEkrani extends ConsumerStatefulWidget {
  final FaturaModel? mevcutFatura;
  const FaturaEkleEkrani({super.key, this.mevcutFatura});
  @override
  ConsumerState<FaturaEkleEkrani> createState() => _FaturaEkleEkraniState();
}

class _FaturaEkleEkraniState extends ConsumerState<FaturaEkleEkrani> {
  final _formKey    = GlobalKey<FormState>();
  final _faturaDepo = FaturaDeposu();
  final _cariDepo   = CariDeposu();
  final _urunDepo   = UrunDeposu();

  List<CariModel> _cariler  = [];
  List<_Kalem>    _kalemler = [_Kalem()];
  String          _varsayilanKdv = '18';

  CariModel? _seciliCari;
  String   _faturaTipi   = 'Satis';
  DateTime _tarih        = DateTime.now();
  DateTime? _vadeTarihi;
  String   _odemeDurumu  = 'beklemede';
  bool     _yukleniyor   = false;

  final _faturaNoCtrl    = TextEditingController();
  final _nereyeCtrl      = TextEditingController();
  String _odemeSekli = 'Nakit';
  final _teslimEdenCtrl  = TextEditingController();
  final _teslimAlanCtrl  = TextEditingController();

  double get _araToplam   => _kalemler.fold(0.0, (s, k) => s + k.araToplam);
  // 🔴 DÜZELTME (kritik — bağımsız yeniden denetimde bulundu): FaturaModel.
  // toplamAraToplam alanı codebase genelinde NET (indirim uygulanmış)
  // tutar olarak saklanır (Madde 21 kuralı) — ama bu ekran gönderirken
  // YUKARIDAKİ _araToplam'ı (ekranda "Ara Toplam" etiketiyle GÖSTERİLEN,
  // bilerek BRÜT bırakılan değeri) kullanıyordu. Ekrandaki gösterim
  // doğruydu (brüt gösterip altında İndirim/Net satırlarıyla açıklıyor),
  // ama SAKLANAN toplamAraToplam brüt kalıyordu — bu da basılan faturada
  // (toplamAraToplam+toplamIskonto ile brüte geri çevrilen diğer 4
  // yüzeyde) indirimin İKİ KEZ eklenmiş görünmesine yol açıyordu (ör.
  // gerçek brüt 100 iken 110 basılıyordu). Gönderirken KULLANILMASI
  // gereken NET toplam bu.
  double get _araToplamNet => _kalemler.fold(0.0, (s, k) => s + k.netTutar);
  double get _iskonto     => _kalemler.fold(0.0, (s, k) => s + k.iskontoTut);
  double get _kdvToplam   => _kalemler.fold(0.0, (s, k) => s + k.kdvTutar);
  double get _genelToplam => _kalemler.fold(0.0, (s, k) => s + k.toplam);

  @override
  void initState() {
    super.initState();
    // ÖNCEDEN BURADA CİDDİ BİR HUKUKİ UYUMLULUK HATASI VARDI: fatura
    // numarası "şu anki zaman damgası mod 1 milyar" ile üretiliyordu —
    // bu GERÇEKTEN ARTAN BİR SAYAÇ DEĞİLDİ (GİB'in zorunlu kıldığı
    // "boşluksuz, sıralı numara" kuralını ihlal ediyordu) ve zaman
    // damgası periyodik olarak tekrarlandığı için ÇAKIŞMA riski
    // taşıyordu. Artık veritabanında kayıtlı gerçek son numaraya göre
    // hesaplanan, GERÇEKTEN sıralı bir numara kullanılıyor.
    //
    // 2026-09-23: Yerel MAX+1 ile önceden doldurma KALDIRILDI — bu numara
    // başka bir terminale tahsis edilmiş merkezi blokla çakışabiliyordu.
    // Alan boş bırakılırsa numara kayıt anında merkezi seriden
    // (FaturaDeposu.ekleMerkeziSeriIle) atanır; elle yazılırsa (ör. kağıt
    // faturanın sisteme girilmesi) yazılan numara aynen kullanılır.
    _varsayilanKdvYukle();
  }

  // ÖNCEDEN "Varsayılan KDV" ayarı (Ayarlar > Fatura Ayarları) hiçbir
  // yerde okunmuyordu — her yeni kalem her zaman sabit %18 ile
  // başlıyordu. Artık gerçekten ayarlardan yükleniyor.
  Future<void> _varsayilanKdvYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final varsayilan = prefs.getString('varsayilan_kdv') ?? '18';
    if (mounted) {
      setState(() {
        _varsayilanKdv = varsayilan;
        for (final k in _kalemler) {
          k.kdvOran = varsayilan;
        }
      });
    }
    _yukle();
  }

  @override
  void dispose() {
    for (final k in _kalemler) k.dispose();
    _faturaNoCtrl.dispose(); _nereyeCtrl.dispose();
    _teslimEdenCtrl.dispose(); _teslimAlanCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final liste = await _cariDepo.tumunuGetir();
      if (!mounted) return;
      setState(() => _cariler = liste);
    } catch (e) {
      if (kDebugMode) debugPrint('Fatura cari yükleme: $e');
    }
  }

  void _kalemEkle() {
    setState(() => _kalemler.add(_Kalem(varsayilanKdv: _varsayilanKdv)));
  }

  void _kalemSil(int i) {
    if (_kalemler.length <= 1) return;
    _kalemler[i].dispose();
    setState(() => _kalemler.removeAt(i));
  }

  Future<void> _urunSec(int i) async {
    UrunModel? secilen;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final araCtrl = TextEditingController();
        var liste = <UrunModel>[];
        return StatefulBuilder(
          builder: (ctx, ss) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Ürün Seç'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: araCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Ürün adı veya barkod ara...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (q) async {
                    if (q.trim().isEmpty) { ss(() => liste = []); return; }
                    final r = await _urunDepo.ara(q.trim(), limit: 30);
                    ss(() => liste = r);
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: liste.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, j) {
                      final u = liste[j];
                      return ListTile(
                        dense: true,
                        title: Text(u.urunAdi,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(u.barkod ?? ''),
                        trailing: Text(ParaUtils.formatla(u.satisFiyati),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          secilen = u;
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('İptal')),
            ],
          ),
        );
      },
    );
    if (secilen == null || !mounted) return;
    setState(() {
      _kalemler[i].urun = secilen;
      _kalemler[i].adCtrl.text  = secilen!.urunAdi;
      _kalemler[i].fiyCtrl.text = secilen!.satisFiyati.toStringAsFixed(2);
      _kalemler[i].kdvOran      = secilen!.kdvOran;
    });
  }

  Future<void> _tarihSec({bool vade = false}) async {
    try {  
      final d = await showDatePicker(
        context: context,
        initialDate: vade
            ? (_vadeTarihi ?? DateTime.now().add(const Duration(days: 30)))
            : _tarih,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      if (d == null || !mounted) return;
      setState(() { if (vade) _vadeTarihi = d; else _tarih = d; });
        } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _kaydet() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_seciliCari == null) {
      BildirimServisi.uyari(context, 'Cari seçin');
      return;
    }
    if (_kalemler.any((k) => k.adCtrl.text.trim().isEmpty)) {
      BildirimServisi.uyari(context, 'Tüm kalemlerde ürün adı olmalı');
      return;
    }

    setState(() => _yukleniyor = true);
    try {
      final detaylar = _kalemler.map((k) => FaturaDetayModel(
        urunId:        k.urun?.id,
        urunAdi:       k.adCtrl.text.trim(),
        barkod:        k.urun?.barkod,
        miktar:        k.miktar,
        birimFiyat:    k.birimFiyat,
        iskontoOrani:  k.iskontoOran,
        iskontoTutari: k.iskontoTut,
        kdvOrani:      double.tryParse(k.kdvOran) ?? 18,
        kdvTutari:     k.kdvTutar,
        // 🔴 DÜZELTME (kritik — derin denetimde bulundu): araToplam burada
        // indirim UYGULANMADAN ÖNCEKİ tutara (k.araToplam) eşitleniyordu.
        // Codebase'in her yerinde geçerli kural "araToplam = toplamTutar -
        // kdvTutari" (Madde 21) — burada bozuluyordu. İki sonucu vardı:
        // (1) basılan faturada "Vergiler Hariç Toplam" indirimi iki kez
        // düşüyordu, (2) GİB'e giden UBL XML'de LineExtensionAmount/
        // TaxableAmount indirim UYGULANMAMIŞ (fazla) tutarla gidiyor,
        // TaxAmount ise indirim uygulanmış (doğru, küçük) matrah üzerinden
        // hesaplanıyordu — TaxAmount ≠ TaxableAmount×oran uyuşmazlığı.
        araToplam:     k.netTutar,
        toplamTutar:   k.toplam,
      )).toList();

      // 🔴 Derin denetimde bulundu (P2): satış/iade üzerinden otomatik
      // oluşturulan faturalarda (faturalandirma_servisi.dart) cariVergiDairesi/
      // cariAdres doluyordu ama bu manuel ekranda hiç set edilmiyordu —
      // GİB e-Fatura XML'i bu alanları kullanıyor (bkz. gib_servisi.dart
      // düzeltmesi), eksik kalırlarsa gönderim reddedilebilir. Aynı
      // kontrol fonksiyonu (FaturalandirmaServisi.kontrolEt) burada da
      // kullanılıp adres/vergi dairesi dolduruluyor.
      final cariKontrol = await FaturalandirmaServisi.kontrolEt(_seciliCari!.id!);

      final girilenFaturaNo = _faturaNoCtrl.text.trim();
      final fatura = FaturaModel(
        faturaNo:       girilenFaturaNo,
        odemeSekli:     _odemeSekli,
        faturaTipi:     _faturaTipi,
        cariId:         _seciliCari!.id,
        cariUnvan:      _seciliCari!.unvan,
        cariVergiNo:    _seciliCari!.vergiNo,
        cariVergiDairesi: _seciliCari!.vergiDairesi,
        cariAdres:      cariKontrol?.adresMetni,
        tarih:          _tarih,
        vadeTarihi:     _vadeTarihi,
        malinNereye:    _nereyeCtrl.text.trim().isEmpty ? null : _nereyeCtrl.text.trim(),
        teslimEden:     _teslimEdenCtrl.text.trim().isEmpty ? null : _teslimEdenCtrl.text.trim(),
        teslimAlan:     _teslimAlanCtrl.text.trim().isEmpty ? null : _teslimAlanCtrl.text.trim(),
        toplamAraToplam: _araToplamNet,
        toplamIskonto:  _iskonto,
        toplamKdv:      _kdvToplam,
        genelToplam:    _genelToplam,
        kalanTutar:     _genelToplam,
        odemeDurumu:    _odemeDurumu,
        detaylar:       detaylar,
      );

      final otomatikNo = girilenFaturaNo.isEmpty;
      if (!otomatikNo) {
        // Elle girilen numara mevcut bir faturayla çakışıyorsa sessizce
        // değiştirmek yerine kullanıcıya sor (kağıt faturanın numarası
        // değişmemeli).
        if (await _faturaDepo.faturaNoKullanildiMi(girilenFaturaNo)) {
          if (mounted) {
            BildirimServisi.hata(context,
                '"$girilenFaturaNo" numaralı bir fatura zaten var. Farklı bir '
                'numara yazın ya da alanı boş bırakıp otomatik atanmasını sağlayın.');
          }
          return;
        }
      }
      final faturaId = otomatikNo
          ? await _faturaDepo.ekleMerkeziSeriIle(fatura, detaylar,
              seri: await FaturalandirmaServisi.faturaSeriOneki())
          : await _faturaDepo.ekle(fatura, detaylar);
      if (!mounted) return;
      // 🔴 Derin denetimde bulundu (P2): fatura_no alanı serbestçe
      // düzenlenebiliyordu — kullanıcı otomatik üretilen numarayı silip
      // mevcut bir faturayla ÇAKIŞAN bir değer yazabilirdi. faturalar.
      // fatura_no UNIQUE olduğu için FaturaDeposu.ekle() bunu
      // yakalayıp SESSİZCE farklı, otomatik bir numarayla değiştiriyor
      // — kullanıcı kendi seçtiği numaranın değiştirildiğinden habersiz
      // kalıyordu. Kaydedilen faturanın gerçek numarası kontrol edilip
      // farklıysa açıkça bildiriliyor.
      final kaydedilen = await _faturaDepo.idileGetir(faturaId);
      if (!mounted) return;
      if (otomatikNo) {
        BildirimServisi.basari(context,
            'Fatura oluşturuldu — No: ${kaydedilen?.faturaNo ?? '-'}');
      } else if (kaydedilen != null && kaydedilen.faturaNo != girilenFaturaNo) {
        BildirimServisi.uyari(context,
            'Fatura oluşturuldu — ama "$girilenFaturaNo" numarası zaten '
            'kullanıldığı için otomatik olarak "${kaydedilen.faturaNo}" '
            'verildi.');
      } else {
        BildirimServisi.basari(context, 'Fatura oluşturuldu');
      }
      context.pop(true);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy');
    // Cari listesi yüklenene kadar loading
    if (_cariler.isEmpty && !_yukleniyor) {
      // Yükleme tamamlandı ama cari yok - normal devam et
    }
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Yeni Fatura',
        aksiyonlar: [
          if (_yukleniyor)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
                icon: const Icon(Icons.save, color: Colors.white),
                tooltip: 'Kaydet',
                onPressed: _kaydet),
        ],
      ),
      body: TsResponsive.formSarmalayici(context: context, maxGenislik: 960, child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // Fatura bilgileri
            _bolum('FATURA BİLGİLERİ', Icons.receipt_long),
            Row(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: _faturaNoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Fatura No',
                      hintText: 'Otomatik',
                      helperText: 'Boş bırakılırsa merkezi seriden atanır',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _faturaTipi,
                  decoration: const InputDecoration(
                      labelText: 'Fatura Tipi',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: ['Satis', 'Alis', 'Iade', 'Proforma']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => _faturaTipi = v!),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _odemeSekli,
              decoration: const InputDecoration(
                  labelText: 'Ödeme Şekli',
                  prefixIcon: Icon(Icons.payments_outlined),
                  border: OutlineInputBorder(),
                  isDense: true),
              items: ['Nakit', 'Kredi Kartı', 'Havale/EFT', 'Çek', 'Diğer']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _odemeSekli = v!),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _tarihSec,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Fatura Tarihi',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.calendar_today, size: 16)),
                    child: Text(fmt.format(_tarih)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _tarihSec(vade: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Vade Tarihi',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.event, size: 16)),
                    child: Text(
                      _vadeTarihi != null
                          ? fmt.format(_vadeTarihi!)
                          : 'Secilmedi',
                      style: TextStyle(
                          color: _vadeTarihi != null ? null : context.textSecondary),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _odemeDurumu,
              decoration: const InputDecoration(
                  labelText: 'Odeme Durumu',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                const DropdownMenuItem(value: 'beklemede', child: Text('Beklemede')),
                const DropdownMenuItem(value: 'odendi', child: Text('Odendi')),
                const DropdownMenuItem(value: 'kismi', child: Text('Kismi Odendi')),
              ],
              onChanged: (v) => setState(() => _odemeDurumu = v!),
            ),

            // Cari
            _bolum('CARİ', Icons.business),
            DropdownButtonFormField<CariModel>(
              value: _seciliCari,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Cari Sec *',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.people, size: 18)),
              items: _cariler.isEmpty
                  ? [const DropdownMenuItem(value: null, child: Text('Cari bulunamadi - once cari ekleyin'))]
                  : _cariler.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.unvan, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: _cariler.isEmpty ? null : (v) => setState(() => _seciliCari = v),
              validator: (v) => v == null ? 'Cari seçin' : null,
            ),
            if (_seciliCari != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: TsRenk.zemin(TsRenk.bilgi),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Text(
                    'Bakiye: ${ParaUtils.formatla(_seciliCari!.bakiye)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _seciliCari!.bakiye > 0
                            ? Colors.red
                            : Colors.green),
                  ),
                  if (_seciliCari!.vergiNo != null) ...[
                    const SizedBox(width: 16),
                    Text('VKN: ${_seciliCari!.vergiNo}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ]),
              ),

            // Kalemler
            _bolum('KALEMLER', Icons.list_alt),
            ...List.generate(_kalemler.length, (i) => _kalemSatiri(i)),
            TextButton.icon(
              onPressed: _kalemEkle,
              icon: const Icon(Icons.add),
              label: const Text('Kalem Ekle'),
            ),

            // Sevk
            _bolum('SEVK BİLGİLERİ', Icons.local_shipping_outlined),
            _ctrl(_nereyeCtrl, 'Malın Teslim Edileceği Yer'),
            Row(children: [
              Expanded(child: _ctrl(_teslimEdenCtrl, 'Teslim Eden')),
              const SizedBox(width: 10),
              Expanded(child: _ctrl(_teslimAlanCtrl, 'Teslim Alan')),
            ]),

            // Toplam
            _bolum('TOPLAM', Icons.calculate_outlined),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: TsRenk.arkaplan(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TsRenk.ayirac(context))),
              child: Column(children: [
                _toplamSatir('Ara Toplam', _araToplam),
                if (_iskonto > 0)
                  _toplamSatir('İskonto', -_iskonto, renk: Colors.red),
                _toplamSatir('KDV', _kdvToplam),
                const Divider(height: 16),
                _toplamSatir('GENEL TOPLAM', _genelToplam,
                    bold: true, renk: TsRenk.primaryKoyu),
              ]),
            ),
            const SizedBox(height: 100),
          ],
        ),
      )),
      floatingActionButton: FloatingActionButton.extended(
        elevation: 6,
        backgroundColor: TsRenk.primary,
        foregroundColor: Colors.white,
        onPressed: _yukleniyor ? null : _kaydet,
        icon: const Icon(Icons.save),
        label: const Text('Faturayı Oluştur'),
      ),
    );
  }

  Widget _kalemSatiri(int i) {
    final k = _kalemler[i];
    return Container(
      key: ValueKey(k),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: TsRenk.kart(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TsRenk.ayirac(context)),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 4)
          ]),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: k.adCtrl,
              decoration: const InputDecoration(
                  labelText: 'Urun/Hizmet *',
                  border: OutlineInputBorder(),
                  isDense: true),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Zorunlu' : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
            tooltip: 'Ürün Seç',
            onPressed: () => _urunSec(i),
          ),
          if (_kalemler.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _kalemSil(i),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: k.miktCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Miktar',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: k.fiyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              decoration: const InputDecoration(
                  labelText: 'Birim Fiyat',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: k.iskCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Isk.%',
                  border: OutlineInputBorder(),
                  isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: k.kdvOran,
              isDense: true,
              decoration: const InputDecoration(
                  labelText: 'KDV%', border: OutlineInputBorder()),
              items: ['0', '1', '8', '10', '18', '20']
                  .map((v) => DropdownMenuItem(
                      value: v, child: Text('%$v')))
                  .toList(),
              onChanged: (v) => setState(() => k.kdvOran = v!),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Toplam: ',
              style:
                  TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
          Text(
            ParaUtils.formatla(k.toplam),
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: TsRenk.primaryKoyu),
          ),
        ]),
      ]),
    );
  }

  Widget _bolum(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: TsRenk.primaryKoyu),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TsRenk.primaryKoyu,
                  letterSpacing: 0.5)),
          const Expanded(child: Divider(indent: 8)),
        ]),
      );

  Widget _ctrl(TextEditingController ctrl, String label,
          {bool zorunlu = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true),
          validator: zorunlu
              ? (v) =>
                  (v == null || v.trim().isEmpty) ? 'Zorunlu' : null
              : null,
        ),
      );

  Widget _toplamSatir(String label, double val,
          {bool bold = false, Color? renk}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: bold ? 15 : 13,
                      fontWeight: bold
                          ? FontWeight.w700
                          : FontWeight.normal)),
              Text(
                ParaUtils.formatla(val),
                style: TextStyle(
                    fontSize: bold ? 16 : 13,
                    fontWeight:
                        bold ? FontWeight.w800 : FontWeight.w600,
                    color: renk ?? (val < 0 ? Colors.red : null)),
              ),
            ]),
      );
}
