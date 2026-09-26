import 'dart:async';

import 'package:flutter/material.dart';

import '../models/show.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/show_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.service,
    required this.onSelect,
  });
  final TmdbService service;
  final ValueChanged<Show> onSelect;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<Show>>? _results;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_queryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_queryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _queryChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _activeQuery = '';
          _results = null;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(query);
    });
  }

  void _runSearch([String? submitted]) {
    _debounce?.cancel();
    final query = (submitted ?? _controller.text).trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _activeQuery = query;
      _results = widget.service.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: _runSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Movies, shows and more',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () => _runSearch(),
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: 'Search',
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_results == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 62,
                color: AppColors.violetLight,
              ),
              SizedBox(height: 14),
              Text(
                'Find your next favorite',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Search films and TV series from the TMDB catalog.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }
    return FutureBuilder<List<Show>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: AppColors.violetLight,
                  ),
                  const SizedBox(height: 14),
                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _runSearch(_activeQuery),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'No titles found',
              style: TextStyle(color: AppColors.muted),
            ),
          );
        }
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                child: Text(
                  '${items.length} results for “$_activeQuery”',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => ShowGridTile(
                  show: items[index],
                  onTap: () => widget.onSelect(items[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
