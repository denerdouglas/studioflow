import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studioflow/core/utils/phone_normalizer.dart';
import 'package:studioflow/database/database_schema_latest.dart';
import 'package:studioflow/models/domain/configuracao_comercial.dart';
import 'package:studioflow/models/domain/mensagem_modelo.dart';
import 'package:studioflow/repositories/configuracao_comercial_repository.dart';
import 'package:studioflow/repositories/modelos_mensagens_repository.dart';
import 'package:studioflow/services/mensagem_service.dart';

void main() {
  sqfliteFfiInit();

  group('Sprint 6.1', () {
    test('normaliza telefones brasileiros e rejeita inválidos', () {
      expect(PhoneNormalizer.paraWhatsapp('(11) 99999-1234'), '5511999991234');
      expect(
        PhoneNormalizer.paraWhatsapp('+55 11 99999-1234'),
        '5511999991234',
      );
      expect(PhoneNormalizer.paraWhatsapp('5511999991234'), '5511999991234');
      expect(PhoneNormalizer.paraWhatsapp('1234'), isNull);
      expect(PhoneNormalizer.paraWhatsapp(''), isNull);
    });

    test('resumo oculta seções vazias e informa pagamento', () {
      const service = MensagemService();
      final onlyService = service.montar(
        modelosMensagensPadrao['resumo_comanda']!.texto,
        const DadosMensagem(
          cliente: 'Ana',
          salao: 'Studio',
          valorPago: 35,
          formaPagamento: 'Pix',
          servicos: [
            ItemResumoMensagem(
              nome: 'Manicure',
              profissional: 'Rafa',
              valorUnitario: 40,
              desconto: 5,
            ),
          ],
        ),
      );
      expect(onlyService, contains('Serviços realizados'));
      expect(onlyService, isNot(contains('Produtos adquiridos')));
      expect(onlyService, contains('Pagamento concluído'));

      final onlyProducts = service.montar(
        modelosMensagensPadrao['resumo_comanda']!.texto,
        const DadosMensagem(
          cliente: 'Ana',
          salao: 'Studio',
          valorPago: 10,
          produtos: [
            ItemResumoMensagem(
              nome: 'Esmalte',
              quantidade: 2,
              valorUnitario: 8,
            ),
          ],
        ),
      );
      expect(onlyProducts, isNot(contains('Serviços realizados')));
      expect(onlyProducts, contains('2x Esmalte'));
      expect(onlyProducts, contains('Valor pendente: R\$ 6,00'));
    });

    test('endereço e modelos persistem isolados por comércio', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: DatabaseSchemaLatest.criar,
        ),
      );
      addTearDown(db.close);
      final now = DateTime.now().toIso8601String();
      await db.insert('comercios', {
        'id': 'c1',
        'codigo_acesso': 'TESTE001',
        'nome': 'Studio',
        'nome_exibicao': 'Studio',
        'responsavel': 'Dona',
        'telefone': '11999991234',
        'email': 'dona@studio.test',
        'ativo': 1,
        'criado_em': now,
        'atualizado_em': now,
      });
      final locations = ConfiguracaoComercialRepository(
        databaseProvider: () async => db,
      );
      await locations.salvar(
        const ConfiguracaoComercial(
          comercioId: 'c1',
          cep: '01001-000',
          rua: 'Praça da Sé',
          numero: '1',
          cidade: 'São Paulo',
          estado: 'SP',
        ),
      );
      final reloaded = await locations.carregar('c1');
      expect(reloaded.enderecoCompleto, contains('Praça da Sé, 1'));
      expect(reloaded.uriRota.toString(), contains('maps/search'));

      final messages = ModelosMensagensRepository(
        databaseProvider: () async => db,
      );
      final models = await messages.listar('c1');
      expect(models.length, greaterThanOrEqualTo(18));
      final custom = models.first;
      await messages.salvar(
        ModeloMensagem(
          id: custom.id,
          comercioId: custom.comercioId,
          chave: custom.chave,
          nome: custom.nome,
          texto: 'Texto personalizado [cliente]',
          textoPadrao: custom.textoPadrao,
          ativo: false,
        ),
      );
      final saved = await messages.porChave('c1', custom.chave);
      expect(saved.texto, 'Texto personalizado [cliente]');
      expect(saved.ativo, isFalse);
      await messages.restaurar(saved);
      expect(
        (await messages.porChave('c1', custom.chave)).texto,
        custom.textoPadrao,
      );
    });
  });
}
