part of 'main.dart';

GiftCard historyCard(Map<String, dynamic> data) {
  final expiry = data['expirationDate'];
  return GiftCard(
    code: data['code'].toString(),
    amount: data['amount'].toString(),
    expirationDate: expiry is Timestamp ? expiry.toDate() : expiry as DateTime?,
    dedication: data['dedication']?.toString() ?? '',
    senderName: data['senderName']?.toString() ?? '',
    recipientName: data['recipientName']?.toString() ?? '',
    status: data['status']?.toString() ?? 'Activa',
  );
}

class CardHistoryPage extends StatefulWidget {
  const CardHistoryPage({super.key, this.service});
  final GiftCardService? service;
  @override
  State<CardHistoryPage> createState() => _CardHistoryPageState();
}

class _CardHistoryPageState extends State<CardHistoryPage> {
  late final service = widget.service ?? GiftCardService();
  late final cards = service.watchGiftCards();
  late final usages = service.watchAllGiftCardUsages();
  String query = '';
  Widget records(
    Stream<List<Map<String, dynamic>>> stream,
    bool used,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const Center(
          child: Text('No se pudo cargar el historial. Verificá la conexión.'),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final records = snapshot.data!
          .where(
            (r) => (r[used ? 'giftCardCode' : 'code'] ?? '')
                .toString()
                .toUpperCase()
                .contains(query),
          )
          .toList();
      if (records.isEmpty)
        return const Center(child: Text('No hay registros para mostrar.'));
      return ListView.builder(
        itemCount: records.length,
        itemBuilder: (context, i) {
          final record = records[i];
          final code = record[used ? 'giftCardCode' : 'code'].toString();
          final date = record['usedAt'];
          final dateText = date is Timestamp ? formatDate(date.toDate()) : '';
          return ListTile(
            leading: Icon(
              isVoucherCode(code)
                  ? Icons.confirmation_number_outlined
                  : Icons.card_giftcard,
              color: greenColor,
            ),
            title: Text('${cardLabel(code)} $code'),
            subtitle: Text(
              used
                  ? '${money(record['amountUsed'].toString())} · $dateText'
                  : '${money(record['amount'].toString())} · ${record['status']}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CardHistoryDetailPage(code: code, service: service),
              ),
            ),
          );
        },
      );
    },
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: greenColor,
        foregroundColor: Colors.white,
        bottom: const TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Emitidos'),
            Tab(text: 'Usos'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por código',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => query = value.trim().toUpperCase()),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [records(cards, false), records(usages, true)],
            ),
          ),
        ],
      ),
    ),
  );
}

class CardHistoryDetailPage extends StatefulWidget {
  const CardHistoryDetailPage({
    super.key,
    required this.code,
    this.service,
    this.profile,
  });
  final String code;
  final GiftCardService? service;
  final AccountProfile? profile;
  @override
  State<CardHistoryDetailPage> createState() => _CardHistoryDetailPageState();
}

class _CardHistoryDetailPageState extends State<CardHistoryDetailPage> {
  late final service = widget.service ?? GiftCardService();
  late final cards = service.watchGiftCards();
  late final usages = service.watchAllGiftCardUsages();
  AccountProfile? profile;
  bool updating = false;
  @override
  void initState() {
    super.initState();
    profile = widget.profile;
    if (profile == null) loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final result = await AccountService().getCurrentProfile();
      if (mounted) setState(() => profile = result);
    } catch (_) {
      /* Reading/sharing remains available; mutations stay hidden. */
    }
  }

  Future<void> changeStatus(String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar estado'),
        content: Text('¿Confirmás cambiar el estado a $status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => updating = true);
    try {
      await service.updateGiftCardStatus(code: widget.code, status: status);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cambiar el estado. Intentá nuevamente.'),
          ),
        );
    } finally {
      if (mounted) setState(() => updating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${cardLabel(widget.code)} ${widget.code}'),
      backgroundColor: greenColor,
      foregroundColor: Colors.white,
    ),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: cards,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text('No se pudo cargar. Verificá la conexión.'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final matches = snapshot.data!.where((r) => r['code'] == widget.code);
        if (matches.isEmpty)
          return const Center(child: Text('No se encontró la tarjeta.'));
        final data = matches.first;
        final card = historyCard(data);
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: usages,
          builder: (context, usageSnapshot) {
            if (usageSnapshot.hasError)
              return const Center(
                child: Text(
                  'No se pudieron cargar los usos. Verificá la conexión.',
                ),
              );
            if (!usageSnapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final movements = usageSnapshot.data!
                .where((r) => r['giftCardCode'] == widget.code)
                .toList();
            num parse(Object? value) =>
                num.tryParse(value?.toString() ?? '') ?? 0;
            final used = data['usedAmount'] == null
                ? movements.fold<num>(
                    0,
                    (total, r) => total + parse(r['amountUsed']),
                  )
                : parse(data['usedAmount']);
            final remaining = data['remainingAmount'] == null
                ? parse(card.amount) - used
                : parse(data['remainingAmount']);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  card.displayStatus,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Importe: ${money(card.amount)}'),
                Text('Utilizado: ${money(used.toStringAsFixed(0))}'),
                Text(
                  'Saldo disponible: ${money(remaining.toStringAsFixed(0))}',
                ),
                Text(
                  'Vencimiento: ${card.expirationDate == null ? 'Sin vencimiento' : formatDate(card.expirationDate!)}',
                ),
                const SizedBox(height: 20),
                if (card.status != 'Anulada')
                  FilledButton.icon(
                    icon: const Icon(Icons.share_outlined),
                    label: Text('Ver y compartir ${card.label}'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VoucherDetailPage(giftCard: card),
                      ),
                    ),
                  ),
                if (profile?.isAdministrator == true &&
                    profile?.active == true) ...[
                  if (card.status == 'Activa' ||
                      card.status == 'Parcialmente usada')
                    OutlinedButton(
                      onPressed: updating
                          ? null
                          : () => changeStatus('Bloqueada'),
                      child: const Text('Bloquear'),
                    ),
                  if (card.status == 'Bloqueada')
                    OutlinedButton(
                      onPressed: updating ? null : () => changeStatus('Activa'),
                      child: const Text('Reactivar'),
                    ),
                  if (card.status != 'Anulada')
                    OutlinedButton(
                      onPressed: updating
                          ? null
                          : () => changeStatus('Anulada'),
                      child: const Text('Anular'),
                    ),
                ],
                const SizedBox(height: 24),
                if (movements.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Ver comprobante de usos'),
                    onPressed: () => showUsageReceipt(
                      context: context,
                      code: card.code,
                      username: movements.first['username']?.toString() ?? '',
                      originalAmount: card.amount,
                      usedAmount: used.toStringAsFixed(0),
                      remainingAmount: remaining.toStringAsFixed(0),
                      status: card.displayStatus,
                      usageRecords: movements,
                    ),
                  ),
                const Text(
                  'Usos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                if (movements.isEmpty) const Text('Todavía no tiene usos.'),
                for (final movement in movements)
                  ListTile(
                    title: Text(money(movement['amountUsed'].toString())),
                    subtitle: Text(
                      '${movement['username'] ?? ''}${movement['usedAt'] is Timestamp ? ' · ${formatDate((movement['usedAt'] as Timestamp).toDate())}' : ''}',
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
