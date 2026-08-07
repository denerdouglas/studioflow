import '../models/domain/segmento_template.dart';
import '../repositories/segmento_templates_repository.dart';

class SegmentoSeeder {
  final SegmentoTemplatesRepository _repo;

  SegmentoSeeder({SegmentoTemplatesRepository? repo})
    : _repo = repo ?? SegmentoTemplatesRepository();

  Future<void> seedTemplates() async {
    final existing = await _repo.getAllActive();
    if (existing.isNotEmpty) return;

    final templates = [
      SegmentoTemplate(
        slug: 'salao',
        nome: 'Salão de Beleza',
        grupo: 'Beleza',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Corte Feminino',
              'categoria': 'Cabelo',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Corte Masculino',
              'categoria': 'Cabelo',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Escova',
              'categoria': 'Cabelo',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Mão e Pé',
              'categoria': 'Manicure',
              'preco': 0.0,
              'duracao_minutos': 90,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'barbearia',
        nome: 'Barbearia',
        grupo: 'Beleza',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Corte',
              'categoria': 'Cabelo',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
            {
              'nome': 'Barba',
              'categoria': 'Barba',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
            {
              'nome': 'Corte e Barba',
              'categoria': 'Combo',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'esmalteria',
        nome: 'Esmalteria',
        grupo: 'Beleza',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Mão',
              'categoria': 'Unhas',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Pé',
              'categoria': 'Unhas',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Mão e Pé',
              'categoria': 'Unhas',
              'preco': 0.0,
              'duracao_minutos': 90,
            },
            {
              'nome': 'Alongamento',
              'categoria': 'Unhas',
              'preco': 0.0,
              'duracao_minutos': 120,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'estetica',
        nome: 'Clínica de Estética',
        grupo: 'Saúde',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Limpeza de Pele',
              'categoria': 'Facial',
              'preco': 0.0,
              'duracao_minutos': 90,
            },
            {
              'nome': 'Drenagem Linfática',
              'categoria': 'Corporal',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Massagem Modeladora',
              'categoria': 'Corporal',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'podologia',
        nome: 'Podologia',
        grupo: 'Saúde',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Podologia Tradicional',
              'categoria': 'Saúde dos Pés',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Tratamento de Calos',
              'categoria': 'Saúde dos Pés',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Reflexologia',
              'categoria': 'Massagem',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'tatuagem',
        nome: 'Estúdio de Tatuagem',
        grupo: 'Arte',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Tatuagem Pequena',
              'categoria': 'Tatuagem',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Tatuagem Média',
              'categoria': 'Tatuagem',
              'preco': 0.0,
              'duracao_minutos': 180,
            },
            {
              'nome': 'Piercing',
              'categoria': 'Piercing',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'spa',
        nome: 'SPA / Massoterapia',
        grupo: 'Bem Estar',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Massagem Relaxante',
              'categoria': 'Massagem',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Pedras Quentes',
              'categoria': 'Massagem',
              'preco': 0.0,
              'duracao_minutos': 90,
            },
            {
              'nome': 'Spa Day',
              'categoria': 'Combo',
              'preco': 0.0,
              'duracao_minutos': 240,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'sobrancelha',
        nome: 'Design de Sobrancelhas',
        grupo: 'Beleza',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Design Simples',
              'categoria': 'Sobrancelha',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
            {
              'nome': 'Design com Henna',
              'categoria': 'Sobrancelha',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Micropigmentação',
              'categoria': 'Sobrancelha',
              'preco': 0.0,
              'duracao_minutos': 120,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'maquiagem',
        nome: 'Maquiagem',
        grupo: 'Beleza',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Maquiagem Social',
              'categoria': 'Maquiagem',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Maquiagem Festa',
              'categoria': 'Maquiagem',
              'preco': 0.0,
              'duracao_minutos': 120,
            },
            {
              'nome': 'Penteado',
              'categoria': 'Cabelo',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'bronzeamento',
        nome: 'Bronzeamento',
        grupo: 'Estética',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Bronzeamento Natural',
              'categoria': 'Corpo',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Bronzeamento Artificial',
              'categoria': 'Corpo',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Esfoliação',
              'categoria': 'Corpo',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'depilacao',
        nome: 'Depilação',
        grupo: 'Estética',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Axila',
              'categoria': 'Depilação',
              'preco': 0.0,
              'duracao_minutos': 15,
            },
            {
              'nome': 'Perna Inteira',
              'categoria': 'Depilação',
              'preco': 0.0,
              'duracao_minutos': 45,
            },
            {
              'nome': 'Virilha',
              'categoria': 'Depilação',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      SegmentoTemplate(
        slug: 'petshop',
        nome: 'Pet Shop (Banho e Tosa)',
        grupo: 'Pets',
        payloadConfigJson: {
          'servicos': [
            {
              'nome': 'Banho P',
              'categoria': 'Banho',
              'preco': 0.0,
              'duracao_minutos': 60,
            },
            {
              'nome': 'Tosa Higiênica',
              'categoria': 'Tosa',
              'preco': 0.0,
              'duracao_minutos': 30,
            },
            {
              'nome': 'Banho e Tosa M',
              'categoria': 'Combo',
              'preco': 0.0,
              'duracao_minutos': 120,
            },
          ],
        },
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    ];

    for (final t in templates) {
      await _repo.save(t);
    }
  }
}
