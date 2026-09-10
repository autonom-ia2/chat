# 2026-09-10 · Entrega 5 · Limitar a cotação repetida a uma, e deixá-la registrada

Plano do Agente de Cotação (épico #291). Branch `feat/entrega-5-intencao-de-envio`. Era a janela #337.

## Termo 1 — medido: o portal NÃO lista cotações

Sondagem read-only com a sessão de teste, 14 nomes plausíveis nas duas APIs (`/calculo/negocios`,
`/calculo/cotacoes`, `/calculo/historico`, `/calculo/meusCalculos`, `/calculo/listar`, `/cotacoes`,
`/usuario/cotacoes`, `/cfg/corretora/cotacoes`…): 403 do API Gateway (rota inexistente) ou 404
"Não encontrado". O catálogo do adapter (41 rotas com caminho) tampouco tem listagem. Uma cotação só
é endereçável pelo id que nasce no `quote/start`. Logo, não há como perguntar "já existe?": o
contador é o desenho.

## Decisões (revisadas em 10/09/2026 após Codex REPROVADO e revisão adversarial)

- `AsyncRunJob#submeter`: anota a INTENÇÃO (`autonomia_intencoes` no handle, via
  `ToolRun#record_handle!`, sem contar tentativa) ANTES do `start`; o NÚMERO vem depois com
  `SUBMITTED_KEY` (que passou a morar em `ToolRun`). Intenção sem número na passada seguinte → no
  máximo mais UMA submissão (`MAXIMO_DE_INTENCOES = 2`), com `autonomia_possivelmente_duplicada = true`
  e um `warn`; na terceira, `fail_run('envio_incerto')` — o portal não é chamado.
- **A fronteira é a chamada paga** (`InsuranceQuote::Envio`). `quote_start` que falha com
  `timeout`/`unavailable`/`protocol`, erro fora do connector, ou resposta sem `quote_id`, levanta
  `Native::EnvioIncerto` (com `motivo` nosso e `cause`): o job **mantém** a intenção. `auth_required`
  (renovado por `with_fresh_session`), `validation`, `config` e `not_implemented` sobem como estão, e
  qualquer falha ANTES da chamada (login) também: a intenção **volta atrás** (2→1 tira a marca).
  Era o achado ALTA do Codex e da revisão: timeout depois de o portal criar a cotação era lido como
  "não fez", e a passada seguinte cotava de novo sem marca.
- **Escritas do handle mescladas no banco, nunca copiadas da memória**: `ToolRun#merge_handle!`
  e `#record_attempt!` fazem `handle = (handle || ?::jsonb) - ?::text[]` (e `attempts + 1` em SQL).
  Um processo com objeto velho não apaga o número nem a marca que outro gravou. `encerrar` e
  `marcar_envio_incerto!` usam o mesmo caminho; a condição de "envio incerto" é avaliada no
  próprio `UPDATE`.
- **Posse da passada** (`intencao:`): a escrita só vale se a linha ainda estiver na intenção lida
  **E sem número** (`COALESCE((handle->>'autonomia_intencoes')::int, 0) = ? AND
  (handle->>'autonomia_submitted') IS NULL`). O contador sozinho não bastava (Codex, rodada 2): ele
  volta atrás (2→1) e não muda quando o número entra, então B com leitura velha passava depois de A
  registrar e apagava `quote-A`. Anotação e número usam a posse; quando não vale (pedido novo
  supersedeu; outro processo anotou a intenção seguinte; outro processo registrou o número) o job
  levanta `MudouDeDono` e a passada PARA sem chamar o portal, sem gravar e sem se reagendar.
  Reproduzidos em spec com objetos independentes: supersede entre `perform` e `start`; B anota 2
  durante o `start` de A; A registra antes da segunda anotação de B; objeto velho no desfecho.
- `Sidekiq::Shutdown` é `Interrupt`: nenhum `rescue StandardError` roda no desligamento, e a intenção
  fica. Spec faz `start` levantar `Sidekiq::Shutdown` e afirma que a intenção permanece e o sinal
  sobe — `rescue Exception` reprova.
- `ToolRun#envio_incerto?` (intenção sem número) e `#marcar_envio_incerto!`: `fail_run` e o
  `ReapStaleRunsJob` marcam a execução para `possivelmente_duplicadas`, e publicam
  `uncertain_message` (novo texto de classe do contrato, guardado por `base_contrato_de_nivel_spec`)
  em vez de `failure_message`: "Não consegui confirmar se a cotação foi aberta nas seguradoras…".
- Marcas entram POR ÚLTIMO no handle gravado (`submitted_handle`, `merged_handle`); a ferramenta
  nunca as vê — na consulta nem no fechamento (`closing_deliveries` recebe `tool_handle`).
- Comentário do job corrigido: o requeue é no HARD shutdown, depois dos 25 s de `:timeout`
  (`TimeoutStopSec=30` no serviço); SIGKILL antes disso perde o job sem requeue e cai no varredor.

## Revisões

- Codex (rodada 1, `4fff228f89`): REPROVADO — P1 timeout apaga intenção; P1 sem CAS na anotação;
  P1 anotação que não grava é ignorada. Os três entraram no redesenho acima.
- Revisão adversarial (agente, 10/09): APROVADO COM RESSALVAS — mesmos achados (D ALTA, B1/B2),
  mais duas mutações que sobreviviam (`rescue Exception`; guarda do número no varredor) e a frase
  "um atendente vai retomar" sem ninguém avisado (E — decisão de produto, levada ao Rodrigo; é
  texto pré-existente de `failure_message`, não desta entrega).
- Codex (rodada 2, árvore de trabalho): REPROVADO — P1 o CAS comparava só o contador (B velho
  passava depois de A registrar e apagava o número); P1 `marcar_envio_incerto!` substituía o handle
  por cópia velha; P3 comentários prometendo mais que o código. Correção: mescla no banco e posse
  com número ausente (acima); comentário "NUNCA deixa exceção subir" corrigido para `StandardError`.

## Validação
