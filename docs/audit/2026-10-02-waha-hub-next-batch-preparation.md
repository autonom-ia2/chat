# WAHA 2026.9.2 — próximo conjunto restrito Hub2You, preparação e aplicação

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/867.
Piloto aceito e limites de QA: https://github.com/autonom-ia2/chat/pull/866.
Estado final: **duas caixas aplicadas e confirmadas, sem falhas; nenhuma expansão adicional**.

## Escopo inicial da preparação

Rodrigo autorizou seguir com a preparação do próximo conjunto pequeno após o piloto.
Escopo escolhido: mesma instalação e conta do piloto, máximo de duas caixas, sessões distintas.
A preparação foi somente inventário e dry-run; a autorização posterior de APPLY está registrada abaixo.
Sem novo merge/deploy, logout, QR, pareamento ou Autonom.ia.
Identidades de conta/Inbox/canal/sessão e configuração ficam no registro privado, fora do Git/GitHub.
Origem feat/waha-2026-9-2-chatwoot-sync preservada; R1–R5/N1–N3 e código publicado não alterados.

## Runtime e inventário

M4 identificado para todas as operações com estado local. Perfil AWS Hub2You já existente, conta esperada,
sem nova credencial/auth. Parâmetros atuais: i-0f5f268683059c096, imagem d28a87ad9b7264042a92823c5b6f4d04831d1713,
target healthy. SHA de web e worker e serviços ativos conferidos também no comando do dry-run.
Runner valida frontend https://chat.hub2you.ai e WAHA https://wa-hub.autonomia.site.

Inventário limitado à mesma conta do piloto: 33 canais WAHA locais. Planner original consulta somente
metadados de sessão/Apps e módulo, sem mensagens. Resultado: 24 candidatos a atualizar, um já compatível
(o piloto), sete falhas de consulta Waha::Client::Error e um skip session_not_working:FAILED.
Esses oito alvos ficam excluídos, sem tentar reparo, reativação, QR ou substituição de filtro.
Falha da consulta não identifica por si só a causa; não foi apresentada como diagnóstico de autenticação.

Seleção determinística: os dois menores IDs de Inbox elegíveis, habilitados, ainda não compatíveis e com
sessões distintas. Ambas WORKING, identidade local/remota correta, lista/GET Chatwoot iguais, módulo disponível,
nenhum resolver existente/duplicado e lista de Apps contendo somente Chatwoot. Não ampliou para outra conta.
Inventário SSM 858c5587-4216-415c-8459-5d0d9a3787ea, Success/0, 20:13:19–20:14:11 UTC.
Transação PostgreSQL read-only, bloqueio HTTP de mutações e hash local antes/depois igual.

## Dry-run concreto do conjunto

Task original waha:backfill_existing_inboxes, APPLY=false, ACCOUNT_ID e INBOX_ID juntos para cada alvo.
Uma invocação por caixa; nenhum comando sem INBOX_ID. Wrapper interrompe se resultado não for o esperado.
SSM 6831d76a-5c08-431e-8cd9-4f9bd99e8c14, Success/0, 20:15:35–20:15:48 UTC (17:15 BRT).
Saída integral lida; em cada caixa: total=1, would_update=1, updated=0, unchanged=0, skipped=0, failed=0,
recovered=0, recovery_failed=0, halted=false. Hash dos atributos das duas caixas/canais permaneceu igual.
As duas execuções sob transação read-only e Waha::Client GET-only, sem escrita remota/local.

Quatro mudanças propostas por alvo, iguais ao piloto: configuração de conversas do App Chatwoot
(outgoing=message, syncMessageStatus=true, sort=created_newest, qualquer status), resolver brasileiro,
referência local do resolver e lock_to_single_conversation=true. Configuração de sessão e demais campos
preservados pelo executor original. A lista atual não tem Apps extras para exercitar esse cenário real.

## Procedimento preparado para eventual aplicação

Registro operacional privado: /Users/rodrigosilva/.codex/operations/waha-2026-10-02-lote4/next-batch/.
selection.json fixa alvos; execution-plan.json fixa ordem, local do backup e parada; runners privados
partem do procedimento usado no piloto, com somente o ID da Inbox trocado e mesma comparação integral.
Sintaxe verificada com Ruby 3.4.4. Runners operacionais não são código novo do produto.

Antes de escrever: aprovação explícita destes dois alvos e janela sem escritores de Apps/configuração
nas duas sessões, cobrindo eventual recuperação R1. Rodrigo responde pela decisão de restauração;
Codex executa o procedimento documentado. A exclusão do piloto anterior não é presumida para novas sessões.
GET/PUT de WAHA não é atômico: N1 compara novamente o snapshot, mas não substitui essa janela.

Com autorização e janela confirmadas, por caixa e nessa ordem:

1. Revalidar runtime/identidade/WORKING, capturar backup completo local/remoto em diretório privado 0700,
   arquivos 0600 e cópia persistente no host com hash conferido. Na preparação, backup ainda não capturado:
   exigido fresco na janela efetiva de aplicação, sem reutilizar o backup da Inbox piloto.
2. Exigir igualdade local/remota com o backup, executar task original APPLY=true com ambos os filtros,
   preservando todas as guardas N1/R1 e confirmação remota antes de persistir vínculo/trava locais.
3. Exigir updated=1, zero skipped/failed/recovered/recovery_failed, halted=false; confirmar WORKING,
   sessão/config/Apps, resolver único e referência local. Fazer dry-run individual e exigir unchanged=1.
4. Somente após caixa anterior confirmada, seguir para a seguinte. Qualquer falha/skip/recuperação para o
   conjunto. Se a segunda falhar, a primeira já aplicada não é desfeita silenciosamente: registrar estado
   parcial e preparar decisão específica. Não usar retry cego, provisioner ou merge silencioso de Apps.

