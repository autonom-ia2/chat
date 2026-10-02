# WAHA 2026.9.2 — próximo conjunto Hub2You, preparação somente leitura

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/867.
Piloto aceito e limites de QA: https://github.com/autonom-ia2/chat/pull/866.
Estado: **duas caixas prontas para avaliar autorização de APPLY; nenhuma aplicação neste conjunto**.

## Escopo autorizado

Rodrigo autorizou seguir com a preparação do próximo conjunto pequeno após o piloto.
Escopo escolhido: mesma instalação e conta do piloto, máximo de duas caixas, sessões distintas.
Somente inventário e dry-run; sem APPLY, merge/deploy, logout, QR, pareamento ou Autonom.ia.
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
   arquivos 0600 e cópia persistente no host com hash conferido. Backup ainda não capturado neste conjunto:
   precisa ser fresco na janela efetiva de aplicação, não reutilizar o backup da Inbox piloto.
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
APPLY desse conjunto aguarda a aprovação operacional separada dos alvos/janela acima.
