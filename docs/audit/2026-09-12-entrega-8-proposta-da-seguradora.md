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
  e a frase `INCERTO`. Deploy no meio de um `poll`: a passada é refeita DO ZERO — se o shutdown cai
  entre o `deliver` e o `record_attempt!`, o handle daquela passada NÃO chegou ao banco (nem
  `pendentes`, nem `enviadas`), e o retry baixa o PDF de novo. Quem impede a duplicata no cliente é
  o TOKEN por conteúdo, que encontra a mensagem já publicada. *[Frase corrigida na rodada 3 (M6 do
  verificador cego): a anterior dizia que "o handle já gravado impede refazer o que saiu", e nesse
  instante ele não foi gravado. Desde a rodada 3 quem decide o que falta entregar é a própria
  mensagem publicada, o que torna o caso inócuo.]*

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
  *[FEITO na rodada 3 — ver abaixo: era o residual do P1, e a janela não era "de segundos".]*
- **`pedido` (entrega 10) na proposta** (D10): fora do escopo da rodada.
- **C8** (URL do portal no handle): registrado, não tratado — mesmo escopo da revisão de dados
  pessoais.
- **Marca `possivelmente_duplicada` numa proposta refeita por deploy**: é o mecanismo genérico do
  job (entrega 5); a proposta não consome cotação, e separar "duplicada de cotação" de "duplicada de
  proposta" na lista do corretor é decisão de produto, não desta rodada.

---

## Rodada 3 (12/09/2026) — PR #399, três lacunas do Codex e duas do verificador cego

Base: `8588a95e96`, árvore limpa (a rodada 2 já com o merge da entrega 9). Suíte-base antes de
qualquer edição: **1188 exemplos, 0 falhas, 0 erros fora**. Commit da rodada: `956416ae2b`.

O fio comum dos cinco achados é o mesmo: **a proposta é um arquivo que sai de uma COTAÇÃO, e entre o
pedido e a mensagem há minutos em que essa cotação pode deixar de valer** — e o código conferia isso
em um lugar só (o `start`), decidindo o resto por marcas no handle em vez de pelo que existe no banco.

### Achados e o que mudou

| # | Achado | Correção | Guarda |
|---|---|---|---|
| 1 | **Codex P1 / verificador I1** — a validade da origem só era conferida no `start` e, no `poll`, só por `dead?`. Duas janelas ficavam abertas: (a) origem `done` + cotação nova correndo sem preço — `done` NUNCA vira `superseded` (`open!` só supersede a viva), então a proposta da lista velha saía; (b) a publicação ADIADA pela cadeia humanizada (até 90 s) ou RETOMADA não passa de novo pelo `poll` | (a) O `poll` confere também `cotacao_em_andamento?`, com recusa nomeada (`recusar(onde: 'envio')`). (b) Hook novo `Native::Base#publicavel?(run, entrega)` (padrão `true`), consultado pelo publicador dentro da MESMA conferência sob o lock (`AutorizacaoDaExecucao#autorizacao(conversation, entrega:)`, motivo fechado `ferramenta_recusou`, terceiro de `RECUSAS`). `InsuranceProposal#publicavel?` devolve falso quando a origem está morta OU há cotação mais nova correndo — e SÓ para as propostas (ver R1) | `insurance_proposal_spec` «a cotacao nova em andamento entre o start e o poll barra a entrega» (MA), «#publicavel?» ×5, «a entrega adiada nao vira mensagem quando a cotacao e refeita antes da publicacao» (caminho real, pelo publicador); `async_publisher_spec` «a ferramenta autoriza a propria entrega» ×3 (MH), inclusive a não-regressão da cotação; `recusa_registro_spec` gatilho `poll#2` |
| 2 | **Codex P2** — enquanto havia pendente, nenhuma gerada era entregue: com a 2ª seguradora em tempo esgotado, a execução gastava as passadas nela, o prazo estourava e a proposta pronta nunca saía | O `poll` entrega as GERADAS antes de pedir a próxima pendente, uma por passada. E `closing_deliveries` (que a cotação já usava para o comparativo) passa a existir na proposta: entrega o que o portal gerou e não chegou ao cliente, mais o aviso de quem ficou pelo caminho — pendente no fim é, para quem espera, o mesmo que não gerada | `insurance_proposal_spec` «entrega a proposta pronta antes de pedir a pendente ao portal» (MG), «#closing_deliveries» ×3 (MC), e o caminho real «com o prazo curto e a segunda seguradora por pedir, a Porto sai e o aviso da Suhai tambem» |
| 3 | **Codex P2** — `enviadas` avançava ANTES de publicar: `AsyncPublisher#publish` devolve `blocked` em falha transitória e o job grava o handle assim mesmo → arquivo marcado como enviado sem mensagem, e `anotar_propostas!` faturando uma proposta que o cliente não recebeu | A fonte de verdade passou a ser a MENSAGEM: `Tools::EntregaPublicada` (extraído do publicador, que agora o usa) procura pelo token da entrega (`ToolRun#delivery_token`, `execution_key` + digest do conteúdo). `nao_publicadas` pergunta ao banco; `confirmar` anota na cotação só o que já virou mensagem; `ENVIADAS` deixou de decidir e ficou como CACHE do que já foi anotado. Para montar o token a ferramenta precisa da linha: `Native::Base` ganhou `run:` (o `AsyncRunJob#ferramenta` passa) | `insurance_proposal_spec` «reentrega o arquivo cuja publicacao nao virou mensagem, e so anota depois que ela existe» (ME), «entrega um arquivo por passada e so encerra depois de o ultimo virar mensagem», «o link de reserva publicado encerra a entrega daquela proposta»; `medida_spec` adaptada ao caminho novo |
| 4 | **Verificador I2** — `cotacao_em_andamento?` usava `ultima.active?`, e uma `pending` órfã (worker morto entre o aceite e o despacho — um deploy basta) contava como "em andamento" por até uma hora, travando a proposta | `running?`, a mesma convenção de `ToolRun.opened_for_turn?` e pelo mesmo motivo | `insurance_proposal_spec` «a cotacao aceita e nunca promovida nao barra a proposta» (MI) |
| 5 | **Menores M1/M2/M4** — escopo de conversa em `cotacao_fixada` sem guarda; a gravação de `argumentos` só testada por ferramenta anônima; execução `pending` anterior ao deploy, sem `ORIGEM`, lia "não encontrei cotação" (texto enganoso: a conversa PODE ter cotação — o que se perdeu foi a escolha do turno) | Specs de escopo e de aceite pelo caminho real (`Bound#execute`, lendo `run.arguments[ORIGEM]`); recusa própria `proposta_sem_origem`, com texto honesto ("Não consegui localizar a cotação desta conversa… me peça de novo"), antes de `proposta_sem_cotacao`. `recusar_entrada` foi dividido (`recusar_origem`) por complexidade — as saídas mudaram de nome na varredura | `insurance_proposal_spec` «a cotacao de OUTRA conversa nao conta, mesmo fixada pelo id» (MS), «o aceite grava a origem nos argumentos da execucao, pelo caminho do Bound» (MB), «sem a origem fixada nos argumentos…»; `recusa_registro_spec` gatilhos `recusar_origem#1..#4` |
| 6 | **Menores M6/M7** — a auditoria dizia que o handle gravado impedia refazer uma passada interrompida (não impedia: naquele instante ele não foi gravado); a §5 do `principal.md` ensinava o modelo a tratar "a cotação foi refeita", que ele NUNCA lê no turno (a origem é escolhida entre as não mortas) | Frase do "Prazo do worker" corrigida acima; §5 passa a falar só de "há uma cotação nova em andamento", com a âncora da spec ajustada | `builder_instrucao_da_proposta_spec` «há uma cotação nova em andamento» |

