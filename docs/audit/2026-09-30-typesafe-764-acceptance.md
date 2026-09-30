# #764 — Jev na leitura da lista e recuperação no editor

## Decisão e autorização

Rodrigo autorizou corrigir a interpretação antes de produção, adicionar recuperação utilizável no editor e executar 20–30 planilhas com Jev real. O limite pago foi confirmado como US$ 1. A execução ocorreu no worktree `codex/764-import-runtime-diagnosis`, separado do checkout principal. Esta etapa não executou merge, deploy, reimportação na conta 16 ou envio de e-mail.

## Problema e comportamento entregue

O XLSX original `05_duplicidade_normalizada.xlsx` era recusado por `duplicated_name_header` antes de consultar o Jev: Cliente e Contato eram tratados como dois nomes. A apresentação pública ainda reduzia essa causa a `import_failed`.

Com TypeSafe configurado e ativo, o Jev interpreta os cabeçalhos antes dos aliases locais. Recebe cabeçalhos, presença de endereço válido por coluna e formatos de até três exemplos de 80 caracteres. Todas as linhas são examinadas localmente para detectar endereço válido, mesmo quando está fora da amostra de até 50 linhas. Valores de nomes, telefones, notas e endereços são mascarados; contagens/proporções de linhas inválidas ficam locais. Colunas com endereço confirmado mostram apenas o marcador de formato válido. Identificação da coluna e validação de cada destinatário permanecem decisões separadas.

A saída exige modelo correto, tipos/índices válidos, confiança mínima de 0,8 na coluna de e-mail, confirmação de esquema acima de 0,5 e endereço válido constatado localmente na coluna escolhida. Nome é opcional: baixa confiança deixa a coluna como dado adicional. Não se reduziu o modelo ou limiar para aprovar o caso esparso. Duas colunas igualmente plausíveis continuam recusadas; falha de provedor configurado não provoca troca silenciosa para aliases.

O editor abre um popup para falha em campanha editável, com motivo, proposta de correção e escolha de CSV/XLSX na mesma campanha. Detalhes oferecem abertura manual. Somente falhas temporárias/desconhecidas permitem repetir o arquivo original. Configuração inválida e solicitação recusada orientam procurar o administrador. A antiga ação de repetição sem essa distinção foi removida. A API exige permissão de gerenciamento para upload/repetição, inclusive para funções personalizadas. Motivos públicos conhecidos passam pela lista permitida; mensagens arbitrárias permanecem ocultas. Sem rota nova, migração ou mudança de envio.

## Rodada real final

- Ambiente local Rails/Vite isolado, PostgreSQL `127.0.0.1:55779`, banco `email764_acceptance`, Redis isolado e conta sintética.
- Upload multipart real pelo endpoint do produto, processamento real, leitura pública e conferência de registros, campos adicionais e rascunho preservado.
- **30/30 resultados esperados: 26 concluídas e quatro recusas justificadas**. As recusas cobrem ambiguidade real, ausência de e-mail, todos os endereços inválidos e arquivo vazio; nenhuma adicionou contatos.
- Cinco XLSX originais conferidos por SHA-256, incluindo o arquivo 05: um contato importado e um duplicado, com empresa e pessoa distinguidas.
- Caso 28: um elegível e três excluídos por falha permanente, spam e descadastro.
- Caso 31: um contato importado, 119 inválidos, total 120; confiança do e-mail 1,0 e confirmação de esquema 0,97. Um endereço fora da amostra não impede a identificação da coluna.
- O conjunto final substitui o caso redundante 27, já coberto pelo original 05, pelo caso esparso 31. Continua contendo 30 arquivos.
- [Pacote, hashes e resultados por arquivo](../testing/email-import-764/README.md).

A rodada final fez **27 avaliações novas do Jev real** e três recusas estruturais locais sem gasto. Depois da interrupção do RDS, o transporte passou a consultar a configuração uma vez por lote em sessões somente leitura desde o boot e desconectar o banco antes de consultar o provedor. A chave permaneceu dentro da instalação. Cada resposta nova foi vinculada ao SHA-256 da requisição e do arquivo e usada uma única vez no fluxo local. Os resultados não foram simulados; esse procedimento não comprova o transporte de rede do worker produtivo. Detalhes da interrupção e da contenção estão no [registro do RDS](2026-09-30-typesafe-764-rds-interruption.md).

Rodadas anteriores expuseram interpretações de confiança booleana, tratamento de nome opcional, evidência de endereço fora da amostra e influência indevida da frequência de inválidos. A rodada 29/30 não foi tratada como aprovação final: depois da última correção, todos os 30 arquivos foram processados novamente com decisões novas do provedor.

## Uso pago e orçamento