Desfazer atualização bem-sucedida exige decisão própria: confrontar estado atual com o pós-aplicação,
parar se houver alterações posteriores, confirmar restauração remota antes de escrever atributos locais.
Não há rollback automático global; voltar imagem não desfaz dados/configuração desse backfill.
Não ampliar nem transportar IDs para Autonom.ia. Essa instalação precisa de seleção/piloto próprios.

## Revisão e limites

Preparação somente leitura, com proteção efetiva no banco e cliente HTTP; não prova aplicação nessas caixas.
Não mudou código, UI, schema, dependências de produto, rotas ou Guia. A bateria do lote publicado não foi
reexecutada nem apresentada como nova. git diff --check e hooks normais na auditoria, sem --no-verify.
Logs/seleção privados com acesso restrito; nenhum conteúdo de mensagem, telefone ou secret publicado.
Este era o estado da preparação; autorização e execução subsequentes seguem abaixo.

## Autorização operacional e resultado final

Após apresentar o plano concreto da PR #868, alvos privados, ordem e limites, Rodrigo respondeu “ok”
à solicitação de aplicação somente das duas caixas e confirmação da janela sem outros escritores de
Apps/configuração, incluindo eventual recuperação R1. A autorização anterior do piloto não foi reutilizada.
Registro privado atualizado antes da primeira aplicação; ordem fixa A, depois B, ambas na mesma conta.

Cada caixa recebeu backup fresco completo de atributos locais, sessão e todos os Apps, com arquivo
exclusivo (sem sobrescrever backup), comparação integral e validade máxima de 15 minutos antes de APPLY.
Cópias before.json e after.json persistidas no host atual, diretórios 0700/root e arquivos 0600/root;
hashes da cópia iguais aos calculados no runner. Nenhum conteúdo dos backups foi publicado.
Locais exatos e hashes constam do execution-plan.json e resultados privados por caixa.

| Alvo privado | Etapa | Comando SSM | Início–fim UTC | Resultado |
| --- | --- | --- | --- | --- |
| A | backup | 4dbd0385-e2ce-4f05-8be1-77116314f058 | 2026-10-02T21:31:58.135Z–2026-10-02T21:32:11.135Z | Success/0 |
| A | apply | 25b3327b-9344-4bcf-aed3-3f9f00af0219 | 2026-10-02T21:32:36.185Z–2026-10-02T21:32:57.185Z | Success/0 |
| A | confirmation | bf5c74d7-581f-4184-93de-3cfc9031ee44 | 2026-10-02T21:33:13.158Z–2026-10-02T21:33:24.158Z | Success/0 |
| B | backup | 43b8ba84-d963-4022-8a8d-1a3f90491e3e | 2026-10-02T21:33:45.907Z–2026-10-02T21:33:56.907Z | Success/0 |
| B | apply | e11042a1-f7bf-4ed3-b79b-c494e75f7849 | 2026-10-02T21:34:30.855Z–2026-10-02T21:34:50.855Z | Success/0 |
| B | confirmation | d3d5491b-d8af-4121-b5ea-f130bb94fa07 | 2026-10-02T21:35:17.655Z–2026-10-02T21:35:28.655Z | Success/0 |

Primeiro APPLY confirmou UPDATED=1, WORKING, configuração da sessão preservada, resolver único e
habilitado, referência local igual ao resolver remoto, lock_to_single_conversation=true e plano final vazio.
Dry-run individual com transação read-only e cliente GET-only confirmou unchanged=1, sem escrita e com
hash local inalterado. Só então foi enviado o backup da segunda caixa, repetindo todas as etapas.

Resultado agregado das aplicações: total=2, updated=2, skipped=0, failed=0, recovered=0,
recovery_failed=0, halted=false. Cada execução usou ACCOUNT_ID e INBOX_ID juntos, sem modo conta inteira.
Ambas continuaram WORKING; dry-run posterior de cada caixa: would_update=0, updated=0, unchanged=1,
zero skips/falhas/recuperações. Não houve retry, recuperação R1 ou rollback a executar.

Identidade AWS, instância e imagem atuais conferidas antes de cada comando; web/worker ativos e SHA
publicado conferidos no próprio SSM. Target permaneceu healthy durante a execução e na conferência final.
Origem permaneceu limpa no SHA 62af5b0493dda09aba9c764e9e62f58197895f34; nenhuma edição no produto.
Autonom.ia e demais caixas/contas não foram chamadas nem alteradas. Sem merge/deploy, logout, QR,
pareamento, envio de mensagem pelo operador ou ampliação para os demais candidatos.

## Validação e próximo limite

Saídas integrais das seis etapas lidas, incluindo contadores, código de saída, hash e permissões.
Sintaxe do transporte privado Python validada, guardas de ordem e contadores revisadas antes do envio.
A auditoria é a única alteração em Git: git diff --check e hooks normais; sem --no-verify.
Não houve mudança Ruby do produto/Guia, portanto RuboCop, specs amplos e pnpm guia:check locais
não foram repetidos; não se apresentam os testes do lote publicado como novas execuções.

Configuração e idempotência verificadas nestas duas caixas. Tráfego real, chegada única, reabertura e
variante com/sem nono dígito foram aceitos no piloto anterior; não foram repetidos nem presumidos aqui.
Acompanhar o uso normal destas caixas antes de propor próximo conjunto. Não enviar mensagens extras
só para produzir evidência. Expansão para outras caixas exige seleção, dry-run e autorização específicos.
Autonom.ia exige inventário e piloto próprios, sem transportar IDs ou configuração do Hub2You.
