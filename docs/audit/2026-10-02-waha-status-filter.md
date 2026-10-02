# WAHA — filtro prospectivo de Status em sessões existentes

## Decisão e escopo

Rodrigo relatou a entrada de publicações de Status do WhatsApp durante a ampliação do lote Hub2You e definiu que o histórico deve permanecer. A correção bloqueia novas publicações conforme a política da instalação, sem UI e sem apagar conversas/mensagens. Confirmações de entrega/leitura continuam ativas.

Issue: https://github.com/autonom-ia2/chat/issues/871. Continuidade do lote interrompido: #869/#870. Branch isolada: `codex/waha-status-filter-2026-10-02`, base `0fec5c828af18f8cecde64eb15e1f5a86367c81c`.

## Evidência e causa

- Leitura de produção no Hub2You, sem escrita de configuração: a política da instalação exige `ignore.status=true`, mas as quatro sessões já aplicadas mantêm `ignore.status=false`. As 21 restantes elegíveis já possuem o filtro ligado. Oito caixas ficaram fora por indisponibilidade/falha de leitura ou estado não elegível.
- O migrador publicado preservava a configuração antiga integralmente e podia declarar uma sessão compatível mesmo com o filtro desligado. Esse é o defeito reproduzido e corrigido.
- A documentação oficial define `config.ignore.status=true` para ignorar publicações de Status: https://waha.devlike.pro/docs/how-to/sessions/#ignore. `conversations.syncMessageStatus` controla confirmações de entrega/leitura: https://waha.devlike.pro/docs/apps/chatwoot/.
- Inspeção somente de leitura do código do runtime WAHA confirmou o filtro de JID antes dos eventos da integração. Teste puro do filtro no runtime: Status permitido com `false`, bloqueado com `true`; chat direto permitido. Nenhuma sessão foi alterada nesse teste.
- Essa evidência não determina quando ou por qual caminho cada Status do histórico foi importado. Não há limpeza nem promessa de remoção de eventos já enfileirados.

A leitura agregada foi concluída pelo comando SSM `62943665-5500-4979-a20c-c03f7081495b` com sucesso/0 em 2026-10-02, 21:46:10–21:47:01 UTC. Configurações completas, identificadores operacionais e backups ficam em armazenamento privado, fora do Git.

## Alteração

- O planejador deriva `desired_config` do snapshot completo, alterando somente `ignore.status` conforme `Waha::Config.session_ignore` e sinalizando `session_status_filter` no plano.
- O executor escreve e confirma essa configuração desejada. A comparação N1 anterior ao PUT continua usando o snapshot original de sessão e Apps.
- A recuperação R1 continua restaurando e confirmando o snapshot original, inclusive o filtro anterior. Qualquer falha ou recuperação interrompe o lote.
- Apps completos, outros filtros, proxy e opções desconhecidas permanecem preservados. Uma sessão já compatível requer apenas a mudança do filtro; não grava alterações locais.
- `WAHA_IGNORE_STATUS=false` continua sendo o opt-in explícito já existente da instalação. Não foi criado botão ou preferência por usuário.
- Nenhum override correspondente do planejador/executor existe em `enterprise/`; o contrato foi verificado nos chamadores existentes.

## Validação

Ruby 3.4.4; PostgreSQL de teste `chat2you_waha_status_20261002` e Redis de teste isolado. Nenhum banco de produção usado nos testes.

