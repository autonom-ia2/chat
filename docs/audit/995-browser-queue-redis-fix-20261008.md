# Issue 995 — correção da leitura da fila de operações Instagram

## Problema comprovado

A publicação aprovada no PR #1129 chegou aos dois ambientes AWS e à VPS no commit `d27814313fd96e7bc52266efa6177d7421dc4875`. O blue-green de ativação somente na Hub2You (run `37708017246`) concluiu com sucesso. Isso não comprovou a conexão Instagram.

No piloto autorizado da conta 18, uma busca entrou na fila e expirou sem claim, permit ou escrita. O painel mostrou integração indisponível. A operação não chegou ao Chrome nem à Meta. Autonom.ia permaneceu com as operações novas desativadas. Não houve convite, OAuth ou DM neste piloto.

`BrowserOperationStore#next_request` chamava `Redis::Alfred.zrange` e `Redis::Alfred.zrem`. A fachada `lib/redis/alfred.rb` não define nenhum desses métodos. Uma leitura sanitizada do runtime Hub2You confirmou `respond_to?` falso para ambos na fachada e verdadeiro na conexão Redis, com o SHA esperado. O erro acontece antes de o publisher produzir o envelope para a VPS.

## Correção mínima

As duas chamadas passam pela conexão de `Redis::Alfred.with`, como o restante das transações desse serviço. A conexão é liberada antes da iteração: a expiração de um pedido pode abrir sua própria transação. Não há mudança em TTL, claim, autorização, convite, OAuth, perfil ou protocolo. Nenhuma extensão Enterprise correspondente altera esse contrato.

## Validação

- O mesmo harness operacional, carregando a fachada e os serviços reais, reproduziu `NoMethodError: Redis::Alfred.zrange` no código de `d278` e aprovou o código corrigido.
- Redis real descartável, socket Unix privado, pool de uma conexão; nenhum boot Rails, banco da aplicação, rede externa ou chamada Meta.
- Dez verificações: fachada real sem os métodos; leitura de pedido; preservação dos bytes e fila sem claim; envelope do publisher real; limpeza de órfão; expiração sem timeout; persistência CAS e remoção da fila; fila vazia; reutilização do pool; todas as chamadas diretas presentes na fachada.
- `bundle exec rubocop app/services/instagram/testers/browser_operation_store.rb`: um arquivo, zero infrações.
- `git diff --check`: aprovado.
- O planner MacCluster excluiu os nós para esse cwd (`m2=cwd-missing`, `m4=insufficient disk`). O harness leve executou no M4 identificado, com Redis descartável; não houve cópia de checkout ativo nem teste Rails com ambiente de produção.

Os testes anteriores com fachada simulada não detectaram a incompatibilidade. Este resultado local valida a correção do caminho da fila; ainda não valida conexão/reconexão na Meta.

## Proveniência dos recibos locais

- Harness SHA-256: `021ecc21ea41418d7a13b6508cb488979703d74a405dbaab2185d206d0a2631b`.
- Fonte corrigida SHA-256: `0e568f0a1cd54002aa9533b200b45f8433e75a51ef793e5ca57792e76309c7ca`.
- Recibo: `.codex/queue-redis-facade-regression-result.json` (10 verificações, Ruby 3.4.4, redis gem 5.0.6).
- Leitura live: `.codex/hub2you-alfred-sorted-set-surface.json`.
- Erro real do painel: captura `hub18-instagram-search-error.jpg` no diretório de visualizações desta tarefa.

## Publicação e rollback

A autorização anterior cobriu o head revisado do PR #1129, não esta correção posterior. Este PR deve passar por revisão e CI no head concreto antes de nova aprovação de merge e publicação.

O rollback da tentativa nova foi autorizado pelo plano já aprovado: desligar apenas as operações novas na Hub2You, preservar perfis, automação administrativa e Autonom.ia. A SSM Hub voltou de versão 10 (`true`) para 11 (`unset`), com readback verificado. O manager Hub também voltou à flag ausente; pós-preflight comprovou oito unidades saudáveis, caps, perfis e locks preservados. Recibos: `.codex/hub2you-manager-1129-rollback-004741187505.json` e `.codex/hub2you-manager-1129-preflight-004744543767.json`. Resta confirmar a carga da flag desativada no runtime AWS pelo caminho blue-green/rollback.

Após nova aprovação: merge pela fila normal, publicação AWS nos dois ambientes com a flag desativada; pacote VPS correspondente se necessário; health e hashes diretos; ativação somente Hub2You; primeiro piloto de leitura/busca e depois status/convite somente se necessário para a conta autorizada. Não repetir convite de resultado desconhecido. Sem DM. Não encerrar #995 até conexão e reconexão verificadas; o @ exato de Autonom.ia continua pendente.
