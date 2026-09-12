# Entrega 8 — a proposta de uma seguradora só (PDF da escolhida, não o comparativo)

Data: 12/09/2026. Plano: entrega 8 do Agente de Cotação (4 termos de aceite). Issue: #396 (Part of #291).
Branch `feat/entrega-8-proposta-da-seguradora`, de `origin/main` `1f49bba324`. Depende das entregas
11 (entrega de ARQUIVO) e 7 (a medida que lê `propostas`). Sem push, sem PR, sem produção.

## O desenho, em uma frase

O cliente leu a lista de preços e escolheu ("me manda a da Porto"); a ferramenta nova
`proposta_da_seguradora` — nativa, ASSÍNCRONA, do PRINCIPAL — lê a última cotação DESTA CONVERSA com
preço entregue, traduz o nome que o cliente falou no código do portal por COMPARAÇÃO DE TEXTO contra o
mapa que a própria cotação gravou (`nomes_entregues`, código -> nome como o portal escreveu), pede ao
portal `quote/proposal` COM `insurerCode` (uma chamada por seguradora, fora do turno), entrega um
`EntregaDeArquivo` por proposta ("Proposta Porto — placa ABC1D23.pdf", legenda "Proposta da Porto.",
reserva com o link) e ANOTA NA LINHA DA COTAÇÃO os códigos que saíram (`propostas`, que
`Insurance::Medida` já contava e até aqui contava zero). Nenhuma cotação nova: `quote_start` não é
chamado em caminho nenhum (termo 4). Emissão e pagamento continuam com pessoa.

## Termos (4)

| # | Termo | Estado |
|---|---|---|
| 1 | Pede a proposta de uma seguradora e recebe a DAQUELA, não a comparação | `InsuranceProposal#start` chama `quote_proposal(insurer_code:)` pelo código do mapa; spec "pede ao portal a proposta da seguradora escolhida… e nao o comparativo"; `http_spec` prova que `insurerCode` viaja |
| 2 | Habilitada nos agentes que JÁ existem (rollout no agente 24) | `registry_spec` «a ferramenta nova e o agente criado antes»: sem o slug em `native_tool_slugs` não ganha, com o slug ganha; script `~/ops/agente-cotacao/entrega-8/rollout-proposta.sh` escrito, **não executado** |
| 3 | Seguradora que não cotou: a resposta diz isso, em vez do comparativo em silêncio | recusa `seguradora_nao_cotou` listando quem cotou, no turno (`precheck`) e no envio (`start`); também quando o PORTAL diz 422 contra o nosso mapa |
| 4 | Duas seguradoras: recebe as duas, e não uma cotação nova | dois `quote_proposal` na mesma execução, dois arquivos no `poll`; `not_to have_received(:quote_start)`; mais de duas é recusa `proposta_acima_do_teto` |
| — | Prova: conversa real — o cliente escolhe, o arquivo chega, e é da seguradora certa | **PENDENTE** (exige deploy + rollout + rodada real na conta 16) |

## O que mudou (por fatia / commit)

**8a — `21a800f0f8`** `feat(cotacao): a cotação grava o nome de quem cotou, por código`
- `InsuranceQuote::NOMES_KEY = 'nomes_entregues'`, gravada em `build_progress` (método `acumular`)
  junto de `entregues` e `seguradoras_acionadas`, ACUMULADA entre consultas (o portal responde em
  pedaços). O nome é `QuoteOffers.nome` — o que o cliente leu na lista de preços.
- `Connector::Http#quote_proposal(insurer_code:)`: exemplos que provam `insurerCode` no corpo do POST
  `/v1/agger/quote/proposal`, e a ausência da chave sem código.
- Achado no caminho: `a_request(:post, url) do |request| … end` tem o bloco IGNORADO pelo WebMock
  (`a_request(method, uri)` não recebe bloco). O exemplo "sends the credentials only when opening a
  session" passava com qualquer POST. Corrigido para `.with { |request| … }` (continua verde).

