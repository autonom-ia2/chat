# Auditoria — importação inteligente TypeSafe Jev (#764)

Data: 2026-09-29. Branch/worktree isolado `feat/764-intelligent-email-import`, base `a97e4a9e5bf7772a6a561437094bfbb0a41cbd89`. O checkout principal com alterações do operador não foi modificado.

## Incidente reproduzido

Produção da conta 17 tinha a campanha `TESTE CHUBB DAY` (id 44) com importações 18/19 falhando em `missing_name_header`. O arquivo armazenado tinha cabeçalho `NOME;E-MAIL;CORRETORA`; o parser anterior usava o separador CSV padrão (vírgula) e lia o cabeçalho inteiro como uma coluna. Esta entrega transforma esse formato em regressão permanente de teste.

## Mudanças

- Parser CSV tolerante a vírgula, ponto e vírgula, TAB e pipe; UTF-8/BOM, UTF-16 LE/BE com BOM e Windows-1252.
- Leitura XLSX de todas as abas e seleção do cabeçalho/aba por evidência de destinatários.
- Nome deixa de ser obrigatório apenas na importação de e-mail, alinhado ao modelo `EmailCampaignRecipient`; e-mail continua obrigatório.
- TypeSafe Jev `jev-1.13.0` como fallback de de/para para cabeçalhos desconhecidos, somente depois de evidência local de e-mails válidos.
- Uma chamada Jev por arquivo ambíguo, antes dos locks de escrita. Nenhum nome/e-mail de linha é enviado; apenas cabeçalhos e contagens derivadas.
- Duplicidade semântica conhecida continua sendo erro e não é entregue ao modelo para adivinhação.
- Credencial TypeSafe em tabela própria com Active Record Encryption; página de SuperAdmin não reexpõe a chave.
- `schema_resolution` guarda somente evidência estrutural não sensível.
- Erro conhecido de importação passa a ser apresentado pela UI em vez da mensagem genérica de ação.

## Evidência de teste

Baseline antes de alterar o código: seleção focada de importação existente, **23 exemplos / 0 falhas**.

Testes novos/focados exercitam: quatro delimitadores; aspas; UTF-8/BOM; UTF-16 LE/BE; Windows-1252; XLSX sintético multiaba; pacote XLSX binário gerado por `openpyxl`; cabeçalho abaixo de linhas informativas; arquivo somente com e-mail; arquivo real do incidente; duplicados/inválidos/suprimidos; 20.000 linhas; limite exato de 50.000; rejeição de 50.001 antes de insert; API HTTP multipart + ActiveStorage + job + PostgreSQL + leitura da API; segredo cifrado; SuperAdmin write-only; falhas/retry TypeSafe; saída inválida do modelo; preservação do arquivo em falha externa; e ausência de PII no request Jev.

A suíte ampla de e-mail foi executada uma vez em um banco de teste reutilizado e encontrou 2 falhas de maintenance por resíduos de `EmailSuppressionEvent` de rodadas anteriores (16 linhas). Os dois mesmos specs foram repetidos em PostgreSQL recém-criado e passaram: **12 exemplos / 0 falhas**. A validação ampla final deve sempre usar banco limpo.

Frontend de proteção de e-mail após o ajuste de mensagem: **14 arquivos / 431 testes / 0 falhas**. Os warnings de Vue/i18n observados já pertencem ao harness existente; não houve erro de ESLint nos arquivos alterados.

RuboCop focado foi mantido sem infrações após os refactors. A execução final de gates é registrada antes da abertura do PR.

## Teste externo

Sem usar qualquer segredo do usuário, `GET https://api.typesafe.ai/v1/models` com bearer deliberadamente inválido retornou **HTTP 401 application/json** em 29/09/2026, confirmando DNS/TLS/rota pública e o boundary de autenticação real.

Não houve chamada autenticada à TypeSafe nesta fase porque a chave não foi compartilhada com o implementador e não deve ser colocada em chat/arquivo/commit. O teste autenticado foi implementado como botão **Test connection** no SuperAdmin e permanece um gate operacional antes de habilitar Jev.

## Segurança / escopo

Nenhum e-mail de campanha foi enviado. Não houve merge, deploy, gravação em produção, leitura de chave TypeSafe real ou alteração de credencial. A feature permanece desligada por padrão. A migration é aditiva.

## Rollback

Desligar `TYPESAFE_JEV_ENABLED` no SuperAdmin é o primeiro rollback: o parser determinístico continua ativo e a chave/importações ficam preservadas. Não reverter schema nem apagar arquivos/resultados. Merge/deploy dependem de aprovação explícita.
