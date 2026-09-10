# 2026-09-10 · Entrega 6 · Registrar por que o agente se recusou a cotar

Plano do Agente de Cotação (épico #291). Branch `feat/entrega-6-registro-de-recusa`.

## Decisões

- Um produtor único (`Tools::Recusa`) para toda saída de recusa da camada de ferramentas: registra
  a linha `[autonomia][tool][recusa] slug= conversa= agente= conta= onde= motivo= faltando= detalhe=
  descricao=` em nível `info` e monta o JSON `{"error": ...}` que o modelo lê, com o código e o
  detalhe como vieram (o filtro de forma é só do registro).
- O registro nunca levanta; falha de logger não derruba o turno nem o job.
- `precheck` devolve `Native::Conferencia` (texto + motivo + nomes dos campos), para o registro dizer
  QUAIS campos faltaram.
- A recusa do `start` leva `faltando` no handle; o `AsyncRunJob` registra com `onde=envio`.
- As cinco saídas em prosa do `Specialists::Runner` (sem pedido, sem credencial, sem resposta,
  exceção, vazio) registram com a conversa: são o único caminho até a cotação.
- Guarda por AST (Prism, `spec/support/varredura_de_recusas.rb`), recursiva sobre
  `app/services/autonomia/agents/**` e `app/jobs/autonomia/agents/**`: `{ error: }`, `h['error'] =`,
  `Hash[...]`, `JSON.generate/dump(error:)` fora do produtor único reprovam; código de recusa
  (literal, constante do arquivo ou lado direito de `||`) fora de `MOTIVOS` reprova; saída sem
  gatilho em `recusa_registro_spec` reprova. 26 saídas, 26 gatilhos, 19 motivos.
- Segunda rodada do Codex (ainda REPROVADO): a nativa síncrona passa a receber o `delivery` do
  turno (a recusa de `capabilities_unavailable` sai com a conversa); as duas recusas antes de rodar
  das condições gerais ("Informe a seguradora/dúvida") entram via `Native::Base#recusar`; a guarda
  vê `::JSON.generate`, `merge(error:)`, `store(:error)` e conta cada `error('x')` de nativa como
  saída própria. O nome que o modelo pediu em `tool_not_available` continua no registro, de
  propósito: é o diagnóstico do caso #356, e é texto do modelo em forma de identificador.
- Fora de escopo, documentado: prosa das ferramentas síncronas de KB; causa do erro HTTP (só a
  categoria e o status vão ao registro); desfechos do job ficam em `tool_runs`.

## Nível de log em produção (termo 4)

Lido na instância green da stack hub2you em 10/09/2026 via SSM (read-only):
`LOG_LEVEL=info`, `RAILS_LOG_TO_STDOUT=true`, driver de log `json-file`. As linhas `INFO` do
worker aparecem em `docker logs chatwoot-worker`.

## Validação

- `bundle exec rspec` recusa_spec + recusa_registro_spec + recusa_guarda_spec + runner_spec +
  insurance_capabilities_spec + insurance_quote_spec: 87 exemplos, 0 falhas.
- Suíte ampla (tools, specialists, answerer, jobs/tools, models/agents): 0 falhas (número no PR).
- `bundle exec rubocop` nos arquivos tocados: 0 ofensas.
- Provas por mutação (cada uma restaurada e conferida byte a byte): `info`→`debug` no registrador
  derruba 30 de 38 exemplos; `{ error: 'x' }.to_json`, `h['error'] = 'x'`, `JSON.generate(error:)`,
  `recusar(CONSTANTE)` fora do catálogo, `return 'motivo_novo'`, saída dinâmica nova e gatilho
  apagado, `::JSON.generate(error:)`, `{}.merge(error:)` e `error('codigo_novo')` numa nativa —
  todos reprovam com arquivo e linha.
- Revisões: Codex (REPROVADO no commit inicial; 6 achados, todos endereçados ou documentados) e
  revisor adversarial (REPROVADO no commit inicial; A1, B1, B3, C1, C2, D1–D5, E1, E2, E5, F1, F3,
  F4, F5, H1–H5 endereçados; E3 e E4 documentados como fora de escopo).

## Bloqueios

- Termo 5 (recusa real em produção encontrada no registro) exige deploy — automático no merge da
  main — e uma conversa real com a Lia.