**8b — `ee6e2f6091`** `feat(cotacao): a proposta de uma seguradora só, como arquivo na conversa`
- `Native::InsuranceProposal` (+ `InsuranceProposal::Escolha`, `InsuranceProposal::Recusas`):
  `precheck` (turno, só dado nosso, o portal NUNCA é chamado), `start` (avaliação de novo + uma
  chamada por seguradora com `with_fresh_session`), `poll` (arquivos + `anotar_na_cotacao`).
  Handle: `{quote_id, cotacao_run_id, sufixo, geradas: [{code,name,url}], nao_saiu: [nomes]}`.
- `ToolRun#anotar_propostas!(codigos)`: união no banco (`jsonb_set` + `jsonb_agg(DISTINCT)`), sob
  `where(id:)` SEM status — a cotação já está `done`; `merge_handle!` só aceita linha viva porque
  protege a posse de uma passada do job, e aqui não há passada.
- `Native::Base#initialize(…, conversation: nil)` + `#conversation` (privado); `AsyncRunJob#ferramenta`
  passa `conversation: run.conversation` (em `advance` e `fechamento`) e continua SEM `delivery`.
- `Recusa::MOTIVOS` +5: `proposta_sem_seguradora`, `proposta_acima_do_teto`, `proposta_sem_cotacao`,
  `seguradora_ambigua`, `seguradora_nao_cotou`. Sete saídas na varredura, sete gatilhos em
  `recusa_registro_spec` (1 no turno via `Bound#execute`, 6 no envio via `AsyncRunJob`).
- `Registry::TOOLS` ganha a ferramenta (depois de `VehicleLookup`); `Builder::TOOLS_DO_PRINCIPAL`
  ganha o slug (`TODAS_AS_TOOLS` passa a 5).
- `Comparativo.sufixo_do_arquivo(placa:, produto:)` compartilhado com a proposta.

