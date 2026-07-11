String formatKopecks(int kopecks) {
  final rubles = kopecks ~/ 100;
  final text = rubles.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ' ',
      );
  return '$text ₽';
}
