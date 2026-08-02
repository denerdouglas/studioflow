import 'package:sqflite/sqflite.dart';

class MigrationV22 {
  static Future<void> executar(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS auditoria_estoque_consumo (
      id TEXT PRIMARY KEY,
      comercio_id TEXT NOT NULL,
      data_hora TEXT NOT NULL,
      profissional_id TEXT NOT NULL,
      cliente_id TEXT,
      servico_id TEXT NOT NULL,
      agendamento_id TEXT NOT NULL,
      unidade_id TEXT,
      estoque_id TEXT NOT NULL,
      quantidade REAL NOT NULL,
      tipo_movimento TEXT NOT NULL CHECK (tipo_movimento IN ('baixa', 'estorno')),
      criado_em TEXT NOT NULL,
      versao_local INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY (profissional_id) REFERENCES profissionais(id),
      FOREIGN KEY (cliente_id) REFERENCES clientes(id),
      FOREIGN KEY (servico_id) REFERENCES servicos(id),
      FOREIGN KEY (agendamento_id) REFERENCES agendamentos(id) ON DELETE CASCADE,
      FOREIGN KEY (estoque_id) REFERENCES estoque(id),
      FOREIGN KEY (comercio_id) REFERENCES comercios(id) ON DELETE CASCADE
    )''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_auditoria_estoque_consumo_agendamento ON auditoria_estoque_consumo(comercio_id, agendamento_id)',
    );
  }
}