O controle serializado contabilizou 151 avaliações reservadas, incluindo calibrações, revisões e teste de tela: 148 respostas confirmadas, duas tentativas comprovadamente interrompidas antes de consultar o Jev e uma tentativa de transporte sem resultado conclusivo. As respostas confirmadas somam **182.498 tokens de entrada**. Estimativa pelo uso retornado: **US$ 0,007664916**, a US$ 0,042/milhão de entrada e saída gratuita, conforme [documentação do modelo](https://docs.typesafe.ai/models). Não é valor conferido em fatura.

A reserva considera até três tentativas do mesmo payload por avaliação: tokens confirmados × 3 para respostas conhecidas e 65.536 tokens × 3 para cada chamada pendente/desconhecida. O último lote foi autorizado pelo controlador com reserva total máxima de US$ 0,250416054, antes de executar. Com as respostas recebidas, a reserva conservadora final ficou em **US$ 0,031252284**, mantendo a chamada desconhecida no pior caso. Nenhuma etapa ultrapassou o US$ 1 aprovado. A contabilização não depende de descartar chamadas sem resposta como gratuitas.

## Evidência pelo navegador

Popup verificado no Chrome desktop e em 390 × 844, sem transbordamento. A permissão da extensão impediu o upload local no Chrome; nenhuma permissão foi alterada. O fluxo completo de arquivo corrigido foi concluído no navegador integrado.

Na campanha sintética 24, a tentativa original 24 permaneceu registrada como falha `schema_not_resolved`. O arquivo 22 escolhido no popup gerou importação 66 concluída, com dois contatos. O diálogo fechou e a leitura local confirmou o mesmo rascunho e `body_html`. A pressão de memória do host afetou essa sessão; não é medição de desempenho de produção. Capturas abaixo são telas reais da implementação, anteriores aos ajustes de privacidade e permissão que preservam o fluxo visual.

![Popup real com arquivo corrigido selecionado](assets/2026-09-30-import-764/recovery-desktop.jpg)
![Resultado real depois do reenvio](assets/2026-09-30-import-764/recovery-success.jpg)
![Popup em tela estreita](assets/2026-09-30-import-764/recovery-mobile.jpg)

## Validação de código e revisão

- Regressão Ruby final em banco novo: **1.050 exemplos, zero falhas, dois pendentes antigos**. Pendentes: `CampaignImports::UndoLabelsJob` e `Account has_many autonomia_account_links`, já em quarentena na base.
- Frontend: **441 testes em 14 arquivos aprovados**.
- RuboCop dos arquivos Ruby alterados: zero infrações após revisão da formatação.
- ESLint: zero erros bloqueantes; avisos existentes de i18n dinâmica e namespace.
- Catálogos próprios: nove catálogos, 15.864 mensagens compiladas; gates de campanhas aprovados.
- Build Vite de teste: 6.036 módulos, concluído; avisos existentes de tamanho de chunks.
- Nove grupos puros finais: 56 testes, 50.870 asserções, zero falhas/erros. O teste de codificação carrega explicitamente o novo profiler.
- Revisão independente confirmou privacidade, evidência por coluna, nome opcional, autorização e repetição restrita; delta semântico revisado com 16 exemplos, zero falhas, sem provedor pago ou produção.

Uma execução simultânea ao build Vite sofreu timeout de 14 segundos num exportador preexistente de mais de 10.000 linhas; a repetição focada passou. Isso não foi chamado de suíte completa verde. A validação final acima foi repetida em outro banco novo, sem build pesado em paralelo, e passou inteira. A saída das validações foi lida antes de commit; nenhum teste foi encadeado com commit.

Comandos: `bundle exec rspec` com a seleção de campanhas/TypeSafe e regressão limitada mais os specs de apresentação/permissões, `bundle exec rubocop`, `pnpm vitest run`, wrapper ESLint do CI, gates i18n e `pnpm vite build --mode test`. rbenv e dependências travadas foram usados. Setup, orçamento, transporte e arquivos intermediários ficam em `.codex/`, sem credenciais em Git.

Os catálogos próprios en/pt_BR seguem `config/fork_i18n.json` e a exclusão Crowdin vigente. OSS e Enterprise foram conferidos; o novo spec Enterprise de permissão entra no seletor de campanhas pelo nome `email_campaign_recipient_import_permissions_spec.rb`. Sem override adicional necessário.

## Liberação

PR #796 atualizado com código, corpus, revisão e evidências. O CI precisa corresponder ao commit final; resultados de revisões anteriores não substituem essa checagem. A liberação usa o fluxo aprovado do projeto e deploy blue-green, com validação sintética após publicação e sem iniciar envio. Reversão: imagem/revisão anterior pelo rollback existente; não há migração nesta alteração. A conta 16 e sua importação original não foram modificadas por esta rodada.
