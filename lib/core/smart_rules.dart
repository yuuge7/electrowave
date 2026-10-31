import 'dart:convert';
import 'database/app_database.dart';

/// All conditions must match; the saved definition is portable JSON.
class SmartRules {
  const SmartRules({
    this.genre,
    this.artist,
    this.minimumPlays = 0,
    this.minimumRating = 0,
    this.addedSinceYear,
    this.year,
  });
  final String? genre, artist;
  final int minimumPlays, minimumRating;
  final int? addedSinceYear, year;

  bool matches(Track track) =>
      (genre == null || track.genre?.toLowerCase() == genre!.toLowerCase()) &&
      (artist == null ||
          track.artist.toLowerCase().contains(artist!.toLowerCase())) &&
      track.totalPlayCount >= minimumPlays &&
      track.rating >= minimumRating &&
      (addedSinceYear == null ||
          (track.dateAdded?.year ?? 0) >= addedSinceYear!) &&
      (year == null || track.year == year);

  String encode() => jsonEncode({
    'genre': genre,
    'artist': artist,
    'minimumPlays': minimumPlays,
    'minimumRating': minimumRating,
    'addedSinceYear': addedSinceYear,
    'year': year,
  });
  factory SmartRules.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return SmartRules(
      genre: json['genre'] as String?,
      artist: json['artist'] as String?,
      minimumPlays: (json['minimumPlays'] as num?)?.toInt() ?? 0,
      minimumRating: (json['minimumRating'] as num?)?.toInt() ?? 0,
      addedSinceYear: (json['addedSinceYear'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
    );
  }
}
