/// Texto curto para "quanto tempo faz": "agora há pouco", "há 5 min"…
String formatRelative(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'agora há pouco';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  final days = diff.inDays;
  return days == 1 ? 'há 1 dia' : 'há $days dias';
}
