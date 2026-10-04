// ignore_for_file: invalid_use_of_protected_member
// lib/ekranlar/ayarlar/yazici_ayar_sekmeleri.dart
//
// yazici_ayar_ekrani.dart'ın parçası (part/part of) — WiFi/Bluetooth/USB/Fiş
// sekme gövdeleri. Davranış BİREBİR aynı: State üzerine extension (setState
// aynı State örneği üzerinde çağrılır; analizci yalnızca extension içinden
// "korumalı üye" uyarısı verir).
part of 'yazici_ayar_ekrani.dart';

extension _YaziciAyarSekmeleri on _YaziciAyarEkraniState {
  // ═════════════════════════════════════════════════════════════════════════
  // TAB 1 — WiFi/LAN
  // ═════════════════════════════════════════════════════════════════════════
  Widget _wifiTab() {
    final wifiKayitlilar = _kayitlilar.where((y) => y.tur == 'ag').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ── Bağlantı durumu ──
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      // ── Butonlar ──
      Row(children: [
        Expanded(child: _ActionButon(
          label: _wifiTaraniyor ? 'Taranıyor...' : 'Ağı Tara',
          icon: _wifiTaraniyor ? null : Icons.search,
          loading: _wifiTaraniyor,
          onTap: _wifiTaraniyor ? null : _wifiTara,
          outlined: true,
          renk: _blue,
        )),
        const SizedBox(width: 10),
        Expanded(child: _ActionButon(
          label: 'Manuel IP',
          icon: Icons.add_link,
          onTap: _wifiManuelBaglan,
          renk: _blue,
        )),
      ]),
      const SizedBox(height: 16),

      // ── Bulunan cihazlar ──
      if (_wifiCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan Yazıcılar', sayi: _wifiCihazlar.length),
        const SizedBox(height: 8),
        ..._wifiCihazlar.map((ip) => _CihazKarti(
          ikon: Icons.print,
          renkTon: Colors.green,
          baslik: ip,
          altBaslik: 'Port 9100 · TCP/IP',
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _green,
          onAksiyon: () => _wifiBaglan(ip),
        )),
        const SizedBox(height: 8),
      ],

      // ── Bilgi kutusu ──
      _BilgiKutu(
        renk: _blue,
        ikon: Icons.info_outline,
        mesaj: 'Epson TM, Bixolon, Star Micronics ve diğer ağ yazıcıları TCP/IP '
            '(port 9100) üzerinden bağlanır. Yazıcı ve telefon aynı WiFi ağında olmalıdır.',
      ),

      // ── Kayıtlı yazıcılar ──
      if (wifiKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı WiFi Yazıcılar', sayi: wifiKayitlilar.length),
        const SizedBox(height: 8),
        ...wifiKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB 2 — Bluetooth
  // ═════════════════════════════════════════════════════════════════════════
  Widget _btTab() {
    final btKayitlilar = _kayitlilar.where((y) => y.tur == 'bluetooth').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      _ActionButon(
        label: _btTaraniyor ? 'Taranıyor...' : 'Bluetooth Cihazları Tara',
        icon: _btTaraniyor ? null : Icons.bluetooth_searching,
        loading: _btTaraniyor,
        onTap: _btTaraniyor ? null : _btTara,
        renk: _purple,
        genislik: true,
      ),
      const SizedBox(height: 16),

      if (_btCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan BT Cihazlar', sayi: _btCihazlar.length),
        const SizedBox(height: 8),
        ..._btCihazlar.map((c) => _CihazKarti(
          ikon: Icons.bluetooth,
          renkTon: Colors.purple,
          baslik: c.platformName.isNotEmpty ? c.platformName : 'Bilinmeyen Cihaz',
          altBaslik: c.remoteId.str,
          altBaslikMono: true,
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _purple,
          onAksiyon: () => _btBaglan(c),
        )),
        const SizedBox(height: 8),
      ],

      _BilgiKutu(
        renk: _purple,
        ikon: Icons.bluetooth,
        mesaj: 'Sewoo, Rongta, Bixolon SPP vb. taşınabilir yazıcılar için '
            'önce telefon Ayarlar > Bluetooth ekranından eşleştirin.',
      ),

      if (btKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı BT Yazıcılar', sayi: btKayitlilar.length),
        const SizedBox(height: 8),
        ...btKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB — USB
  // ═════════════════════════════════════════════════════════════════════════
  Widget _usbTab() {
    final usbKayitlilar = _kayitlilar.where((y) => y.tur == 'usb').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _BaglantiDurumKarti(yazdirma: _yazdirma, onKes: () async {
        await _yazdirma.baglantiKes();
        if (!mounted) return;
        setState(() {});
        BildirimServisi.uyari(context, 'Bağlantı kesildi');
      }),
      const SizedBox(height: 16),

      _ActionButon(
        label: _usbTaraniyor ? 'Taranıyor...' : 'USB Cihazları Tara',
        icon: _usbTaraniyor ? null : Icons.usb,
        loading: _usbTaraniyor,
        onTap: _usbTaraniyor ? null : _usbTara,
        renk: _orange,
        genislik: true,
      ),
      const SizedBox(height: 16),

      if (_usbCihazlar.isNotEmpty) ...[
        _Seksiyon(baslik: 'Bulunan USB Cihazlar', sayi: _usbCihazlar.length),
        const SizedBox(height: 8),
        ..._usbCihazlar.map((c) => _CihazKarti(
          ikon: Icons.usb,
          renkTon: Colors.deepOrange,
          baslik: c.productName?.isNotEmpty == true ? c.productName! : 'Bilinmeyen USB Cihaz',
          altBaslik: 'VID:${c.vid?.toRadixString(16) ?? '?'} PID:${c.pid?.toRadixString(16) ?? '?'}',
          altBaslikMono: true,
          aksiyonEtiket: 'Bağlan',
          aksiyonRenk: _orange,
          onAksiyon: () => _usbBaglan(c),
        )),
        const SizedBox(height: 8),
      ],

      _BilgiKutu(
        renk: _orange,
        ikon: Icons.usb,
        mesaj: 'USB kablo ile takılı termal yazıcılar burada listelenir. '
            'Android ilk bağlantıda "USB cihazına erişime izin ver" '
            'sorabilir — izin verin. Yazıcı bir seri (CDC-ACM) cihaz olarak '
            'görünmelidir; bazı özel sürücü gerektiren modellerle çalışmayabilir.',
      ),

      if (usbKayitlilar.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Seksiyon(baslik: 'Kayıtlı USB Yazıcılar', sayi: usbKayitlilar.length),
        const SizedBox(height: 8),
        ...usbKayitlilar.map((y) => _KayitliYaziciKarti(
          yazici: y, onSil: () => _yaziciKaldir(y))),
      ],
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TAB 3 — Fiş Ayarları
  // ═════════════════════════════════════════════════════════════════════════
  Widget _fisTab() => ListView(padding: const EdgeInsets.all(16), children: [
    // ── Firma bilgileri ──
    _KartBolum(
      baslik: 'Firma Bilgileri',
      ikon: Icons.store,
      renk: _blue,
      children: [
        _inputField(context, _firmaAdiCtrl, 'Firma Adı *', 'BarkoPro', Icons.store),
        const SizedBox(height: 12),
        _inputField(context, _firmaAdresCtrl, 'Adres', 'Atatürk Cad. No:1', Icons.location_on),
        const SizedBox(height: 12),
        _inputField(context, _firmaTelCtrl, 'Telefon', '0532 000 00 00', Icons.phone,
            tip: TextInputType.phone),
      ],
    ),
    const SizedBox(height: 16),

    // ── Fiş tasarımı ──
    _KartBolum(
      baslik: 'Fiş Tasarımı',
      ikon: Icons.receipt_long,
      renk: _orange,
      children: [
        _inputField(context, _altYaziCtrl, 'Alt Yazı', 'Teşekkür ederiz!', Icons.text_fields),
        const SizedBox(height: 12),

        // Kağıt boyutu seçici
        DropdownButtonFormField<String>(
          value: _kagitBoy,
          decoration: InputDecoration(
            labelText: 'Kağıt Genişliği',
            prefixIcon: const Icon(Icons.straighten),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          borderRadius: BorderRadius.circular(12),
          items: const [
            DropdownMenuItem(value: '58mm', child: Text('58mm — Mobil yazıcılar')),
            DropdownMenuItem(value: '80mm', child: Text('80mm — Masa yazıcıları (Standart)')),
            DropdownMenuItem(value: '57mm', child: Text('57mm — Kompakt termal')),
            DropdownMenuItem(value: 'A4',   child: Text('A4 — Lazer / Inkjet')),
            DropdownMenuItem(value: 'A4-PDF', child: Text('A4 PDF — Dijital fatura')),
          ],
          onChanged: (v) { if (v != null) setState(() => _kagitBoy = v); },
        ),
        const SizedBox(height: 8),

        // KDV toggle
        Container(
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: SwitchListTile(
            title: const Text('KDV Detayı Göster', style: TsMetin.govdeVurgu),
            subtitle: const Text('Fiş üzerinde KDV dökümünü göster', style: TextStyle(fontSize: 12)),
            value: _kdvGoster,
            onChanged: (v) => setState(() => _kdvGoster = v),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
    const SizedBox(height: 24),

    // ── Eylemler ──
    Row(children: [
      Expanded(child: _ActionButon(
        label: 'Test Fişi',
        icon: Icons.print_outlined,
        onTap: _testFis,
        outlined: true,
        renk: _orange,
      )),
      const SizedBox(width: 12),
      Expanded(child: _ActionButon(
        label: 'Kaydet',
        icon: Icons.save_rounded,
        onTap: _fisAyarlariKaydet,
        renk: _green,
      )),
    ]),
    const SizedBox(height: 8),
  ]);
}