**8c — `8f9834d1a4`** `feat(cotacao): a Lia entrega a proposta da seguradora escolhida; emitir segue com pessoa`
- `principal.md`: §2 ("Emitir apólice, processar pagamento" — a proposta em PDF é dela), §5 ("Você
  tem quatro" + `### proposta_da_seguradora` com quando usar, nome como saiu na lista, ambíguo
  pergunta, não cotou oferece as que cotaram, "Proposta não é emissão"), §6 item 1 ("Não emite, não
  cobra"), §10 ("gostei dessa"/"me manda a da Porto" -> proposta primeiro; escala ao emitir/pagar).
  **§7 intocada** (hunks nas linhas originais 22, 82, 101, 114, 182; a §7 começa na 131).
- `builder_instrucao_da_proposta_spec`: 7 promessas ancoradas por frase exata -> capacidade; 2
  proibições revogadas ausentes; 3 mantidas presentes; todo `###` do texto == `TOOLS_DO_PRINCIPAL`.
  Sem md5, de propósito: a §7 é da entrega 9.
- `~/ops/agente-cotacao/entrega-8/rollout-proposta.sh` (fora do repo), molde exato da entrega 2:
  `backup|aplicar|conferir|rollback`, psql via SSM, `DO $$` com `ROW_COUNT = 1`, precondição
  `NOT (config->'native_tool_slugs' ? 'proposta_da_seguradora')`. SÓ o agente 24 (conta 16); o
  especialista NÃO muda — em `tool_slugs` dele a ferramenta ficaria RESERVADA e sumiria do principal.
  Só depois do deploy da PR (o `Registry` precisa conhecer o slug). Sintaxe conferida (`zsh -n`),
  bloco de execução idêntico ao da entrega 2 (diff normalizado vazio). **Não executado.**

## Decisões onde o desenho não fechava (nomeadas)

**D1 — a conversa em `start` (o desenho dizia `delivery.conversation`).** `start` roda no
`AsyncRunJob`, que monta a ferramenta SEM `delivery` — e a presença do `delivery` é, por desenho da
entrega 2, a marca de "dentro do turno" (`Veiculo#consultar_placa` escolhe a sessão por ela). Passar
um `Delivery` no job mudaria a sessão da cotação. Decisão: `Native::Base` ganha `conversation:`
(o job passa `run.conversation`; no turno vem do `delivery`), lida por `#conversation`. Uma linha em
cada um dos dois `native.new` do job (`ferramenta`). Spec «pelo job» prova que `start` acha a
cotação da conversa fora do turno.

**D2 — sessão em `start`: `with_fresh_session`, não `with_live_session`.** O pedido dizia "use
`with_live_session` como a entrega 2 fez". A entrega 2 fez, literalmente, `delivery.present? ?
with_live_session : with_fresh_session` — viva no TURNO, fresca no JOB. `start` é o job; a cotação
usa `with_fresh_session` em `start`, `poll` e no comparativo. `with_live_session` ali faria a
proposta FALHAR sempre que a sessão tivesse vencido (a proposta pedida na manhã seguinte à cotação),
sem ninguém a reabrir além do healthcheck. A regra não negociável — nunca `with_fresh_session` no
TURNO — está cumprida por construção: `precheck` não toca no conector (dublê estrito na spec; exemplo
"sem sessao viva o turno segue igual"). Reversível numa palavra, se o PO discordar.

**D3 — homônimo: "Bp" com 48 e 55 cotadas é AMBÍGUA (ver contradição C1).** Regra implementada
(`Escolha`): o falado normalizado é PREFIXO de exatamente um nome cotado -> esse; de mais de um ->
ambíguo, lista as candidatas; de nenhum -> não cotou. O casamento exato é caso particular do prefixo
e NÃO vence sozinho quando há irmão de prefixo entre as cotadas. Nada de semelhança ("Portu" não é
"Porto"). Normalização: `transliterate` + `downcase` + `squeeze(' ')` + `strip`.

**D4 — o nome mais longo que o do portal ("Porto Seguro" vs "Porto") não casa.** Prefixo só na
direção falado -> nome. A direção inversa faria "Bp Assinatura" casar também com "Bp" (48) e virar
ambígua. Mitigação: a descrição do parâmetro e a §5 mandam o modelo escrever o nome COMO SAIU NA
LISTA DE PREÇOS (que é o mesmo mapa); quem entende a frase é o modelo. Se escrever errado, a recusa
no turno lista quem cotou e ele corrige com o cliente.

**D5 — `precheck` faz a avaliação inteira (nomes, cotação, casamento) e recusa NO TURNO** com o
MESMO texto que o cliente leria no envio — um texto por motivo, escrito para pessoa ler. Uma saída
dinâmica na varredura (`precheck#1`), seis estáticas no envio; os 5 motivos têm gatilho.

**D6 — o registro `propostas` é escrito em `poll`** (como pedido), pela linha achada por
`cotacao_run_id` guardado no handle em `start`, dentro da conta e do slug `cotar_seguro`. Idempotente
(união). Se a linha sumiu: `warn`, e a entrega segue.

**D7 — as chaves do handle da proposta chamam-se `geradas` e `nao_saiu`, não `propostas`.** O nome
`propostas` é o da chave na LINHA DA COTAÇÃO (só códigos); dois formatos sob o mesmo nome em duas
linhas é como uma medida passa a somar a linha errada. Spec «pelo job» afirma que a linha da
proposta NÃO tem `propostas`.

**D8 — o portal recusando UMA de duas (422) não apaga a outra:** sai o arquivo que saiu e um aviso
("Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima."). Só quando NENHUMA
sai é recusa `seguradora_nao_cotou`.

**D9 — cotação usável = a mais recente por id, qualquer status, com `quote_id`, `entregues` não
vazio E `nomes_entregues` objeto.** Cotação anterior à entrega 8 (sem o mapa) não conta:
`proposta_sem_cotacao`, e a instrução manda oferecer cotar de novo. Transitório.

**D10 — `pedido` (entrega 10) não implementado na proposta:** repetir "me manda a da Porto" abre
outra execução (a anterior é supersedida se viva). Custo: uma chamada ao portal a mais; benefício:
o cliente que perdeu o arquivo o recebe de novo.

## Fatos que contradizem o desenho (reportados, não contornados)

**C1 — issue #396: "exato > prefixo único > ambíguo" E "Bp ambígua entre 48 e 55" não cabem juntos
com os nomes reais.** No portal, 48 chama-se exatamente "Bp" e 55 "Bp Assinatura" (fixture do adapter
e `quote_offers_spec`). Com "exato vence", "Bp" -> 48, nunca ambígua. Implementei a leitura em que o
EXEMPLO da issue vale (D3): mandar a proposta da 48 a quem leu a 55 custa mais que uma pergunta.
Se o PO preferir "exato vence", é uma linha em `Escolha#casar` e dois exemplos.

**C2 — "`start` localiza … da conversa (`delivery.conversation`)"** — o job não passa `delivery`
(D1).

**C3 — "Use `with_live_session` como a entrega 2 fez"** — a entrega 2 usou viva no turno e fresca
no job (D2).

**C4 — `recusa_registro_spec` exige um gatilho por SAÍDA e um gatilho por MOTIVO:** com uma saída
dinâmica só não daria para cobrir os 5 motivos; por isso o envio tem saídas estáticas
(`recusar_entrada#1-3`, `recusar_escolha#1-2`, `gerar#1`).

**C5 — `a_request(...) do … end` no `http_spec` existente não verificava nada** (bloco ignorado).
Corrigido no mesmo arquivo (8a). Não vi outros usos em `spec/services/autonomia`.

**C6 — nome de método `registrar` em qualquer arquivo de `app/services/autonomia/agents` é lido
pela `VarreduraDeRecusas` como registrador de recusa.** Minha primeira versão de `build_progress`
extraiu um `registrar(handle, …)` e a guarda acusou uma saída falsa; renomeado `acumular`.

**C7 — dentro de `module A::B::C` compacto, o nome curto `Comparativo` não se resolve.** A primeira
versão de `nome_do_comparativo` levantava `NameError`, engolido pelo `rescue` de `comparison_pdf`: o
comparativo SUMIA em silêncio (6 exemplos do job reprovaram e mostraram). Caminho completo, com o
porquê no comentário.

**C8 — o handle da proposta guarda a URL do PDF do portal entre `start` e `poll`** (no
`autonomia_agent_tool_runs.handle`). Pela memória do projeto, o nome do arquivo no blob do portal
pode carregar o nome do segurado. É o mesmo banco que guarda a conversa; o comparativo já leva a
URL pelos args do `AsyncPublishJob`. Registrado, não tratado.

## Validação (números)

Banco `chatwoot_test_e8` (criado nesta sessão). `bundle exec rspec … --format json`, exit 0 = verde.

| Rodada | Arquivos | Exemplos | Falhas | Exit |
|---|---|---|---|---|
| 8a alvo | `insurance_quote_ramo_auto_spec`, `http_spec`, `insurance_quote_medida_spec`, `insurance_quote_spec`, `insurance_quote_comparativo_arquivo_spec` | 110 | 0 | 0 |
| 8b ferramenta | `insurance_proposal_spec` | 41 | 0 | 0 |
| 8b guardas | `recusa_registro_spec`, `recusa_guarda_spec`, `medida_spec`, `tool_run_spec`, `registry_spec`, `builder_spec`, `openai_schema_spec`, `base_contrato_de_nivel_spec` | 189 | 0 | 0 |
| 8b jobs/Bound | `spec/jobs/autonomia`, `bound_async_spec`, `bound_spec`, `bound_pedido_repetido_spec`, `answerer_native_tools_spec`, comparativo + ramo_auto | 180 | 0 | 0 |
| 8c | `spec/services/autonomia/insurance/quote_agent/` + `requests/…/quote_agent_spec` | 115 | 0 | 0 |
| **Final** | `spec/services/autonomia/insurance` + `spec/services/autonomia/agents` + `spec/jobs/autonomia` + `spec/models/autonomia` | **1126** | **0** | **0** (0 erros fora dos exemplos; 42 s) |

Por spec (na rodada final): `insurance_proposal_spec` 41 · `recusa_registro_spec` 48 (era 41; +7
gatilhos) · `medida_spec` 36 (+1) · `tool_run_spec` 27 (+4) · `registry_spec` 9 (+3) · `builder_spec`
33 (+1) · `builder_instrucao_da_proposta_spec` 13 (novo) · `insurance_quote_ramo_auto_spec` 43 (+2) ·
`http_spec` 15 (+2) · `openai_schema_spec` 21 · `base_contrato_de_nivel_spec` 11 (as duas varrem a
ferramenta nova automaticamente).

`bundle exec rubocop` nos 21 `.rb` tocados (`git diff --name-only 1f49bba324..HEAD`): **0 ofensas**
(duas ofensas pré-existentes de indentação em `insurance_quote_ramo_auto_spec.rb:631-632`, já em
`HEAD`, corrigidas de passagem).

## Mutações (editar -> rodar alvo -> `git checkout --` -> md5 igual)

| # | Mutação | Specs alvo | Resultado | Restaurado |
|---|---|---|---|---|
| M1 | `Escolha#casar`: prefixo com mais de um candidato vira escolha (some o ramo ambíguo) | `insurance_proposal_spec` + `recusa_registro_spec` | **reprova**: 89 ex., 4 falhas (homônimo Bp em start, ambígua no precheck ×2, gatilho `recusar_escolha#1`) | md5 `6ed35997…` igual |
| M2 | `seguradora_nao_cotou` vira comparativo: recusa removida, `gerar` chama `quote_proposal` sem código | idem | **reprova**: 88 ex., 5 falhas ("Portu", termo 3 ×2, precheck não-cotou, "gatilho para saída que não existe mais") | md5 `e4b7f358…` igual |
| M3 | `anotar_na_cotacao` procura a linha pelo slug da FERRAMENTA (grava fora da cotação) | `insurance_proposal_spec` + `medida_spec` | **reprova**: 77 ex., 4 falhas (anota na cotação, acumula, pelo job, «a medida conta») | md5 igual |
| M4 | duas seguradoras chamam `quote_start` | `insurance_proposal_spec` | **reprova**: 41 ex., 1 falha (termo 4 «sem abrir cotacao») | md5 igual |
| M5 | `'required' => false` no parâmetro `seguradoras` (vira `['array','null']`) | `insurance_proposal_spec` + `openai_schema_spec` | **reprova**: 62 ex., 1 falha («array de texto obrigatorio, sem null») | md5 igual |

Árvore limpa depois das cinco (`git status --short` vazio).

## Riscos e o que fica

- **Prova real pendente** (termo "Prova"): deploy da PR, `rollout-proposta.sh backup` ->
  `aplicar` -> `conferir` na conta 16, e uma conversa em que o cliente escolhe uma seguradora. Só
  então "o arquivo chega, e é da seguradora certa" deixa de ser spec.
- Duas seguradoras = duas chamadas ao portal (~60 s cada) FORA do turno; o job passa a `poll` na
  passada seguinte. Deploy no meio de `start` repete o `start` (a proposta não consome cotação —
  `EnvioIncerto` não é levantado daqui, de propósito).
- C1 é decisão de produto: confirmar com o PO se "Bp" deve perguntar (como implementado) ou ir
  direto para a 48.
- C8 (URL do portal no handle) fica registrado para a revisão de dados pessoais.
- Cotações anteriores ao deploy não têm `nomes_entregues`: a proposta responde "não encontrei
  cotação" e oferece cotar de novo (D9). Janela de horas, não de dias.
