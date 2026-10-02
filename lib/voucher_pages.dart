part of 'main.dart';

/// Both account roles enter exactly the same creation flow.
class VoucherMenu extends StatelessWidget {
  const VoucherMenu({super.key});

  @override
  Widget build(BuildContext context) => !vouchersEnabled ? const SizedBox.shrink() : Column(
    children: [
      Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: const Icon(
            Icons.confirmation_number_outlined,
            color: greenColor,
            size: 38,
          ),
          title: const Text(
            'Crear voucher',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('Con importe y vencimiento obligatorios.'),
          trailing: const Icon(Icons.chevron_right, color: greenColor),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateVoucherPage()),
          ),
        ),
      ),
    ],
  );
}

class CreateVoucherPage extends StatefulWidget {
  const CreateVoucherPage({super.key});

  @override
  State<CreateVoucherPage> createState() => _CreateVoucherPageState();
}

class _CreateVoucherPageState extends State<CreateVoucherPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  int _integerAmount = 0;
  DateTime? _expiration;
  bool _saving = false;
  String? _pendingCode;
  String? _pendingSignature;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _expiration == null || _expiration!.isBefore(today)
        ? today
        : _expiration!;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => ExpirationCalendarDialog(initialDate: initial),
    );
    if (!mounted || selected == null) return;
    setState(() => _expiration = selected);
    field.didChange(selected);
  }

  Future<void> _preview() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final signature = '${_integerAmount}|$_expiration';
    if (_pendingSignature != signature) {
      setState(() => _saving = true);
      try {
        _pendingCode = await GiftCardService().reserveNextVoucherCode();
        _pendingSignature = signature;
      } catch (error) {
        if (!mounted) return;
        await showGiftCheckErrorDialog(
          context: context,
          title: 'No se pudo reservar el código',
          message: error is FirebaseException && error.code == 'permission-denied'
              ? 'Firebase no autorizó la creación del voucher. Verificá que las reglas para vouchers estén publicadas y que la cuenta esté activa.'
              : 'Verificá la conexión e intentá nuevamente.',
        );
        return;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      if (!mounted) return;
    }
    final card = GiftCard(
      code: _pendingCode!,
      amount: _integerAmount.toString(),
      expirationDate: _expiration,
      dedication: '',
      status: 'Activa',
    );
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => VoucherPreviewPage(giftCard: card)),
    );
    if (!mounted || confirmed != true) return;
    // Revalidate when returning: the form may have remained open past midnight.
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final profile = await AccountService().getCurrentProfile();
      if (profile == null ||
          !profile.active ||
          !(profile.isAdministrator || profile.isLocal)) {
        throw StateError('La sesión no está habilitada para crear vouchers.');
      }
      await GiftCardService().saveVoucher(
        code: card.code,
        amount: card.amount,
        expirationDate: card.expirationDate!,
        creatorUid: profile.uid,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VoucherDetailPage(giftCard: card, justCreated: true),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await showGiftCheckErrorDialog(
        context: context,
        title: 'No se pudo confirmar el voucher',
        message:
            'Verificá la conexión e intentá nuevamente. '
            'Si el envío anterior se completó, se recuperará el mismo voucher.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => !vouchersEnabled
      ? Scaffold(appBar: AppBar(title: const Text('Sección no disponible')), body: const Center(child: Text('Esta sección no está habilitada.')))
      : PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Crear voucher'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nuevo voucher',
                  style: TextStyle(
                    color: darkTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Completá el importe y la fecha de vencimiento.',
                  style: TextStyle(color: grayTextColor, fontSize: 15),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  key: const Key('voucher-amount'),
                  controller: _amount,
                  onChanged: (text) =>
                      _integerAmount = cleanIntegerAmount(text),
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [IntegerAmountFormatter()],
                  decoration: appInputDecoration(
                    label: 'Importe (obligatorio)',
                    hint: 'Ejemplo: 50.000',
                    prefixIcon: Icons.payments_outlined,
                  ),
                  validator: (value) =>
                      validateVoucherAmount(amountDigits(value ?? '')),
                ),
                const SizedBox(height: 18),
                FormField<DateTime>(
                  validator: (value) => validateVoucherExpiration(value),
                  builder: (field) => InkWell(
                    key: const Key('voucher-expiration'),
                    onTap: _saving ? null : () => _pickDate(field),
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: appInputDecoration(
                        label: 'Vencimiento (obligatorio)',
                        prefixIcon: Icons.calendar_month_outlined,
                      ).copyWith(errorText: field.errorText),
                      child: Text(
                        _expiration == null
                            ? 'Elegí una fecha'
                            : formatDate(_expiration!),
                        style: const TextStyle(color: darkTextColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _preview,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.confirmation_number_outlined),
                    label: Text(_saving ? 'Guardando...' : 'Crear voucher'),
                    style: FilledButton.styleFrom(
                      backgroundColor: greenColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class VoucherPreviewPage extends StatelessWidget {
  const VoucherPreviewPage({super.key, required this.giftCard});
  final GiftCard giftCard;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vista previa del voucher'),
      backgroundColor: greenColor,
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GiftCardVisual(giftCard: giftCard),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar voucher'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver a editar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class VoucherDetailPage extends StatefulWidget {
  const VoucherDetailPage({
    super.key,
    required this.giftCard,
    this.justCreated = false,
  });
  final GiftCard giftCard;
  final bool justCreated;
  @override
  State<VoucherDetailPage> createState() => _VoucherDetailPageState();
}

class _VoucherDetailPageState extends State<VoucherDetailPage> {
  final _imageKey = GlobalKey();
  bool _sharing = false;
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await precacheImage(
        const AssetImage('assets/el-cielo-logos.png'),
        context,
      );
      await GoogleFonts.pendingFonts();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null || !mounted) return;
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          title: widget.giftCard.label,
          files: [
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: '${widget.giftCard.label}_${widget.giftCard.code}.png',
            ),
          ],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo compartir el voucher. Intentá nuevamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.justCreated
            ? 'Voucher creado'
            : 'Detalle de ${widget.giftCard.label}',
      ),
      backgroundColor: greenColor,
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.justCreated) ...[
              const Text(
                'Voucher guardado correctamente',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
            RepaintBoundary(
              key: _imageKey,
              child: GiftCardVisual(giftCard: widget.giftCard),
            ),
            const SizedBox(height: 24),
            if (widget.giftCard.status != 'Anulada')
              FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: const Icon(Icons.share_outlined),
                label: Text(
                  _sharing
                      ? 'Preparando imagen...'
                      : 'Compartir ${widget.giftCard.label}',
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class VoucherHistoryPage extends StatelessWidget {
  const VoucherHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vouchers emitidos'),
      backgroundColor: greenColor,
      foregroundColor: Colors.white,
    ),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: GiftCardService().watchGiftCards(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'No se pudo cargar el historial. Verificá la conexión.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data!
            .where((r) => isVoucherCode(r['code'] as String))
            .toList();
        if (records.isEmpty) {
          return const Center(child: Text('Todavía no hay vouchers emitidos.'));
        }
        return ListView.builder(
          itemCount: records.length,
          itemBuilder: (context, index) {
            final record = records[index];
            final card = GiftCard(
              code: record['code'],
              amount: record['amount'],
              expirationDate: record['expirationDate'],
              dedication: '',
              status: record['status'],
            );
            return ListTile(
              title: Text('Voucher ${card.code}'),
              subtitle: Text(
                '${money(card.amount)} · ${card.displayStatus}\nVence: ${formatDate(card.expirationDate!)}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoucherDetailPage(giftCard: card),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
