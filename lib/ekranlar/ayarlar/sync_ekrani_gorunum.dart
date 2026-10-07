// lib/ekranlar/ayarlar/sync_ekrani_gorunum.dart
//
// QR tarayıcı, bağlantı kartları ve akış butonları — sync_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
// ignore_for_file: invalid_use_of_protected_member
part of 'sync_ekrani.dart';

extension _SyncGorunum on _SyncEkraniState {
  // ── QR Tarayıcı ─────────────────────────────────────────────────────────
  Widget _qrTarayiciEkrani() {
    _qrCtrl ??= MobileScannerController();
    return Stack(children: [
      MobileScanner(
        controller: _qrCtrl,
        onDetect: (capture) {
          final val = capture.barcodes.firstOrNull?.rawValue;
          if (val != null && val.startsWith('http')) {
            _qrCtrl?.stop();
            _qrBaglan(val);
          }
        },
      ),
      // Overlay
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent)),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20)),
          ),
          const SizedBox(height: 24),
          const Text('Diğer cihazdaki QR kodu okutun',
            style: TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600)),
          const Spacer(),
          SafeArea(child: Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('İptal'),
              onPressed: () => setState(() { _qrTarayici = false; _qrCtrl?.dispose(); _qrCtrl = null; }),
              style: FilledButton.styleFrom(foregroundColor: Colors.white,
          backgroundColor: Colors.red),
            ),
          )),
        ]),
      ),
    ]);
  }

  // ── Ana Ekran ───────────────────────────────────────────────────────────
  Widget _anaEkran() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // BU CİHAZ — QR
        _qrKarti(),
        const SizedBox(height: 20),
        // BAĞLI CİHAZ
        _bagliCihazKarti(),
        const SizedBox(height: 20),
        // BUTONLAR
        if (_uzakCihaz != null) _akisButonlari(),
        // PROGRESS
        if (_progressGoster) ...[
          const SizedBox(height: 20),
          _progressWidget(),
        ],
        // DURUM
        if (_durum.isNotEmpty) ...[
          const SizedBox(height: 12),
          _durumWidget(),
        ],
      ]),
    );
  }

  Widget _qrKarti() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [TsRenk.primaryKoyu, TsRenk.primary],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(
          color: Color.fromARGB(76, 21, 101, 192),
          blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.phone_android, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text('Bu Cihaz', style: TextStyle(
              color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _sunucuAktif ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(20)),
            child: Text(_sunucuAktif ? 'Hazır' : 'Başlatılıyor...',
              style: const TextStyle(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        if (_sunucuAktif && _sunucuAdres.isNotEmpty) ...[
          // QR Kod
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TsRenk.kart(context),
              borderRadius: BorderRadius.circular(12)),
            child: QrImageView(
              data: _sunucuAdres,
              version: QrVersions.auto,
              size: 150,
            ),
          ),
          const SizedBox(height: 12),
          Text(_sunucuAdres,
            style: const TextStyle(color: Colors.white70,
                fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          const Text('Diğer cihazda bu QR\'ı okutun',
            style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.copy, color: Colors.white54, size: 16),
            label: const Text('Kopyala',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _sunucuAdres));
              BildirimServisi.basari(context, 'Adres kopyalandı');
            },
          ),
        ] else
          const CircularProgressIndicator(color: Colors.white),
      ]),
    );
  }

  Widget _bagliCihazKarti() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _uzakCihaz != null
              ? Colors.green.shade300 : TsRenk.ayirac(context)),
        boxShadow: const [BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: _uzakCihaz == null
          ? Column(children: [
              Icon(Icons.qr_code_scanner,
                size: 48, color: TsRenk.metinIkincil(context)),
              const SizedBox(height: 12),
              Text('Diğer Cihaz',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: TsRenk.metinIkincil(context))),
              const SizedBox(height: 4),
              Text('Bağlanmak için QR okutun',
                style: TextStyle(fontSize: 13, color: TsRenk.metinIkincil(context))),
              const SizedBox(height: 16),
              if (!Platform.isWindows)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _islemde
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.qr_code_scanner),
                  label: Text(_islemde ? 'Bağlanıyor...' : 'QR Okut ve Bağlan'),
                  onPressed: _islemde ? null : () => setState(() => _qrTarayici = true),
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: TsRenk.zemin(TsRenk.basarili),
                    shape: BoxShape.circle),
                  child: const Icon(Icons.phone_android,
                      color: Colors.green, size: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_uzakCihaz!['cihaz']?.toString() ?? 'Cihaz',
                    style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w700)),
                  Text('Bağlı ✅',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ])),
                TextButton(
                  onPressed: () => setState(() {
                    _uzakCihaz = null; _bagliAdres = '';
                    _durum = ''; _progressGoster = false; _progress = 0;
                  }),
                  child: const Text('Bağlantıyı Kes',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              // Cihaz istatistikleri
              Row(children: [
                _statKutu('Ürün',
                    '${_uzakCihaz!['urun_sayisi'] ?? 0}', TsRenk.primaryKoyu),
                const SizedBox(width: 8),
                _statKutu('Cari',
                    '${_uzakCihaz!['cari_sayisi'] ?? 0}', Colors.orange),
                const SizedBox(width: 8),
                _statKutu('Satış',
                    '${_uzakCihaz!['satis_sayisi'] ?? 0}', Colors.green),
              ]),
            ]),
    );
  }

  Widget _akisButonlari() {
    return Column(children: [
      // Veri Al
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: _islemde
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.download_rounded),
          label: const Text('Veri Al',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: _islemde ? null : _veriAl,
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
          backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 10),
      // Veri Gönder
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: _islemde
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.upload_rounded),
          label: const Text('Veri Gönder',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          onPressed: _islemde ? null : _veriGonder,
          style: FilledButton.styleFrom(
            foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
      const SizedBox(height: 10),
      // Tüm DB Al
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.storage, color: Colors.orange),
          label: const Text('Tüm Veritabanını Al (Komple Kopyala)',
            style: TextStyle(color: Colors.orange,
                fontWeight: FontWeight.w600, fontSize: 13)),
          onPressed: _islemde ? null : _dbAl,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.orange),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        ),
      ),
    ]);
  }

  Widget _progressWidget() => SyncProgressWidget(progress: _progress);

  Widget _durumWidget() => SyncDurumWidget(durum: _durum);

  Widget _statKutu(String baslik, String deger, Color renk) =>
      SyncStatKutu(baslik: baslik, deger: deger, renk: renk);
}
