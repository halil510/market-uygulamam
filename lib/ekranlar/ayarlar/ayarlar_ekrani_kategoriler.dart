// lib/ekranlar/ayarlar/ayarlar_ekrani_kategoriler.dart
//
// ayarlar_ekrani.dart'ın parçası (part/part of) — Ayarlar'ın kategori
// düzeni. Önceden ~48 satır tek uzun listedeydi ("Sistem" başlığı altında
// Günlük Rapor, Etiket Yazdır gibi alakasız öğeler); artık her öğe bir
// kategoriye ait, ekran kategori kartlarıyla açılır, arama tüm
// kategorilerde arar. Öğelerin davranışı (gittikleri rota / çağırdıkları
// metot) BİREBİR eskisi gibi.
part of 'ayarlar_ekrani.dart';

class _Ayar {
  final IconData ikon;
  final Color? renk;
  final String baslik;
  final String? alt;
  final VoidCallback? onTap;
  final bool tehlikeli;

  /// Düz satır yerine özel görünüm (tema seçimi, masa anahtarı).
  final Widget? ozel;

  /// Başlık/alt başlıkta geçmeyen ama aranınca bulunması gereken sözcükler.
  final String ekAnahtar;

  const _Ayar({
    required this.ikon,
    required this.baslik,
    this.renk,
    this.alt,
    this.onTap,
    this.tehlikeli = false,
    this.ozel,
    this.ekAnahtar = '',
  });

  bool eslesir(String normalArama) =>
      aramaNormalize('$baslik ${alt ?? ''} $ekAnahtar').contains(normalArama);
}

class _AyarKategori {
  final String ad;
  final IconData ikon;
  final Color renk;
  final List<_Ayar> ayarlar;
  const _AyarKategori(this.ad, this.ikon, this.renk, this.ayarlar);
}

extension _AyarlarKategorileri on _AyarlarEkraniState {
  _Ayar _git(
    IconData ikon,
    String baslik,
    String rota, {
    String? alt,
    Color? renk,
    String ekAnahtar = '',
  }) => _Ayar(
    ikon: ikon,
    baslik: baslik,
    alt: alt,
    renk: renk,
    ekAnahtar: ekAnahtar,
    onTap: () => context.push(rota),
  );

