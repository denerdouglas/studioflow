# Homologação de leituras, OCR, PDF e GTIN

Data da auditoria: 2026-08-12

## Escopo e inventário

| Fluxo | Arquivos/funções principais | Tela/entrada | Campos automáticos | Validações atuais | Cobertura atual |
|---|---|---|---|---|---|
| Scanner de código de barras genérico | `screens/barcode_scanner_page.dart`: `_detectar`, `normalizeBarcode`, `isSupportedBarcode` | Câmera (`mobile_scanner`) ou digitação | Código bruto normalizado | Comprimento para códigos numéricos; bloqueio da última leitura; formatos EAN-8, EAN-13, UPC-A, UPC-E e Code 128 | Sem teste nativo; sem teste direto da tela |
| Scanner Vision | `screens/vision_scanner_page.dart`: `_detectar`, `_processarCodigo`, `_usarOcr` | Câmera, OCR de foto ou digitação | GTIN/referência; rascunho de produto | `DetectionSpeed.noDuplicates`; revisão em `ScannerDraftPage` | Coordinator apenas com mocks; sem câmera/ML Kit real |
| Captura OCR | `screens/vision_ocr_capture_page.dart`: `_pickImage` | Câmera/galeria (`image_picker`) | Caminhos de frente e verso | Frente obrigatória antes de analisar | Sem teste nativo; sem fixtures reais de imagem |
| OCR de produto | `services/scanner/mlkit_vision_provider.dart`: `analyzeImage`, `_parseText` | Imagem capturada | Código, nome e marca | Campos OCR recebem confiança baixa | Sem ML Kit real; coordinator testado com provider mock |
| OCR de etiqueta legado | `services/vision_ocr_service.dart`: `recognizeText`, `parseText`, `processImage` | Imagem/ML Kit | Código, nome, fornecedor, descrição, material e preço | Padrões de preço, código e material; conferência em `VisionScannerPreviewPage` | Dois unit tests somente com texto fabricado; sem imagem real |
| Conferência do scanner | `screens/scanner_draft_page.dart`: `_buildField`, `_confirmar` | Rascunho do scanner | Nome, GTIN, marca e finalidade | Confiança baixa destacada; nome obrigatório; retorno ao chamador antes de persistir | Sem teste específico de revisão/persistência |
| Lookup de GTIN | `services/product_lookup_service.dart`: `isValidGtin`, `lookup` | Código vindo do scanner ou digitação | Nome, marca, categoria, descrição, imagem, quantidade e unidades | Dígito verificador GTIN-8/12/13/14; busca exata por `gtin`; ordem local, catálogo StudioFlow, cache e backend | Validação de formatos; lookup com provedores mock; sem backend real |
| Catálogo local/compartilhado | `LocalProductCatalogProvider.findByGtin`, `StudioFlowCatalogProvider.findByGtin` | SQLite | Dados cadastrados do produto | Consulta SQL exata por GTIN | Cobertura indireta; sem matriz completa de conflito/duplicidade |
| Catálogo oficial/backend | `OfficialProductCatalogProvider.findByGtin`; `BackendSyncService.buscarProdutoGtin` | Backend | Produto e metadados retornados | Exige `found == true`; erro vira indisponibilidade | Somente mock; não há teste de identidade GTIN da resposta |
| Cadastro/importação por GTIN | `repositories/catalog_registration_repository.dart`; telas `produtos_loja_page.dart` e `commercial_center_page.dart` | Lookup/scanner | Dados de cadastro/estoque | Validação GTIN no repositório; confirmação varia por tela | Cobertura parcial em testes de estoque/catálogo |
| PDF de consignação | `services/consignment_document_import_service.dart`: `importPdf`, `_ocrPdf`; `consignment_sheet_parser.dart`: `parse` | `NovaRemessaConsignacaoPage`, `file_picker` | Cabeçalho, datas, zona, categorias, materiais, itens e totais | Texto direto primeiro; OCR se texto inútil; divergência de total; linhas pendentes; conferência antes do repositório | Unit tests com extratores mock; fixture real 5128; teste Android nativo criado, ainda não concluído por restrição de instalação do aparelho |
| Imagem de consignação | `ConsignmentDocumentImportService.importImage`; `VisionOcrService` | JPG/PNG selecionado | Mesmo DTO da consignação ou etiqueta individual | Exige produto reconhecido; conferência posterior | Reconhecedor mock; sem OCR real em Android |
| Fotos de cliente e marca | `cliente_detalhes_premium_page.dart`; `marca_service.dart` | Câmera/galeria | Arquivo de imagem | Crop/seleção; não interpreta dados comerciais | Fora do parser, mas depende de plugin nativo; sem teste real nesta auditoria |

Chamadores do `VisionScannerPage`: vendas, suprimentos, produtos da loja, loja do salão, centro comercial, comandas e catálogos da loja.

## Bugs e riscos encontrados

### Prioridade alta