Também: a recusa da ENTRADA do publicador (`authorized_conversation`) passou a REGISTRAR o motivo,
com a mesma linha da recusa sob o lock. Era silenciosa desde a entrega 11 — `blocked` sem uma palavra
no log, justamente no caso em que se quer saber por quê. `Recusa::MOTIVOS` +1 (`proposta_sem_origem`).

### Como uma execução passou a correr

| Passada | Uma seguradora | Duas seguradoras |
|---|---|---|
| 0 | `start`: pede a 1ª ao portal | idem |
| 1 | `poll`: entrega o arquivo | entrega o arquivo da 1ª |
| 2 | `poll`: confirma a mensagem, anota na cotação, encerra | pede a 2ª ao portal |
| 3 | — | entrega o arquivo da 2ª |
| 4 | — | confirma, anota, encerra |

Uma passada é OU uma chamada ao portal (até 60 s) OU um download (20 s) OU uma confirmação (duas
consultas ao banco) — nunca duas coisas. O custo da correção é UMA passada a mais por execução
(3–5 s de intervalo do `AsyncConfig`), contra os 420 s de prazo.

### Decisões onde o desenho da rodada não fechava

**R1 — o hook recebe a ENTREGA, não só a execução.** O pedido dizia `publicavel?(run)`. Assim ele
barraria TUDO o que aquela execução publica — inclusive a frase que EXPLICA o que houve ("a cotação
foi refeita…", que o próprio `poll` produz quando a origem morre) e o fecho do job. O cliente ficaria
em silêncio depois de "já estou buscando", que é o defeito oposto ao que se está corrigindo. Com a
entrega em mãos, a ferramenta barra só o que saiu da origem — comparação de dado nosso contra dado
nosso (a URL que o handle gravou), como arquivo ou como o texto de reserva que termina na mesma URL.

**R2 — a confirmação custa uma passada a mais.** Anotar na cotação só depois de a mensagem existir
implica que a ÚLTIMA entrega precisa de uma passada seguinte para ser confirmada; por isso a execução
encerra em 3 (uma seguradora) ou 5 passadas (duas), e não em 2 ou 4. A alternativa — anotar
otimista na última — é exatamente o defeito 3.

**R3 — `deferred` e `blocked` são indistinguíveis para a ferramenta.** Ela vê "não há mensagem" nos
dois casos e reentrega na passada seguinte. Para o `blocked` isso é a correção; para o `deferred`
(cadeia humanizada aberta) é uma reentrega desnecessária, que o publicador resolve sozinho pelo token
(acha a mensagem, ou o adiamento já a caminho) — sem duplicar nada para o cliente. O volume por
passada não muda: continua UMA entrega. Medido nas specs do caminho real.

**R4 — o encerramento por prazo continua condicionado a `delivered_count > 0`** (`AsyncRunJob#fail_run`,
comportamento genérico, o mesmo da cotação). Resíduo conhecido: se o prazo estourar ANTES da primeira
entrega, o arquivo gerado não sai e o cliente lê a frase de falha. Com as geradas saindo primeiro
(achado 2) essa janela ficou estreita — a entrega acontece na primeira passada depois do `start` —,
e mudar `fail_run` mexeria no fecho de todas as ferramentas assíncronas, fora do escopo desta rodada.

**R5 — `Native::Base` ganhou `run:`, e não um `poll(run:)`.** A ferramenta precisa do `execution_key`
para montar o token; o contrato de `poll` é compartilhado por todas as nativas. `run:` entra como o
`conversation:` entrou na rodada 1 — opcional, nil fora do job, com o porquê no comentário.

**R6 — `publicavel?` NÃO é consultado na retomada de envio pendente** (`RetomadaDeEnvio`): ali não há
entrega em mãos e a mensagem JÁ EXISTE — bloquear o reenvio deixaria uma mensagem no painel que nunca
sai para o cliente. O que vale lá é o que já valia: execução morta, vínculo, canal, nota privada.
*[REVERTIDA na rodada 4 (P1 do Codex): a mensagem existir no painel NÃO é ter chegado ao cliente —
reenfileirar o `SendReplyJob` dela é entregar o arquivo agora. A entrega passou a ser identificada
pelo TOKEN da mensagem, e a pendência é ABANDONADA (resolvida, não deixada para o varredor).]*

**R7 — cotação mais nova ENCERRADA sem preço não barra a proposta (M3): decisão de PRODUTO pendente,
sem mudança nesta rodada.** Cenário: o cliente manda refazer, a cotação nova falha sem entregar preço
nenhum, e ele então pede "me manda a da Porto". Hoje a proposta sai da lista antiga — que é a única
lista que existe, e a que ele leu. Barrar seria não ter o que oferecer. Registrado para o PO; o dado
para decidir (com que frequência uma recotação morre sem preço) está em `autonomia_agent_tool_runs`.
*[DECIDIDA na rodada 4 pelo revisor final: BARRA. O verificador cego reproduziu o caso pelo caminho
real — saía o anexo da lista antiga sem uma palavra ao cliente —, e a regra da última cotação o cobre
sem cláusula própria.]*

### Validação (números)

Banco `chatwoot_test_e8`. `bundle exec rspec … --format json`, exit 0 = verde.

| Rodada | Arquivos | Exemplos | Falhas | Erros fora |
|---|---|---|---|---|
| Base (`8588a95e96`, antes de editar) | os 4 diretórios | 1188 | 0 | 0 |
| Ferramenta | `insurance_proposal_spec` | 79 | 0 (5 na 1ª rodada: a ordem nova das passadas) | 0 |
| Guardas | `recusa_registro_spec`, `recusa_guarda_spec`, `async_publisher_spec`, `medida_spec`, `base_contrato_de_nivel_spec`, `bound_async_spec`, `tool_run_spec`, `insurance_quote_medida_spec`, `spec/jobs/autonomia` | 300 | 0 (2 na 1ª rodada: âncora do `.md` quebrada pela quebra de linha, e a recusa de entrada que não registrava) | 0 |
| Instrução | `spec/services/autonomia/insurance/quote_agent/` | 120 | 0 | 0 |
| **Final** | `spec/services/autonomia/insurance` + `spec/services/autonomia/agents` + `spec/jobs/autonomia` + `spec/models/autonomia` | **1206** (+18) | **0** | **0** (51 s) |

Por spec (final): `insurance_proposal_spec` 79 (era 66) · `recusa_registro_spec` 54 (+2: `poll#2` e
`recusar_origem#4`) · `async_publisher_spec` 46 (+3) · `builder_instrucao_da_proposta_spec` 15 ·
`base_contrato_de_nivel_spec` 11 (`publicavel?` entrou na varredura de nível) · `medida_spec` 36 ·
`tool_run_spec` 29 · `bound_async_spec` 17 · `insurance_quote_medida_spec` 14 · `recusa_guarda_spec` 4.

`bundle exec rubocop` nos 17 `.rb` tocados: **0 ofensas**. Seis apareceram no caminho e foram
resolvidas: `Metrics/CyclomaticComplexity` em `recusar_entrada` (extraído `recusar_origem`),
`Metrics/ClassLength` 178/175 em `insurance_proposal.rb` (o fecho voltou para dentro de `entregar` e
`publicadas` saiu), `Layout/LineLength` no catálogo de motivos, `RSpec/MultipleMemoizedHelpers` ×3
(três `let` viraram método) e `RSpec/MultipleExpectations` no exemplo das passadas.

### Mutações (editar -> rodar alvo -> `git checkout --` -> md5 igual; árvore commitada em `956416ae2b`)

| # | Mutação | Specs alvo | Ex. | Falhas | md5 | Resultado |
|---|---|---|---|---|---|---|
| MA | `poll` sem a conferência de "cotação em andamento" | proposta + `recusa_registro` | 132 | 2 | igual | **reprova** |
| MH | o publicador ignora `publicavel?` | `async_publisher` + proposta | 125 | 2 | igual | **reprova** |
| MG | pendentes antes das geradas | proposta | 79 | 5 | igual | **reprova** |
| MC | `closing_deliveries` sem as geradas | proposta | 79 | 1 | igual | **reprova** |
| ME | `enviadas` avança na entrega e volta a decidir (o handle no lugar da mensagem) | proposta + `medida` | 115 | 3 | igual | **reprova** |
| MI | `active?` de volta em `cotacao_em_andamento?` | proposta | 79 | 1 | igual | **reprova** |
| MS | `unscope` da conversa em `cotacao_fixada` | proposta + `recusa_registro` | 133 | 2 | igual | **reprova** |
| MB | o aceite grava `args` em vez de `ferramenta.argumentos` | proposta + `bound_async` | 96 | 2 | igual | **reprova** |

Cada mutação aborta se a âncora não existir e confere que o arquivo REALMENTE mudou antes de rodar
(mutação que não muta passa e mente). Árvore limpa depois das oito (`git status --short` vazio).

### O que NÃO foi feito nesta rodada, e por quê

- **Prova real** (termo "Prova"): continua pendente de deploy + rollout na conta 16. Nada foi
  executado em produção; o script `rollout-proposta.sh` só ganhou um COMENTÁRIO sobre as execuções
  abertas antes do deploy (não há passo de dados para elas: a janela é o prazo de uma execução).
- **M3 / R7** (cotação mais nova encerrada sem preço): decisão de produto, registrada acima.
  *[FEITO na rodada 4.]*
- **`fail_run` com `delivered_count` zero** (R4): mexe no fecho de todas as assíncronas.
  *[FEITO na rodada 4, com spec de não-regressão da cotação.]*
- **C8** (URL do portal no handle) e **`pedido` da entrega 10 na proposta** (D10): sem mudança, como
  nas rodadas anteriores.
- **Reentrega desnecessária no caso `deferred`** (R3): custo aceito, medido, documentado.

---

## Rodada 4 (12/09/2026) — PR #399, os dois P1 e o P2 do Codex, e os quatro do verificador cego

Base: `168e1df557`, árvore limpa. Suíte-base antes de qualquer edição: **1206 exemplos, 0 falhas**.
Commit da rodada: `8a3f8c4c58`. O Codex REPROVOU a rodada 3 (dois P1 e um P2); o verificador cego
APROVOU sem bloqueante, confirmou por spec própria que não há regressão na cotação em produção, e
trouxe um achado novo. Esta rodada fecha os cinco e encerra a PR.

### Achados e o que mudou

| # | Achado | Correção | Guarda |
|---|---|---|---|
| 1 | **Codex P1 ×2 + R7** — a validade da origem era descrita por DOIS predicados (`dead?` e "há uma cotação nova VIVA e ainda sem preço") e cada versão deixava um buraco, porque uma cotação `done` nunca vira `superseded`: (a) `dead?` não pegava a origem `done` com outra aberta depois; (b) a guarda "viva sem preço" voltava a AUTORIZAR a origem antiga assim que a nova recebia preço — o cliente podia receber o PDF de A depois de já estar lendo os preços de B (`origem.rb:91`); (c) recotação `failed` sem preço não barrava nada, e o anexo da lista antiga saía sem uma palavra (R7, reproduzido pelo verificador) | REGRA ÚNICA, decidida pelo revisor final: **a origem fixada só vale enquanto for a ÚLTIMA cotação da conversa e não estiver morta** (`Origem#ultima_cotacao?`), seja qual for o estado da mais nova — viva, com preço, encerrada ou falhada. Um predicado, um motivo (`cotacao_substituida`), nos QUATRO pontos: turno/`start`, `poll`, `closing_deliveries` e `publicavel?`. `cotacao_em_andamento` deixou de existir (motivo, texto, gatilho e frase da §5) | `insurance_proposal_spec` «A cotou e B esta correndo sem preco…», «a cotacao nova que JA recebeu preco tambem barra» (MU + MO), «a recotacao que falhou sem preco tambem barra», «a origem que ainda e a ultima… gera a proposta», «a cotacao nova entre o start e o poll…», «a cotacao nova COM preco…», `#publicavel?` ×2, `#closing_deliveries`; `recusa_registro_spec` `recusar_origem#1` e `poll#1` |
| 2 | **Codex P1** — `RetomadaDeEnvio#decidir` chamava `autorizacao(conversation)` SEM entrega, pulando o hook: uma proposta que virou mensagem e falhou no enfileiramento era reenviada depois, mesmo com a cotação já refeita. O desvio R6 dizia "a mensagem já existe"; existir no painel não é ter chegado ao cliente | A retomada passa o TOKEN da mensagem (`EntregaPublicada::CHAVE`); a ferramenta o resolve na própria entrega (`Native::Base#entrega_do_token`, padrão nil) e responde `publicavel?`. Recusada, a pendência é ABANDONADA com motivo `ferramenta_recusou` — resolvida, não deixada para o varredor achar a cada 10 min | `retomada_de_envio_spec` «abandona a pendencia em vez de reenviar a proposta de uma cotacao ja refeita» (MR) e «reenvia normalmente enquanto a cotacao de origem continua sendo a ultima» |
| 3 | **Codex P2** — com o PDF gerado e `delivered_count` zero, o encerramento por prazo publicava só "Não consegui gerar a proposta" e o arquivo nunca saía | `fail_run` deixou de filtrar por `delivered_count`: o encerramento é SEMPRE oferecido à ferramenta, e o fecho vem DEPOIS das entregas — parcial se algo chegou (antes ou agora), frase de falha se nada chegou. O filtro mora em cada ferramenta | `insurance_proposal_spec` «com o PDF gerado e o prazo estourado antes de qualquer entrega, o arquivo sai antes da frase» (MF) e, no molde pedido, a NÃO-REGRESSÃO da cotação em `async_run_job_encerramento_parcial_spec` «a cotacao que morre sem preco nenhum nao passa a mandar comparativo» |
| 4 | **Verificador, importante 1 (NOVO)** — `confirmar` só rodava no `poll`: a proposta que virava mensagem na última passada antes do prazo sumia da medida da entrega 7 (`PROPOSTAS_KEY` nil com o cliente já com o PDF) | `closing_deliveries` chama `confirmar` antes de montar o que falta | `insurance_proposal_spec` «anota na cotacao a proposta que ja virou mensagem, no proprio encerramento» (MM) |
| 5 | **Verificador, menores 1 e 4** — o encerramento podia baixar DOIS arquivos na mesma passada (2×20 s num worker com shutdown de 25 s), contra a própria regra; e o que `publicavel?` levantasse subia, fazendo o publicador devolver `blocked` para QUALQUER entrega daquela execução — calando o cliente | UM arquivo por passada também no encerramento (`.first(1)`); a exceção é tratada DENTRO do hook (log + decisão explícita): o arquivo não sai, as frases saem | `insurance_proposal_spec` «entrega no maximo UM arquivo no encerramento» (MD) e «a conferencia que levanta nao sobe para o publicador» (MX) |

### Decisões onde o desenho da rodada não fechava

**S1 — `cotacao_em_andamento` foi REMOVIDO, não mantido ao lado do novo.** Dois motivos para a mesma
coisa ("a lista que você leu não vale mais") custam duas frases, dois gatilhos e uma âncora na
instrução — e foi exatamente a coexistência dos dois predicados que abriu os três buracos. O texto
que ficou (`SUBSTITUIDA`) serve aos dois casos porque diz o que o cliente precisa saber: a cotação
foi refeita, e a proposta sai dos preços novos quando eles chegarem. `Recusa::MOTIVOS` perdeu uma
chave; `recusa_registro_spec` perdeu duas saídas (`recusar_origem#2`, `poll#2`) e renumerou o resto.

**S2 — cotação que NUNCA virou trabalho não conta como recotação** (`Origem::SEM_TRABALHO` =
`pending`, `discarded`, `blocked`). Sem isto, a regra da última ressuscitaria o I2 da rodada 3: uma
`pending` órfã (worker morto entre o aceite e o despacho — um deploy basta) travaria a proposta por
até uma hora por uma cotação que ninguém vai executar. É a MESMA lista de `ToolRun.opened_for_turn?`,
pelo mesmo motivo. A `pending` legítima do mesmo turno não escapa: quando ela é promovida, o `poll`
e a publicação conferem de novo.

**S3 — o reconhecimento pelo token é um HOOK NOVO da ferramenta, não lógica na retomada.** A retomada
tem a mensagem, não a entrega; montar a entrega ali exigiria que ela soubesse o formato de cada
ferramenta. `entrega_do_token(run, token)` devolve nil por padrão — quem não reconhece nada não barra
nada —, e só a proposta o implementa, comparando o token com o de cada proposta gerada (arquivo ou
reserva, a mesma identidade dos dois lados).

**S4 — o encerramento NÃO conta em `delivered_count`.** Continuou usando `publish`, não `deliver`:
esse contador é o da entrega do TRABALHO e é lido pela janela do pedido repetido (entrega 10,
`conta_como_pedido?`). Contar o comparativo/arquivo de fecho ali faria uma cotação que falhou passar
a bloquear o mesmo pedido por 24 h — mudança de produto que ninguém pediu. Quem decide o fecho é o
retorno das publicações do encerramento, em memória.

**S5 — o que o hook levantar decide `false` (o arquivo não sai).** Na dúvida, a decisão é a do
dinheiro: o risco errado com cara de certo é pior que o silêncio de UMA entrega. E o silêncio é só
dela: a frase que explica o que houve não é da origem, e responde `true` antes de a conferência
começar. É estritamente melhor que o estado anterior, em que a exceção calava tudo.

**S6 — `publicavel?`/`da_origem?`/`publicada?` saíram para um módulo (`InsuranceProposal::Publicacao`).**
A classe estava a 175/175 de `Metrics/ClassLength` desde a rodada 3; o módulo era o caminho que o
arquivo já vinha seguindo (`Origem`, `Geracao`, `Recusas`). **E o C7 cobrou pedágio de novo**: dentro
do módulo compacto o nome curto `GERADAS` (que mora em `Geracao`) não se resolve, o `NameError` caiu
no `rescue` novo e `publicavel?` passou a devolver `false` para tudo — 11 exemplos vermelhos, seis
deles do caminho real «pelo job», com a conversa MUDA. Corrigido usando o método `geradas` da classe
em vez da constante, com o porquê no comentário. Foi o `rescue` que transformou um erro de escopo em
silêncio: a lição vale para o próximo módulo.

**S7 — a spec «o start usa a origem fixada, e nao a ultima com preco» foi SUBSTITUÍDA, não removida.**
A premissa dela (origem fixada antiga + cotação nova com preço ⇒ gera da fixada) deixou de ser
verdade: agora recusa. O que ela guardava (a mutação MO, "o job escolhe em vez de usar a fixada")
passou para «a cotacao nova que JA recebeu preco tambem barra a origem antiga» — ignorar a fixada ali
geraria a proposta de B em vez de recusar, e o exemplo reprova igual.

### Validação (números)

Banco `chatwoot_test_e8`. `bundle exec rspec … --format json`, exit 0 = verde.

| Rodada | Arquivos | Exemplos | Falhas | Erros fora |
|---|---|---|---|---|
| Base (`168e1df557`, antes de editar) | os 4 diretórios | 1206 | 0 | 0 |
| Alvo (1ª passada) | proposta, recusas, retomada, publicador, contrato de nível, `spec/jobs/autonomia`, `quote_agent/` | 415 | 16 | 0 |
| Alvo (2ª passada, depois do C7) | idem | 414 | 1 | 0 |
| **Final** | `spec/services/autonomia/insurance` + `agents` + `spec/jobs/autonomia` + `spec/models/autonomia` | **1215** (+9) | **0** | **0** (58 s) |

Por spec (final): `insurance_proposal_spec` 87 (era 79: +9 novos, −1 substituída) ·
`recusa_registro_spec` 52 (era 54: −2 saídas) · `retomada_de_envio_spec` 4 (era 2) ·
`async_run_job_encerramento_parcial_spec` 2 (era 1) · `async_run_job_intencao_de_envio_spec` 24 ·
`async_publisher_spec` 46 · `base_contrato_de_nivel_spec` 11 (`entrega_do_token` entrou na varredura
de nível) · `builder_instrucao_da_proposta_spec` 15 · `medida_spec` 36 · `tool_run_spec` 29.

`bundle exec rubocop` nos **17 `.rb`** tocados (10 de `app`, 7 de `spec`): **0 ofensas**, sem nenhuma
no caminho — `Publicacao` nasceu justamente para não estourar o `ClassLength`.

### Mutações (editar -> rodar alvo -> `git checkout --` -> md5 igual; árvore commitada em `8a3f8c4c58`)

| # | Mutação | Specs alvo | Ex. | Falhas | md5 | Resultado |
|---|---|---|---|---|---|---|
| MU | `origem_ainda_vale?` sem `ultima_cotacao?` (aceita não ser a última) | proposta + `recusa_registro` | 139 | 8 | igual | **reprova** |
| MR | `decidir` volta a chamar `autorizacao(conversation)` sem o token | `retomada_de_envio` | 4 | 1 | igual | **reprova** |
| MF | `fail_run` volta a exigir `delivered_count > 0` | proposta + `encerramento_parcial` | 89 | 1 | igual | **reprova** |
| MM | `closing_deliveries` sem `confirmar` | proposta | 87 | 1 | igual | **reprova** |
| MD | `closing_deliveries` sem o `.first(1)` (dois arquivos) | proposta | 87 | 1 | igual | **reprova** |
| MX | `publicavel?` sem o `rescue` (a exceção volta a subir) | proposta | 87 | 1 | igual | **reprova** |

Cada mutação aborta se a âncora não existir e confere que o arquivo REALMENTE mudou antes de rodar.
Árvore limpa depois das seis (`git status --short` vazio).

### O que NÃO foi feito nesta rodada, e por quê

- **Menor 2 do verificador** (`deferred` reemite e infla `delivered_count`): comportamento GENÉRICO
  do motor assíncrono, afeta todas as ferramentas e hoje é inócuo para o cliente (o token impede a
  mensagem duplicada; nenhum consumidor lê a magnitude do contador, só o sinal). **Issue
  [#402](https://github.com/autonom-ia2/chat/issues/402)**, com a prova do verificador (3 passadas =
  3 `AsyncPublishJob` e `delivered_count` 3 para um arquivo) e os dois caminhos possíveis. Refs #291.
- **RESÍDUO CONHECIDO, aberto nesta rodada: a proposta entregue NO PRÓPRIO encerramento não é
  anotada na medida.** `confirmar` anota o que JÁ virou mensagem, e o arquivo que o encerramento
  entrega vira mensagem depois dele — não há passada seguinte para confirmá-lo. Anotar antes de
  publicar seria exatamente o defeito 3 da rodada 3 (faturar o que o cliente não recebeu). Custa uma
  proposta na contagem da entrega 7, no caso em que o prazo estoura antes de qualquer entrega.
- **O varredor (`ReapStaleRunsJob`) não oferece `closing_deliveries`**: ele tem fecho próprio
  (`uncertain_message`/`failure_message`) e não passa por `fail_run`. Fora do escopo dos cinco
  pontos; a execução abandonada pelo varredor perde o arquivo já gerado do mesmo jeito que perdia.
- **Prova real** (termo "Prova"): continua pendente de deploy + rollout na conta 16.
- **C8** (URL do portal no handle) e **`pedido` da entrega 10 na proposta** (D10): seguem
  registrados, sem mudança.


## Rodada 5 (12/09/2026) — PR #399, os sete pontos do Codex confirmados pelo revisor final

Base: `c165edf9bb`, árvore limpa. Suíte-base antes de qualquer edição: **1215 exemplos, 0 falhas, exit 0**.
Commit da rodada: `d50dbe15a6`. A rodada 4 teve CI verde e passou pelo verificador cego, mas o Codex a
REPROVOU e o revisor final confirmou os achados lendo o código: dois P1, dois P2 e três P3.

**A ARMADILHA DO `bundle`, medida de novo e registrada.** Neste worktree `bundle` resolve para
`/usr/bin/bundle` e FALHA com `Could not find 'bundler' (2.5.16)`: rspec e rubocop "rodam" sem executar
nada e o resumo do wrapper `rtk` mostra sucesso. Toda validação desta rodada foi feita com
`PATH="$HOME/.rbenv/shims:$PATH"` (ruby 3.4.4, bundler 2.5.16) e com o **exit code conferido** — em zsh,
`${pipestatus[1]}` quando há pipe. Sem isso, nenhum número abaixo valeria.

### Achados e o que mudou

| # | Achado | Correção | Guarda |
|---|---|---|---|
| P1-1 | **`blocked` não é sinônimo de "nunca trabalhou"** (`origem.rb:41`). A lista `SEM_TRABALHO` veio copiada de `ToolRun.opened_for_turn?`, que responde outra pergunta — lá é "ainda não virou trabalho NESTE turno", aqui é "NUNCA trabalhou". Quem escreve `blocked` é `AsyncRunJob#block_run` (freio do operador), e ele desce DEPOIS de a cotação rodar, às vezes depois de ela já ter entregado preço: a cotação nova sumia da conta, a antiga voltava a ser "a última", e a proposta do risco velho publicava depois de uma recotação real — o P1 da rodada 3 reaberto por outra transição | "Nunca trabalhou" virou pergunta por ESTADO, não lista de status: `discarded` sempre fora; `blocked` fora só sem número no portal E sem nada entregue (`Origem#cotacoes_que_contam`) | `insurance_proposal_spec` «a recotacao barrada pelo operador DEPOIS de entregar preco continua sendo a ultima» (M1) e «a cotacao barrada pelo gate antes de trabalhar nao barra a proposta» |
| P1-2 | **Janela entre a conferência e a publicação.** O publicador roda sob `conversation.with_lock` e `ToolRun#promote!` sob `pg_advisory_xact_lock(conversa+slug)`: mecanismos disjuntos. A causa-raiz não é "faltou lock" — é a AMBIGUIDADE do `pending`: a mesma lista tratava como órfã tanto a aceitação que vai promover em milissegundos quanto a que ficou parada porque o worker morreu | Separadas por IDADE (`PROMOCAO_ATE = 2.minutes`, o teto de 120 s de HTTP do turno que aceitou). Caminho (b), não (a) — ver decisão T1 | `insurance_proposal_spec` «a cotacao aceita agora, ainda por promover, barra a proposta da lista antiga» (M2) e, provando que o I2 não volta, «a cotacao aceita e nunca promovida, velha demais para promover, nao barra a proposta» |
| P2-1 | **O varredor perdia PDF pronto** (`reap_stale_runs_job.rb:100`): `close` publicava a frase de falha e `finish!('failed')` sem oferecer `closing_deliveries`. O MESMO defeito P2 da rodada 3 na outra porta de encerramento — fora do alcance daquela correção porque o varredor não passa por `fail_run` | O encerramento inteiro passou a morar em `Tools::Encerramento`, usado pelas DUAS portas: adquire a marca `closed`, oferece as entregas, deixa a ferramenta anotar, publica o fecho. Quem publica é quem chama (o motor espera a cadeia; o varredor força) | `reap_stale_runs_job_spec` «entrega o que a ferramenta ainda tinha antes de publicar o fecho» e, pelo caminho REAL, `insurance_proposal_spec` «o varredor entrega a proposta ja gerada antes de fechar a linha abandonada» (M3) |
| P2-2 | **A recotação que morre sem preço trancava a proposta para sempre** (`origem.rb:97`): A entregou preços, o cliente mandou refazer, B morreu `failed` sem preço — e o cliente, com os preços de A na tela, lia "quando os preços novos chegarem, é só me pedir de novo". Preços que nunca chegam | Muda a FRASE, não a regra (decisão do revisor final, mantida): `recotacao_sem_preco` diz que a recotação não trouxe preços e oferece cotar de novo. `SEM_TRABALHO` NÃO foi tocado para isto — incluir `failed`-sem-preço lá reabriria o R7 | `insurance_proposal_spec` «a recotacao que morreu sem preco barra a origem antiga, e a frase oferece cotar de novo» (M4), «a recotacao ainda viva mantem a frase de esperar pelos precos novos»; `recusa_registro_spec` `recusa_da_substituicao#1` e `recusar_substituicao#1` |
| P3-1 | **`entrega_do_token` não tem `rescue` e o comentário afirmava que tinha** (`autorizacao_da_execucao.rb:45-47`): verdade só para `publicavel?` | A INVARIANTE ESCRITA foi corrigida, e o hook continua sem `rescue` — de propósito (T4). O que ele levanta sobe até o `rescue` de quem chamou, e o efeito é o mesmo dos dois lados: o que não se consegue conferir NÃO SAI | `retomada_de_envio_spec` «o hook que levanta nao reenvia a proposta: nada vai ao cliente, e a marca fica» (M5) |
| P3-2 | **A proposta entregue NO encerramento não era anotada na medida** (`insurance_proposal.rb:164-171`): `confirmar` roda antes e anota só o que já virou mensagem; a entrega devolvida em seguida é publicada pelo job e nada mais roda. O teste da rodada 4 publicava ANTES de chamar `closing_deliveries`, então cobria só a passada anterior | Hook novo no contrato (`Native::Base#confirmar_publicadas`), chamado pelo `Encerramento` DEPOIS de publicar. A pergunta continua sendo a MENSAGEM publicada, nunca o handle — anotar aqui não fatura o que o cliente não recebeu | `insurance_proposal_spec` «anota na cotacao a proposta que o PROPRIO encerramento entregou» (M6), com a `Insurance::Medida` conferida |
| P3-3 | **`PARCIAL` mentia sobre a segunda proposta**: `closing_deliveries` usa `first(1)` e `aviso_de` só cobria `NAO_SAIU`/`PENDENTES`, então a segunda proposta GERADA era descartada em silêncio e o cliente lia "não consegui gerar todas as propostas a tempo" | O descarte fica (trade-off dos 25 s de shutdown); a frase é que muda: a gerada que não coube é dita pelo nome (`Recusas#nao_enviada`) e `PARCIAL` passou a dizer "enviar", que é verdade nos dois casos | `insurance_proposal_spec` «anuncia a segunda proposta GERADA como pronta, nunca como "nao consegui gerar"» (M7) |

### Decisões onde o desenho não fechou sozinho

**T1 — o P1-2 foi fechado por IDADE, não por lock (caminho b).** O caminho (a) — `ultima_cotacao?` pegando o
advisory lock do slug — teria de adquiri-lo JÁ SEGURANDO o lock da conversa, porque `publicavel?` roda dentro
de `conversation.with_lock`. Isso cria uma ordem de aquisição (conversa → advisory) que não aparece em nenhum
dos dois arquivos: hoje ninguém faz o contrário, e no dia em que alguém fizer o deadlock é em produção, no
caminho do dinheiro. Pior: no turno (`precheck`) não há transação, e `pg_advisory_xact_lock` ali é adquirido e
solto na mesma instrução — não serializa nada. A idade ataca a ambiguidade real ("esta `pending` ainda pode
virar `running`?"), é legível no ponto de uso e não cria invariante invisível. O custo é conhecido e
auto-resolvido: uma órfã recém-criada segura a proposta por até 2 min, e o pedido seguinte funciona.

**T2 — o silêncio do varredor não era opcional de manter; a correção do P2-1 o mata.** O gate
`if native.present? && run.delivered_count.zero?` é INCOMPATÍVEL com oferecer `closing_deliveries`: com ele,
entregar o PDF pronto continuaria sendo seguido de "não consegui gerar a proposta" (o próprio defeito), e no
caso `delivered_count > 0` o cliente receberia um arquivo sem nenhuma palavra de fecho. Então o varredor passou
a usar a regra do motor (parcial se algo chegou, falha/incerteza se nada chegou). **Mudança de comportamento
registrada:** a execução abandonada que JÁ tinha entregado algo passa a ler o fecho parcial onde antes havia
silêncio — que é a decisão da entrega 4 ("acabar sem fechar também é um desfecho") aplicada à porta que ficara
de fora. Dois exemplos que documentavam o silêncio foram reescritos, com o porquê no comentário.

**T3 — motivo NOVO (`recotacao_sem_preco`), não um segundo texto sob o motivo antigo.** A regra é uma só, mas o
que o cliente pode FAZER é diferente ("espere" × "peça outra cotação"), e o registro de recusa é a única janela
do operador para saber por que uma proposta não saiu: fundir os dois esconderia justamente o caso em que o
cliente fica preso. Custo pago: o catálogo `MOTIVOS` ganhou uma frase e `recusa_registro_spec` ganhou dois
gatilhos. A escolha do texto ficou em métodos próprios (`recusa_da_substituicao`, `recusar_substituicao`) para
que o código continue sendo LITERAL no ponto de chamada — a guarda estática só confere o que é literal.

**T4 — no P3-1, corrigir a INVARIANTE ESCRITA, e não "tratar".** Um `rescue` devolvendo nil em
`entrega_do_token` seria o contrário da decisão do dinheiro: nil significa "não reconheço esta entrega" e NÃO
barra nada — o `SendReplyJob` seria reenfileirado e o arquivo de uma cotação possivelmente refeita chegaria ao
cliente. Sem `rescue`, a exceção sobe e vira `blocked`/marca mantida: o arquivo não sai, que é o que se quer.
O comentário passou a dizer isso, distinguindo os dois hooks.

**T5 — a MUTAÇÃO REPROVOU O MEU PRÓPRIO TESTE, e é o achado de método desta rodada.** A primeira versão do
exemplo do P3-1 substituía `entrega_do_token` por uma subclasse que levantava. Ele passava — e passava
IGUALMENTE com a mutação M5 (`rescue StandardError; nil` no hook de verdade) aplicada: **5 exemplos, 0 falhas**.
O dublê provava o dublê. Reescrito para quebrar algo DENTRO do hook real (`delivery_token`, que ele chama para
montar o token de cada proposta gerada), M5 passou a reprovar. Sem a passada de mutação, esta correção teria
ido para a PR com uma guarda de mentira.

**T6 — `CLOSED_KEY` mudou de dono; `MARCAS` não.** A marca do encerramento passou a ser definida em
`Tools::Encerramento` (dono do conceito) e `AsyncRunJob::CLOSED_KEY` virou apelido, para não quebrar quem já a
referencia. `MARCAS` ficou no motor, que é quem as escreve; o `Encerramento` a lê de lá. É uma seta de serviço
para job, feia e explícita, preferida a mover as marcas do motor nesta rodada.

### Validação (números)

Banco `chatwoot_test_e8` (o mesmo das rodadas anteriores; `schema_migrations` = `20260904180000`, igual a
`db/schema.rb`). Sempre com o PATH do rbenv e exit code conferido.

| Rodada | Alvo | Exemplos | Falhas | Exit |
|---|---|---|---|---|
| Base (`c165edf9bb`, antes de editar) | `spec/services/autonomia/insurance` + `agents` + `spec/jobs/autonomia` + `spec/models/autonomia` | 1215 | 0 | **0** |
| Final (`d50dbe15a6`) | os mesmos 4 diretórios | **1226** (+11) | **0** | **0** (57,5 s) |

Por spec tocada (final): `insurance_proposal_spec` **94** (era 87: +7) · `recusa_registro_spec` **54** (era 52:
+2 gatilhos) · `retomada_de_envio_spec` **5** (era 4) · `reap_stale_runs_job_spec` **15** (era 14) ·
`async_run_job_intencao_de_envio_spec` 24 · `base_contrato_de_nivel_spec` 11 (`confirmar_publicadas` entrou na
varredura de nível).

`bundle exec rubocop` nos **15 `.rb`** da rodada (9 de `app`, 6 de `spec`): **0 ofensas, exit 0**. O cop
`Rails/WhereNotWithMultipleConditions` reprovou a primeira forma da regra do `pending` (`where.not` com duas
condições) e ela virou SQL explícito.

### Mutações (editar -> conferir que o arquivo mudou -> rodar alvo -> `git checkout --` -> md5 igual)

Árvore commitada em `d50dbe15a6` ANTES das mutações — `git checkout --` restaura o commit, não apaga trabalho.
Cada mutação aborta se a âncora não existir exatamente uma vez.

| # | Mutação (desfaz a correção) | Specs alvo | Ex. | Falhas | md5 | Resultado |
|---|---|---|---|---|---|---|
| M1 | `blocked` volta a sair sempre (`where.not(status: BLOQUEADA)`) | proposta | 94 | 1 | igual | **reprova** |
| M2 | `pending` volta a sair sempre, sem idade | proposta | 94 | 1 | igual | **reprova** |
| M3 | o varredor volta a publicar só a frase de falha, sem `closing_deliveries` | varredor + proposta + intenção | 133 | 5 | igual | **reprova** |
| M4 | `recotacao_sem_preco?` sempre falso (a frase volta a ser uma só) | proposta + `recusa_registro` | 148 | 3 | igual | **reprova** |
| M5 | `rescue StandardError; nil` em `entrega_do_token` | `retomada_de_envio` | 5 | 1 | igual | **reprova** (ver T5: com o teste anterior, 0 falhas) |
| M6 | `Encerramento` sem `confirmar_publicadas` | proposta | 94 | 2 | igual | **reprova** |
| M7 | `closing_deliveries` sem `aviso_da_gerada` | proposta | 94 | 1 | igual | **reprova** |

Árvore limpa depois das sete (`git status --porcelain` vazio).

### O que NÃO foi feito nesta rodada, e por quê

- **A entrega ADIADA no encerramento continua sem anotação.** `confirmar_publicadas` pergunta pela mensagem
  publicada; quando a publicação do fecho é adiada (cadeia humanizada aberta), a mensagem nasce ~90 s depois,
  e já não há ninguém para confirmá-la. É o mesmo limite de origem (a verdade é a mensagem, não o handle),
  agora estreitado ao caso adiado em vez de valer para todo encerramento.
- **O segundo arquivo do encerramento continua descartado** — trade-off dos 25 s de shutdown do Sidekiq,
  mantido de propósito (P3-3 pedia a frase, não o segundo download).
- **Issue [#402]** (`deferred` reemite e infla `delivered_count`) e **C8**/**D10**: sem mudança.
- **Prova real** (termo "Prova"): continua pendente de deploy + rollout na conta 16.
- **Merge e deploy**: não feitos — dependem de aprovação explícita do Rodrigo.
