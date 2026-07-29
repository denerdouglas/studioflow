import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/database/migrations/migration_v12.dart';
import 'package:studioflow/models/domain/mensagem_modelo.dart';
import 'package:studioflow/repositories/aniversarios_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('migração 12 cria agenda de contatos e backup lógico', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE comercios(id TEXT PRIMARY KEY)');
    await db.execute('''CREATE TABLE clientes(
      id TEXT PRIMARY KEY, comercio_id TEXT, nome TEXT, ativo INTEGER,
      data_nascimento TEXT, data_cadastro TEXT, whatsapp TEXT, telefone TEXT,
      total_gasto REAL)''');
    await db.execute('''CREATE TABLE backups_logicos(
      versao_origem INTEGER, tabela TEXT, estrutura_sql TEXT,
      dados_json TEXT, criado_em TEXT)''');
    await db.insert('comercios', {'id': 'salao-1'});
    await db.insert('clientes', {
      'id': 'c1',
      'comercio_id': 'salao-1',
      'nome': 'Ana',
      'ativo': 1,
    });

    await MigrationV12.executar(db, criarBackup: true);

    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='contatos_agendados'",
      ),
      isNotEmpty,
    );
    expect((await db.query('backups_logicos')).single['versao_origem'], 11);
    await db.close();
  });

  test('aniversários permanecem isolados entre três salões', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE clientes(
      id TEXT PRIMARY KEY, comercio_id TEXT, nome TEXT, ativo INTEGER,
      data_nascimento TEXT, data_cadastro TEXT, whatsapp TEXT, telefone TEXT,
      total_gasto REAL)''');
    await db.execute('''CREATE TABLE servicos(
      id TEXT PRIMARY KEY, nome TEXT)''');
    await db.execute('''CREATE TABLE agendamentos(
      id TEXT PRIMARY KEY, comercio_id TEXT, cliente_id TEXT, servico_id TEXT,
      inicio TEXT, status TEXT, valor_recebido REAL)''');
    await db.execute('''CREATE TABLE contatos_agendados(
      id TEXT PRIMARY KEY, comercio_id TEXT, cliente_id TEXT, tipo TEXT,
      agendado_para TEXT, observacao TEXT, status TEXT, criado_por_id TEXT,
      criado_em TEXT, atualizado_em TEXT)''');
    final hoje = DateTime(2026, 7, 29, 10);
    for (var i = 1; i <= 3; i++) {
      await db.insert('clientes', {
        'id': 'cliente-$i',
        'comercio_id': 'salao-$i',
        'nome': 'Cliente $i',
        'ativo': 1,
        'data_nascimento': '1990-07-29',
        'data_cadastro': '2020-01-01',
        'whatsapp': '551199999000$i',
        'telefone': '',
        'total_gasto': 100.0 * i,
      });
    }
    final repository = AniversariosRepository(
      databaseProvider: () async => db,
      comercioId: 'salao-2',
      usuarioId: 'dono-2',
    );

    final itens = await repository.listarDoDia(hoje);
    expect(itens, hasLength(1));
    expect(itens.single.nome, 'Cliente 2');
    expect(itens.single.idadeEm(hoje), 36);

    await repository.agendarContato(
      clienteId: 'cliente-2',
      quando: DateTime.now().add(const Duration(days: 1)),
    );
    final contatos = await db.query('contatos_agendados');
    expect(contatos, hasLength(1));
    expect(contatos.single['comercio_id'], 'salao-2');
    expect(contatos.single['status'], 'pendente');
    await db.close();
  });

  test('modelos automáticos são editáveis por comércio', () {
    expect(modelosMensagensPadrao, contains('lembrete_dia_anterior'));
    expect(modelosMensagensPadrao, contains('lembrete_duas_horas'));
    expect(modelosMensagensPadrao, contains('alerta_aniversario_dona'));
    expect(modelosMensagensPadrao, contains('aniversario_cliente'));
  });
}
