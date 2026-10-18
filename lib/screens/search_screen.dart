import 'dart:async';

import 'package:flutter/material.dart';

import '../models/show.dart';
import '../services/catalog_service.dart';
import '../theme/app_theme.dart';
import '../widgets/show_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.service,
    required this.onSelect,
  });

  final CatalogService service;
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
    _controller
      ..removeListener(_queryChanged)
      ..dispose();
    super.dispose();
  }

  void _queryChanged() {
    _debounce?.cancel();
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _activeQuery = '';
        _results = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query, dismissKeyboard: false),
    );
  }

  void _runSearch(String? submitted, {required bool dismissKeyboard}) {
    _debounce?.cancel();
    final query = (submitted ?? _controller.text).trim();
    if (query.isEmpty) return;
    if (dismissKeyboard) FocusScope.of(context).unfocus();
    setState(() {
      _activeQuery = query;
      _results = widget.service.search(query);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onSubmitted: (query) =>
                          _runSearch(query, dismissKeyboard: true),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search title, genre, category, or type',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: _controller.clear,
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    ),
  );

  Widget _buildBody() {
    final results = _results;
    if (results == null) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 52,
                color: AppColors.violetLight,
              ),
              SizedBox(height: 14),
              Text(
                'Find your next favorite',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Search the StreamFlix catalog by title, genre, category, movie, or series.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }
    return FutureBuilder<List<Show>>(
      future: results,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => _runSearch(_activeQuery, dismissKeyboard: false),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'No matching titles',
              style: TextStyle(color: AppColors.muted),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 5 : 3;
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
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
      },
    );
  }
}
