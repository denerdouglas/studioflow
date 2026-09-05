import 'package:flutter/material.dart';

import '../models/domain/global_course.dart';
import '../repositories/commercial_campaign_repository.dart';
import 'commercial_campaigns_page.dart';

class GlobalCoursesPage extends StatefulWidget {
  final CommercialCampaignRepository repository;
  GlobalCoursesPage({super.key, CommercialCampaignRepository? repository})
    : repository = repository ?? CommercialCampaignRepository();

  @override
  State<GlobalCoursesPage> createState() => _GlobalCoursesPageState();
}

class _GlobalCoursesPageState extends State<GlobalCoursesPage> {
  final _query = TextEditingController();
  Future<List<GlobalCourse>>? _result;

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() => setState(
    () => _result = widget.repository.searchCourses(_query.text.trim()),
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catálogo global de cursos')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            decoration: InputDecoration(
              hintText: 'Buscar por curso, categoria ou tema',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<GlobalCourse>>(
            future: _result,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Cursos indisponíveis. Tente novamente.'),
                );
              }
              final courses = snapshot.data ?? const [];
              if (courses.isEmpty) {
                return const Center(child: Text('Nenhum curso encontrado.'));
              }
              return ListView.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final course = courses[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: ListTile(
                      title: Text(course.title),
                      subtitle: Text(
                        '${course.provider} • ${course.category}${course.campaign == null ? '' : '\n${course.campaign!.disclosure}'}',
                      ),
                      isThreeLine: course.campaign != null,
                      trailing: course.campaign == null
                          ? null
                          : const Icon(Icons.open_in_new),
                      onTap: course.campaign == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CommercialCampaignDetailPage(
                                  item: course.campaign!,
                                  repository: widget.repository,
                                ),
                              ),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
