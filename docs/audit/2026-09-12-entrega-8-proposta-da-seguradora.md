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
| 4 | Duas seguradoras: recebe as duas, e não uma cotação nova | dois `quote_proposal` na mesma execução — UM por passada desde a rodada de 12/09 (`start` pede a 1ª, `poll` a 2ª) —, dois arquivos no `poll`, um por passada; `not_to have_received(:quote_start)`; mais de duas é recusa `proposta_acima_do_teto` |
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

**D3 — homônimo: "Bp" com 48 e 55 cotadas é AMBÍGUA (ver contradição C1).** *[REVERTIDA em 12/09 pela
rodada de correção — ver "Rodada de correção", achado 2: o exato vence; "Bp" -> 48.]* Regra da primeira
versão (`Escolha`): o falado normalizado é PREFIXO de exatamente um nome cotado -> esse; de mais de um ->
ambíguo, lista as candidatas; de nenhum -> não cotou. O casamento exato era caso particular do prefixo
e NÃO vencia sozinho quando havia irmão de prefixo entre as cotadas. Nada de semelhança ("Portu" não é
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
(união). Se a linha sumiu: `warn`, e a entrega segue. *[Revisto em 12/09: a anotação é UM código por
passada, no instante em que o arquivo dele sai; e se a linha sumiu o `poll` FALHA (`cotacao_ausente`)
em vez de seguir — sem a linha não há como conferir se a origem ainda vale.]*

**D7 — as chaves do handle da proposta chamam-se `geradas` e `nao_saiu`, não `propostas`.** O nome
`propostas` é o da chave na LINHA DA COTAÇÃO (só códigos); dois formatos sob o mesmo nome em duas
linhas é como uma medida passa a somar a linha errada. Spec «pelo job» afirma que a linha da
proposta NÃO tem `propostas`.

**D8 — o portal recusando UMA de duas (422) não apaga a outra:** sai o arquivo que saiu e um aviso
("Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima."). Só quando NENHUMA
sai é recusa `seguradora_nao_cotou`. *[Corrigido em 12/09 (verificador cego, B1): quando NENHUMA sai
a recusa é `proposta_nao_gerada` — "não consegui gerar", nunca "não cotou": o cliente acabou de ler o
preço dela. E a falha do portal (503, tempo, sem URL) deixou de levantar: fica pendente por seguradora,
com até 2 tentativas.]*

**D9 — cotação usável = a mais recente por id, qualquer status, com `quote_id`, `entregues` não
vazio E `nomes_entregues` objeto.** Cotação anterior à entrega 8 (sem o mapa) não conta:
`proposta_sem_cotacao`, e a instrução manda oferecer cotar de novo. Transitório. *[REVERTIDA em 12/09
(Codex, P1): "qualquer status" incluía a supersedida — a origem passa a ser escolhida UMA vez, no
aceite, entre as NÃO mortas, e fixada nos argumentos; ver "Rodada de correção", achado 1.]*

**D10 — `pedido` (entrega 10) não implementado na proposta:** repetir "me manda a da Porto" abre
outra execução (a anterior é supersedida se viva). Custo: uma chamada ao portal a mais; benefício:
o cliente que perdeu o arquivo o recebe de novo.

## Fatos que contradizem o desenho (reportados, não contornados)

**C1 — issue #396: "exato > prefixo único > ambíguo" E "Bp ambígua entre 48 e 55" não cabem juntos
com os nomes reais.** No portal, 48 chama-se exatamente "Bp" e 55 "Bp Assinatura" (fixture do adapter
e `quote_offers_spec`). Com "exato vence", "Bp" -> 48, nunca ambígua. A primeira versão implementou a
leitura em que o EXEMPLO da issue valia (D3): mandar a proposta da 48 a quem leu a 55 custaria mais que
uma pergunta. **Decisão revertida pela revisão (Codex, P2, 12/09):** sem o exato vencer, a 48 era
INSELECIONÁVEL — qualquer texto que a alcançasse alcançava também a 55, e não havia frase nenhuma que
pedisse a proposta da Bp. Vale a regra da issue: exato > prefixo único > ambíguo. "Bp" -> 48;
"Bp Assinatura" e "bp a" -> 55; "B" -> ambígua. A leitura que preferia a pergunta trocava um arquivo
possivelmente errado por uma seguradora impossível de pedir.

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
- Duas seguradoras = duas chamadas ao portal (~60 s cada) FORA do turno, UMA por passada (revisto
  em 12/09 — ver "Prazo do worker" na rodada de correção). Deploy no meio de `start` repete o
  `start` (a proposta não consome cotação — `EnvioIncerto` não é levantado daqui, de propósito).
- C1 resolvida pela revisão: o exato vence ("Bp" -> 48). Não é mais decisão pendente.
- C8 (URL do portal no handle) fica registrado para a revisão de dados pessoais.
- Cotações anteriores ao deploy não têm `nomes_entregues`: a proposta responde "não encontrei
  cotação" e oferece cotar de novo (D9). Janela de horas, não de dias.

---

## Rodada de correção (12/09/2026) — PR #399, vereditos do Codex e do verificador cego

Base: `73396a265d` + merge de `origin/main` (`22d5c9c333`, entrega 9: §7.1 do `principal.md` e
`answerer.rb` sem `web_search` para o agente de cotação). Merge automático, sem conflito (hunks
distintos do `principal.md`). Suíte-base pós-merge, ANTES de qualquer edição: **1151 exemplos, 0
falhas, 0 erros fora, 36 s**.

### Achados e o que mudou

| # | Achado | Correção | Guarda |
|---|---|---|---|
| 1 | **Codex P1** — `precheck` e `start` escolhiam "a última cotação com preço" cada um por si, inclusive supersedida, sem olhar cotação nova sem preço: a proposta de A saía durante B | A origem é escolhida UMA vez, no TURNO (`InsuranceProposal::Origem`), entre as com preço + mapa e NÃO mortas (`ToolRun::DEAD_STATUSES`, constante nova que `dead?` usa), e gravada nos ARGUMENTOS da execução pelo aceite (`Native::Base#argumentos`, hook novo; `Bound#accept_async` grava `ferramenta.argumentos`). `start` lê só a fixada (`params[ORIGEM]`); `poll` a fixa de novo pelo handle. Morta em `start` OU `poll` -> `cotacao_substituida`, sem portal e sem entrega; cotação mais nova VIVA sem preço -> `cotacao_em_andamento` (turno e job) | `insurance_proposal_spec` «#argumentos» ×4, «qual cotacao» ×9 (A cotou/B correndo; supersedida aceite->start; start usa a fixada — MO; sem origem nos argumentos), «#poll» supersedida start->poll; `bound_async_spec` «records the arguments the tool fixes»; `base_contrato_de_nivel_spec` (+`argumentos` de instância); `recusa_registro_spec` gatilhos `recusar_entrada#3/#4`, `poll#1` |
| 2 | **Codex P2** — "Bp" inselecionável (todo prefixo de "bp" casa 48 e 55) | `Escolha#candidatos_de`: nome EXATO normalizado vence; prefixo só sem exato; ambíguo só com mais de um prefixo. C1 revertida (acima) | «homonimo: "Bp" … é a 48» (MB); «"B" … ambíguo»; «"bp a" é a Bp Assinatura»; gatilho `recusar_escolha#1` passa a "B" |
| 3 | **Codex P2** — o polling da cotação carregava `propostas` do handle e o `record_attempt!` gravava a cópia velha por cima da anotação concorrente | `InsuranceQuote#poll` tira `PROPOSTAS_KEY` do handle na primeira linha (`handle.to_h.except`); chave ausente no payload preserva a do banco (`ToolRun#mesclar`: `handle \|\| ?`) | `insurance_quote_medida_spec` «nao devolve `propostas` no handle da consulta» e «a anotacao feita entre a leitura do handle e o record_attempt! da consulta fica no banco» (job real, anotação dentro do dublê de `quote_result`) — MP; `tool_run_spec` «record_attempt! sem a chave no payload preserva a anotacao do banco; com a chave, a substitui» |
| 4 | **Codex P2** — as duas chamadas ao portal num `index_with`: falha na 2ª perdia a URL da 1ª e o job refazia as duas | `InsuranceProposal::Geracao`: UMA chamada ao portal POR PASSADA. `start` pede a PRIMEIRA seguradora e devolve o handle com `pendentes`; `poll` pede a próxima pendente (uma por passada) e só depois entrega. A URL gerada está no banco (handle gravado pelo job) antes de a chamada seguinte sair — a ferramenta não tem a linha para gravar no meio do `start`, e este é o único jeito de "persistir cada URL antes da próxima" sem mudar o contrato do job. Falha do portal NÃO levanta: `tentativas[code]` conta, `MAX_TENTATIVAS = 2` (a primeira e UMA repetição); 422 (`validation`) é definitivo na primeira; esgotado -> `nao_saiu[code] = motivo` (a categoria do conector: `validation`, `unavailable`, `timeout`, `protocol`) | «Porto sai e Suhai falha: a Porto chega, o aviso é sobre a Suhai, e a Porto não é refeita» (`pedidos == %w[8 20 20]`, PROPOSTAS_KEY da cotação `['8']`) — MF; «a falha do portal (503) nao levanta: fica pendente, com a tentativa contada»; «resposta sem URL … protocol»; «o start pede só a primeira e deixa a segunda pendente»; `pelo job` «duas seguradoras … em quatro passadas» |
| 5 | **Verificador A** — oferta cotada com `insurer.code` vazio entrava em `nomes_entregues`; `quote_proposal(insurer_code: "")` omite `insurerCode` e devolve o COMPARATIVO com nome de proposta | `InsuranceQuote#nomes` filtra código vazio (`.present?`, como `acionadas`); `Geracao#proposta` levanta `Connector::Error(:protocol)` para código em branco ANTES do conector | `insurance_quote_medida_spec` «nao grava no mapa de nomes a oferta cotada sem codigo» (MV2); `insurance_proposal_spec` «codigo de seguradora em branco no mapa nunca vira pedido ao portal» (MV) |
| 6 | **Verificador B1/B2** — 422 para código no mapa virava "Não tenho preço de Porto… Quem cotou: Porto" (autocontraditório); o `rescue :validation` envolvia o `with_fresh_session` (credencial ausente virava "não cotou" sem chamar o portal) | Motivo próprio `proposta_nao_gerada` ("Não consegui gerar a proposta de X agora. Posso tentar de novo daqui a pouco, ou um atendente retoma daqui."): no `start` quando a única pedida é recusada (`Geracao#iniciar`), no `poll` quando nenhuma saiu (`sem_nenhuma`). O `rescue` mora em `pedir_ao_portal`, SÓ ao redor de `connector.quote_proposal`; `auth_required` sobe para o `with_fresh_session` renovar; o que a sessão levanta (credencial ausente `:validation`, login recusado `:auth_required`, sem conexão `:config`) sobe como está e o job retenta | «o portal recusando (422) a seguradora que cotou vira "nao consegui gerar", nunca "nao cotou"»; «quando NENHUMA sai…»; «credencial ausente na conexao sobe como erro» (conexão REAL sem senha), «login recusado pelo portal sobe», «sem conexao pronta sobe» — MR; gatilhos `geracao.rb#iniciar#1`, `sem_nenhuma#1` |
| 7 | **Mutações sobreviventes** M1 (`start_with?`->`include?`), M2 (`anotar_propostas!` só em `done`), M3 (§5 invertida) | Specs que as matam: «"assinatura" nao e Bp Assinatura» (M1); `tool_run_spec` «escreve na cotacao ainda viva e na encerrada por prazo, nao so na done» + `insurance_proposal_spec` «anota tambem na cotacao ainda viva…» (M2 — o cliente escolhe na lista parcial; quem barra a MORTA é o `poll`, antes de anotar, não o modelo); `builder_instrucao_da_proposta_spec` âncora «nunca mande a comparação no lugar, em silêncio» (M3) | tabela de mutações abaixo |
| 8 | **Prazo do worker** — `poll` com dois PDFs = 2×20 s num worker com shutdown de 25 s | UM `EntregaDeArquivo` por passada (`entregar`/`entregar_proxima`): `running` com o primeiro, `done` com o último (+ aviso de quem não saiu). Uma passada é OU uma chamada ao portal OU um download, nunca os dois | «entrega um arquivo por passada: running com o primeiro, done com o ultimo» (M8) |

Também: `Native::Base#recusar` ganha `onde:` e registra a conversa de `#conversation` (pelo
`delivery` no turno, pela execução no job) — a recusa do `poll` (`cotacao_substituida`,
`proposta_nao_gerada`) sai registrada com a conversa, pelo mesmo produtor único. `Recusa::MOTIVOS`
+3: `cotacao_em_andamento`, `cotacao_substituida`, `proposta_nao_gerada` (frase e gatilho para cada).
`principal.md` §5 ganha UMA frase ("Se disser que a cotação foi refeita ou ainda está em andamento,
diga que a proposta sai dos preços novos…"), ancorada na spec ao catálogo; a §7.1 da entrega 9 não
muda (md5 dela intacto em `builder_instrucao_do_principal_promessas_spec`).

### O handle da proposta, depois da rodada

`{ quote_id, cotacao_run_id (ORIGEM), sufixo, geradas: [{code, name, url}], pendentes: [code],
tentativas: {code => n}, nao_saiu: {code => motivo}, enviadas: [code] }`. `nao_saiu` deixou de ser
lista de nomes: é código -> categoria do conector; o nome vem do mapa da origem na hora do texto.
`enviadas` não se chama `entregues` (nome da cotação) pelo mesmo motivo de D7.

### Prazo do worker e retomada por intenção (item 8, documentado)

- `start` = login (até 60 s, só quando a sessão da conexão venceu) + UMA chamada `quote/proposal`
  (até 60 s). Não é mais login + 2×60 s: a segunda seguradora é da passada seguinte.
- `poll` = OU uma chamada ao portal (até 60 s) OU um download (`PRAZO_SEGUNDOS = 20`) — nunca os
  dois. Duas seguradoras são QUATRO passadas (pede, pede, entrega, entrega), com os intervalos de
  `AsyncConfig` (3, 3, 5, 5 s…) entre elas; cabe com folga nos 420 s do prazo.
- O que continua acima dos 25 s do shutdown é UMA chamada ao portal, o mesmo teto do `start` da
  cotação. Deploy no meio dela: `Sidekiq::Shutdown` passa por `tentar_start` sem apagar a intenção
  (entrega 5); o job re-enfileirado entra na intenção 2, marcada `possivelmente_duplicada`, e refaz
  o `start` — que aqui é gerar o MESMO PDF de novo (a proposta não consome cotação; a marca é ruído
  aceitável para o corretor, registrado). Um segundo deploy no meio -> intenção 3 -> `envio_incerto`
  e a frase `INCERTO`. Deploy no meio de um `poll`: a passada é refeita e o handle já gravado impede
  refazer o que saiu (`pendentes`/`enviadas`); a publicação é idempotente pelo conteúdo.

### Decisões onde o desenho da rodada não fechava

**R1 — uma chamada por passada, e não "as duas no `start` persistindo entre elas".** O pedido dizia
"persista cada URL antes da próxima (no handle devolvido, ou `merge_handle!` se aplicável)". A
ferramenta não recebe a linha da execução (`Native::Base#initialize` não tem `run:`; dar-lhe a linha
mudaria o contrato de todas as nativas), e `merge_handle!` exige a posse da passada, que é do job.
O único lugar em que o handle é gravado é o retorno de `start`/`poll` — logo "antes da próxima" só é
verdade se a próxima for outra passada. Custo: duas seguradoras levam uma passada a mais (3–5 s).
Benefício: nenhuma URL se perde num deploy, e cada passada tem UM teto.

**R2 — ordem das recusas de entrada: morta > em andamento > sem cotação.** A primeira versão desta
rodada checava "em andamento" antes de "morta", e o cenário "origem supersedida entre aceite e start"
respondia `cotacao_em_andamento` (verdadeiro, mas menos específico: a nova está correndo PORQUE a
fixada foi refeita). A origem morta é o motivo do job; "em andamento" é o do aceite (no turno a
escolhida nunca está morta) e também vale no job quando a fixada está `done` e uma nova abriu sem
preço. "Sem cotação" só depois das duas: com uma nova correndo, oferecer "faço a cotação primeiro"
seria errado.

**R3 — o `poll` confere só `dead?`, não "em andamento".** Pedido literal. Se a fixada estava `done`
e uma nova abriu SEM preço entre o `start` e o `poll` (janela de segundos, o cliente corrigiu um dado
imediatamente depois de pedir a proposta), o arquivo já gerado da lista antiga é entregue. Uma cotação
`done` nunca vira `superseded` (`open!` só supersede a viva), então `dead?` não pega esse caso.
Registrado; não implementado nesta rodada porque exigiria decidir se descartar um arquivo já gerado
é melhor que entregá-lo com a lista que o cliente leu ao pedir.

**R4 — origem sempre DESTA conversa, também no `poll`.** `cotacao_fixada(id)` filtra por conta E
conversa; sem conversa (`Testar`, playground) não há origem e o `poll` falha `cotacao_ausente`. O id
é escrito por nós no aceite; filtrar pela conversa é defesa contra um id de outra conversa da mesma
conta, e custa uma cláusula.

**R5 — linha da origem apagada entre `start` e `poll` -> `failed('cotacao_ausente')`**, e não
"segue a entrega" como D6 dizia. Sem a linha não há como saber se ela morreu; o job publica `FALHOU`.
Só acontece por deleção manual (nada no código apaga `tool_runs`).

**R6 — recusa do `poll` registrada pela ferramenta, não pelo job.** O job só registra a recusa do
`start` (`registrar_recusa` em `submeter`). Ensinar o job a registrar recusas de `poll` exigiria
distinguir o `pedido` novo do `pedido` do `start` que o `poll` da cotação devolve no handle. A
ferramenta tem conversa e agente; `Base#recusar` com `onde: 'envio'` passa pelo produtor único e pela
varredura (duas saídas novas, dois gatilhos).

**R7 — `MAX_TENTATIVAS = 2` por seguradora.** A primeira e UMA repetição, uma por passada. A proposta
não custa cotação, mas cada tentativa é uma passada de até 60 s com o cliente esperando; um portal
que falhou duas vezes seguidas na mesma seguradora não vai gerar na terceira. 422 é definitivo na
primeira: a mesma pergunta traz a mesma resposta.

**R8 — o job ignora os argumentos do modelo em favor de `ferramenta.argumentos`.** Só a proposta
redefine; as outras nativas devolvem `params` (o comportamento anterior, sem mudança de linha
gravada). `bound_async_spec` guarda a semântica com uma ferramenta anônima que fixa uma chave.

### Validação (números)

Banco `chatwoot_test_e8`. `bundle exec rspec … --format json`, exit 0 = verde.

| Rodada | Arquivos | Exemplos | Falhas | Erros fora |
|---|---|---|---|---|
| Base pós-merge (antes de editar) | `spec/services/autonomia/insurance` + `agents` + `spec/jobs/autonomia` + `spec/models/autonomia` | 1151 | 0 | 0 |
| Spec antiga contra o código novo (diagnóstico) | `insurance_proposal_spec`, `recusa_registro_spec`, `recusa_guarda_spec`, `medida_spec`, `base_contrato_de_nivel_spec` | 144 | 35 | 0 |
| Ferramenta reescrita | `insurance_proposal_spec` | 66 | 0 (2 na 1ª rodada: a ordem de R2) | 0 |
| Guardas atualizadas | `recusa_registro_spec`, `recusa_guarda_spec`, `base_contrato_de_nivel_spec`, `bound_async_spec`, `medida_spec`, `insurance_quote_medida_spec`, `tool_run_spec`, `quote_agent/` | 283 | 0 (1 na 1ª rodada: âncora quebrada pela quebra de linha do `.md`) | 0 |
| **Final** | os 4 diretórios | **1188** (+37) | **0** | **0** (45 s) |

Por spec (final): `insurance_proposal_spec` 66 (era 41) · `recusa_registro_spec` 52 (era 48: −1
`gerar#1`, +5 saídas: `recusar_entrada#4/#5`, `geracao.rb#iniciar#1`, `sem_nenhuma#1`, `poll#1`) ·
`tool_run_spec` 29 (+2) · `insurance_quote_medida_spec` 14 (+3) · `medida_spec` 36 (adaptada: duas
passadas) · `bound_async_spec` 17 (+1) · `base_contrato_de_nivel_spec` 11 · `builder_instrucao_da_proposta_spec`
15 (+2) · `recusa_guarda_spec` 4 · `insurance_quote_ramo_auto_spec` 43.

`bundle exec rubocop` nos 18 `.rb` tocados: **0 ofensas** (uma na primeira passada — `ClassLength`
177/175 em `insurance_quote.rb`, resolvida compactando `nomes` numa linha; e `Naming/MethodParameterName`
em `rodar_passadas(de:)`, renomeado `desde:`). `insurance_proposal.rb` foi dividido em três módulos
(`Origem`, `Geracao`, `Recusas` + `Escolha`) — constantes dentro de módulo compacto não se resolvem
pelo nome curto (C7): `Origem::ORIGEM` só é visível na classe via ancestrais, e `Geracao` chega a ela
por `origem_no_handle`.

### Mutações (editar -> rodar alvo -> `git checkout --` -> md5 igual; árvore commitada em `7cbd8c4b16`)

| # | Mutação | Specs alvo | Ex. | Falhas | md5 | Resultado |
|---|---|---|---|---|---|---|
| MO | `Origem#cotacao` ignora a fixada: sempre `escolher_cotacao` | `insurance_proposal_spec` | 66 | 4 (start usa a fixada; sem origem nos argumentos; supersedida aceite->start ×2) | igual | **reprova** |
| MB | `Escolha#candidatos_de` sem o ramo do exato | idem | 66 | 1 («"Bp" … é a 48») | igual | **reprova** |
| MP | `InsuranceQuote#poll` sem `except(PROPOSTAS_KEY)` | `insurance_quote_medida_spec` | 14 | 2 (handle da consulta; anotação concorrente pelo job) | igual | **reprova** |
| MF | `Geracao#nao_gerou` zera `geradas` (a falha da 2ª descarta a 1ª) | `insurance_proposal_spec` | 66 | 2 (Porto sai e Suhai falha; 422 numa das duas) | igual | **reprova** |
| MV | `Geracao#proposta` sem o `raise` de código em branco | idem | 66 | 1 | igual | **reprova** |
| MV2 | `InsuranceQuote#nomes` sem o filtro `.present?` | `insurance_quote_medida_spec` | 14 | 1 | igual | **reprova** |
| MR | `rescue Connector::Error` movido para `proposta`, envolvendo o `with_fresh_session` | `insurance_proposal_spec` | 66 | 4 (credencial ausente; login recusado; sem conexão; código em branco) | igual | **reprova** |
| M1 | `start_with?` -> `include?` | idem | 66 | 1 («"assinatura" nao e Bp Assinatura») | igual | **reprova** |
| M2 | `anotar_propostas!` com `status: 'done'` no `where` | `tool_run_spec` + `insurance_proposal_spec` | 95 | 3 (viva e vencida no modelo; viva na ferramenta; mescla preserva) | igual | **reprova** |
| M3 | §5: "nunca mande a comparação no lugar" -> "mande a comparação no lugar" | `builder_instrucao_da_proposta_spec` | 15 | 1 | igual | **reprova** |
| M8 | `entregar` entrega todos os arquivos numa passada | `insurance_proposal_spec` | 66 | 8 | igual | **reprova** |

Árvore limpa depois das onze (`git status --short` vazio).

### O que NÃO foi feito, e por quê

- **Prova real** (termo "Prova"): continua pendente de deploy + rollout na conta 16.
- **`poll` conferindo "em andamento"** (R3): não pedido; registrado com a janela e o trade-off.
- **`pedido` (entrega 10) na proposta** (D10): fora do escopo da rodada.
- **C8** (URL do portal no handle): registrado, não tratado — mesmo escopo da revisão de dados
  pessoais.
- **Marca `possivelmente_duplicada` numa proposta refeita por deploy**: é o mecanismo genérico do
  job (entrega 5); a proposta não consome cotação, e separar "duplicada de cotação" de "duplicada de
  proposta" na lista do corretor é decisão de produto, não desta rodada.
