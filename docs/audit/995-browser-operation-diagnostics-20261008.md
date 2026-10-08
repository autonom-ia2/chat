# Diagnóstico das operações assistidas do Instagram — 2026-10-08

Issue #995 permanece aberta. A correção Redis do PR #1134 foi publicada pela fila normal em `372ca4eb5da63a6d87d01d3c40f78344b4c2d7cf` nos dois ambientes AWS. O único piloto Hub2You autorizado terminou `failed/meta_unavailable`, sem conexão funcional. Não foi enviado convite, OAuth ou DM. A fase da falha histórica não foi preservada; não atribuímos a causa a login, Chrome ou Meta.

## Estado seguro confirmado

A desativação Hub-only usou deploy normal `37741910042`, concluído com Deploy Green success e rollback job skipped. Leitura direta às 07:25:06 UTC confirmou web/worker no merge372 e destinos/listeners atuais saudáveis nas duas stacks, browser operations unset. Manager VPS voltou a operações desligadas; código d278, perfis/caps e demais serviços preservados. Os destinos anteriores não estão saudáveis para rollback imediato. O recibo sanitizado está em `995-pr1134-final-off-health-20261008.json`.

## Mudança proposta

O executor informa a última fase alcançada apenas quando falha: validação, observadores, rotas, navegação/captura de papéis, abertura do diálogo, seleção do papel e resposta da busca. Registra apenas ação permitida, código de erro existente, contagens e booleans. Não registra IDs, handle, URLs, mensagens de exceção, cookies, tokens ou corpos de requisição/resposta.

O gestor registra chegada de resposta de claim, início/retorno da execução e tentativa/retorno de complete. O campo `read_received` separa falha de leitura de resposta de fila vazia. `received` significa resposta recebida, antes da validação de identidade; não prova confirmação válida. Uma busca vazia do polling não gera log. O formato de resposta ao backend, gates, permissões, bloqueio de repetição de escrita e comportamento de busca/convite/status permanecem iguais.

Este PR torna a próxima falha diagnosticável. Não corrige uma causa ainda desconhecida nem comprova conexão ou reconexão funcional.

## Validação local

- `git diff --check` e Node `--check` nos dois scripts: aprovados.
- Suite existente `tests/instagram_testers/session-manager.test.mjs`: 55 testes executados, 0 falhas, 0 skipped.
- Planner MacCluster recusou M2 por cwd ausente e M4 pelo limite genérico de disco. Recursos reais M4: 18.6GB livres, thermal Nominal. Suite pequena de builtins/fixtures executada explicitamente no M4, 496ms inicial / 475ms após ajustes; sem banco, Meta ou alteração de limites/infra.
- Harness operacional sintético confirmou falha em `roles_navigation`, nenhuma exposição do canary/IDs/handle/URL e mesmas oito chaves do envelope terminal. Fixtures incompletos omitiram proxy, app_id ou requestGuard; corrigidos sem alteração do produto e sem Meta.
- Revisão Nexo e Iris encontrou callback opcional sem proteção; corrigido com try/catch no executor. Harness adicional confirmou que callback lançando exceção preserva o envelope terminal. Revisões finais Nexo e Iris verdes; Prettier check aprovado.

## Publicação e rollback propostos

1. Revisão independente e CI no head concreto; aprovação explícita para merge, deploys e atualização da VPS.
2. Merge pela fila normal e acompanhar ambos deploys automáticos; não duplicar dispatch. Manter browser operations desligadas nas duas stacks e verificar fonte, worker, destino e listener.
3. Preparar pacote VPS da fonte mergeada com hash, dependências existentes e rollback para d278; estes scripts mudaram, portanto a identidade antiga não dispensa instalação. Preservar perfis/caps/locks, n8n, Traefik, Redis, DNS e IAM. Atualizar guards dos helpers e submetê-los a revisão antes de uso.
4. Verificar fonte/saúde das oito unidades; ativar somente Hub2You mediante procedimento revisado com versões SSM atuais (baseline v13 unset). Helpers antigos v11/v12/v13 não podem ser reaplicados às cegas.
5. Confirmar fila vazia e sessão válida; uma busca exata no alvo já autorizado. Recolher só os novos campos permitidos, correlacionados por tempo e pela execução única. Não enviar DM, não substituir perfil e não repetir escrita com resultado desconhecido.
6. Se falhar: preservar diagnóstico sanitizado, drenar operações, desligar manager e flag Hub por deploy normal, comprovar saúde. Não usar a ação antiga de rollback do workflow. Restaurar fonte VPS somente com unidades drenadas e guards revisados.

A aprovação deste plano não deve ser confundida com aceite funcional. A publicação ainda não ocorreu para este PR.
