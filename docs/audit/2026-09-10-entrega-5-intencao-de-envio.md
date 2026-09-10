# 2026-09-10 · Entrega 5 · Limitar a cotação repetida a uma, e deixá-la registrada

Plano do Agente de Cotação (épico #291). Branch `feat/entrega-5-intencao-de-envio`. Era a janela #337.

## Termo 1 — medido: o portal NÃO lista cotações

Sondagem read-only com a sessão de teste, 14 nomes plausíveis nas duas APIs (`/calculo/negocios`,
`/calculo/cotacoes`, `/calculo/historico`, `/calculo/meusCalculos`, `/calculo/listar`, `/cotacoes`,
`/usuario/cotacoes`, `/cfg/corretora/cotacoes`…): 403 do API Gateway (rota inexistente) ou 404
"Não encontrado". O catálogo do adapter (41 rotas com caminho) tampouco tem listagem. Uma cotação só
é endereçável pelo id que nasce no `quote/start`. Logo, não há como perguntar "já existe?": o
contador é o desenho.

## Decisões

- `AsyncRunJob#submeter`: anota a INTENÇÃO (`autonomia_intencoes` no handle, via
  `ToolRun#record_handle!`, sem contar tentativa) ANTES do `start`; o NÚMERO vem depois com
  `SUBMITTED_KEY`. Intenção sem número na passada seguinte → no máximo mais UMA submissão
  (`MAXIMO_DE_INTENCOES = 2`), com `autonomia_possivelmente_duplicada = true` e um `warn`; na
  terceira, `fail_run('envio_incerto')` — o cliente é avisado, o portal não é chamado.
- `start` que levanta apaga a intenção: o portal disse que não fez (ou nem foi alcançado); a
  execução segue podendo ser tentada, e a intenção não vira sentença de "já foi".
- `ToolRun.possivelmente_duplicadas` lista as marcadas (jsonb `@>`); o `ReapStaleRunsJob` marca a
  abandonada que morreu com intenção e sem número.
- A ferramenta nunca vê as marcas (`tool_handle` remove `MARCAS`); as consultas as preservam.

## Validação

- Suíte ampla (tools, specialists, answerer, operate, jobs/tools, models/agents): 409 exemplos, 0 falhas.
- Mutações (cada uma reprova o exemplo que a nomeia): teto 2 → 60; anotar depois do `start`; falha
  não apagar a intenção; marca não sobreviver à consulta; a ferramenta ver as marcas.
- Não se finge matar o processo: o estado "intenção sem número" é reproduzido e observado; sinal não
  é o que a suíte sabe reproduzir.
