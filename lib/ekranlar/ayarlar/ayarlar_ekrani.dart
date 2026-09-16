import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:typed_data';
// lib/ekranlar/ayarlar/ayarlar_ekrani.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../widgetlar/ortak/app_widgetlar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../../servisler/auth_servisi.dart';
import '../../depolar/kullanici_deposu.dart';
import '../../saglayicilar/riverpod/auth_provider.dart';
import '../../servisler/bildirim_servisi.dart';
import '../../depolar/ayarlar_deposu.dart';
import '../../servisler/excel_servisi.dart';
import '../../saglayicilar/riverpod/masa_modu_provider.dart';
import '../../depolar/urun_deposu.dart';
import '../../veri/database/veritabani.dart';
import '../../cekirdek/sabitler/db_sabitleri.dart';
import '../../cekirdek/sabitler/uygulama_sabitleri.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../widgetlar/ortak/yukleniyor_widget.dart';
import '../../widgetlar/ortak/onay_dialog.dart';
import '../../saglayicilar/riverpod/tema_provider.dart';
import '../../servisler/bulut/supabase_ayarlari.dart';

class AyarlarEkrani extends ConsumerStatefulWidget {
  const AyarlarEkrani({super.key});
  @override
  ConsumerState<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends ConsumerState<AyarlarEkrani> {
  final _ayarlarDepo = AyarlarDeposu();
  final _urunDepo = UrunDeposu();
  Map<String, String> _ayarlar = {};
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  Future<void> _yukle() async {
    if (mounted) setState(() => _yukleniyor = true);
    try {
      final ayarlar = await _ayarlarDepo.hepsiGetir();
      if (mounted) {
        setState(() {
          _ayarlar = ayarlar;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      // 🔴 DÜZELTME: catch bloğu _yukleniyor'u hiç false yapmıyordu —
      // hata olursa ekran sonsuza kadar "yükleniyor" durumunda kalıyordu.
      if (kDebugMode) debugPrint('Hata: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _ayarGuncelle(String anahtar, String deger) async {
    try {
      await _ayarlarDepo.kaydet(anahtar, deger);
      if (mounted) setState(() => _ayarlar[anahtar] = deger);
    } catch (e) {
      if (kDebugMode) debugPrint('Ayar kaydetme hatası: $e');
    }
  }

  Future<void> _cikisYap() async {
    bool onay = false;
    try {
      onay = await OnayDialog.goster(
        context,
        baslik: 'Çıkış Yap',
        icerik: 'Oturumu kapatmak istiyor musunuz?',
        onayYazi: 'Çıkış Yap',
        onayRengi: Colors.red,
        ikon: Icons.logout,
      );
    } catch (_) {
      onay = false;
    }
    if (!onay || !mounted) return;
    try {
      await ref.read(authProvider.notifier).cikisYap();
      if (mounted) context.go('/giris');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Çıkış hatası: $e');
    }
  }

  void _temaDegistir(String tema) {
    // ÖNEMLİ DÜZELTME: Önceden sadece SharedPreferences'a yazılıyordu,
    // canlı tema (MaterialApp) hiç güncellenmiyordu — kullanıcı "Koyu Tema"
    // seçtiğinde uygulama yeniden başlatılana kadar hiçbir şey değişmiyordu.
    // Artık temaProvider üzerinden değiştiriliyor; ekran anında güncelleniyor.
    ref.read(temaProvider.notifier).degistir(tema);
    setState(() => _ayarlar['tema'] = tema);
  }

  Future<void> _firmaBilgisiDuzenle() async {
    final adCtrl = TextEditingController(text: _ayarlar['firma_adi'] ?? '');
    final adrCtrl = TextEditingController(text: _ayarlar['firma_adres'] ?? '');
    final telCtrl =
        TextEditingController(text: _ayarlar['firma_telefon'] ?? '');
    final verCtrl =
        TextEditingController(text: _ayarlar['firma_vergi_no'] ?? '');

    await showDialog(
      context: context,
      builder: (dCtx1) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Firma Bilgileri'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: adCtrl,
                decoration: const InputDecoration(
                    labelText: 'Firma Adı', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: adrCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Adres', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: telCtrl,
                decoration: const InputDecoration(
                    labelText: 'Telefon', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
                controller: verCtrl,
                decoration: const InputDecoration(
                    labelText: 'Vergi No', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx1),
              child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              try {
                await _ayarGuncelle('firma_adi', adCtrl.text.trim());
                await _ayarGuncelle('firma_adres', adrCtrl.text.trim());
                await _ayarGuncelle('firma_telefon', telCtrl.text.trim());
                await _ayarGuncelle('firma_vergi_no', verCtrl.text.trim());
                if (!mounted) return;
                Navigator.pop(dCtx1);
                BildirimServisi.basari(context, 'Firma bilgileri kaydedildi ✓');
              } catch (e) {
                if (!mounted) return;
                BildirimServisi.hata(context, 'Kayıt hatası: $e');
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    adCtrl.dispose();
    adrCtrl.dispose();
    telCtrl.dispose();
    verCtrl.dispose();
  }

  // ── VERİTABANINI İÇE AKTAR (DÜZELTİLMİŞ) ─────────────────────────────────────
  Future<void> _veritabaniniIceriAl() async {
    final onay = await OnayDialog.goster(
      context,
      baslik: 'Veritabanını İçe Aktar',
      icerik:
          'Mevcut veritabanının üzerine yazılacak. Bu işlem geri alınamaz.\n\nDevam etmek istediğinize emin misiniz?',
      onayYazi: 'Devam Et',
      onayRengi: Colors.orange,
    );
    if (!onay) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final dosya = result.files.single;
      if (dosya.path == null) {
        if (mounted) BildirimServisi.hata(context, 'Dosya yolu alınamadı');
        return;
      }

      final uzanti = dosya.extension?.toLowerCase();
      if (uzanti != 'db') {
        if (mounted)
          BildirimServisi.hata(context, 'Lütfen .db uzantılı dosya seçin');
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            const ProgressDialog(mesaj: 'Veritabanı içe aktarılıyor...'),
      );

      try {
        final bytes = await File(dosya.path!).readAsBytes();
        // Basit SQLite imza doğrulaması
        if (bytes.length < 16 ||
            String.fromCharCodes(bytes.sublist(0, 15)) != 'SQLite format 3') {
          if (mounted) Navigator.of(context).pop();
          if (mounted)
            BildirimServisi.hata(
                context, 'Geçerli bir SQLite veritabanı dosyası değil');
          return;
        }

        await Veritabani().kapat();

        final dbPath = await getDatabasesPath();
        final dbFile = File(p.join(dbPath, DbSabitler.dbAdi));
        // ÖNCEDEN BURADA CİDDİ İKİ EKSİKLİK VARDI:
        // 1) Sadece ana .db dosyası siliniyordu, -wal ve -shm
        //    dosyaları SİLİNMİYORDU. SQLite WAL modunda son yazılan
        //    (henüz ana dosyaya işlenmemiş) veriler -wal dosyasında
        //    durur — kullanıcının "banka işlemleri temizlenmedi/geri
        //    geldi" şikayeti tam olarak buydu: eski -wal dosyası
        //    kalınca, YENİ içe aktarılan veritabanı açıldığında
        //    SQLite bu ESKİ, artık ilgisiz WAL kayıtlarını yeni
        //    dosyaya karıştırıyordu.
        // 2) İçe aktarmadan önce mevcut veritabanının güvenlik
        //    kopyası alınmıyordu — yanlış bir dosya seçilirse mevcut
        //    veri geri dönüşsüz kaybolabilirdi (Yedekleme'de daha
        //    önce bulup düzelttiğim aynı hata sınıfı).
        final walFile = File(p.join(dbPath, '${DbSabitler.dbAdi}-wal'));
        final shmFile = File(p.join(dbPath, '${DbSabitler.dbAdi}-shm'));
        final guvenlikYedegi =
            '${dbFile.path}.import_oncesi_${DateTime.now().millisecondsSinceEpoch}.bak';
        if (await dbFile.exists()) await dbFile.copy(guvenlikYedegi);

        if (await dbFile.exists()) await dbFile.delete();
        if (await walFile.exists()) await walFile.delete();
        if (await shmFile.exists()) await shmFile.delete();
        await dbFile.writeAsBytes(bytes);

        final prefs = await SharedPreferences.getInstance();
        final savedTheme = prefs.getString('tema_adi');
        await prefs.clear();
        if (savedTheme != null) {
          await prefs.setString('tema_adi', savedTheme);
        }

        if (mounted) Navigator.of(context).pop();

        if (mounted) {
          BildirimServisi.basari(context,
              'Veritabanı içe aktarıldı. Uygulama yeniden başlatılıyor...');
          Future.delayed(const Duration(seconds: 1), () => exit(0));
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) BildirimServisi.hata(context, 'İçe aktarma hatası: $e');
      }
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Dosya seçme hatası: $e');
    }
  }

  // ── VERİTABANINI TEMİZLE (DÜZELTİLMİŞ) ─────────────────────────────────────
  // lib/ekranlar/ayarlar/ayarlar_ekrani.dart
// ... (üstteki kodlar aynı) ...

  // silinecek _veritabaniniTemizle metodunun YERİNE bunu koy:
  Future<void> _veritabaniniTemizle() async {
    // 🔴🔴 KRİTİK DÜZELTME (kullanıcı bulgusu: "veritabanı temizlemede
    // borç kalıyor"): Bu fonksiyon SADECE yerel SQLite dosyasını
    // siliyordu — Supabase'e (buluta) daha önce senkronize edilmiş
    // hiçbir veriye DOKUNMUYORDU. Sonuç: kullanıcı "temizle" deyip
    // sıfırdan başlasa bile, AYNI Supabase projesine tekrar bağlanıp
    // "Buluttan Al" yaptığı an TÜM eski veriler (borçlar dahil) buluttan
    // geri iniyordu — "temizlik" kalıcı olmuyordu. Artık Supabase
    // yapılandırılmışsa kullanıcı AÇIKÇA uyarılıyor.
    // 🔴 DÜZELTME: Burada 'mp_supa_url' (eski/kullanılmayan anahtar adı)
    // okunuyordu — gerçek bağlantı bilgisi SupabaseAyarlari üzerinden
    // (artık güvenli depoda) tutuluyor. Bu yüzden bu uyarı, Supabase
    // gerçekten yapılandırılmış olsa bile HİÇBİR ZAMAN tetiklenmiyordu.
    final bulutUrl = await SupabaseAyarlari.urlOku() ?? '';
    final bulutYapilandirilmis = bulutUrl.isNotEmpty;

    // await SharedPreferences sonrası — ekran kapanmış olabilir
    if (!mounted) return;
    final onay = await OnayDialog.goster(
      context,
      baslik: 'VERİTABANI TEMİZLEME',
      icerik:
          // ÖNCEDEN BURADA YANLIŞ BİR BİLGİ VARDI: "Admin kullanıcısı ve
          // temel ayarlar korunacak" deniyordu, ama fonksiyon aslında
          // veritabanı DOSYASININ TAMAMINI siliyor — admin kullanıcısı
          // KORUNMUYOR, uygulama yeniden açıldığında SIFIRDAN, varsayılan
          // şifreyle (1234) yeniden oluşturuluyor. Kullanıcıyı yanıltmamak
          // için metin düzeltildi.
          'Bu işlem GERİ ALINAMAZ!\n\nTüm ürünler, satışlar, cariler, '
          'kullanıcılar ve diğer TÜM veriler bu CİHAZDAN kesin olarak '
          'silinecek.\n\nUygulama yeniden açıldığında sıfırdan başlayacak — '
          'admin kullanıcısı varsayılan şifreyle (1234) yeniden '
          'oluşturulacak, bunu ilk girişte değiştirmeniz gerekecek.'
          '${bulutYapilandirilmis ? '\n\n⚠️ BULUT UYARISI: Bu cihaz bir '
              'Supabase projesine bağlı. Bu işlem BULUTTAKİ veriyi SİLMEZ '
              '— sadece bu cihazı temizler. Buluta tekrar bağlanıp '
              '"Buluttan Al" yaparsanız (borçlar dahil) ESKİ VERİLER GERİ '
              'GELİR. Buluttaki veriyi de silmek isterseniz, temizlik '
              'sonrası çıkan talimatları izleyin.' : ''}',
      onayYazi: 'Evet, Temizle',
      onayRengi: Colors.red,
      ikon: Icons.warning_amber_rounded,
    );
    if (!onay) return;

    // Kullanıcı isteği: "hatayla temizlenme yapmayalım diye şifre
    // girme yapalım." Az önceki onay diyaloğu tek bir tıkla geçiliyor
    // — kazara dokunma riski var. Artık burada AYRICA mevcut kullanıcının
    // şifresini tekrar girmesi isteniyor; şifre doğrulanmadan temizleme
    // İŞLEMİ BAŞLAMIYOR.
    final aktifKullanici = AuthServisi().aktifKullanici;
    if (aktifKullanici == null) return;
    final sifreCtrl = TextEditingController();
    bool sifreGizli = true;
    if (!mounted) return;
    final sifreDogruMu = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Şifrenizi Doğrulayın'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Devam etmek için mevcut şifrenizi girin.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: sifreCtrl,
              obscureText: sifreGizli,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Şifre',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      sifreGizli ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setStateDialog(() => sifreGizli = !sifreGizli),
                ),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: TsRenk.hata),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Doğrula ve Temizle'),
            ),
          ],
        ),
      ),
    );
    if (sifreDogruMu != true) {
      sifreCtrl.dispose();
      return;
    }

    final girisSonucu = await KullaniciDeposu()
        .girisKontrol(aktifKullanici.kullaniciAdi, sifreCtrl.text);
    sifreCtrl.dispose();
    if (girisSonucu == null) {
      if (mounted)
        BildirimServisi.hata(context, 'Şifre yanlış. Temizleme iptal edildi.');
      return;
    }

    // Loading dialog — girisKontrol await'inden sonra ekran kapanmış olabilir
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const ProgressDialog(mesaj: 'Veritabanı temizleniyor...'),
    );

    try {
      // 1. Veritabanı bağlantısını kapat
      await Veritabani().kapat();

      // 2. DB dosyasının tam yolunu al
      final dbPath = await getDatabasesPath();
      final dbFile = File(p.join(dbPath, DbSabitler.dbAdi));
      final walFile = File(p.join(dbPath, '${DbSabitler.dbAdi}-wal'));
      final shmFile = File(p.join(dbPath, '${DbSabitler.dbAdi}-shm'));

      // 3. Dosyaları sil (WAL modunda -wal ve -shm de silinmeli)
      if (await dbFile.exists()) await dbFile.delete();
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      // 4. Uygulama belgelerindeki gereksiz klasörleri temizle
      final appDir = await getApplicationDocumentsDirectory();
      for (final dir in ['urun_resimleri', 'yedekler', 'raporlar']) {
        final d = Directory('${appDir.path}/$dir');
        if (await d.exists()) {
          await d.delete(recursive: true);
        }
      }

      // 5. SharedPreferences'ta sadece tema bilgisini koru
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('tema_adi');
      await prefs.clear();
      if (savedTheme != null) {
        await prefs.setString('tema_adi', savedTheme);
      }

      // 6. ÖNCEDEN BURASI HİÇ YOKTU: flutter_secure_storage temizlenmiyordu.
      // Bu, GİB şifresi, oturum token'ı gibi hassas bilgilerin "tam
      // temizlik" sonrası bile cihazda KALMASINA yol açıyordu — "temizle"
      // dediğinizde gerçekten HER ŞEYİN silinmesi bekleniyor.
      const secure = FlutterSecureStorage();
      await secure.deleteAll();

      // 6. Dialog'u kapat
      if (mounted) Navigator.of(context).pop();

      // 7. Bulut yapılandırılmışsa, buluttaki veriyi de temizlemek
      // isteyip istemediğini SQL talimatıyla birlikte göster — RLS
      // (bkz. Supabase şeması) anon anahtarla DELETE'e izin vermiyor,
      // bu yüzden uygulama kendisi silemez; kullanıcı Supabase SQL
      // Editor'de kendi kontrolünde çalıştırmalı.
      if (bulutYapilandirilmis && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Bulut Verisi Hâlâ Duruyor'),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bu cihaz temizlendi, ama Supabase projenizdeki '
                        'veri hâlâ duruyor. Buluta tekrar bağlanırsanız eski '
                        'veriler (borçlar dahil) geri gelir.\n\n'
                        'Buluttaki veriyi de silmek isterseniz, Supabase '
                        'projenizin SQL Editor\'ünde aşağıdaki komutu '
                        'ÇALIŞTIRMANIZ gerekir (uygulama güvenlik nedeniyle '
                        'bunu otomatik yapamaz):'),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8)),
                      child: const SelectableText(
                        "-- DİKKAT: Bu, TÜM iş verisini kalıcı olarak siler!\n"
                        "-- Sadece emin olduğunuzda çalıştırın.\n"
                        "DO \$\$\nDECLARE r RECORD;\nBEGIN\n"
                        "  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname='public') LOOP\n"
                        "    EXECUTE 'TRUNCATE TABLE public.' || quote_ident(r.tablename) || ' CASCADE';\n"
                        "  END LOOP;\nEND \$\$;",
                        style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Not: RLS politikaları anon anahtarla silmeye izin '
                        'vermez (bilinçli güvenlik önlemi) — bu yüzden bu komut '
                        'Supabase panelinden, projenizin sahibi olarak '
                        'çalıştırılmalıdır.',
                        style: TextStyle(
                            fontSize: 11, color: context.textSecondary)),
                  ]),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Anladım')),
            ],
          ),
        );
      }

      // 7. Kullanıcıyı bilgilendir ve uygulamayı kapat
      if (mounted) {
        BildirimServisi.basari(
            context, 'Veritabanı temizlendi. Uygulama yeniden başlatılıyor...');
        // Uygulamayı kapat
        Future.delayed(const Duration(seconds: 2), () {
          exit(0);
        });
      }
    } catch (e) {
      // Hata durumunda dialog'u kapat
      if (mounted) Navigator.of(context).pop();
      if (mounted) BildirimServisi.hata(context, 'Temizleme hatası: $e');
    }
  }

  // ── EXCEL DIŞA AKTAR ───────────────────────────────────────────────────
  Future<void> _urunleriExcelEAktar() async {
    try {
      final urunler = await UrunDeposu().tumunuGetir(sadecaAktif: false);
      if (urunler.isEmpty) {
        if (mounted) BildirimServisi.uyari(context, 'Ürün bulunamadı');
        return;
      }
      if (mounted) BildirimServisi.bilgi(context, 'Excel hazırlanıyor...');
      final yol = await ExcelServisi().urunleriExcelEAktar(urunler);
      await ExcelServisi().paylasExcel(yol);
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  // ── EXCEL İÇE AKTAR (DÜZELTİLMİŞ) ─────────────────────────────────────
  Future<void> _exceldenUrunIceAl() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final dosya = result.files.single;
      // bytes veya path ile oku
      final Uint8List? fileBytes = dosya.bytes ??
          (dosya.path != null ? await File(dosya.path!).readAsBytes() : null);
      if (fileBytes == null) {
        if (mounted) BildirimServisi.hata(context, 'Dosya okunamadı');
        return;
      }

      if (!mounted) return;

      if (!mounted) return;
      final progressCtx = context;
      showDialog(
        context: progressCtx,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (ctx) =>
            const ProgressDialog(mesaj: 'Excel dosyası işleniyor...'),
      );

      IceriAktarSonuc? sonuc;
      try {
        sonuc = await ExcelServisi().exceldenurunleriBytesIceriAl(fileBytes);
      } catch (e) {
        if (mounted) Navigator.of(progressCtx, rootNavigator: true).pop();
        if (mounted) BildirimServisi.hata(context, 'Excel işleme hatası: $e');
        return;
      }

      if (mounted) Navigator.of(progressCtx, rootNavigator: true).pop();
      if (!mounted) return;

      if (sonuc != null && (sonuc.eklenen + sonuc.guncellenen) > 0) {
        await _yukle();
        if (mounted) _excelSonucDialog(sonuc);
      } else {
        if (mounted) _excelHataDialog(sonuc);
      }
    } catch (e) {
      try {
        if (mounted) Navigator.of(context).pop();
      } catch (e) {/* ignore */}
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  void _excelSonucDialog(IceriAktarSonuc sonuc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text('İçe Aktarma Tamamlandı')
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _SonucSatiri('Eklenen Ürün', sonuc.eklenen, Colors.green),
          _SonucSatiri('Güncellenen Ürün', sonuc.guncellenen, Colors.blue),
          if (sonuc.indirimliKaydedilen > 0)
            _SonucSatiri(
                'Otomatik İndirimli', sonuc.indirimliKaydedilen, Colors.orange),
          if (sonuc.hatali > 0)
            _SonucSatiri('Hatalı Satır', sonuc.hatali, Colors.red),
          const SizedBox(height: 8),
          Text('Toplam ${sonuc.toplam} satır işlendi'),
          if (sonuc.indirimliKaydedilen > 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.local_offer, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  '${sonuc.indirimliKaydedilen} üründe otomatik indirim aktif edildi. '
                  'Hızlı satışta barkod okutunca indirimli fiyat uygulanır.',
                  style: const TextStyle(fontSize: 11),
                )),
              ]),
            ),
        ]),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))
        ],
      ),
    );
  }

  void _excelHataDialog(IceriAktarSonuc? sonuc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Text('İçe Aktarma Başarısız')
        ]),
        content: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Hiç ürün eklenemedi.'),
                if (sonuc != null && sonuc.hatalar.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Hatalar:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...sonuc.hatalar.take(5).map((h) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            '• ${h.length > 200 ? '${h.substring(0, 200)}…' : h}',
                            style: const TextStyle(fontSize: 12)),
                      )),
                ],
              ])),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))
        ],
      ),
    );
  }

  Future<void> _pasifleriAktifYap() async {
    try {
      final sonuc = await _urunDepo.tumPasifleriAktifYap();
      if (mounted) {
        BildirimServisi.basari(context, '$sonuc ürün aktif yapıldı');
        await _yukle();
      }
    } catch (e) {
      if (kDebugMode) if (mounted) debugPrint('Hata: $e');
    }
  }

  Future<void> _dbDisariAktar() async {
    try {
      final dbYolu = await Veritabani().dbYolu();
      final dbDosya = File(dbYolu);
      if (!await dbDosya.exists()) {
        if (mounted) BildirimServisi.hata(context, 'DB dosyası bulunamadı');
        return;
      }
      await Share.shareXFiles([XFile(dbYolu)], text: 'MarketPlus Veritabanı');
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }

  Future<bool> _onWillPop() async {
    final isFirst = ModalRoute.of(context)?.isFirst ?? false;
    if (isFirst) {
      final exitConfirmed = await OnayDialog.goster(
        context,
        baslik: 'Uygulamadan Çık',
        icerik: 'Uygulamadan çıkmak istediğinize emin misiniz?',
        onayYazi: 'Evet, Çık',
        onayRengi: Colors.red,
      );
      if (exitConfirmed) exit(0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final aktif = AuthServisi().aktifKullanici;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _onWillPop();
      },
      child: Scaffold(
        appBar: TsAppBar(
          baslik: 'Ayarlar',
          lider: BackButton(onPressed: () => context.go('/')),
        ),
        body: _yukleniyor
            ? const AppYukleniyor()
            : ListView(children: [
                _AyarBaslik('Hesap'),
                ListTile(
                  leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFF4361EE), Color(0xFF3A0CA3)]),
                          shape: BoxShape.circle),
                      child: Center(
                          child: Text(
                              aktif?.adSoyad.isNotEmpty == true
                                  ? aktif!.adSoyad[0]
                                  : 'K',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)))),
                  title: Text(aktif?.adSoyad ?? ''),
                  subtitle: Text(aktif?.rol ?? ''),
                  trailing: TextButton(
                      onPressed: () => context.push('/sifre'),
                      child: const Text('Şifre Değiştir')),
                ),
                const Divider(),
                _AyarBaslik('Firma'),
                ListTile(
                  leading:
                      const Icon(Icons.business, color: AppRenkler.primary),
                  title: Text(_ayarlar['firma_adi'] ?? 'MarketPlus'),
                  subtitle: Text(_ayarlar['firma_adres'] ?? 'Adres girilmemiş'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _firmaBilgisiDuzenle,
                ),
                const Divider(),
                _AyarBaslik('Görünüm'),
                RadioListTile<String>(
                    title: const Text('Açık Tema'),
                    value: 'light',
                    groupValue: _ayarlar['tema'] ?? 'light',
                    onChanged: (v) => _temaDegistir(v!)),
                RadioListTile<String>(
                    title: const Text('Koyu Tema'),
                    value: 'dark',
                    groupValue: _ayarlar['tema'] ?? 'light',
                    onChanged: (v) => _temaDegistir(v!)),
                const Divider(),
                // 🆕 Hızlı tuş yönetimi — kasadaki favori ürün panelini
                // buradan da düzenlenebilir yaptık (birincil giriş yolu
                // Hızlı Satış ekranındaki şimşek butonu).
                _AyarBaslik('Satış'),
                ListTile(
                  leading:
                      const Icon(Icons.bolt_rounded, color: Color(0xFF4361EE)),
                  title: const Text('Hızlı Tuşlar'),
                  subtitle: const Text(
                      'Barkodsuz/sık satılan ürünler için kasa tuşları '
                      '(ekmek, poşet, çay, su)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/satis/hizli-tuslar'),
                ),
                const Divider(),
                _AyarBaslik('Sistem'),
                SwitchListTile(
                  secondary: const Icon(Icons.table_restaurant,
                      color: Color(0xFF6D4C41)),
                  title: const Text('Masa / Restoran Modülü'),
                  subtitle: const Text(
                      'Sadece kafe/lokanta hizmeti olan şubelerde açın. '
                      'Kapatırsanız "Masalar" ve "Mutfak/Bar" ana ekrandan gizlenir.'),
                  value: ref.watch(masaModuProvider),
                  onChanged: (v) =>
                      ref.read(masaModuProvider.notifier).degistir(v),
                ),
                ListTile(
                    leading: const Icon(Icons.print, color: AppRenkler.primary),
                    title: const Text('Yazdırma Merkezi'),
                    subtitle: const Text(
                        'Yazıcılar · Fiş Tasarımı · Fatura Ayarları — tek sayfa'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/yazdirma')),
                ListTile(
                    leading: const Icon(Icons.store, color: Colors.indigo),
                    title: const Text('Şube Yönetimi'),
                    subtitle: const Text('Çoklu şube ekle ve yönet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/sube')),
                ListTile(
                    leading:
                        const Icon(Icons.local_shipping, color: Colors.teal),
                    title: const Text('İrsaliye / Sevkiyat'),
                    subtitle: const Text('Sevk irsaliyeleri yönetimi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/irsaliye')),
                ListTile(
                    leading: const Icon(Icons.inventory_2, color: Colors.brown),
                    title: const Text('Lot / Seri No Takibi'),
                    subtitle: const Text('SKT ve lot takibi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/lot')),
                ListTile(
                    leading: const Icon(Icons.auto_graph, color: Colors.purple),
                    title: const Text('Akıllı Analiz'),
                    subtitle:
                        const Text('Yapay zeka destekli satış analizleri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ai')),
                ListTile(
                    leading: const Icon(Icons.receipt_long, color: Colors.red),
                    title: const Text('GIB e-Fatura Entegrasyonu'),
                    subtitle: const Text('e-Fatura / e-Arşiv yapılandırması'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/gib')),
                ListTile(
                    leading:
                        const Icon(Icons.backup, color: AppRenkler.primary),
                    title: const Text('Yedekleme'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/yedek')),
                ListTile(
                    leading:
                        const Icon(Icons.people, color: AppRenkler.primary),
                    title: const Text('Kullanıcı Yönetimi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/kullanici')),
                ListTile(
                    leading:
                        const Icon(Icons.bar_chart, color: AppRenkler.primary),
                    title: const Text('Günlük Rapor'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/rapor/gunluk')),
                const Divider(),
                _AyarBaslik('Kategoriler & Diğer'),
                ListTile(
                    leading:
                        const Icon(Icons.category, color: AppRenkler.primary),
                    title: const Text('Kategoriler'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/kategori')),
                ListTile(
                    leading: const Icon(Icons.branding_watermark,
                        color: AppRenkler.primary),
                    title: const Text('Markalar'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/marka')),
                ListTile(
                    leading: const Icon(Icons.label, color: AppRenkler.primary),
                    title: const Text('Etiket Yazdır'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/barkod/etiket')),
                ListTile(
                    leading:
                        const Icon(Icons.qr_code_2, color: Colors.deepPurple),
                    title: const Text('Barkod Üreteci'),
                    subtitle: const Text('EAN-13, QR, Code128 üret ve kaydet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/barkod/uret')),
                ListTile(
                    leading: const Icon(Icons.local_offer,
                        color: AppRenkler.primary),
                    title: const Text('Promosyonlar'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/promosyon')),
                ListTile(
                    leading: const Icon(Icons.local_shipping,
                        color: AppRenkler.primary),
                    title: const Text('Tedarikçi Siparişleri'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/tedarik')),
                ListTile(
                    leading: const Icon(Icons.lightbulb_outline,
                        color: AppRenkler.primary),
                    title: const Text('Satın Alma Önerileri'),
                    subtitle: const Text('Kritik stoktaki ürünler için sipariş önerisi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/tedarik/oneriler')),
                ListTile(
                    leading: const Icon(Icons.straighten, color: Colors.brown),
                    title: const Text('Birim Yönetimi'),
                    subtitle: const Text('Adet, kg, lt gibi birimler'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/birim')),
                ListTile(
                    leading: Icon(Icons.history, color: context.textSecondary),
                    title: const Text('Sistem Logları'),
                    subtitle: const Text('Hata ve işlem kayıtları'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/log')),
                ListTile(
                    leading: Icon(Icons.currency_exchange,
                        color: context.textSecondary),
                    title: const Text('Döviz Kurları'),
                    subtitle: const Text('USD, EUR, GBP karşılıkları'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/doviz')),
                ListTile(
                    leading: Icon(Icons.smart_toy_outlined,
                        color: context.textSecondary),
                    title: const Text('AI Asistan Ayarları'),
                    subtitle: const Text(
                        'Gemini API anahtarı, akıllı sohbet ve foto doldurma'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/ai-asistan')),
                ListTile(
                  leading: const Icon(Icons.cloud_sync, color: Colors.blue),
                  title: const Text('Bulut Senkronizasyon'),
                  subtitle:
                      const Text('Supabase ile bulut veri senkronizasyonu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/bulut-sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined, color: Colors.deepOrange),
                  title: const Text('Hata İzleme'),
                  subtitle: const Text(
                      'Uygulama hatalarını uzaktan görmek için Sentry bağlayın (isteğe bağlı)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/hata-izleme'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: Colors.teal),
                  title: const Text('İşyeri Fotoğrafları (Web Sitesi)'),
                  subtitle: const Text(
                      'QR menü sitesindeki fotoğrafları buradan yönetin'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/site-fotograflari'),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.edit_note_outlined, color: Colors.teal),
                  title: const Text('Site İçeriği (Web Sitesi)'),
                  subtitle: const Text(
                      'İşletme adı, hakkımızda, iletişim ve konum bilgilerini buradan düzenleyin'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/site-icerik'),
                ),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.deepPurple),
                  title: const Text('İşlem Geçmişi (Audit Log)'),
                  subtitle: const Text('Kim, ne zaman, ne değiştirdi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/audit-log'),
                ),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined,
                      color: Colors.green),
                  title: const Text('Veri Sağlığı Merkezi'),
                  subtitle: const Text(
                      'Mutabakat, negatif stok, mükerrer barkod, sync durumu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/veri-sagligi'),
                ),
                ListTile(
                  leading: const Icon(Icons.event_repeat_outlined,
                      color: Colors.indigo),
                  title: const Text('Dönem Yönetimi / Yıl Sonu Devir'),
                  subtitle: const Text(
                      'Yıl sonu kontrolü, yedekleme, dönem kapatma'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/ayarlar/donem-yonetimi'),
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_outlined,
                      color: Colors.brown),
                  title: const Text('Fiyat Grupları (Bayi/Toptan)'),
                  subtitle: const Text('Bayi tipleri ve toptan fiyatlandırma'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/toptan/fiyat-gruplari'),
                ),
                ListTile(
                    leading:
                        const Icon(Icons.sync_alt, color: AppRenkler.primary),
                    title: const Text('Veri Aktarımı WiFi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/ayarlar/sync')),
                const Divider(),
                _AyarBaslik('Veri İşlemleri'),
                ListTile(
                    leading: const Icon(Icons.bolt_outlined,
                        color: Colors.deepPurple),
                    title: const Text('Toplu Ürün İşlemi'),
                    subtitle: const Text('Fiyat, grup, KDV toplu güncelleme'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/toplu-islem')),
                ListTile(
                    leading: const Icon(Icons.price_change_outlined,
                        color: Colors.orange),
                    title: const Text('Toplu Fiyat Güncelleme'),
                    subtitle: const Text('Kategori/marka bazlı zam/indirim'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/urun/toplu-fiyat')),
                ListTile(
                    leading: const Icon(Icons.trending_up, color: Colors.green),
                    title: const Text('Kar / Zarar Raporu'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/rapor/kar')),
                ListTile(
                    leading: const Icon(Icons.visibility, color: Colors.green),
                    title: const Text('Pasif Ürünleri Aktif Yap'),
                    subtitle: const Text(
                        'Listede görünmeyen ürünleri aktif hale getir'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pasifleriAktifYap),
                ListTile(
                    leading: const Icon(Icons.upload_file, color: Colors.green),
                    title: const Text('Ürünleri Excel\'e Aktar'),
                    subtitle: const Text('Tüm ürünleri xlsx olarak paylaş'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _urunleriExcelEAktar),
                ListTile(
                    leading: const Icon(Icons.download_for_offline,
                        color: Colors.blue),
                    title: const Text('Excel\'den Ürün Al'),
                    subtitle:
                        const Text('Xlsx dosyasından toplu yükle/güncelle'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exceldenUrunIceAl),
                ListTile(
                    leading: const Icon(Icons.download, color: Colors.purple),
                    title: const Text('Veritabanını İçe Aktar'),
                    subtitle: const Text('.db dosyasından geri yükleme yap'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _veritabaniniIceriAl),
                ListTile(
                    leading:
                        const Icon(Icons.upload_file, color: Colors.orange),
                    title: const Text('Veritabanını Dışa Aktar'),
                    subtitle: const Text(
                        '${DbSabitler.dbAdi} dosyasını kaydet/paylaş'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _dbDisariAktar),
                ListTile(
                    leading: const Icon(Icons.delete_sweep, color: Colors.red),
                    title: const Text('Veritabanını Temizle',
                        style: TextStyle(color: Colors.red)),
                    subtitle: const Text('Tüm verileri kalıcı olarak siler'),
                    trailing:
                        const Icon(Icons.warning_amber, color: Colors.red),
                    onTap: _veritabaniniTemizle),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Çıkış Yap',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: _cikisYap,
                ),
                const SizedBox(height: 8),
                Center(
                    child: Text('MarketPlus v${UygSabitler.versiyon}',
                        style: TextStyle(
                            color: TsRenk.metinIkincil(context),
                            fontSize: 12))),
                const SizedBox(height: 16),
              ]),
      ),
    );
  }
}

// ── Yardımcı widget'lar ───────────────────────────────────────────────────────

class _SonucSatiri extends StatelessWidget {
  final String etiket;
  final int sayi;
  final Color renk;
  const _SonucSatiri(this.etiket, this.sayi, this.renk);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(etiket, style: const TextStyle(fontSize: 14)),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                  color: Color.fromARGB(26, renk.red, renk.green, renk.blue),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('$sayi',
                  style: TextStyle(fontWeight: FontWeight.w700, color: renk))),
        ]),
      );
}

class _AyarBaslik extends StatelessWidget {
  final String baslik;
  const _AyarBaslik(this.baslik);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(baslik,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary)),
      );
}
