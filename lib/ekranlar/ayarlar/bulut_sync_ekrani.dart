// lib/ekranlar/ayarlar/bulut_sync_ekrani.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../servisler/supabase_sync_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../veri/database/veritabani.dart';
import '../../depolar/cari_deposu.dart';
import '../../depolar/stok_deposu.dart';
import '../../depolar/masa_deposu.dart';
import '../../depolar/borc_deposu.dart';
import '../../depolar/kredi_karti_deposu.dart';
import '../../servisler/puan_servisi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/sync_cakisma_deposu.dart';
import '../../servisler/bulut/supabase_ayarlari.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

class BulutSyncEkrani extends ConsumerStatefulWidget {
  const BulutSyncEkrani({super.key});
  @override
  ConsumerState<BulutSyncEkrani> createState() => _BulutSyncEkraniState();
}

class _BulutSyncEkraniState extends ConsumerState<BulutSyncEkrani> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  // Kullanıcı isteği: müşterilerin mobil veriyle de sipariş
  // verebilmesi için — Supabase Storage'a yüklenen QR menü sayfasının
  // herkese açık (public) adresi buraya kaydediliyor.
  final _qrMenuUrlCtrl = TextEditingController();
  bool _keyGizli = true;

  bool   _yukleniyor   = false;
  bool   _kayitYukleniyor = false;
  bool?  _bagliMi;
  String _baglantiMesaj = '';
  String? _cihazId;

  final List<String> _loglar = [];
  SyncSonuc? _sonSonuc;
  int _cozulmemisCakisma = 0;

  @override
  void initState() {
    super.initState();
    _ayarlariYukle();
    _cakismaSayisiniYukle();
  }

  Future<void> _cakismaSayisiniYukle() async {
    final sayi = await SyncCakismaDeposu().cozulmemisSayisi();
    if (mounted) setState(() => _cozulmemisCakisma = sayi);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _qrMenuUrlCtrl.dispose();
    super.dispose();
  }

 Future<void> _ayarlariYukle() async {
  final prefs = await SharedPreferences.getInstance();
  final url = await SupabaseAyarlari.urlOku();
  final key = await SupabaseAyarlari.keyOku();
  final cId = await SupabaseSyncServisi.cihazId();
  if (mounted) {
    setState(() {
      _urlCtrl.text = url ?? '';
      _keyCtrl.text = key ?? '';
      _qrMenuUrlCtrl.text = prefs.getString('qr_menu_web_url') ?? '';
      _cihazId = cId;
    });
    if (url != null && key != null) _baglantiKontrol();
  }
}

  Future<void> _ayarlariKaydet() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      _snack('URL ve API Key boş olamaz', Colors.red);
      return;
    }
    setState(() => _kayitYukleniyor = true);
    final test = await SupabaseSyncServisi.baglantiTest(url: url, key: key);
    if (!test.basarili) {
      if (!mounted) return;
      setState(() { _kayitYukleniyor = false; _bagliMi = false; _baglantiMesaj = test.mesaj; });
      _snack('Bağlantı başarısız: ${test.mesaj}', Colors.red);
      return;
    }
    await SupabaseSyncServisi.ayarlariKaydet(url, key);
    // Yeni bağlantı bilgileriyle otomatik (kuyruk) senkronu ANINDA
    // yeniden başlat — kullanıcı uygulamayı kapatıp açmak zorunda
    // kalmasın.
    await BulutManager().baslat();
    if (!mounted) return;
    setState(() { _kayitYukleniyor = false; _bagliMi = true; _baglantiMesaj = test.mesaj; });
    // Kullanıcının yaşadığı "490 hata" durumu: güvenlik kilidi (RLS)
    // açıkken uygulamada herkese-açık (publishable) anahtar kalırsa
    // TÜM senkron 401 ile reddedilir — ve bunu fark etmek zordu.
    // Artık anahtar tipine göre anında bilgi veriliyor.
    if (key.startsWith('sb_secret_')) {
      _snack('Secret anahtar kaydedildi ✓ — tam yetkili senkron aktif', Colors.green);
    } else if (key.startsWith('sb_publishable_') || key.startsWith('eyJ')) {
      _snack('⚠️ Bu HERKESE AÇIK (publishable) anahtar. Güvenlik kilidi '
          'kuruluysa senkron 401 hatası verir — Supabase → Settings → '
          'API Keys sayfasından sb_secret_ ile başlayan anahtarı girin.',
          Colors.orange);
    } else {
      _snack('Bağlantı bilgileri kaydedildi ✓', Colors.green);
    }
  }

  Future<void> _qrMenuUrlKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('qr_menu_web_url', _qrMenuUrlCtrl.text.trim());
    if (mounted) _snack('QR Menü adresi kaydedildi ✓', Colors.green);
  }

  Future<void> _baglantiKontrol() async {
    setState(() { _bagliMi = null; _baglantiMesaj = 'Test ediliyor...'; });
    try {
      final sonuc = await SupabaseSyncServisi.baglantiTest();
      if (mounted) setState(() { _bagliMi = sonuc.basarili; _baglantiMesaj = sonuc.mesaj; });
    } catch (e) {
      // 🔴 DÜZELTME: try-catch yoktu — servis hata verirse ekran
      // sonsuza kadar "Test ediliyor..." durumunda kalabilirdi.
      if (mounted) setState(() { _bagliMi = false; _baglantiMesaj = 'Hata: $e'; });
    }
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() {
      _loglar.add('[${TimeOfDay.now().format(context)}] $m');
      if (_loglar.length > 150) _loglar.removeAt(0);
    });
  }

  void _snack(String mesaj, Color renk) {
    if (!mounted) return;
    // 🔴 UX TUTARLILIK DÜZELTMESİ: bu ekran kendi ham SnackBar'ını
    // çiziyordu (uygulamanın geri kalanından farklı görünüyordu).
    // Artık paylaşılan BildirimServisi üzerinden gösteriliyor — tüm
    // çağrı yerleri (renk == red/green/orange) değişmeden aynı kalıyor.
    if (renk == Colors.red) {
      BildirimServisi.hata(context, mesaj);
    } else if (renk == Colors.orange) {
      BildirimServisi.uyari(context, mesaj);
    } else {
      BildirimServisi.basari(context, mesaj);
    }
  }

  // lib/ekranlar/ayarlar/bulut_sync_ekrani.dart
