part of 'main.dart';

class ExpirationCalendarDialog extends StatefulWidget {
  const ExpirationCalendarDialog({super.key, required this.initialDate});
  final DateTime initialDate;
  @override
  State<ExpirationCalendarDialog> createState() =>
      _ExpirationCalendarDialogState();
}

class _ExpirationCalendarDialogState extends State<ExpirationCalendarDialog> {
  late DateTime selected = widget.initialDate;
  DateTime get today => DateUtils.dateOnly(DateTime.now());
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  void chooseMonth(int year, int month) {
    var date = DateTime(
      year,
      month,
      math.min(selected.day, DateUtils.getDaysInMonth(year, month)),
    );
    if (date.isBefore(today)) date = today;
    setState(() => selected = date);
  }

  Future<void> chooseYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elegí el año'),
        content: SizedBox(
          width: 340,
          height: 360,
          child: YearPicker(
            firstDate: today,
            lastDate: DateTime(9999, 12, 31),
            selectedDate: selected,
            onChanged: (date) => Navigator.pop(context, date.year),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (mounted && year != null) chooseMonth(year, selected.month);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Fecha de vencimiento'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('month-${selected.year}-${selected.month}'),
                    initialValue: selected.month,
                    decoration: const InputDecoration(
                      labelText: 'Mes',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        enabled:
                            selected.year > today.year || i + 1 >= today.month,
                        child: Text(months[i]),
                      ),
                    ),
                    onChanged: (month) {
                      if (month != null) chooseMonth(selected.year, month);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: chooseYear,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Año',
                        border: OutlineInputBorder(),
                      ),
                      child: Text('${selected.year} ▾'),
                    ),
                  ),
                ),
              ],
            ),
            CalendarDatePicker(
              key: ValueKey(selected),
              initialDate: selected,
              firstDate: today,
              lastDate: DateTime(9999, 12, 31),
              onDateChanged: (date) => setState(() => selected = date),
              onDisplayedMonthChanged: (date) =>
                  chooseMonth(date.year, date.month),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (selected.isBefore(today)) {
            setState(() => selected = today);
            return;
          }
          Navigator.pop(context, selected);
        },
        child: const Text('Elegir fecha'),
      ),
    ],
  );
}
