# B1 — revisão final limitada de estilo

Issue #1120. Revisão final estritamente do resíduo de lint registrado no fim de
`docs/audit/2026-10-07-agentes-b1-codigo-causa-raiz.md`. Não é uma nova revisão
geral do B1 e não reabre runtime, permissões, contratos, frontend ou os serviços
BE-19/BE-31.

## Base e método

- Snapshot congelado antes desta escrita: `20261007-163238-532a5b7b-9baf372e0e`.
- SHA-256 do snapshot: `9baf372e0e18d8ab6adf0b2cef23146e0f605c35979f3f14e2bb02a3fa0f04f8`.
- Arquivo revisado: `app/models/autonomia/agents/build_thread.rb`.
- Escopo: somente as chamadas das linhas 194, 196 e 212 apontadas pelo lint
  consolidado como `Style/HashSyntax`.
- Não executei RSpec, Vitest, RuboCop, build, serviço, banco, navegador, M2/M4
  ou produção. A bateria de lint consolidada e a suíte ampla atualizadas ficam
  para a execução do owner principal.

## Verificação

As três chamadas agora usam valores explícitos:

```ruby
image_signed_ids: image_signed_ids
client_message_id: client_message_id
```

Isso preserva exatamente a semântica anterior da abreviação Ruby: cada keyword
continua recebendo a variável local homônima. Não houve alteração de método,
ordem dos argumentos, defaults, fluxo de lock, deduplicação ou payload.

Os comprimentos medidos das linhas 194, 196 e 212 são, respectivamente, 135,
133 e 133 caracteres, todos abaixo do limite de 150 em `.rubocop.yml`.
`Style/HashSyntax` está ativo com `EnforcedShorthandSyntax: never`, portanto a
forma explícita é a exigida pelo repositório.

## Resultado

A revisão final limitada de estilo **PASSA, sem residual concreto**. O parecer
cobre somente as três chamadas indicadas pelo lint; não constitui aprovação do
lint consolidado, da suíte ampla, de runtime, de telas reais ou de release.
