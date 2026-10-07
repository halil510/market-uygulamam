// ignore_for_file: invalid_use_of_protected_member
//
// bulut_sync_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Ayar kaydetme, işletme hesabı giriş/çıkış, bağlantı kontrolü, kalıcı hataları yeniden deneme, şimdi gönder.
part of 'bulut_sync_ekrani.dart';

extension _BulutSyncIslemlerExt on _BulutSyncEkraniState {
  Future<void> _simdiGonder() async {
    setState(() => _simdiGonderiliyor = true);
    try {
      await BulutManager().simdiGonder();
      await _ozetiYukle();
      await _kaliciHatalariYukle();
    } finally {
      if (mounted) setState(() => _simdiGonderiliyor = false);
    }
  }

  Future<void> _kaliciHatalariYenidenDene() async {
    setState(() => _kaliciYenidenDeneniyor = true);
    try {
      final adet = await BulutManager().kaliciHatalariYenidenDene();
      _snack('$adet kayıt yeniden gönderim kuyruğuna alındı — sonuç birkaç '
          'saniye içinde burada görünür', Colors.green);
      // Gönderim turunun bitmesine fırsat ver, sonra listeyi tazele.
      await Future.delayed(const Duration(seconds: 5));
      await _kaliciHatalariYukle();
    } finally {
      if (mounted) setState(() => _kaliciYenidenDeneniyor = false);
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
    // Herkese açık anahtarla, işletme hesabına giriş yapılmadan önce
    // bağlantı testi (güvenlik kuralları gereği) 401 döner — adres/anahtar
    // test edilmeden kaydedilir, test girişten sonra yapılır.
    if (!SupabaseOturum.gizliAnahtarMi(key) && !SupabaseOturum().girisli) {
      await SupabaseSyncServisi.ayarlariKaydet(url, key);
      if (!mounted) return;
      setState(() => _kayitYukleniyor = false);
      _snack('Adres ve anahtar kaydedildi ✓ — şimdi aşağıdan işletme hesabıyla giriş yapın.',
          Colors.green);
      return;
    }
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
    if (SupabaseOturum.gizliAnahtarMi(key)) {
      _snack('⚠️ Tam yetkili GİZLİ anahtar kaydedildi — senkron çalışır ama '
          'cihazda tutulması güvensiz. Herkese açık (sb_publishable_) anahtarı '
          'girip işletme hesabıyla giriş yapın.', Colors.orange);
    } else {
      _snack('Bağlantı bilgileri kaydedildi ✓', Colors.green);
    }
  }

  Future<void> _qrMenuUrlKaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(QrMenuAdresi.bulutUrlAnahtari, _qrMenuUrlCtrl.text.trim());
    if (mounted) _snack('QR Menü adresi kaydedildi ✓', Colors.green);
  }

  Future<void> _girisYap() async {
    final eposta = _epostaCtrl.text.trim();
    if (eposta.isEmpty || _sifreCtrl.text.isEmpty) {
      _snack('E-posta ve şifre girin', Colors.red);
      return;
    }
    setState(() => _girisYapiliyor = true);
    try {
      await SupabaseOturum().girisYap(eposta, _sifreCtrl.text);
      _sifreCtrl.clear();
      await BulutManager().baslat();
      // Girişten önce (yetkisiz) denenip kalıcı hataya düşmüş kayıtlar
      // artık gönderilebilir — kuyruğa geri al.
      await BulutManager().kaliciHatalariYenidenDene();
      await _kaliciHatalariYukle();
      if (!mounted) return;
      setState(() => _girisYapiliyor = false);
      _snack('Giriş yapıldı ✓ — bulut bağlantısı işletme hesabıyla güvenli.', Colors.green);
      _baglantiKontrol();
    } catch (e) {
      if (!mounted) return;
      setState(() => _girisYapiliyor = false);
      _snack(e is OturumHatasi ? e.mesaj : 'Giriş yapılamadı: $e', Colors.red);
    }
  }

  Future<void> _cikisYap() async {
    await SupabaseOturum().cikis();
    if (!mounted) return;
    setState(() {});
    _snack('Oturum kapatıldı — cihaz yeniden giriş yapana kadar buluta erişemez.',
        Colors.orange);
    _baglantiKontrol();
  }

  Future<void> _baglantiKontrol() async {
    setState(() { _bagliMi = null; _baglantiMesaj = 'Test ediliyor...'; });
    try {
      final sonuc = await SupabaseSyncServisi.baglantiTest();
      if (mounted) setState(() { _bagliMi = sonuc.basarili; _baglantiMesaj = sonuc.mesaj; });
    } catch (e) {
      // 🔴 DÜZELTME: try-catch yoktu — servis hata verirse ekran
      // sonsuza kadar "Test ediliyor..." durumunda kalabilirdi.
      if (mounted) setState(() { _bagliMi = false; _baglantiMesaj = 'Hata: ${bildirimMetniniSadelestir(e.toString())}'; });
    }
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
}
