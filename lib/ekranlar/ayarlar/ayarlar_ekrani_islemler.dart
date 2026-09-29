// ignore_for_file: invalid_use_of_protected_member
//
// ayarlar_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Firma bilgisi, veritabanı içe al/temizle/dışa aktar, Excel ürün içe/dışa aktarma, pasif ürünleri aktifleştirme.
part of 'ayarlar_ekrani.dart';

extension _AyarlarIslemlerExt on _AyarlarEkraniState {
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
    dialogSonrasiBirak([adCtrl, adrCtrl, telCtrl, verCtrl]);
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
    if (!onay || !mounted) return;
    // Yedek geri yükleme / DB temizleme ile aynı koruma: tüm veritabanının
    // üzerine yazan bu işlem şifre istemiyordu (2026-09-23).
    final onaylandi = await yoneticiSifresiIleOnayIste(
      context,
      baslik: 'Veritabanı İçe Aktarma Onayı',
      aciklama: 'Seçeceğiniz dosya mevcut TÜM verilerin yerine geçecek. '
          'Devam etmek için şifrenizi girin.',
    );
    if (!onaylandi || !mounted) return;
    if (!AuthServisi().isMudur) return; // savunma: eylem anında ikinci kez doğrula

    try {
      final dosya = await FilePicker.pickFile(type: FileType.any);
      if (dosya == null) return;
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
        // İmza + güvenlik kopyası + -wal/-shm temizliği + bütünlük kontrolü
        // (bozuksa önceki veri geri konur) — bkz. VeritabaniDosyaServisi.
        await VeritabaniDosyaServisi().iceAktar(dosya.path!);

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
    final girilenSifre = sifreCtrl.text;
    dialogSonrasiBirak([sifreCtrl]);
    if (sifreDogruMu != true) return;

    final girisSonucu = await KullaniciDeposu()
        .girisKontrol(aktifKullanici.kullaniciAdi, girilenSifre);
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
      // Veritabanı (+wal/shm), resim/yedek/rapor klasörleri, ayarlar (tema
      // hariç) ve güvenli depo (GİB şifresi, oturum) — bkz. servis.
      await VeritabaniDosyaServisi().cihaziSifirla();

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
      final dosya = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (dosya == null) return;
      final Uint8List? fileBytes = await dosya.readAsBytes();
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

      if ((sonuc.eklenen + sonuc.guncellenen) > 0) {
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
                color: TsRenk.zemin(TsRenk.uyari),
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
      final dbYolu = await VeritabaniDosyaServisi().dosyaYolu();
      final dbDosya = File(dbYolu);
      if (!await dbDosya.exists()) {
        if (mounted) BildirimServisi.hata(context, 'DB dosyası bulunamadı');
        return;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(dbYolu)], text: 'BarkoPro Veritabanı'));
    } catch (e) {
      if (mounted) BildirimServisi.hata(context, 'Hata: $e');
    }
  }
}

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