  List<_AyarKategori> _kategoriler() {
    final masaAcik = ref.watch(masaModuProvider);
    return [
      _AyarKategori(
        'Firma & Görünüm',
        Icons.storefront_outlined,
        TsRenk.primary,
        [
          _Ayar(
            ikon: Icons.business,
            baslik: 'Firma Bilgileri',
            alt:
                '${_ayarlar['firma_adi'] ?? 'BarkoPro'} · '
                '${_ayarlar['firma_adres'] ?? 'Adres girilmemiş'}',
            ekAnahtar: 'adres vergi telefon unvan',
            onTap: _firmaBilgisiDuzenle,
          ),
          _Ayar(
            ikon: Icons.dark_mode_outlined,
            baslik: 'Tema',
            ekAnahtar: 'açık koyu karanlık gece görünüm renk',
            ozel: RadioGroup<String>(
              groupValue: _ayarlar['tema'] ?? 'light',
              onChanged: (v) => _temaDegistir(v!),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text('Açık Tema'),
                    value: 'light',
                  ),
                  RadioListTile<String>(
                    title: Text('Koyu Tema'),
                    value: 'dark',
                  ),
                ],
              ),
            ),
          ),
          _git(
            Icons.bolt_rounded,
            'Hızlı Tuşlar',
            '/satis/hizli-tuslar',
            alt:
                'Barkodsuz/sık satılan ürünler için kasa tuşları '
                '(ekmek, poşet, çay, su)',
            ekAnahtar: 'favori plu',
          ),
          _Ayar(
            ikon: Icons.table_restaurant,
            baslik: 'Masa / Restoran Modülü',
            ekAnahtar: 'kafe lokanta mutfak bar',
            ozel: SwitchListTile(
              secondary: const Icon(
                Icons.table_restaurant,
                color: TsRenk.masaAcik,
              ),
              title: const Text('Masa / Restoran Modülü'),
              subtitle: const Text(
                'Sadece kafe/lokanta hizmeti olan şubelerde açın. '
                'Kapatırsanız "Masalar" ve "Mutfak/Bar" ana ekrandan gizlenir.',
              ),
              value: masaAcik,
              onChanged: (v) => ref.read(masaModuProvider.notifier).degistir(v),
            ),
          ),
          if (masaAcik)
            _git(
              Icons.add_box_outlined,
              'Masa Ekle / Yönet',
              '/masa/yonet',
              alt: 'Tek veya toplu masa ekle · QR menü kartlarını yazdır',
              renk: TsRenk.masaAcik,
            ),
          _git(
            Icons.photo_library_outlined,
            'İşyeri Fotoğrafları (Web Sitesi)',
            '/ayarlar/site-fotograflari',
            alt: 'QR menü sitesindeki fotoğrafları buradan yönetin',
          ),
          _git(
            Icons.edit_note_outlined,
            'Site İçeriği (Web Sitesi)',
            '/ayarlar/site-icerik',
            alt:
                'İşletme adı, hakkımızda, iletişim ve konum bilgilerini '
                'buradan düzenleyin',
          ),
        ],
      ),
      _AyarKategori(
        'Yazdırma & Etiket',
        Icons.print_outlined,
        TsRenk.vurguTurkuaz,
        [
          _git(
            Icons.print,
            'Yazdırma Merkezi',
            '/ayarlar/yazdirma',
            alt: 'Yazıcılar · Fiş Tasarımı · Fatura Ayarları — tek sayfa',
            ekAnahtar: 'yazıcı fiş termal bluetooth usb wifi',
          ),
          _git(
            Icons.label,
            'Etiket Yazdır',
            '/barkod/etiket',
            ekAnahtar: 'raf etiketi barkod',
          ),
          _git(
            Icons.qr_code_2,
            'Barkod Üreteci',
            '/barkod/uret',
            alt: 'EAN-13, QR, Code128 üret ve kaydet',
          ),
        ],
      ),
      _AyarKategori(
        'Ürün & Stok',
        Icons.inventory_2_outlined,
        TsRenk.basarili,
        [
          _git(
            Icons.category,
            'Kategoriler',
            '/urun/kategori',
            ekAnahtar: 'grup',
          ),
          _git(Icons.branding_watermark, 'Markalar', '/urun/marka'),
          _git(
            Icons.straighten,
            'Birim Yönetimi',
            '/birim',
            alt: 'Adet, kg, lt gibi birimler',
          ),
          _git(
            Icons.inventory_2,
            'Lot / Seri No Takibi',
            '/lot',
            alt: 'SKT ve lot takibi',
            ekAnahtar: 'son kullanma tarihi',
          ),
          _git(
            Icons.local_offer,
            'Promosyonlar',
            '/promosyon',
            ekAnahtar: 'kampanya indirim',
          ),
          _git(
            Icons.storefront_outlined,
            'Fiyat Grupları (Bayi/Toptan)',
            '/toptan/fiyat-gruplari',
            alt: 'Bayi tipleri ve toptan fiyatlandırma',
          ),
          _git(
            Icons.bolt_outlined,
            'Toplu Ürün İşlemi',
            '/urun/toplu-islem',
            alt: 'Fiyat, grup, KDV toplu güncelleme',
          ),
          _git(
            Icons.price_change_outlined,
            'Toplu Fiyat Güncelleme',
            '/urun/toplu-fiyat',
            alt: 'Kategori/marka bazlı zam/indirim',
          ),
          _Ayar(
            ikon: Icons.visibility,
            baslik: 'Pasif Ürünleri Aktif Yap',
            alt: 'Listede görünmeyen ürünleri aktif hale getir',
            onTap: _pasifleriAktifYap,
          ),
          _Ayar(
            ikon: Icons.upload_file,
            baslik: 'Ürünleri Excel\'e Aktar',
            alt: 'Tüm ürünleri xlsx olarak paylaş',
            onTap: _urunleriExcelEAktar,
          ),
          _Ayar(
            ikon: Icons.download_for_offline,
            baslik: 'Excel\'den Ürün Al',
            alt: 'Xlsx dosyasından toplu yükle/güncelle',
            onTap: _exceldenUrunIceAl,
          ),
          _git(Icons.local_shipping, 'Tedarikçi Siparişleri', '/tedarik'),
          _git(
            Icons.lightbulb_outline,
            'Satın Alma Önerileri',
            '/tedarik/oneriler',
            alt: 'Kritik stoktaki ürünler için sipariş önerisi',
          ),
          _git(
            Icons.local_shipping_outlined,
            'İrsaliye / Sevkiyat',
            '/irsaliye',
            alt: 'Sevk irsaliyeleri yönetimi',
          ),
        ],
      ),
      _AyarKategori(
        'Fatura & e-Belge',
        Icons.receipt_long_outlined,
        TsRenk.uyari,
        [
          _git(
            Icons.receipt_long,
            'GİB e-Fatura Entegrasyonu',
            '/ayarlar/gib',
            alt: 'e-Fatura / e-Arşiv yapılandırması',
            ekAnahtar: 'gib entegratör e-irsaliye',
          ),
          _git(
            Icons.format_list_numbered,
            'Fatura Seri Mutabakatı',
            '/ayarlar/seri-mutabakati',
            alt: 'Numara blokları, kullanılan/kalan numaralar, boşluk kontrolü',
          ),
          _git(
            Icons.point_of_sale_outlined,
            'Terminaller',
            '/ayarlar/terminaller',
            alt:
                'Fatura kesen cihazlar — ad verme, kaybolan cihazı pasife alma',
            ekAnahtar: 'kasa cihaz',
          ),
          _git(
            Icons.currency_exchange,
            'Döviz Kurları',
            '/ayarlar/doviz',
            alt: 'USD, EUR, GBP karşılıkları',
            ekAnahtar: 'dolar euro kur',
          ),
        ],
      ),
      _AyarKategori('Kullanıcı & Şube', Icons.people_outline, TsRenk.bilgi, [
        _git(
          Icons.people,
          'Kullanıcı Yönetimi',
          '/kullanici',
          ekAnahtar: 'personel yetki rol kasiyer',
        ),
        _git(
          Icons.store,
          'Şube Yönetimi',
          '/sube',
          alt: 'Çoklu şube ekle ve yönet',
        ),
        _git(
          Icons.history,
          'İşlem Geçmişi (Audit Log)',
          '/ayarlar/audit-log',
          alt: 'Kim, ne zaman, ne değiştirdi',
        ),
      ]),
      _AyarKategori(
        'Bulut, Yedek & Veri',
        Icons.cloud_outlined,
        TsRenk.vurguMor,
        [
          _git(
            Icons.cloud_sync,
            'Bulut Senkronizasyon',
            '/ayarlar/bulut-sync',
            alt: 'Supabase ile bulut veri senkronizasyonu',
            ekAnahtar: 'sync senkron',
          ),
          _git(
            Icons.backup,
            'Yedekleme',
            '/ayarlar/yedek',
            ekAnahtar: 'yedek geri yükle otomatik',
          ),
          _git(
            Icons.sync_alt,
            'Veri Aktarımı WiFi',
            '/ayarlar/sync',
            ekAnahtar: 'cihazlar arası aktar bluetooth',
          ),
          _git(
            Icons.health_and_safety_outlined,
            'Veri Sağlığı Merkezi',
            '/ayarlar/veri-sagligi',
            alt: 'Mutabakat, negatif stok, mükerrer barkod, sync durumu',
          ),
          _git(
            Icons.event_repeat_outlined,
            'Dönem Yönetimi / Yıl Sonu Devir',
            '/ayarlar/donem-yonetimi',
            alt: 'Yıl sonu kontrolü, yedekleme, dönem kapatma',
            ekAnahtar: 'devir arşiv',
          ),
          _Ayar(
            ikon: Icons.download,
            baslik: 'Veritabanını İçe Aktar',
            alt: '.db dosyasından geri yükleme yap',
            onTap: _veritabaniniIceriAl,
          ),
          _Ayar(
            ikon: Icons.upload_file,
            baslik: 'Veritabanını Dışa Aktar',
            alt: '${DbSabitler.dbAdi} dosyasını kaydet/paylaş',
            onTap: _dbDisariAktar,
          ),
          _git(
            Icons.history,
            'Sistem Logları',
            '/ayarlar/log',
            alt: 'Hata ve işlem kayıtları',
          ),
          _git(
            Icons.bug_report_outlined,
            'Hata İzleme',
            '/ayarlar/hata-izleme',
            alt:
                'Uygulama hatalarını uzaktan görmek için Sentry bağlayın '
                '(isteğe bağlı)',
          ),
          _Ayar(
            ikon: Icons.delete_sweep,
            baslik: 'Veritabanını Temizle',
            alt: 'Tüm verileri kalıcı olarak siler',
            tehlikeli: true,
            onTap: _veritabaniniTemizle,
          ),
        ],
      ),
      _AyarKategori(
        'Rapor & Yapay Zekâ',
        Icons.insights_outlined,
        TsRenk.notr,
        [
          _git(
            Icons.bar_chart,
            'Günlük Rapor',
            '/rapor/gunluk',
            ekAnahtar: 'gün sonu',
          ),
          _git(
            Icons.trending_up,
            'Kâr / Zarar Raporu',
            '/rapor/kar',
            ekAnahtar: 'kar zarar',
          ),
          _git(
            Icons.auto_graph,
            'Akıllı Analiz',
            '/ai',
            alt: 'Yapay zeka destekli satış analizleri',
          ),
          _git(
            Icons.smart_toy_outlined,
            'AI Asistan Ayarları',
            '/ayarlar/ai-asistan',
            alt: 'Gemini API anahtarı, akıllı sohbet ve foto doldurma',
            ekAnahtar: 'asistan yapay zeka',
          ),
        ],
      ),
    ];
  }

  // ── Görünümler ────────────────────────────────────────────────────────

  Widget _aramaKutusu() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: _aramaCtrl,
      focusNode: _aramaOdak,
      onChanged: _aramaDegis,
      decoration: InputDecoration(
        hintText: 'Ayarlarda ara (ör. yazıcı, yedek, şube)',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _arama.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Temizle',
                onPressed: _aramaTemizle,
              ),
      ),
    ),
  );

  Widget _satir(_Ayar a, Color kategoriRenk) {
    if (a.ozel != null) return a.ozel!;
    final renk = a.tehlikeli ? TsRenk.hata : (a.renk ?? kategoriRenk);
    return ListTile(
      leading: Icon(a.ikon, color: renk),
      title: Text(
        a.baslik,
        style: a.tehlikeli ? const TextStyle(color: TsRenk.hata) : null,
      ),
      subtitle: a.alt == null ? null : Text(a.alt!),
      trailing: Icon(
        a.tehlikeli ? Icons.warning_amber : Icons.chevron_right,
        color: a.tehlikeli ? TsRenk.hata : null,
      ),
      onTap: a.onTap,
    );
  }

  /// Kategori kartları ızgarası (arama boş, kategori seçilmemişken).
  Widget _kategoriIzgarasi(List<_AyarKategori> kategoriler) {
    final kolon = TsResponsive.izgaraKolonSayisi(
      context,
      telefon: 2,
      tablet: 3,
      genis: 4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: kolon,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: kolon >= 4 ? 2.6 : (kolon == 3 ? 1.9 : 1.45),
        children: [for (final k in kategoriler) _kategoriKarti(k)],
      ),
    );
  }

  Widget _kategoriKarti(_AyarKategori k) {
    final ozet = k.ayarlar.take(3).map((a) => a.baslik).join(' · ');
    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(TsRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(TsRadius.md),
        onTap: () => _kategoriSec(k.ad),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TsRadius.md),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: TsRenk.zemin(k.renk),
                      borderRadius: BorderRadius.circular(TsRadius.sm),
                    ),
                    child: Icon(k.ikon, color: k.renk, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    '${k.ayarlar.length}',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                k.ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TsMetin.govdeVurgu.copyWith(color: context.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                ozet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TsMetin.kucuk.copyWith(color: context.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seçili kategorinin ayarları.
  List<Widget> _kategoriIcerigi(_AyarKategori k) => [
    ListTile(
      leading: const Icon(Icons.arrow_back),
      title: Text(k.ad, style: TsMetin.baslikM),
      subtitle: const Text('Tüm ayarlara dön'),
      onTap: () => _kategoriSec(null),
    ),
    const Divider(height: 1),
    for (final a in k.ayarlar) _satir(a, k.renk),
  ];

  /// Arama sonucu: eşleşen ayarlar, kategori başlıklarıyla.
  List<Widget> _aramaSonucu(List<_AyarKategori> kategoriler) {
    final q = aramaNormalize(_arama.trim());
    final cikti = <Widget>[];
    for (final k in kategoriler) {
      final eslesen = k.ayarlar.where((a) => a.eslesir(q)).toList();
      if (eslesen.isEmpty) continue;
      cikti
        ..add(_AyarBaslik(k.ad))
        ..addAll(eslesen.map((a) => _satir(a, k.renk)));
    }
    if (cikti.isEmpty) {
      cikti.add(
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              '"${_arama.trim()}" ile eşleşen ayar yok',
              style: TextStyle(color: context.textSecondary),
            ),
          ),
        ),
      );
    }
    return cikti;
  }
}
