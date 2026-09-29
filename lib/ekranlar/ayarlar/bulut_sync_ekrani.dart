// lib/ekranlar/ayarlar/bulut_sync_ekrani.dart
// ignore_for_file: use_build_context_synchronously

import '../../cekirdek/utils/hata_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../servisler/supabase_sync_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../servisler/bulut/otomatik_bulut_cekme.dart';
import '../../servisler/bulut/supabase_oturum.dart';
import '../../servisler/senkron_sonrasi_mutabakat.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../depolar/sync_cakisma_deposu.dart';
import '../../servisler/bulut/supabase_ayarlari.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
part 'bulut_sync_ekrani_islemler.dart';
part 'bulut_sync_ekrani_kartlar.dart';

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

  int _otoCekmeSn = OtomatikBulutCekme.varsayilanSaniye;

  ({int bekleyen, int yenidenDenenen, DateTime? enEski, String? sonHata})? _ozet;
  bool _simdiGonderiliyor = false;

  Future<void> _ozetiYukle() async {
    try {
      final o = await BulutManager().bekleyenOzeti();
      if (mounted) setState(() => _ozet = o);
    } catch (_) {
      // görünürlük amaçlı — ekranı bozmamalı
    }
  }

  void _kuyrukDegisti() {
    _ozetiYukle();
    _kaliciHatalariYukle();
  }

  @override
  void initState() {
    super.initState();
    _ayarlariYukle();
    _cakismaSayisiniYukle();
    _kaliciHatalariYukle();
    _ozetiYukle();
    BulutManager().durum.addListener(_kuyrukDegisti);
    BulutManager().istatistik.addListener(_kuyrukDegisti);
    OtomatikBulutCekme.aralikOku().then((sn) {
      if (mounted) setState(() => _otoCekmeSn = sn);
    });
  }

  Future<void> _cakismaSayisiniYukle() async {
    final sayi = await SyncCakismaDeposu().cozulmemisSayisi();
    if (mounted) setState(() => _cozulmemisCakisma = sayi);
  }

  // Kalıcı (4xx) hataya düşmüş, otomatik gönderimden çıkmış kuyruk satırları.
  List<({String tablo, int adet, String? ornekHata})> _kaliciHatalar = [];
  bool _kaliciYenidenDeneniyor = false;

  Future<void> _kaliciHatalariYukle() async {
    try {
      final liste = await BulutManager().kaliciHataOzeti();
      if (mounted) setState(() => _kaliciHatalar = liste);
    } catch (_) {
      // görünürlük amaçlı — ekranı bozmamalı
    }
  }

  @override
  void dispose() {
    BulutManager().durum.removeListener(_kuyrukDegisti);
    BulutManager().istatistik.removeListener(_kuyrukDegisti);
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _epostaCtrl.dispose();
    _sifreCtrl.dispose();
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

  // ── İşletme hesabıyla güvenli giriş (2026-09-28) ─────────────────────────
  final _epostaCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  bool _girisYapiliyor = false;

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
    final sonuc = await SupabaseSyncServisi.yerelBulutaGonder(
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
    final sonuc = await SupabaseSyncServisi.yerelBuluttanAl(
      sadeceDegisenler: !tamSync,
      log: _log,
    );
    // Mutabakat adımları (mükerrer cari kodu, cari bakiye, stok, masa,
    // borç, kart limiti, puan) artık SupabaseSyncServisi.buluttanAl içinde,
    // bir şey indiyse otomatik çalışıyor (bkz. SenkronSonrasiMutabakat).
    // Elle "Buluttan Al"da hiçbir şey inmese de kullanıcı bir kontrol
    // bekliyor — o durumda burada çalıştırılır.
    if (sonuc.toplamEklenen + sonuc.toplamGuncellenen + sonuc.toplamSilinen == 0) {
      await SenkronSonrasiMutabakat.calistir(log: _log);
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
                      labelText: 'API Key (herkese açık — sb_publishable_…)',
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

            _hesapKarti(),
            const SizedBox(height: 16),

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
              const SizedBox(height: 12),
              _otomatikCekmeKarti(),
              const SizedBox(height: 8),
            ],

            _senkronOzetKarti(),
            if (_kaliciHatalar.isNotEmpty) _kaliciHataKarti(),

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
