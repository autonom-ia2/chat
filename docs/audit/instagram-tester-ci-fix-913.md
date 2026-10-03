# PR #913 — correção das duas causas de CI

> Atualização posterior: este documento preserva a evidência histórica. O código, os testes de sessão/proxy e os gates operacionais da rodada de conclusão estão em [instagram-tester-conclusion-910.md](instagram-tester-conclusion-910.md). Os resultados anteriores não validam as alterações posteriores ao commit `e685cb0018`.

03/10/2026. Alteração local revisada, sem merge/deploy.

## Causas comprovadas

- `RSpec (6/8)`: o catálogo do Guia ficou com 218/362 contratos completos (60,22%), abaixo do piso de 60,5%. Os novos endpoints liam parâmetros crus. O piso permaneceu intacto.
- `Email backend and bounded regression`: o lint cumulativo incluiu `DashboardController`; `return` dentro de `each` causou `Lint/NonLocalExitFromIterator`. Não foi falha de entrega de e-mail.

## Correções

Os endpoints agora recortam parâmetros escalares via strong params. Tokens inválidos são rejeitados antes de construir o cliente externo. Token ausente continua usando o OAuth legado; token presente inválido não pode fazer downgrade silencioso. O redirect do Dashboard usa `any?`, preservando a decisão de descarte de destino inseguro.

O comando oficial `autonomia:guia:formatos` regenerou os artefatos: 221/362 contratos completos (61,05%), em 492 ações. Não houve edição manual do catálogo, redução de piso, skips novos ou exclusões de CI.

## Evidência local

- RSpec amplo: **358 exemplos, zero falhas**, 33 arquivos (Instagram, Dashboard, Guia e regressões #898).
- Lint cumulativo usado pelo Email CI: **34 arquivos, zero infrações**.
- Vitest de regressão: **86 testes, zero falhas**, nove arquivos.
- Guia de navegação e formatos gerados: em dia.
- Revisão independente: achados encerrados para esta correção.

Escopo: fecha causas de CI; não declara concluídos sessão automática, proxy ou homologação externa. Os checks precisam executar novamente sobre o commit publicado. Logs locais em `tmp/instagram-910/completion/`, sem dados reais de sessão.