1. `VisionScannerPage` cria `ScannerCoordinator` somente com `MlKitVisionProvider`. Esse provider sempre retorna `null` em `searchBarcode`; portanto a leitura de código não consulta `ProductLookupService` nem catálogo externo e devolve apenas o código como se tivesse confiança alta.
2. `BarcodeScannerPage.isSupportedBarcode` aceita GTIN numérico apenas pelo comprimento. O dígito verificador só é validado posteriormente em alguns chamadores; o scanner isolado pode devolver GTIN inválido.
3. `OfficialProductCatalogProvider` não confirma que o GTIN retornado em `product.barcode/gtin` é idêntico ao solicitado. Uma resposta inconsistente pode preencher dados de outro produto.
4. `OfficialProductCatalogProvider` atribui confiança fixa `0.85`, mesmo que o backend/fonte não forneça uma medição real. Isso não deve ser tratado como score técnico observado.
5. `MlKitVisionProvider._parseText` aceita qualquer sequência de 4 a 14 dígitos como GTIN e não valida dígito verificador; referências comerciais podem ser apresentadas como código de barras.
6. O teste Android do PDF real executou o `read_pdf_text` e revelou ordenação invertida do PDFBox. O parser foi adaptado genericamente, mas a execução final do aceite foi bloqueada pelo aparelho com `INSTALL_FAILED_USER_RESTRICTED`; portanto ainda não está homologado.

### Prioridade média

1. `ScannerProductDraft.exigeRevisaoHumana` só observa GTIN, nome e marca. Quantidade, unidade, validade, lote e categoria de baixa confiança não acionam revisão.
2. O merge frente/verso em `ScannerCoordinator.analyzeImages` descarta quantidade, unidade, validade, lote e categoria, mesmo quando reconhecidos pelo verso.
3. `VisionOcrService` aceita apenas código numérico; códigos alfanuméricos são perdidos no OCR de etiqueta legado.
4. O OCR pode escolher a primeira linha não reconhecida como nome e a próxima como marca, sem evidência estrutural. Os campos ficam preenchidos sem metadados de origem/confiança nesse fluxo legado.
5. A conversão monetária protege `89,00`, mas não há matriz de regressão para ponto de milhar, ruído OCR ou ambiguidades `0/O`, `1/I/l`, `5/S`, `8/B`, `2/Z`.
6. `ScannerDraftPage` não valida GTIN antes de devolver o rascunho confirmado e permite GTIN vazio; o nome é a única obrigatoriedade efetiva.
7. O botão diz “Confirmar e Salvar”, mas a tela apenas retorna dados. A persistência depende do chamador, o que dificulta provar uniformemente que nenhuma gravação ocorre antes da confirmação.
8. Não existe detecção central de leitura duplicada entre produtos já cadastrados; o comportamento depende de cada repositório/tela.

### Prioridade baixa/observabilidade

1. Erros dos providers do `ScannerCoordinator` são ignorados silenciosamente; o usuário recebe fallback manual, mas não há diagnóstico ou estado explícito de fonte indisponível.
2. `OfficialProductCatalogProvider` registra a resposta completa do catálogo em `debugPrint`, podendo expor dados desnecessários nos logs.
3. Não existem fixtures reais organizadas de imagens/barcodes/textos; apenas `test/fixtures/5128.pdf` está disponível.

## Estado dos testes

### Testes reais existentes

- `test/fixtures/5128.pdf`: PDF real com texto embutido.
- `integration_test/consignment_pdf_native_test.dart`: usa `ConsignmentDocumentImportService()` sem injeção e, quando instalado no Android, chama `ReadPdfText.getPDFtext` real.
- A extração nativa do 5128 foi observada no aparelho; o teste completo ainda não passou após os últimos ajustes porque o Android recusou reinstalações via USB.

### Testes unitários reais de regra, mas sem plugin

- Dígito verificador para GTIN-8, GTIN-12, GTIN-13 e GTIN-14.
- Parser de OCR a partir de strings.
- Parser de consignação, múltiplas colunas, códigos alfanuméricos, repetidos, totais e erros.
- Repositórios SQLite e confirmação/persistência em fluxos comerciais relacionados.

### Testes com mocks/injeções

- `scanner_coordinator_test.dart`: provider integralmente mockado.
- `consignment_document_import_test.dart`: extração PDF, OCR PDF e OCR de imagem injetados.
- Lookup externo de produto: `MockProductCatalogProvider`.

### Ausências que exigem Android real

- `mobile_scanner`: EAN-8, EAN-13, UPC-A/GTIN-12, inválido e leitura repetida.
- `google_mlkit_text_recognition`: fotos reta, inclinada, pouca luz, reflexo, fonte pequena, tabela e múltiplas colunas.
- `image_picker`: câmera e galeria.
- PDF escaneado multipágina: renderização `pdfx` seguida de ML Kit real.
- Reexecução final do 5128 com o parser corrigido.

## Plano de homologação

1. Corrigir primeiro a validação de identidade GTIN e remover confiança inventada do catálogo externo.
2. Unificar o fluxo de scanner para que a câmera consulte o lookup exato e sempre produza rascunho revisável, sem persistência.
3. Expandir `ScannerField`/revisão estrutural para todos os campos importados, sem fabricar probabilidade.
4. Criar fixtures sem dados pessoais em `test/fixtures/importacao/{pdf,imagens,barcodes,textos}` e documentar origem/licença.
5. Adicionar unit tests para GTIN inexistente, resposta com GTIN divergente, duplicidade, OCR alfanumérico, moeda brasileira e merges.
6. Adicionar integration tests Android separados para câmera, ML Kit, PDF textual e PDF imagem/OCR.
7. Executar cada teste nativo em aparelho desbloqueado com instalação via USB autorizada e registrar aparelho/Android/resultado.
8. Só considerar um leitor homologado após teste unitário, teste nativo quando aplicável e prova de que nenhuma persistência ocorre antes da confirmação.

## Critério de segurança adotado

Campo ausente ou estruturalmente duvidoso deve permanecer vazio ou marcado para revisão. Nenhum dado aproximado deve ser apresentado como correspondência exata, e nenhum score numérico será criado sem evidência fornecida pela tecnologia/fonte.