// _bulutaGonder ve _buluttanAl metodları:

Future<void> _bulutaGonder({bool tamSync = false}) async {
  final baslik = tamSync ? 'Tam Sync — Buluta Gönder' : 'Hızlı Sync — Buluta Gönder';
  final aciklama = tamSync
      ? 'TÜM veriler Supabase\'e gönderilecek (yavaş ama eksiksiz).'
      : 'Sadece DEĞİŞEN veriler Supabase\'e gönderilecek (hızlı).';
  if (!await _onayla(baslik, '$aciklama\n\nDevam?')) return;
  if (!mounted) return;
  setState(() { _yukleniyor = true; _loglar.clear(); _sonSonuc = null; });
  try {
    final db = Veritabani();
    final sonuc = await SupabaseSyncServisi.bulutaGonder(
      veriGetir: (tablo, filtrele) => db.supaTumKayitlariGetirTemiz(tablo, filtrele),
      log: _log,
      sadeceDegisenler: !tamSync,
    );
    if (mounted) setState(() { _yukleniyor = false; _sonSonuc = sonuc; });
    _log('✅ TAMAMLANDI: ${sonuc.ozet}');
  } catch (e) {
    // 🔴 DÜZELTME: Bu fonksiyonda hiç try-catch yoktu — hata olursa
    // ekran sonsuza kadar "yükleniyor" durumunda kalıyordu.
    _log('❌ HATA: $e');
    if (mounted) setState(() => _yukleniyor = false);
  }
}

