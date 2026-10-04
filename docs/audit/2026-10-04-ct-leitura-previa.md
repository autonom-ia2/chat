# CT — tempo da leitura prévia de 53 ids (AC-CT7)

Issue #934 (frente CT do PRD `docs/guia-operante/PRD-5-FRENTES.md`). Medido em 04/10/2026,
local (MacBook Air M4, Postgres e Redis de teste, `RAILS_ENV=test`), na branch
`feat/934-guia-contexto-tela`.

## O que se mede

`Autonomia::Guide::Tela#bloco` com 3 abertos e 50 selecionados: 53 leituras por id,
cada uma pela `Consulta` (pilha completa do Rails em processo, com o token da pessoa,
controller e Pundit). É o que o `ChatJob` faz antes da primeira ida ao modelo.

Spec: `spec/services/autonomia/guide/tela_spec.rb`, exemplo "lê 53 ids em menos de 3
segundos". `CT7_MEDIR=1` imprime o tempo.

## Resultado

| Cenário | Tempo de 53 ids | Por id |
|---|---|---|
| Cards (`crm/cards`), como em produção | 0,34 s a 0,52 s (6 rodadas) | ~8 ms |
| Conversas (`conversations`), como em produção | 0,38 s | ~7 ms |
| Cards, ambiente de teste cru | 2,83 s | ~41-53 ms |
| Conversas, ambiente de teste cru | 2,34 s | ~44 ms |

Teto do AC: 3 s. Passa com folga de ~6×.

## Por que o ambiente de teste cru é 5× mais lento

O `config/environments/test.rb` tem `cache_classes = false`, então a cada pedido interno o
recarregador confere a data de todos os arquivos. Medido com `stackprof` (modo wall, 20
leituras): `Dir.[]` 54,7% e `File.mtime` 18,5% do tempo; SQL, 2 ms de 42 ms por leitura.

Produção tem `cache_classes = true` e `eager_load = true` e não faz essa conferência. A
medida "como em produção" desliga só ela (`Rails.application.reloader.check!` → `false`) e
mantém todo o resto: roteamento, autenticação por token, Pundit, jbuilder e o `Resumo`.

## Custo no prompt (mesmo AC)

- Só a rota: 100 caracteres com `crm_kanban_index` (teto 200).
- Um aberto com descrição longa + 50 selecionados + filtros: abaixo de 2.600 (spec "com um
  aberto e 50 selecionados").