- Reprodução antes da correção: 57 exemplos, 4 falhas, correspondentes aos novos casos de filtro ausente/desligado e confirmação/recuperação.
- Specs focados após correção: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb --format progress` — 57 exemplos, 0 falhas.
- Regressão delimitada: `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb spec/models/channel/api_spec.rb spec/models/conversation_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events` — 323 exemplos, 0 falhas, 3 pendentes já em quarentena. Dois são de conversas com bot e um é do webhook de conversas WAHA Status; este último não testa a entrada de Status pelo App remoto. Os três estavam pendentes antes desta mudança.
- Cinco exemplos novos: dry-run sem escrita; aplicação prospectiva preservando Apps/configuração/sync de entrega/leitura/estado local; configuração legada sem `ignore`; opt-in explícito; restauração e parada quando o filtro não é confirmado.
- RuboCop: os três arquivos Ruby alterados passaram sem infrações. A primeira execução acusou dois limites de métricas no planejador; a sinalização foi integrada ao cálculo existente e os testes focados passaram novamente.
- Uma tentativa de revalidação partiu do diretório principal errado e terminou com erro de carregamento, sem executar exemplos. Corrigido o diretório, a validação foi repetida no worktree isolado.
- Revisão local: o diff preserva as comparações/recuperação do snapshot original e não altera os outros caminhos de produção. `git diff --check`, hooks normais e CI são verificados na entrega; resultado final fica na PR. Guia não foi tocado.

## Aplicação e recuperação propostas

1. Manter o lote pausado. A primeira caixa já em execução foi confirmada atualizada e `WORKING`; as 21 seguintes não receberam escrita.
2. Revisar e aprovar a alteração específica do filtro nas quatro sessões já aplicadas do Hub2You. Autonom.ia e outras contas ficam fora da operação. A janela de exclusividade já confirmada cobre a conta inteira.
3. Fazer backup completo novo de sessão, Apps e estado local, com acesso restrito; reler sessão/Apps antes da escrita e abortar diante de qualquer diferença. A mudança pretendida nessas quatro caixas é exclusivamente `ignore.status=false` para `true`, mantendo Apps e banco local intactos.
4. Aplicar uma sessão por vez e confirmar `WORKING`, configuração completa desejada, Apps completos e estado local. Se falhar, restaurar o snapshot anterior completo, confirmar recuperação e parar. Não executar retry cego.
5. Validar prospectivamente ausência de novos Status e continuidade das mensagens comuns. Só depois revisar novamente o plano das 21 caixas restantes e continuar pela sequência autorizada, com comparação N1 e parada R1.

O PUT da WAHA provoca restart técnico da sessão. Não há logout, remoção do pareamento, QR ou limpeza de histórico. A releitura N1 não torna GET/PUT atômico; permanece necessária a exclusividade já confirmada.

O merge do produto aciona publicação nas duas instalações pelo fluxo atual. Não executar merge/deploy nem substituir código em produção como atalho. A aplicação operacional restrita do filtro no Hub2You deve ser decidida separadamente dessa publicação. O produto preparado aqui ainda não está publicado. A aplicação operacional do filtro nas quatro sessões foi autorizada e concluída separadamente, conforme o registro abaixo.

## Execução operacional autorizada — concluída

Rodrigo autorizou explicitamente a ativação do filtro nas quatro sessões já aplicadas do Hub2You. A operação foi feita pela API WAHA usando o cliente publicado, sem merge, deploy ou substituição de arquivos da aplicação. O operador administrativo transitório reutilizou as rotinas publicadas de releitura N1, espera por `WORKING` e recuperação R1. Uma restrição de escrita permitiu apenas o PUT da configuração desejada, eventual PUT de restauração do snapshot original e start somente nessa recuperação; nenhuma operação de logout, QR ou exclusão foi permitida.

Antes da operação real, dez cenários locais passaram: caminho normal, novo App concorrente, alterações concorrentes de Chatwoot/resolver/configuração, erro de leitura, falha de escrita, filtro não confirmado, falha de saúde e falha de recuperação. A restrição de escrita também foi validada. Ruby 3.4.4 e sintaxe dos transportes foram conferidos antes de cada despacho.

- Intervalo operacional (Brasília): 2026-10-02 19:06:03 -0300 até 2026-10-02 19:11:53 -0300.
- Quatro backups novos e completos antes da escrita; arquivos antes/depois persistidos no host, diretórios `0700` e arquivos `0600`, root, com hashes verificados. Conteúdo e caminhos completos permanecem privados.
- Cada sessão passou por backup, aplicação e confirmação separada antes da próxima. Todos os 12 comandos SSM terminaram `Success`, código 0.
- Resultado: `updated=4`, `failed=0`, `recovered=0`, `recovery_failed=0`; todas as sessões `WORKING` e `ignore.status=true`.
- A comparação completa confirmou que só `ignore.status` mudou; Apps/configurações não relacionadas e estado local ficaram preservados.
- Toda consulta ao banco ocorreu em transação `READ ONLY`; zero escritas locais. Histórico não foi apagado.
- Não houve alteração de Autonom.ia, outras contas, pareamento, QR ou publicação de aplicação. O runtime continuou `d28a87ad9b7264042a92823c5b6f4d04831d1713`.
- As 21 caixas restantes da ampliação não receberam escrita nesta intervenção; o lote continua pausado. PR #872 permanece aberta para a correção permanente do migrador.

Evidências das quatro aplicações (SSM):

- `cd162eae-c5ec-42a1-a280-226cdc798e16` — Success/0, filtro confirmado e estado preservado.
- `4b51dcf8-eb49-411a-9905-3797f2ed4ca5` — Success/0, filtro confirmado e estado preservado.
- `617421f8-ecb5-4aa2-8d5b-33fee0c1e6a9` — Success/0, filtro confirmado e estado preservado.
- `fb7902c2-1bf1-41ec-bf01-00f415a0f114` — Success/0, filtro confirmado e estado preservado.

Leitura final separada: SSM `e1a67727-2945-4fae-9e68-9315fffabef9`, Success/0, concluída às 19:12:40 de Brasília. As quatro sessões continuavam `WORKING`, compatíveis e com filtro ligado. Foi observada uma mensagem comum de entrada após o ajuste, sem novas mensagens de Status de entrada nesse intervalo; o histórico de Status permanecia presente. Foram selecionadas somente contagens, sem conteúdo das mensagens. A janela é breve e três caixas não tiveram novas mensagens de entrada; não se declara validação de tráfego das quatro nem teste de ponta a ponta de todas elas.

## Autorização de conclusão e publicação

Após a revalidação somente de leitura das 21 caixas restantes, Rodrigo autorizou: “pode seguir! FAça completo e com segurança!”. A autorização cobre concluir o backfill restrito à conta piloto do Hub2You e publicar a correção permanente do migrador nas duas instalações. Autonom.ia receberá somente código; nenhum backfill dessa instalação ou de outras contas faz parte deste trabalho. A janela sem escritores concorrentes do lote restante já havia sido confirmada explicitamente.

Revisão independente somente de leitura, pelo procedimento `caveman:cavecrew`, do HEAD `e50b96b50ae89d8fd4933d6b500d64db6b0c4597` sobre a base `0fec5c828af18f8cecde64eb15e1f5a86367c81c`: **No issues**. Conferidas preservação da comparação N1 com snapshot original, recuperação R1 completa, política da instalação, chamadores e ausência de override Enterprise. A revisão não alterou arquivos nem operou produção. Os testes de concorrência N1 existentes continuam preservados; os cinco novos exemplos são os de filtro listados acima.

A PR #872 foi direcionada ao lote aberto `release/2026-10-02-lote5`, ainda idêntico à main na leitura de preparação. Somente esta correção e sua auditoria estão autorizadas para a publicação deste trabalho. Outro componente ainda aberto nesse lote não será incluído por esta autorização. Antes de publicar, conferir o delta do lote novamente e abortar se surgir código fora do escopo.

Sequência: concluir as 21 aplicações e respectivas confirmações; validar a união de suítes do lote; um merge commit do lote para main; acompanhar os dois workflows automáticos; confirmar SHA, imagem, saúde web/worker, endpoint WAHA separado por instalação e filtro das caixas Hub2You. Não há migration de banco. Rollback de aplicação é um degrau nos workflows blue-green das duas stacks, para as instâncias correntes antes desta publicação, após conferir alvo/saúde; o plano não reverte configurações WAHA ou histórico. Backups operacionais completos ficam protegidos fora do Git.