Future<void> _buluttanAl({bool tamSync = false}) async {
  final baslik = tamSync ? 'Tam Sync — Buluttan Al' : 'Hızlı Sync — Buluttan Al';
  final aciklama = tamSync
      ? 'Supabase\'deki TÜM veriler indirilecek (yavaş ama eksiksiz).'
      : 'Sadece DEĞİŞEN veriler Supabase\'den indirilecek (hızlı).';
  if (!await _onayla(baslik, '$aciklama\n\nDevam?')) return;
  if (!mounted) return;
  setState(() { _yukleniyor = true; _loglar.clear(); _sonSonuc = null; });
  try {
    final db = Veritabani();
    final sonuc = await SupabaseSyncServisi.buluttanAl(
      kayitEkle: (t, k) => db.supaKayitlariEkle(t, k),
      kayitGuncelle: (t, k) => db.supaKayitlariGuncelle(t, k),
      sadeceDegisenler: !tamSync,
      log: _log,
    );
    // Kullanıcı sorusu: "2 cihaz aynı cari kodunu atarsa ne olur?" —
    // senkronizasyon sonrası, farklı cihazlardan gelen carilerin AYNI
    // koda sahip olup olmadığı otomatik kontrol edilip düzeltiliyor.
    final duzeltilenCari = await CariDeposu().mukerrerKodlariDuzelt();
    if (duzeltilenCari > 0) {
      _log('🔧 $duzeltilenCari mükerrer cari kodu otomatik düzeltildi');
    }
    // Kullanıcı isteği: "aynı ürünü başka cihazdan güncelleme" — stok
    // artık her zaman hareketlerin (stok_hareket) toplamından yeniden
    // hesaplanıyor, bu yüzden hangi sırayla senkronize olursa olsun
    // matematiksel olarak her zaman doğru sonuca ulaşılıyor.
    final duzeltilenStok = await StokDeposu().stokMutabakatYap();
    if (duzeltilenStok > 0) {
      _log('📦 $duzeltilenStok ürünün stoğu mutabakatla düzeltildi');
    }
    // Kullanıcı isteği: "3+ terminal, hepsi çakışabilir" — masa
    // siparişlerinin toplamı da, başka cihazlardan senkronize olan
    // kalemleri yansıtacak şekilde yeniden hesaplanıyor.
    final duzeltilenSiparis = await MasaDeposu().siparisToplamlariMutabakatYap();
    if (duzeltilenSiparis > 0) {
      _log('🍽️ $duzeltilenSiparis masa siparişinin toplamı düzeltildi');
    }
    // Kullanıcı isteği: "detaylı analiz et" — borç ödemelerinin de
    // (stok/masa siparişi gibi) hareket bazlı toplamdan mutabakatı
    // yapılıyor, 2 cihazdan aynı borca yapılan ödemelerin kaybolmaması
    // için.
    final duzeltilenBorc = await BorcDeposu().odemeMutabakatYap();
    if (duzeltilenBorc > 0) {
      _log('💳 $duzeltilenBorc borcun ödenen tutarı düzeltildi');
    }
    final duzeltilenKart = await KrediKartiDeposu().limitMutabakatYap();
    if (duzeltilenKart > 0) {
      _log('💳 $duzeltilenKart kredi kartının limiti düzeltildi');
    }
    final duzeltilenPuan = await PuanServisi().puanMutabakatYap();
    if (duzeltilenPuan > 0) {
      _log('⭐ $duzeltilenPuan müşterinin puanı düzeltildi');
    }
    if (mounted) setState(() { _yukleniyor = false; _sonSonuc = sonuc; });
    _log('✅ BULUTTAN ALMA TAMAMLANDI: ${sonuc.ozet}');
    _cakismaSayisiniYukle(); // yeni sync çakışması oluşmuş olabilir
  } catch (e) {
    // 🔴 DÜZELTME: Bu fonksiyonda (buluttan alma + 6 ayrı mutabakat
    // adımı) hiç try-catch yoktu — herhangi bir adımda hata olursa
    // ekran sonsuza kadar "yükleniyor" durumunda kalıyordu.
    _log('❌ HATA: $e');
    if (mounted) setState(() => _yukleniyor = false);
  }
}
  Future<bool> _onayla(String baslik, String mesaj) async {
    if (!mounted) return false;
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(baslik),
        content: Text(mesaj),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Devam Et')),
        ],
      ),
    ) ?? false;
  }

  // 🔥 Hata mesajlarını panoya kopyala
  Future<void> _kopyalaHatalar() async {
    if (_sonSonuc == null || _sonSonuc!.hatalar.isEmpty) {
      _snack('Kopyalanacak hata yok', Colors.orange);
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('Supabase Sync Hataları - ${DateTime.now().toLocal()}');
    buffer.writeln('─' * 40);
    for (final hata in _sonSonuc!.hatalar) {
      buffer.writeln(hata);
    }
    buffer.writeln('─' * 40);
    buffer.writeln('Toplam ${_sonSonuc!.hatalar.length} hata');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    _snack('${_sonSonuc!.hatalar.length} hata panoya kopyalandı', Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Bulut Senkronizasyon',
        aksiyonlar: [
          if (_bagliMi == true)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Bağlantıyı test et',
              onPressed: _baglantiKontrol,
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [

            // BAĞLANTI AYARLARI
            Container(
          decoration: BoxDecoration(
                color: TsRenk.kart(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TsRenk.ayirac(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.cloud_outlined, color: AppRenkler.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Supabase Bağlantı Ayarları',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Settings → API → Project URL ve anon key',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'Supabase URL',
                      hintText: 'https://xxxxx.supabase.co',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.link, size: 18),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _keyGizli,
                    decoration: InputDecoration(
                      labelText: 'API Key (anon/public)',
                      hintText: 'eyJhbGci... veya sb_publishable_...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.key, size: 18),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_keyGizli ? Icons.visibility_off : Icons.visibility, size: 18),
                        onPressed: () => setState(() => _keyGizli = !_keyGizli),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Kullanıcı isteği: "müşteriler kendi telefonuyla,
                  // internetten (mobil veri dahil) QR okutup sipariş
                  // versin." Supabase Storage'a yüklenen menü
                  // sayfasının herkese açık adresi buraya yapıştırılır.
                  Row(children: [
                    const Icon(Icons.qr_code_2, size: 18),
                    const SizedBox(width: 8),
                    const Text('QR Menü Web Adresi',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Supabase Storage\'a yüklediğiniz menü sayfasının herkese açık adresi',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _qrMenuUrlCtrl,
                    decoration: InputDecoration(
                      labelText: 'QR Menü Adresi (opsiyonel)',
                      hintText: 'https://xxxxx.supabase.co/storage/v1/object/public/menu/qr_menu_sayfasi.html',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.public, size: 18),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save, size: 18),
                        onPressed: _qrMenuUrlKaydet,
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _qrMenuUrlKaydet(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _kayitYukleniyor ? null : _ayarlariKaydet,
                      icon: _kayitYukleniyor
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_kayitYukleniyor ? 'Test ediliyor...' : 'Kaydet ve Test Et'),
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.white,
          backgroundColor: AppRenkler.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (_baglantiMesaj.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _bagliMi == true
                            ? TsRenk.zemin(TsRenk.basarili)
                            : _bagliMi == false
                                ? TsRenk.zemin(TsRenk.hata)
                                : TsRenk.zemin(TsRenk.uyari),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _bagliMi == true
                              ? Colors.green.shade200
                              : _bagliMi == false
                                  ? Colors.red.shade200
                                  : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          _bagliMi == true ? Icons.check_circle_outline
                              : _bagliMi == false ? Icons.error_outline
                              : Icons.sync,
                          size: 16,
                          color: _bagliMi == true ? Colors.green
                              : _bagliMi == false ? Colors.red
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_baglantiMesaj,
                            style: TextStyle(
                              fontSize: 12,
                              color: _bagliMi == true ? Colors.green.shade800
                                  : _bagliMi == false ? Colors.red.shade800
                                  : Colors.orange.shade800,
                            ))),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 12),

            // SYNC ÇAKIŞMALARI (protokol §12) — iki cihaz aynı kaydı
            // bağımsız değiştirdiğinde artık sessizce ezilmiyor, burada
            // görünür ve çözülebiliyor (bkz. sync_cakismalari_ekrani.dart).
            if (_cozulmemisCakisma > 0) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await context.push('/ayarlar/sync-cakismalari');
                  _cakismaSayisiniYukle();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TsRenk.zemin(TsRenk.uyari),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$_cozulmemisCakisma çözülmemiş senkron çakışması var',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.orange.shade900),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.orange.shade800),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // SYNC BUTONLARI
            if (_bagliMi == true) ...[
              Row(children: [
                Expanded(child: _SyncButon(
                  label: 'Hızlı Gönder',
                  alt: 'Sadece değişenler →',
                  ikon: Icons.cloud_upload_outlined,
                  renk: Colors.blue,
                  aktif: !_yukleniyor,
                  onPressed: () => _bulutaGonder(tamSync: false),
                )),
                const SizedBox(width: 12),
                Expanded(child: _SyncButon(
                  label: 'Hızlı Al',
                  alt: '← Sadece değişenler',
                  ikon: Icons.cloud_download_outlined,
                  renk: Colors.green.shade700,
                  aktif: !_yukleniyor,
                  onPressed: () => _buluttanAl(tamSync: false),
                )),
              ]),
              const SizedBox(height: 8),
              // Tam sync — ilk kurulum veya sorun çıkınca
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _yukleniyor ? null : () => _bulutaGonder(tamSync: true),
                  icon: const Icon(Icons.cloud_upload, size: 16),
                  label: const Text('Tam Gönder', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      side: BorderSide(color: Colors.blue.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                )),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _yukleniyor ? null : () => _buluttanAl(tamSync: true),
                  icon: const Icon(Icons.cloud_download, size: 16),
                  label: const Text('Tam Al', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                )),
              ]),
              const SizedBox(height: 4),
              Text('Hızlı: sadece değişenler  •  Tam: tüm kayıtlar (yavaş)',
                  style: TextStyle(fontSize: 10, color: context.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],

            // SONUÇ KARTI + KOPYALA BUTONU
            if (_sonSonuc != null) ...[
              _SonucKarti(
                sonuc: _sonSonuc!,
                onCopy: _sonSonuc!.hatalar.isNotEmpty ? _kopyalaHatalar : null,
              ),
              const SizedBox(height: 8),
            ],

            // Progress
            if (_yukleniyor)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),

            // Cihaz ID
            if (_cihazId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.devices, size: 13, color: TsRenk.metinIkincil(context)),
                  const SizedBox(width: 4),
                  Text('Cihaz: $_cihazId',
                      style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
                ]),
              ),

            // Log
            if (_loglar.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              _LogWidget(loglar: _loglar),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Alt widgetlar ─────────────────────────────────────────────────

class _SyncButon extends StatelessWidget {
  final String label, alt; final IconData ikon;
  final Color renk; final bool aktif; final VoidCallback onPressed;
  const _SyncButon({required this.label, required this.alt, required this.ikon,
      required this.renk, required this.aktif, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: aktif ? renk : TsRenk.ayirac(context),
        foregroundColor: aktif ? Colors.white : TsRenk.metinIkincil(context),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: aktif ? onPressed : null,
      icon: Icon(ikon, size: 20),
      label: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(alt, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal)),
      ]),
    );
  }
}

class _SonucKarti extends StatelessWidget {
  final SyncSonuc sonuc;
  final VoidCallback? onCopy;
  const _SonucKarti({required this.sonuc, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sonuc.basarili ? TsRenk.zemin(TsRenk.basarili) : TsRenk.zemin(TsRenk.uyari),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: sonuc.basarili ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sonuc.basarili ? Icons.check_circle_outline : Icons.warning_amber_outlined,
              color: sonuc.basarili ? Colors.green : Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(sonuc.ozet, style: TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13,
            color: sonuc.basarili ? Colors.green.shade800 : Colors.orange.shade800,
          ))),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Tüm Hataları Kopyala',
              onPressed: onCopy,
              color: Colors.orange.shade700,
            ),
        ]),
        if (sonuc.hatalar.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Text('Hatalar (${sonuc.hatalar.length})',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.orange.shade800)),
          const SizedBox(height: 4),
          ...sonuc.hatalar.take(5).map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              const Icon(Icons.circle, size: 5, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(child: Text(h,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          )),
          if (sonuc.hatalar.length > 5)
            Text('... +${sonuc.hatalar.length - 5} hata daha (kopyala)',
                style: TextStyle(fontSize: 10, color: TsRenk.metinIkincil(context))),
        ],
      ]),
    );
  }
}

class _LogWidget extends StatelessWidget {
  final List<String> loglar;
  const _LogWidget({required this.loglar});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: loglar.map((log) {
        final isHata  = log.contains('❌');
        final isBasar = log.contains('✅');
        final isInfo  = log.contains('📤') || log.contains('📥');
        final isDivider = log.contains('─────');

        Color renk = isDivider ? TsRenk.metinIkincil(context)
            : isHata  ? Colors.red.shade700
            : isBasar ? Colors.green.shade700
            : isInfo  ? Colors.blue.shade700
            : context.textPrimary;   // koyu temada okunabilir olsun

        if (isHata) {
          // Hata satırı — tıklanabilir + kopyalanabilir
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Hata Detayı',
                      style: TextStyle(fontSize: 15))),
                ]),
                content: SelectableText(log,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                actions: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                    label: const Text('Kopyala'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: log));
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat'),
                  ),
                ],
              ),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: TsRenk.zemin(TsRenk.hata),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                Expanded(child: Text(log,
                    style: TextStyle(fontFamily: 'monospace',
                        fontSize: 11.5, color: renk))),
                Icon(Icons.info_outline, size: 14, color: Colors.red.shade300),
              ]),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Text(log,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: renk)),
        );
      }).toList(),
    );
  }
}