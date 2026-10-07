// lib/ekranlar/ayarlar/sync_ekrani_bluetooth.dart
//
// Bluetooth aktarım sekmesinin arayüzü — sync_ekrani.dart'tan ayrıldı (2026-10-07 refactor).
// ignore_for_file: invalid_use_of_protected_member
part of 'sync_ekrani.dart';

extension _SyncBluetoothGorunum on _SyncEkraniState {
  Widget _btEkrani() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // ── Nasıl Çalışır ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TsRenk.zemin(TsRenk.uyari),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('Önemli Sınırlama', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange)),
            ]),
            SizedBox(height: 8),
            Text(
              // ÖNCEDEN BURADA "iki cihaz aynı WiFi ağında olmalı" gibi
              // normal bir kullanım metni vardı, ama derin analiz sırasında
              // ÇOK ÖNEMLİ bir mimari eksiklik bulundu: bu cihazın kendini
              // BLE ile "yayınlaması" (advertise/peripheral modu) için
              // HİÇBİR KOD YOK — kullanılan paket (flutter_blue_plus) bunu
              // desteklemiyor. Yani tarama YAPILABİLİYOR ama karşı cihaz
              // ASLA bulunamayabilir, çünkü hiçbir cihaz kendini
              // yayınlayamıyor. Bu, kullanıcıyı yanıltmamak için açıkça
              // belirtiliyor ve güvenilir WiFi+QR yöntemine yönlendiriliyor.
              'Bu cihazlar arası tarama BAZI telefonlarda çalışmayabilir '
              '(Android\'in kendini Bluetooth ile "yayınlama" özelliği '
              'kısıtlı). Bulamazsa, WiFi sekmesindeki QR kod yöntemi '
              'HER ZAMAN güvenilir çalışır — onu kullanmanızı öneririz.',
              style: TextStyle(fontSize: 12, height: 1.6, color: Colors.orange)),
          ]),
        ),
        const SizedBox(height: 20),

        // ── BU CİHAZ - Sunucu bilgisi ──────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [TsRenk.primaryKoyu, TsRenk.primary]),
            borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.phone_android, color: Colors.white70, size: 16),
              SizedBox(width: 6),
              Text('Bu Cihaz (Sunucu)', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.wifi, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _sunucuAktif ? _sunucuAdres : 'WiFi sunucu başlatılıyor...',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace'),
              )),
            ]),
            if (_sunucuAktif) ...[
              const SizedBox(height: 6),
              const Text('Diğer cihaz BLE ile sizi bulabilir',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // ── BLE TARAMA ─────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: TsRenk.kart(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _btTarama ? Colors.blue.shade300 : TsRenk.ayirac(context))),
          child: Column(children: [
            Row(children: [
              Icon(Icons.bluetooth_searching,
                  color: _btTarama ? Colors.blue : context.textSecondary, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cihaz Ara (BLE)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(_btTarama ? 'BarkoPro cihazları aranıyor...' : 'Yakındaki cihazları bulur',
                    style: TextStyle(fontSize: 12, color: TsRenk.metinIkincil(context))),
              ])),
              if (_btTarama)
                const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TsRenk.primary)),
            ]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              icon: Icon(_btTarama ? Icons.stop : Icons.search),
              label: Text(_btTarama ? 'Aramayı Durdur' : 'BLE ile Cihaz Ara'),
              onPressed: _btIslemde ? null : _btTaramaToggle,
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
          backgroundColor: _btTarama ? Colors.red : TsRenk.primaryKoyu,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            )),

            // Bulunan cihazlar listesi
            if (_btCihazlar.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Bulunan Cihazlar:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              const SizedBox(height: 8),
              ..._btCihazlar.entries.map((e) {
                final ip = e.key;
                final ad = e.value;
                final secili = _btSeciliIp == ip;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: secili ? TsRenk.zemin(TsRenk.bilgi) : TsRenk.arkaplan(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: secili ? Colors.blue.shade300 : TsRenk.ayirac(context))),
                  child: ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: TsRenk.zemin(TsRenk.bilgi, opaklik: 0.18),
                        shape: BoxShape.circle),
                      child: const Icon(Icons.phone_android, color: Colors.blue, size: 22)),
                    title: Text(ad, style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: Text(
                      ip == '?' ? 'IP bilinmiyor - WiFi sekmesini kullanın' : ip,
                      style: TextStyle(fontSize: 11,
                          color: ip == '?' ? Colors.orange : TsRenk.metinIkincil(context))),
                    trailing: ip != '?' ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 30, child: FilledButton(
                          onPressed: _btIslemde ? null : () => _btVeriAl(ip, ad),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
          backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text('Al', style: TextStyle(fontSize: 12)),
                        )),
                        const SizedBox(height: 4),
                        SizedBox(height: 30, child: FilledButton(
                          onPressed: _btIslemde ? null : () => _btVeriGonder(ip),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
          backgroundColor: TsRenk.primaryKoyu,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text('Gönder', style: TextStyle(fontSize: 12)),
                        )),
                      ],
                    ) : null,
                  ),
                );
              }),
            ] else if (_btTarama) ...[
              const SizedBox(height: 20),
              Icon(Icons.bluetooth_searching, size: 48, color: TsRenk.ayirac(context)),
              const SizedBox(height: 8),
              Text('Henüz cihaz bulunamadı',
                  style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 13)),
              const SizedBox(height: 4),
              Text('Diğer cihazda WiFi sekmesinden sunucu başlatın',
                  style: TextStyle(color: TsRenk.metinIkincil(context), fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ]),
        ),

        // ── Progress ────────────────────────────────────────────────
        if (_btIslemde || _btProgress > 0 && _btProgress < 100) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: _btIslemde && _btProgress == 0 ? null : _btProgress / 100,
              minHeight: 12,
              backgroundColor: context.borderColor,
              valueColor: const AlwaysStoppedAnimation<Color>(TsRenk.primaryKoyu),
            ),
          ),
          if (_btProgress > 0) ...[
            const SizedBox(height: 4),
            Text('$_btProgress%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700,
                  color: TsRenk.primaryKoyu)),
          ],
        ],

        // ── Durum mesajı ────────────────────────────────────────────
        if (_btDurum.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _btDurum.startsWith('✅') ? TsRenk.zemin(TsRenk.basarili)
                  : _btDurum.startsWith('❌') ? TsRenk.zemin(TsRenk.hata)
                  : TsRenk.arkaplan(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _btDurum.startsWith('✅') ? Colors.green.shade200
                    : _btDurum.startsWith('❌') ? Colors.red.shade200
                    : TsRenk.ayirac(context))),
            child: Text(_btDurum,
              style: TextStyle(fontSize: 13,
                color: _btDurum.startsWith('✅') ? Colors.green.shade700
                    : _btDurum.startsWith('❌') ? Colors.red.shade700
                    : context.textSecondary)),
          ),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

}
