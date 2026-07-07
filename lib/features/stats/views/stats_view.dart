import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/providers/wrapped_stats_provider.dart';

class StatsView extends ConsumerWidget {
  const StatsView({super.key});

  String _formatDurationStr(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statsStateProvider);
    final notifier = ref.read(statsStateProvider.notifier);
    final wrappedAsync = ref.watch(wrappedStatsProvider);

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final years = List.generate(DateTime.now().year - 2024 + 1, (index) => 2024 + index);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Your Stats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // --- TIME FILTERS ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                DropdownButton<StatsFilter>(
                  dropdownColor: const Color(0xFF181818),
                  value: state.filter,
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: StatsFilter.monthly, child: Text('Monthly')),
                    DropdownMenuItem(value: StatsFilter.yearly, child: Text('Yearly')),
                    DropdownMenuItem(value: StatsFilter.allTime, child: Text('All-Time')),
                  ],
                  onChanged: (val) {
                    if (val != null) notifier.setFilter(val);
                  },
                ),
                const SizedBox(width: 24),
                
                if (state.filter == StatsFilter.monthly) ...[
                  DropdownButton<int>(
                    dropdownColor: const Color(0xFF181818),
                    value: state.month,
                    style: const TextStyle(color: Colors.white),
                    underline: const SizedBox(),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(value: index + 1, child: Text(months[index]));
                    }),
                    onChanged: (val) {
                      if (val != null) notifier.setMonth(val);
                    },
                  ),
                  const SizedBox(width: 16),
                ],

                if (state.filter != StatsFilter.allTime)
                  DropdownButton<int>(
                    dropdownColor: const Color(0xFF181818),
                    value: state.year,
                    style: const TextStyle(color: Colors.white),
                    underline: const SizedBox(),
                    items: years.map((y) {
                      return DropdownMenuItem(value: y, child: Text(y.toString()));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) notifier.setYear(val);
                    },
                  ),
              ],
            ),
          ),
          
          const Divider(color: Colors.white10),

          // --- WRAPPED DATA RENDERER ---
          Expanded(
            child: wrappedAsync.when(
              data: (data) {
                if (data.totalDurationMs == 0) {
                  return const Center(child: Text('No listening history found for this period.', style: TextStyle(color: Colors.grey)));
                }

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181818),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            const Text('Total Time Listened', style: TextStyle(color: Colors.grey, fontSize: 14)),
                            const SizedBox(height: 8),
                            Text(
                              _formatDurationStr(data.totalDurationMs), 
                              style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLeaderboard('Top Tracks', data.topTracks),
                            const SizedBox(width: 24),
                            _buildLeaderboard('Top Artists', data.topArtists),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(String title, List<TopItem> items) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(12),
              ),
              child: items.isEmpty
                  ? const Center(child: Text('Not enough data.', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: items.length,
                      separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Text('#${index + 1}', style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                          title: Text(item.title, style: const TextStyle(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${item.subtitle} • ${item.plays} plays', style: const TextStyle(color: Colors.white54)),
                          trailing: Text(_formatDurationStr(item.durationMs), style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}