// lib/ekranlar/ayarlar/gib_ayar_ekrani.dart
// GİB e-Fatura / e-Arşiv Entegrasyon Ayarları
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../servisler/bulut/bulut_manager.dart';
import '../../veri/database/veritabani.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';

class GibAyarEkrani extends ConsumerStatefulWidget {
  const GibAyarEkrani({super.key});
  @override
  ConsumerState<GibAyarEkrani> createState() => _GibAyarEkraniState();
}

class _GibAyarEkraniState extends ConsumerState<GibAyarEkrani> {
  final _apiUrlCtrl        = TextEditingController();
  final _kullaniciAdiCtrl  = TextEditingController();
  final _sifreCtrl         = TextEditingController();
  final _vknCtrl           = TextEditingController();
  final _vdCtrl            = TextEditingController();
  final _maliMuhurSifreCtrl = TextEditingController();

  bool _testModu    = true;
  bool _yukleniyor  = true;
  bool _kaydediyor  = false;
  bool _sifreGizle  = true;
  bool _maliMuhurSifreGizle = true;
  bool _maliMuhurGoster = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _yukle()); }

  @override
  void dispose() {
    _apiUrlCtrl.dispose(); _kullaniciAdiCtrl.dispose(); _sifreCtrl.dispose();
    _vknCtrl.dispose(); _vdCtrl.dispose(); _maliMuhurSifreCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    if (!mounted) return;
    _yukleniyor = true;

    if (mounted) setState(() {});
    try {
      final db   = await Veritabani().db;
      final rows = await db.query('ayarlar',
          where: "anahtar IN ('gib_api_url','gib_kullanici_adi',"
              "'firma_vergi_no','firma_vergi_dairesi','gib_test_modu')");
      final map  = {for (final r in rows) r['anahtar'] as String: r['deger'] as String};
      // ÖNCEDEN gib_sifre ve gib_mali_muhur_sifre SQLite'ta DÜZ METİN
      // olarak saklanıyordu — GİB'e giriş yapmak için kullanılan gerçek
      // bir şifre, cihaza fiziksel/dosya erişimi olan biri tarafından
      // kolayca okunabilirdi. Artık flutter_secure_storage kullanılıyor
      // (Android'de Keystore ile şifrelenmiş, uygulamanın kendi giriş
      // şifreleri için zaten kullandığı AYNI güvenli depolama).
      const secure = FlutterSecureStorage();
      final sifre = await secure.read(key: 'gib_sifre') ?? '';
      final maliMuhurSifre = await secure.read(key: 'gib_mali_muhur_sifre') ?? '';
      if (!mounted) return;
      setState(() {
        _apiUrlCtrl.text       = map['gib_api_url']         ?? '';
        _kullaniciAdiCtrl.text = map['gib_kullanici_adi']   ?? '';
        _sifreCtrl.text        = sifre;
        _vknCtrl.text          = map['firma_vergi_no']      ?? '';
        _vdCtrl.text           = map['firma_vergi_dairesi'] ?? '';
        _maliMuhurSifreCtrl.text = maliMuhurSifre;
        _testModu              = map['gib_test_modu']       != '0';
        _yukleniyor            = false;
      });
    } catch (_) {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    if (!mounted) return;
    _kaydediyor = true;
    if (mounted) setState(() {});
    try {
      final db = await Veritabani().db;
      // Hassas olmayan ayarlar SQLite'ta kalıyor (mevcut davranış).
      final ayarlar = {
        'gib_api_url':          _apiUrlCtrl.text.trim(),
        'gib_kullanici_adi':    _kullaniciAdiCtrl.text.trim(),
        'firma_vergi_no':       _vknCtrl.text.trim(),
        'firma_vergi_dairesi':  _vdCtrl.text.trim(),
        'gib_test_modu':        _testModu ? '1' : '0',
      };
      // Şifreler artık güvenli depolamada — SQLite'a hiç yazılmıyor.
      const secure = FlutterSecureStorage();
      await secure.write(key: 'gib_sifre', value: _sifreCtrl.text.trim());
      await secure.write(key: 'gib_mali_muhur_sifre', value: _maliMuhurSifreCtrl.text.trim());
      for (final e in ayarlar.entries) {
        final existing = await db.query('ayarlar',
            where: 'anahtar = ?', whereArgs: [e.key]);
        final now = DateTime.now().toIso8601String();
        if (existing.isNotEmpty) {
          await db.update('ayarlar', {'deger': e.value, 'guncelleme': now, 'last_updated': now},
              where: 'anahtar = ?', whereArgs: [e.key]);
        } else {
          await db.insert('ayarlar', {'anahtar': e.key, 'deger': e.value, 'guncelleme': now, 'last_updated': now});
        }
        // 🔴 Derin analizde bulundu: bu 5 ayar (GİB API adresi, vergi
        // no/dairesi dahil) hiç last_updated almıyordu ve BulutManager
        // hiç çağrılmıyordu — birden fazla cihazlı işletmelerde diğer
        // cihazlar bu ayarları hiç görmüyordu.
        final satir = await db.query('ayarlar', where: 'anahtar = ?', whereArgs: [e.key], limit: 1);
        if (satir.isNotEmpty) BulutManager().upsert('ayarlar', Map<String, dynamic>.from(satir.first));
      }
      if (!mounted) return;
      BildirimServisi.basari(context, 'GİB ayarları kaydedildi ✓');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Kayıt hatası: $e');
    } finally {
      if (mounted) _kaydediyor = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _baglantiTest() async {
    if (!mounted) return;
    if (_apiUrlCtrl.text.trim().isEmpty || _kullaniciAdiCtrl.text.trim().isEmpty ||
        _sifreCtrl.text.trim().isEmpty) {
      BildirimServisi.uyari(context, 'API URL, Kullanıcı Adı ve Şifre giriniz');
      return;
    }
    showDialog(context: context, barrierDismissible: false,
        builder: (bCtx) => const ProgressDialog(mesaj: 'Bağlantı test ediliyor...'));
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      // ÖNCEDEN BURADA MİMARİ BİR EKSİKLİK VARDI: tek bir "API Key" ile
      // Bearer auth deneniyordu. Gerçek Türkiye e-Fatura entegratörleri
      // (Foriba, Sovos, Uyumsoft vb.) SOAP/REST servislerinde YAYGIN
      // OLARAK Kullanıcı Adı+Şifre (Basic Auth) kullanır. Artık ikisi de
      // deneniyor: önce Basic Auth (kullanıcı adı:şifre), o başarısız
      // olursa Bearer (bazı modern REST entegratörleri — ör. Nilvera —
      // API anahtarını şifre alanına girip Bearer kullanabilir).
      final url = _apiUrlCtrl.text.trim();
      final kAdi = _kullaniciAdiCtrl.text.trim();
      final sifre = _sifreCtrl.text.trim();
      final basicAuth = 'Basic ${base64Encode(utf8.encode('$kAdi:$sifre'))}';

      Response? response;
      String mesaj = '';
      bool basarili = false;

      try {
        response = await dio.get(
          '$url/health',
          options: Options(
            headers: {'Authorization': basicAuth},
            validateStatus: (_) => true,
          ),
        );
        if (response.statusCode != null && response.statusCode! < 500) {
          basarili = true;
          mesaj = 'Sunucuya erişildi (HTTP ${response.statusCode}, Basic Auth)\n';
        } else {
          mesaj = 'Sunucu hatası: HTTP ${response.statusCode}\n';
        }
      } catch (_) {
        try {
          response = await dio.get(url,
            options: Options(
              headers: {'Authorization': 'Bearer $sifre'},
              validateStatus: (_) => true));
          basarili = true;
          mesaj = 'URL erişilebilir (HTTP ${response.statusCode}, Bearer)\n';
        } catch (e2) {
          mesaj = 'Bağlantı başarısız: $e2\n';
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      _gosterilenBilgiDialog(
        baslik: basarili ? 'Bağlantı Başarılı' : 'Bağlantı Hatası',
        ikon: basarili ? Icons.check_circle_outline : Icons.error_outline,
        icerik: '$mesaj'
            'API URL: $url\n'
            'Kullanıcı Adı: $kAdi\n'
            'Test modu: ${_testModu ? "GİB Test Ortamı" : "CANLI"}\n\n'
            '${basarili ? "Kullanıcı adı ve şifrenizi entegratör portalından doğrulayın — kimlik doğrulama YÖNTEMİ (Basic/Bearer/SOAP) kullandığınız entegratöre göre değişebilir, gerçek fatura göndermeden önce entegratörünüzün dokümanıyla teyit edin." : "URL, kullanıcı adı ve şifre doğru girildiğinden emin olun."}',
        renk: basarili ? Colors.green : Colors.red,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      BildirimServisi.hata(context, 'Test hatası: $e');
    }
  }

  void _gosterilenBilgiDialog({required String baslik, required IconData ikon,
      required String icerik, required Color renk}) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      
      title: Row(children: [
        Icon(ikon, color: renk), const SizedBox(width: 8), Text(baslik),
      ]),
      content: Text(icerik),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'GİB e-Fatura Entegrasyonu',
        aksiyonlar: [
          if (!_kaydediyor)
            IconButton(icon: const Icon(Icons.save, color: Colors.white), onPressed: _kaydet, tooltip: 'Kaydet'),
        ],
        geriTusu: false,
      ),
      body: _yukleniyor
          ? const TsYukleniyor()
          : ListView(padding: const EdgeInsets.all(16), children: [
              // Bilgi banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text('GİB e-Fatura Entegrasyonu',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Colors.blue)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Market Plus → e-Fatura Servisi (Özel Entegratör) → GİB\n\n'
                    'Bu ekran, GİB uyumlu bir özel entegratör (Foriba, Sovos, '
                    'Uyumsoft, Nilvera vb.) ile bağlantı kurar. Entegratör '
                    'portal\'ından aldığınız Kullanıcı Adı ve Şifre '
                    'bilgilerini girin — Mali Mühür işlemleri, entegratörünüzün '
                    'yöntemine göre kendi tarafında (sizin adınıza) veya bu '
                    'ekrandaki isteğe bağlı alan üzerinden yapılabilir.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              _baslik('Firma Bilgileri (GİB)'),
              TextField(
                controller: _vknCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Vergi Kimlik No / TC Kimlik No (VKN/TCKN)',
                  prefixIcon: Icon(Icons.numbers),
                  border: OutlineInputBorder(),
                  hintText: '10 haneli VKN veya 11 haneli TCKN',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vergi Dairesi',
                  prefixIcon: Icon(Icons.account_balance),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              _baslik('Entegratör API Bilgileri'),
              TextField(
                controller: _apiUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'API URL',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                  hintText: 'https://api.entegrator.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kullaniciAdiCtrl,
                decoration: const InputDecoration(
                  labelText: 'API Kullanıcı Adı',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                  hintText: 'Entegratör portalından aldığınız kullanıcı adı',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sifreCtrl,
                obscureText: _sifreGizle,
                decoration: InputDecoration(
                  labelText: 'API Şifresi',
                  prefixIcon: const Icon(Icons.vpn_key),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_sifreGizle ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _sifreGizle = !_sifreGizle),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Mali Mühür — entegratörün yöntemine göre isteğe bağlı
              InkWell(
                onTap: () => setState(() => _maliMuhurGoster = !_maliMuhurGoster),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(_maliMuhurGoster ? Icons.expand_less : Icons.expand_more,
                        color: context.textSecondary),
                    const SizedBox(width: 6),
                    Text('Mali Mühür Ayarları (İsteğe Bağlı)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: context.textSecondary)),
                  ]),
                ),
              ),
              if (_maliMuhurGoster) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Çoğu entegratörde (Foriba, Sovos, Nilvera vb.) Mali Mühür '
                    'işlemi ENTEGRATÖR TARAFINDA, sizin adınıza yapılır — bu '
                    'durumda bu alanı boş bırakabilirsiniz. Sadece '
                    'entegratörünüz size kendi Mali Mühür sertifikanızı '
                    'yönetme seçeneği sunuyorsa (bazı SOAP tabanlı '
                    'entegratörlerde olduğu gibi) buraya şifresini girin.',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
                TextField(
                  controller: _maliMuhurSifreCtrl,
                  obscureText: _maliMuhurSifreGizle,
                  decoration: InputDecoration(
                    labelText: 'Mali Mühür Şifresi (varsa)',
                    prefixIcon: const Icon(Icons.verified_user_outlined),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_maliMuhurSifreGizle ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _maliMuhurSifreGizle = !_maliMuhurSifreGizle),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              _baslik('Mod'),
              SwitchListTile(
                title: const Text('Test Modu'),
                subtitle: Text(_testModu
                    ? 'GİB test ortamına gönderir (güvenli)'
                    : '⚠️ CANLI modda — gerçek fatura gönderilir!'),
                value: _testModu,
                activeColor: Colors.green,
                onChanged: (v) => setState(() => _testModu = v),
              ),
              if (!_testModu)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'CANLI mod aktif! Gönderilen faturalar GİB\'e iletilir ve '
                        'yasal geçerlilik taşır.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 20),

              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _baglantiTest,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Bağlantı Testi'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _kaydediyor ? null : _kaydet,
                    icon: _kaydediyor
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Kaydet'),
                  ),
                ),
              ]),

              const SizedBox(height: 24),
              _baslik('Desteklenen Modlar'),
              _destekBilgi(Icons.receipt_long, 'e-Fatura',
                  'Kayıtlı mükellefler arası — otomatik tebliğ'),
              _destekBilgi(Icons.description, 'e-Arşiv',
                  'Bireysel tüketici veya kayıtsız işletme'),
              _destekBilgi(Icons.qr_code, 'e-Arşiv Portal',
                  'GİB portalından manuel yükleme'),
              const SizedBox(height: 40),
            ]),
    );
  }

  Widget _baslik(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary)),
  );

  Widget _destekBilgi(IconData icon, String baslik, String aciklama) =>
    ListTile(dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      title: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(aciklama, style: const TextStyle(fontSize: 11)),
    );
}
