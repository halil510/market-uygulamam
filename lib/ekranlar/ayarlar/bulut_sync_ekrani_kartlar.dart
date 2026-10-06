// ignore_for_file: invalid_use_of_protected_member
//
// bulut_sync_ekrani.dart parçası (god-class bölme, 2026-09-29) — kod
// birebir taşındı, davranış değişmedi. setState extension içinden
// çağrıldığı için protected uyarısı dosya bazında muaf (bkz.
// fatura_detay_islemler_ext.dart'taki açıklama).
// Senkron özeti, otomatik çekme, kalıcı hata ve işletme hesabı kartları + alt widget'lar.
part of 'bulut_sync_ekrani.dart';

extension _BulutSyncKartlarExt on _BulutSyncEkraniState {
  String _gecenSure(DateTime t) {
    final fark = DateTime.now().difference(t);
    if (fark.inMinutes < 1) return 'az önce';
    if (fark.inHours < 1) return '${fark.inMinutes} dk önce';
    if (fark.inDays < 1) return '${fark.inHours} sa önce';
    return '${fark.inDays} gün önce';
  }

  /// Bulut gönderim kuyruğunun tek bakışta özeti (kullanıcı isteği
  /// 2026-09-28: senkron sessiz bozulunca görünürlük yoktu).
  Widget _senkronOzetKarti() {
    final ozet = _ozet;
    final durum = BulutManager().durum.value;
    final sonGonderim = BulutManager().istatistik.value.sonGonderim;
    final sorunlu = durum.sorun || (ozet?.yenidenDenenen ?? 0) > 0;
    final renk = sorunlu ? Colors.orange : Colors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withAlpha(120)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sorunlu ? Icons.sync_problem : Icons.cloud_done_outlined, color: renk, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(durum.metin,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 6),
        Text(
          ozet == null
              ? 'Kuyruk okunuyor…'
              : 'Bekleyen: ${ozet.bekleyen} kayıt'
                '${ozet.yenidenDenenen > 0 ? ' (${ozet.yenidenDenenen} tanesi hata alıp yeniden deneniyor)' : ''}'
                '${ozet.enEski != null ? '\nEn eski bekleyen: ${_gecenSure(ozet.enEski!)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          sonGonderim != null
              ? 'Son başarılı gönderim: ${_gecenSure(sonGonderim)}'
              : 'Bu oturumda henüz gönderim yapılmadı',
          style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
        ),
        if (ozet?.sonHata != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            'Son hata: ${ozet!.sonHata!.length > 160 ? '${ozet.sonHata!.substring(0, 160)}…' : ozet.sonHata!}',
            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
          ),
        ],
        if ((ozet?.bekleyen ?? 0) > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _simdiGonderiliyor ? null : _simdiGonder,
              icon: _simdiGonderiliyor
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Şimdi gönder'),
            ),
          ),
      ]),
    );
  }

  String _aralikEtiketi(int sn) => switch (sn) {
        0 => 'Kapalı',
        < 60 => '$sn saniyede bir',
        _ => '${sn ~/ 60} dakikada bir',
      };

  /// Diğer kasaların verisini otomatik çekme aralığı (kullanıcı isteği
  /// 2026-09-28 — önceden yalnız "Hızlı Al" butonu / masa ekranı çekiyordu).
  Widget _otomatikCekmeKarti() => TsKart(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.autorenew, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('Otomatik veri çekme',
                style: TextStyle(fontWeight: FontWeight.w700))),
            DropdownButton<int>(
              value: _otoCekmeSn,
              underline: const SizedBox.shrink(),
              items: OtomatikBulutCekme.secenekler
                  .map((sn) => DropdownMenuItem(value: sn, child: Text(_aralikEtiketi(sn))))
                  .toList(),
              onChanged: (sn) async {
                if (sn == null) return;
                await OtomatikBulutCekme().aralikAyarla(sn);
                if (mounted) setState(() => _otoCekmeSn = sn);
              },
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Uygulama açıkken diğer kasaların satış, stok ve cari değişiklikleri '
            'bu aralıkla kendiliğinden alınır (yalnız değişenler). İnternet yokken '
            've uygulama arka plandayken bekler.',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AnlikBulutDinleyici().bagli,
            builder: (_, bagli, _) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                bagli
                    ? 'Anlık senkron: AÇIK — diğer cihazlardaki değişiklik saniyeler içinde gelir.'
                    : 'Anlık senkron: bağlanıyor / kapalı — değişiklikler yukarıdaki aralıkla gelir.',
                style: TextStyle(fontSize: 11, color: bagli ? Colors.green : context.textSecondary)),
            ),
          ),
          ValueListenableBuilder<DateTime?>(
            valueListenable: OtomatikBulutCekme().sonKontrol,
            builder: (_, t, _) => t == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Son kontrol: ${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 11, color: context.textSecondary)),
                  ),
          ),
        ]),
      );

  Widget _kaliciHataKarti() {
    final toplam = _kaliciHatalar.fold<int>(0, (t, h) => t + h.adet);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TsRenk.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(120)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('$toplam kayıt buluta gönderilemedi (kalıcı hata)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 4),
        Text('Sunucu bu kayıtları reddetti (ör. yanlış anahtar, eksik sütun). '
            'Veri bu cihazda güvende. Uygulama her açıldığında otomatik yeniden '
            'denenir; sorunu düzelttiyseniz hemen denemek için butona basın.',
            style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context))),
        const SizedBox(height: 8),
        ..._kaliciHatalar.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${h.tablo}: ${h.adet} kayıt',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (h.ornekHata != null)
                  SelectableText(
                    h.ornekHata!.length > 200 ? '${h.ornekHata!.substring(0, 200)}…' : h.ornekHata!,
                    style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
                  ),
              ]),
            )),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _kaliciYenidenDeneniyor ? null : _kaliciHatalariYenidenDene,
            icon: _kaliciYenidenDeneniyor
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.replay, size: 16),
            label: const Text('Yeniden Dene'),
          ),
        ),
      ]),
    );
  }

  Widget _hesapKarti() {
    final oturum = SupabaseOturum();
    final gizli = SupabaseOturum.gizliAnahtarMi(_keyCtrl.text.trim());
    return TsKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.verified_user_outlined, size: 20),
          SizedBox(width: 8),
          Text('İşletme hesabı (güvenli giriş)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 6),
        if (gizli)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: TsRenk.zemin(TsRenk.uyari),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Bu cihazda tam yetkili GİZLİ anahtar kayıtlı. Güvenlik için yukarıya '
              'herkese açık (sb_publishable_…) anahtarı yazıp kaydedin, sonra işletme '
              'hesabıyla giriş yapın.',
              style: TextStyle(fontSize: 12, color: context.textPrimary),
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: oturum.oturumDustu,
          builder: (_, dustu, _) => !dustu
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('⚠️ Oturumun süresi doldu veya şifre değişti — yeniden giriş yapın.',
                      style: TextStyle(fontSize: 12, color: TsRenk.hata)),
                ),
        ),
        if (oturum.girisli) ...[
          Text('Giriş yapıldı: ${oturum.eposta}',
              style: TextStyle(fontSize: 13, color: context.textPrimary)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _cikisYap,
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Oturumu kapat'),
          ),
        ] else ...[
          Text(
            'Supabase panelinde işletmeniz için açtığınız hesabın e-posta ve şifresi. '
            'Her cihaz bir kez giriş yapar; kasiyerler yine PIN ile girer.',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _epostaCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Hesap e-postası',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.alternate_email, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sifreCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Hesap şifresi',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              isDense: true,
            ),
            onSubmitted: (_) => _girisYap(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _girisYapiliyor ? null : _girisYap,
              icon: _girisYapiliyor
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login, size: 18),
              label: const Text('Giriş yap'),
            ),
          ),
        ],
      ]),
    );
  }
}

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
                title: const Row(children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Hata Detayı',
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
