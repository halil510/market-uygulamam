// lib/ekranlar/mail/mail_baglanti_ekrani.dart
import 'package:flutter/material.dart';
import '../../uygulama/tema/uygulama_temasi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../saglayicilar/riverpod/mail_provider.dart';
import '../../servisler/mail/mail_service.dart' show Mail;
import '../../servisler/bildirim_servisi.dart';
import '../../tasarim_sistemi/tasarim_sistemi.dart';
import '../../cekirdek/utils/para_utils.dart';

class MailBaglantiEkrani extends ConsumerStatefulWidget {
  const MailBaglantiEkrani({super.key});

  @override
  ConsumerState<MailBaglantiEkrani> createState() => _MailBaglantiEkraniState();
}

class _MailBaglantiEkraniState extends ConsumerState<MailBaglantiEkrani> {
  final _emailCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();
  bool _sifreGoster = false;
  bool _baglaniyor = false;
  bool _kimlikYuklendi = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kayitliKimligiYukle());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _sifreCtrl.dispose();
    super.dispose();
  }

  Future<void> _kayitliKimligiYukle() async {
    final kimlik = await ref.read(mailKayitliKimlikProvider.future);
    if (!mounted || kimlik.email == null) {
      setState(() => _kimlikYuklendi = true);
      return;
    }
    _emailCtrl.text = kimlik.email!;
    _sifreCtrl.text = kimlik.appSifre ?? '';
    ref.read(mailSaglayiciProvider.notifier).state = kimlik.saglayici;
    setState(() => _kimlikYuklendi = true);
    if (kimlik.appSifre != null && kimlik.appSifre!.isNotEmpty) {
      await _baglan(sessiz: true);
    }
  }

  Future<void> _baglan({bool sessiz = false}) async {
    final email = _emailCtrl.text.trim();
    final sifre = _sifreCtrl.text.trim();
    if (email.isEmpty || sifre.isEmpty) {
      if (!sessiz) BildirimServisi.uyari(context, 'E-posta ve uygulama şifresi girin');
      return;
    }

    setState(() => _baglaniyor = true);
    final service = ref.read(mailServiceProvider);
    final saglayici = ref.read(mailSaglayiciProvider);
    try {
      final basarili = await service.baglan(email: email, appSifre: sifre);
      if (!mounted) return;

      if (basarili) {
        await mailKimlikBilgisiKaydet(email: email, appSifre: sifre, saglayici: saglayici);
        ref.invalidate(mailListesiProvider);
        if (!mounted) return;
        if (!sessiz) BildirimServisi.basari(context, 'Mail hesabına bağlanıldı');
        setState(() {});
      } else {
        if (!sessiz) {
          BildirimServisi.hata(context, service.sonHata ?? 'Bağlantı kurulamadı');
        }
      }
    } catch (e) {
      if (mounted && !sessiz) BildirimServisi.hata(context, 'Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _baglaniyor = false);
    }
  }

  Future<void> _baglantiyiKes() async {
    final service = ref.read(mailServiceProvider);
    await service.cikis();
    await mailKimlikBilgisiSil();
    ref.invalidate(mailListesiProvider);
    if (mounted) setState(() {});
  }

  void _yardimGoster() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.help_outline, color: TsRenk.primary),
          SizedBox(width: 8),
          Text('Nasıl Bağlanır?'),
        ]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _yardimBaslik('Gmail'),
              _yardimMetin('Google Hesabı > Güvenlik > 2 Adımlı Doğrulama açık olmalı.'),
              _yardimMetin('Ardından "Uygulama Şifreleri" bölümünden 16 haneli bir şifre oluşturun.'),
              _yardimMetin('Bu şifreyi aşağıdaki "Uygulama Şifresi" alanına yapıştırın (normal Gmail şifreniz DEĞİL).'),
              const SizedBox(height: 12),
              _yardimBaslik('Outlook / Microsoft 365'),
              _yardimMetin('account.microsoft.com > Güvenlik > Uygulama Şifreleri bölümünden oluşturun.'),
              const SizedBox(height: 12),
              _yardimBaslik('Bu Bağlantı Ne İşe Yarar?'),
              _yardimMetin('Gelen kutunuz taranır, fatura/borç içeren mailler otomatik tespit edilip '
                  'aşağıda listelenir. Hiçbir mail içeriği sunucularımıza gönderilmez, doğrudan '
                  'cihazınızdan e-posta sağlayıcınıza bağlanılır.'),
              const SizedBox(height: 12),
              _yardimBaslik('Güvenlik'),
              _yardimMetin('Uygulama şifreniz cihazınızda (Android Keystore / iOS Keychain) '
                  'şifrelenmiş olarak saklanır.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Widget _yardimBaslik(String t) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
  );
  Widget _yardimMetin(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: TextStyle(fontSize: 13, color: context.textSecondary)),
  );

  @override
  Widget build(BuildContext context) {
    final saglayici = ref.watch(mailSaglayiciProvider);
    final service = ref.watch(mailServiceProvider);
    final bagli = service.bagli;
    final tespitEdilenler = ref.watch(mailBorcProvider);

    return Scaffold(
      backgroundColor: TsRenk.arkaplan(context),
      appBar: TsAppBar(
        baslik: 'Mail Bağlantısı',
        gradyanli: true,
        aksiyonlar: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _yardimGoster,
          ),
        ],
      ),
      body: !_kimlikYuklendi
          ? const TsYukleniyor()
          : ListView(
        padding: const EdgeInsets.all(TsBosluk.lg),
        children: [
          TsKart(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(
                bagli ? Icons.check_circle : Icons.info_outline,
                color: bagli ? TsRenk.basarili : TsRenk.uyari,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bagli
                      ? '${service.hesapAdi} hesabına bağlı. Gelen kutusu taranıyor.'
                      : 'Henüz bağlanmadı. E-posta ve uygulama şifresi ile bağlantı kurun.',
                  style: TextStyle(
                    fontSize: 13,
                    color: bagli ? TsRenk.basarili : TsRenk.uyari,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: TsBosluk.xl),

          if (!bagli) ...[
            TsKart(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.email_outlined, color: TsRenk.primary),
                const SizedBox(width: 12),
                const Text('Sağlayıcı:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                SegmentedButton<MailSaglayici>(
                  segments: const [
                    ButtonSegment(
                      value: MailSaglayici.gmail,
                      label: Text('Gmail'),
                      icon: Icon(Icons.mail_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: MailSaglayici.outlook,
                      label: Text('Outlook'),
                      icon: Icon(Icons.business_center_outlined, size: 16),
                    ),
                  ],
                  selected: {saglayici},
                  onSelectionChanged: (s) =>
                      ref.read(mailSaglayiciProvider.notifier).state = s.first,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: TsRenk.zemin(TsRenk.primary),
                    selectedForegroundColor: TsRenk.primary,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),

            TsInput(
              etiket: 'E-posta Adresi',
              ipucu: 'ornek@mail.com',
              controller: _emailCtrl,
              klavyeTuru: TextInputType.emailAddress,
              oncilIkon: Icons.email,
            ),
            const SizedBox(height: TsBosluk.md),

            TsInput(
              etiket: 'Uygulama Şifresi',
              ipucu: '16 haneli uygulama şifresi',
              controller: _sifreCtrl,
              sifreGizli: !_sifreGoster,
              oncilIkon: Icons.lock,
              sonIkon: IconButton(
                icon: Icon(_sifreGoster ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _sifreGoster = !_sifreGoster),
              ),
            ),
            const SizedBox(height: TsBosluk.sm),

            TsKart(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.info_outline, color: TsRenk.bilgi, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Normal hesap şifreniz değil, hesap ayarlarınızdan '
                    'oluşturduğunuz "Uygulama Şifresi" gerekir. Detay için ⓘ butonuna dokunun.',
                    style: TextStyle(fontSize: 12, color: TsRenk.bilgi),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: TsBosluk.xl),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: TsButon(
                tamGenislik: true,
                yukleniyor: _baglaniyor,
                metin: 'Mail Hesabını Bağla',
                ikon: Icons.link,
                onPressed: _baglaniyor ? null : _baglan,
              ),
            ),
          ] else ...[
            Row(children: [
              Expanded(
                child: Text('Tespit Edilen Faturalar',
                    style: TsMetin.baslikM.copyWith(color: TsRenk.metinIkincil(context))),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
                onPressed: () => ref.invalidate(mailListesiProvider),
              ),
            ]),
            const SizedBox(height: TsBosluk.sm),
            if (tespitEdilenler.isEmpty)
              const TsBosDurum(
                ikon: Icons.mark_email_read_outlined,
                baslik: 'Fatura/borç içeren mail bulunamadı',
                altyazi: 'Son 50 mail tarandı',
              )
            else
              ...tespitEdilenler.map((t) {
                final mail = t['mail'] as Mail;
                final tutar = t['tutar'] as double;
                final firma = t['firma'] as String;
                return Padding(
                  padding: const EdgeInsets.only(bottom: TsBosluk.sm),
                  child: TsKart.liste(
                    ikon: const Icon(Icons.receipt_long_outlined),
                    baslik: firma,
                    altBaslik: mail.subject,
                    deger: tutar > 0 ? ParaUtils.formatla(tutar) : null,
                    etiketler: const [TsBadge(metin: 'MAIL', tur: TsBadgeTuru.bilgi)],
                  ),
                );
              }),
            const SizedBox(height: TsBosluk.xl),
            TsButon.tehlike(
              tamGenislik: true,
              metin: 'Bağlantıyı Kes',
              ikon: Icons.link_off,
              onPressed: _baglantiyiKes,
            ),
          ],
          const SizedBox(height: TsBosluk.lg),
          Center(
            child: Text(
              'Uygulama şifreniz cihazda şifrelenmiş olarak saklanır.',
              style: TextStyle(fontSize: 11, color: TsRenk.metinIkincil(context)),
            ),
          ),
        ],
      ),
    );
  }
}
