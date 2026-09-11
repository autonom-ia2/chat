# Entrega 7 — medir para cobrar e para mostrar retorno

Data: 11/09/2026. Plano: entrega 7 do Agente de Cotação (6 termos de aceite). Issue-mãe: #291.
Depende das entregas 5 (intenção de envio) e 10 (pedido repetido), que são de onde saem as marcas do
handle que a medida lê para dizer o que NÃO sabe.

## O achado que define o desenho

O número de seguradoras acionadas **sempre existiu** — vem no `quote/result` a cada consulta do poll —
e **morria ali**. O handle guardava só `entregues`: quem COTOU, que é o que já foi para o cliente. Na
renovação real de 11/09/2026 eram onze de dezessete; as outras seis (recusa de risco) não deixavam
rastro nenhum, e a corretora pagou pelas dezessete.

Medido no mesmo dia, lendo por `agger quote result` as três cotações reais da conta de teste (leitura,
sem gastar cotação):

| cotação | `quoted` | `declined` | `auth_required` | **ofertas** |
|---|---|---|---|---|
| renovação `b0220871-…:1` | 11 | 6 | 0 | **17** |
| moto `91bef437-…:1` | 2 | 15 | 0 | **17** |
| caminhão `4c278fcf-…:1` | 1 | 15 | 1 | **17** |

Os mesmos dezessete códigos nas três (`1 3 4 5 7 8 11 12 19 20 26 44 46 47 48 50 55`). O caminhão é o
caso que decide a regra: **contar só `quoted` + `declined` diria dezesseis** — uma seguradora a menos
do que a corretora acionou, e justamente a que ela precisa ver (credencial recusada, critério 4.5).
Por isso `QuoteOffers#acionadas` conta TODAS as ofertas, em qualquer status.

## O desenho

- **A matéria-prima fica no handle da execução.** `InsuranceQuote::ACIONADAS_KEY`
  (`seguradoras_acionadas`) é gravada em `build_progress` — na primeira consulta e em todas as
  seguintes — como **união**, nunca como foto: o portal responde em pedaços (medido em 04/09: 3 de 6
  seguradoras em ~35 s, o negócio só assentou aos 392 s), e uma consulta que devolvesse menos do que a
  anterior apagaria seguradoras já pagas. União é idempotente: reconsulta não muda nada. Nenhuma
  chamada nova ao portal — o dado já vinha no `quote/result`.
- **A consulta é `Autonomia::Insurance::Medida`**, uma agregação jsonb sobre
  `autonomia_agent_tool_runs`, agrupada por `account_id` e filtrada por `slug` + `created_at`. O
  índice `idx_autonomia_tool_runs_account_slug (account_id, slug, created_at)` já existia e é
  exatamente o desta consulta — **sem migration**.
- **Nomes de chave vêm das constantes**, nunca digitados na consulta: um rename silencioso faria a
  medida devolver zero, e zero é o número que ninguém questiona (M11).
- **O que a medida não sabe, ela diz.** Três colunas separadas, nunca somadas nos totais:
  `cotacoes_sem_medida` (a cotação existe no portal e o número de seguradoras não foi lido — execução
  morta antes da primeira consulta, ou linha anterior a esta entrega), `cotacoes_sem_confirmacao`
  (intenção anotada sem número: PODE existir no portal) e `cotacoes_possivelmente_duplicadas` (pode
  haver uma A MAIS no portal do que a contada).
- **A janela é lida no fuso da CORRETORA** (`account.reporting_timezone`, o mesmo dos relatórios do
  Chatwoot) quando ela configurou um; sem configuração, o da instalação. "Setembro" da corretora
  termina às 23h59 dela: ler pelo nosso fuso jogaria para outubro toda cotação feita depois das 21h
  de 30/09 em São Paulo — o nosso valor no lugar do dela, numa conta de dinheiro. O resultado sempre
  devolve o fuso e os instantes exatos (a tela do Super Admin, que é cross-conta, usa o da instalação
  e diz isso).
- **Duas superfícies, uma fonte.** Super Admin → *Quote Measurement* (`/super_admin/insurance_measurement`)
  para a operação cobrar; `GET /api/v1/accounts/:id/autonomia/insurance/measurement` para a corretora
  ver o retorno. As duas leem a MESMA `Medida` — dois números diferentes para o mesmo mês, um na
  fatura e outro na tela do cliente, seriam pior do que número nenhum.

### Por que a página do Super Admin, e não só o endpoint (termo 4)

O termo é "não depende de engenheiro". Um endpoint da conta ainda exige token, `curl` e alguém que
saiba montar a URL — é caminho de integração, não de operação. A página do Super Admin custa um
controller (16 linhas), uma view ERB e uma rota, reusa o layout e o gate que já existem, e resolve o
termo de verdade: abre, escolhe duas datas, lê a tabela. O endpoint fica porque a **corretora** não
tem Super Admin e precisa do mesmo número que a fatura dela usa.

### `quotes_with_proposal` é zero, e o contador é real (termo 3)

A ferramenta de proposta por seguradora é a entrega 8. O contador já existe e conta de verdade
(`InsuranceQuote::PROPOSTAS_KEY`, lido pela medida); hoje lê zero porque **ninguém escreve a chave**.
Não é um `0` literal — a mutação M8 troca a coluna por `0` e um exemplo reprova.

**São dois números, decididos na rodada 3 pelo texto do termo** ("quantas COTAÇÕES viraram proposta
individual"): `cotacoes_com_proposta` (`quotes_with_proposal`) conta cotações cuja lista tem pelo
menos um código — uma cotação com duas propostas é UMA, e esta é a linha da fatura; `propostas_emitidas`
(`proposals_issued`) é a soma dos códigos, em separado. Até a rodada 3 a coluna `propostas` somava
códigos e chamava isso de "cotações que viraram proposta": `%w[8 3]` dava 2 onde houve uma.

**Ponto de registro da entrega 8:** o handle da execução, na passada que gerar a proposta. O caminho é
`quote/proposal` com `insurer_code` (o conector já o tem; `comparison_pdf` usa o mesmo endpoint SEM
código para o comparativo). Escrever ali a lista de códigos faz a medida contar sem mudar uma linha.

## Termos (6)

| # | Termo | Estado | Guarda / evidência |
|---|---|---|---|
| 1 | Consulta por corretora e por período devolve cotações E seguradoras acionadas | Fechado | `medida_spec` ("os dois números", "isolamento e janela", incluindo as DUAS bordas da janela e a recusa de medir conta que não se sabe qual é), `measurement_spec` (API, as duas bordas), `insurance_measurements_controller_spec` (Super Admin); M4, M7, M14, M16 |
| 2 | O número bate com o caso conhecido: dezessete acionadas → dezessete | Fechado | `medida_spec` "conta dezessete seguradoras quando a execução acionou dezessete" (os 17 códigos reais); `insurance_quote_medida_spec` "grava as dezessete, em qualquer status" (1 quoted + 15 declined + 1 auth_required, o desenho do caminhão real) e "nao infla a lista quando o portal repete o mesmo resultado" (duas passadas, dezessete nas duas); M1, M2, M15 |
| 3 | Quantas cotações viraram proposta individual; contador definido e zerado, ponto de registro documentado | Fechado | `medida_spec` "propostas individuais (entrega 8)" — `cotacoes_com_proposta` 1 e `propostas_emitidas` 2 para `%w[8 3]`, lista vazia não conta; `measurement_spec` e `insurance_measurements_controller_spec` (as duas colunas); M8, MV5; ponto de registro na seção acima e em `insurance_quote.rb` |
| 4 | A consulta não depende de engenheiro | Fechado | Página do Super Admin + endpoint da conta, documentados em `docs/insurance/README.md`; `insurance_measurements_controller_spec`, `measurement_spec` (gate e permissão); M6 |
| 5 | Nada aqui vira freio | Fechado | `medida_nao_e_freio_spec` (por AST, em `app/**` E `enterprise/app/**`: a medida só é nomeada pelas superfícies de leitura, não é alcançada do caminho da cotação, e não escreve); a medida REIMPLEMENTADA inline no aceite (sem nomear a classe) é pega por `bound_async_spec`, que tem 340 seguradoras na hora; M9, MV4, MV7 |
| 6 | O teto de oito por hora não voltou | Fechado | Três guardas: `bound_async_spec` "there is NO ceiling" (vinte execuções na ÚLTIMA HORA, 340 seguradoras, a vigésima primeira é aceita); `async_run_job_spec` "segue consultando e submetendo com vinte execuções na última hora" (o JOB, onde a chamada paga acontece, submete e entrega em `done`); `async_config_sem_teto_de_execucoes_spec` (a constante pelo nome, agora também `TETO`/`LIMITE` por `HORA`); M10, MV3, MV6 |

### O que fica para prova real / produção

Nada de comportamento novo em conversa: a entrega não muda uma linha do que o cliente lê nem do que
o modelo recebe. O que só a produção fecha é o **dado**: linhas anteriores a 11/09/2026 não têm
`seguradoras_acionadas` e aparecem em `cotacoes_sem_medida` — inclusive as três cotações reais da
conta 16, que foram lidas por CLI e não pelo poll desta versão. A medida passa a ser completa a
partir da primeira cotação depois do deploy. **Não há backfill**: reprocessar exigiria chamar
`quote/result` de cada cotação antiga, e o portal não garante a leitura de cotação encerrada.

## Rodada de correção — duas regras que só existiam no comentário

Revisão cega reprovou a primeira versão com dois achados, e os dois eram reais: reproduzi cada um
antes de corrigir, e nos dois casos os 62 exemplos do trilho passaram COM a regra desligada.

- **A janela só tinha a borda de baixo.** `created_at: inicio..fim` virava `created_at: inicio..` sem
  nada ficar vermelho. Nenhum exemplo criava execução DEPOIS do `fim` — "respeita o periodo pedido"
  só exercitava a linha de 40 dias atrás. O estrago é o pior tipo: a operação pede setembro, a
  cotação de 01/10 entra na fatura de setembro, e a conta fica MAIOR. Número inflado em fatura
  ninguém questiona.
- **A união não era provada idempotente.** O comentário dizia "reconsulta não muda nada" e trocar
  `|` por `+` passava em 62 exemplos do trilho E em 590 de `spec/services/autonomia/agents` +
  `spec/jobs/autonomia`. O portal lista as dezessete desde a PRIMEIRA consulta e o poll consulta a
  cada passada: com `+`, a segunda passada grava 34, a vigésima grava 340 — a medida cobraria
  trezentas e quarenta seguradoras por UMA cotação. Os exemplos existentes não pegavam porque
  "nao perde quem ja tinha aparecido" usa handle `%w[3 9]` contra resultado `['8']` (sem interseção)
  e "nao repete a mesma seguradora" só cobre duplicata DENTRO de uma consulta.

A classe do defeito é uma só — **regra escrita no comentário e não exercitada por nenhum exemplo** —,
então varri as demais decisões da entrega em vez de corrigir só os dois casos. A varredura achou mais
uma: `call` sem conta tem `raise ArgumentError` e nenhuma spec o sustentava; sem ele, `por_conta.first`
devolve a linha da PRIMEIRA corretora com o nome desta, numa conta de dinheiro. Está guardada em M16.
As demais (slug, escopo por conta, `jsonb_typeof`, `.sort`, `.uniq`, `.presence`, fuso, janela
invertida, janela padrão) já tinham guarda — conferido mutação a mutação.

## Mutações (16) — todas aplicadas, rodadas, restauradas e conferidas

Cada uma desliga UMA regra e reprova o exemplo que a sustenta. Restauração conferida por comparação
do conteúdo do arquivo com o original.

| # | Mutação | Arquivo | Reprova |
|---|---|---|---|
| M1 | `acionadas` conta só `quoted` + `declined` | `quote_offers.rb` | "grava as dezessete, em qualquer status" (dá 16 — o caso do caminhão) |
| M2 | `build_progress` não grava `ACIONADAS_KEY` | `insurance_quote.rb` | 8 exemplos de "seguradoras acionadas no handle" |
| M3 | a lista vira a foto da última consulta (sem união) | `insurance_quote.rb` | "nao perde quem ja tinha aparecido numa consulta anterior" e "nao conta de novo quem o handle ja tinha" |
| M4 | a medida conta execução em vez de cotação no portal | `medida.rb` | "nao conta execução que nunca virou cotação", "separa o envio sem confirmação" |
| M5 | `cotacoes_sem_medida` vira `0` | `medida.rb` | 3 exemplos (serviço + API) |
| M6 | data ilegível cai na janela padrão em silêncio | `medida.rb` | 3 exemplos (serviço + API + Super Admin) |
| M7 | a medida deixa de escopar por conta | `medida.rb` | "nao mistura corretoras" (API) |
| M8 | `propostas` vira zero escrito à mão | `medida.rb` | "conta as propostas registradas no handle" |
| M9 | a medida entra no caminho da cotação (o freio pela porta dos fundos) | `insurance_quote.rb` | os 2 exemplos de alcance de `medida_nao_e_freio_spec` |
| M10 | `MAX_RUNS_PER_CONVERSATION = 8` por hora de volta no `Bound` | `bound.rb` | a guarda pelo nome E o exemplo de comportamento |
| M11 | a medida lê um slug digitado à mão | `medida.rb` | 12 exemplos, a começar por "le o slug da propria ferramenta" |
| M12 | o job descarta a chave (`ACIONADAS_KEY` entra em `MARCAS`) | `async_run_job.rb` | "sobrevive ao job e fica no handle que a medida soma" |
| M13 | a janela ignora o fuso da corretora | `medida.rb` | "le as datas no fuso de relatorio da corretora" |
| M14 | a janela perde a borda de cima (`inicio..fim` → `inicio..`) | `medida.rb` | "nao conta cotação feita depois do fim da janela" (serviço + API) |
| M15 | a união vira soma (`\|` → `+`) | `insurance_quote.rb` | "nao infla a lista quando o portal repete o mesmo resultado" e "nao conta de novo quem o handle ja tinha" |
| M16 | a medida de uma conta aceita não saber qual é (sem o `raise`) | `medida.rb` | "recusa medir uma conta sem saber qual é" |

M12 é a que mais importa: sem ela, uma chave que a ferramenta grava e o job descarta passaria em
todos os exemplos de unidade e sumiria em produção. M14 e M15 são as duas que a primeira versão não
tinha, e as duas inflavam o número de COBRANÇA — erro que ninguém contesta, porque quem paga a mais
não reclama de um total que parece grande.

## Rodada 3 — a regra escrita no comentário, de novo (verificador cego)

A revisão da rodada 2 achou cinco pontos; os dois P2 são a MESMA classe da rodada anterior — regra
escrita em prosa e não exercitada por exemplo nenhum — e eu tinha afirmado que a classe estava varrida.
Não estava. Cada achado abaixo foi reproduzido com a mutação ANTES da correção (verde com a regra
desligada), corrigido, e a mutação passou a reprovar.

| Achado | Correção | Guarda | Mutação (reprova) |
|---|---|---|---|
| **P2** `medida.rb:38` — o comentário dizia que `autonomia_submitted` não serve porque a recusa também o recebe; nenhum exemplo tinha a marca. Com `COTACAO = quote_id OU submitted`, 67 exemplos verdes e a medida cobra a recusa | Fixture de "nao conta execução que nunca virou cotação" passou a ser a linha REAL que o job grava (`pedido`, `motivo`, `faltando`, `autonomia_intencoes: 1`, `autonomia_submitted: true`, sem `quote_id`), em `medida_spec` e `measurement_spec`; e um exemplo INTEGRADO em `insurance_quote_medida_spec` roda o `AsyncRunJob` de verdade com o `start` recusando (`dados` ilegível → `json_invalido`), confere a linha e lê `cotacoes: 0` | os três exemplos | MV1b — 3 exemplos reprovam |
| **P2** `async_run_job.rb:70` — um teto literal em `stop?` (contar execuções da conta na última hora, falhar acima de oito) passava por 140 exemplos; a guarda por comportamento só existia no aceite e o comentário prometia cobertura do job | Exemplo em `async_run_job_spec` ("no ceiling (entrega 7, termo 6)"): vinte execuções encerradas da MESMA conta e ferramenta na última hora, cada uma com dezessete seguradoras, mais a vigésima primeira `running`; `perform` faz o `start` e depois o `poll`, e a execução termina em `done` sem frase de falha. Regex de `async_config_sem_teto_de_execucoes_spec` ampliado com `(TETO\|LIMITE)[A-Z_]*HORA`. Comentários de `async_config.rb` e `bound_async_spec` dizem o que cada guarda cobre de fato | `async_run_job_spec` + guarda pelo nome | MV3 — reprova no job (e a guarda pelo nome NÃO pega, como o verificador disse: por isso o exemplo); MV6 — a guarda pelo nome pega `TETO_POR_HORA` |
| **P3** `bound_async_spec.rb:235` — as vinte execuções tinham handle vazio: um teto pela unidade certa (seguradoras) reimplementado inline no aceite passava; a varredura AST só olhava `app/**` | As vinte com `{quote_id, seguradoras_acionadas: dezessete}` (340 na hora); raízes da varredura de `medida_nao_e_freio_spec` = `app` e `enterprise/app` | `bound_async_spec` "there is NO ceiling"; `medida_nao_e_freio_spec` | MV4 — o freio inline (SUM de `jsonb_array_length` da conta na hora > 100 → recusa) reprova o aceite; MV7 — um override em `enterprise/app` que nomeia a medida reprova os 2 exemplos de alcance |
| **P3** `medida.rb:131` — remover `slug:` do escopo passava: nenhum exemplo tinha execução de OUTRA ferramenta com `quote_id` | Exemplo "nao conta execução de outra ferramenta, mesmo com quote_id e seguradoras no handle" (slug `outra_ferramenta`, mesma conta → zero) | `medida_spec` | MV2 — reprova |
| **P3** `medida.rb:55` — `propostas` somava códigos (uma cotação com `%w[8 3]` contava 2) e o termo 3 pergunta por COTAÇÕES | Decisão do orquestrador pelo texto do termo: `cotacoes_com_proposta` = `COUNT(*) FILTER (WHERE jsonb_typeof(...)='array' AND jsonb_array_length(...) > 0)`; a soma segue como `propostas_emitidas`. API (`quotes_with_proposal`, `proposals_issued`), página do Super Admin (duas colunas), README e specs refletem as duas | `medida_spec` (1 e 2; lista vazia = 0), `measurement_spec`, `insurance_measurements_controller_spec` | MV5 — a coluna do termo virando soma reprova 3 exemplos |

Fica dito o que as mutações desta rodada mostraram sobre as guardas: **a guarda pelo nome não vê a
contagem escrita do zero** (MV3 passou por ela e só o exemplo do job a pegou), e **a varredura AST não
vê a medida reimplementada sem nomear a classe** (MV4 passou por `medida_nao_e_freio_spec` e só o
exemplo de comportamento do aceite a pegou). Cada porta em que a contagem poderia entrar tem um
exemplo de comportamento; é isso que segura o termo 6, não o regex.

### Mutações da rodada 3 (7) — aplicadas, rodadas, restauradas e conferidas por hash

| # | Mutação | Arquivo | Reprova |
|---|---|---|---|
| MV1b | `COTACAO` = `quote_id` OU `autonomia_submitted` | `medida.rb` | 3 (serviço, API, integrado pelo job) |
| MV2 | escopo sem `slug:` | `medida.rb` | "nao conta execução de outra ferramenta…" |
| MV3 | teto literal em `AsyncRunJob#stop?` (execuções da conta na hora > 8) | `async_run_job.rb` | "segue consultando e submetendo com vinte execuções na última hora" |
| MV4 | freio inline em `Bound#accept_async` (seguradoras da conta na hora > 100) | `bound.rb` | "there is NO ceiling" |
| MV5 | `cotacoes_com_proposta` vira soma de códigos | `medida.rb` | 3 (serviço, API, Super Admin) |
| MV6 | `TETO_POR_HORA = 8` no `Bound` | `bound.rb` | a guarda pelo nome |
| MV7 | `enterprise/app/services/autonomia/agents/tools/freio_mutacao.rb` nomeando a medida | (arquivo novo, removido) | os 2 exemplos de alcance |

## Rodada 4 — o nosso fuso na tela que cobra, e três valores nossos na borda (verificador cego)

Cinco achados, todos reais e reproduzidos antes de corrigir. O P2 é a mesma classe das rodadas 2 e 3
lida pelo outro lado: a regra do fuso EXISTIA e tinha guarda (M13) — para `call`; `por_conta`, a lista
que a página do Super Admin usa para FATURAR, era uma consulta única agrupada no fuso da instalação, e
o próprio comentário do controller prometia que as duas superfícies não divergiriam. Divergiam em toda
cotação entre 21h e 23h59 de São Paulo no último dia do mês.

| Achado | Correção | Guarda | Mutação (reprova) |
|---|---|---|---|
| **P2** `insurance_measurements_controller.rb:11` — a página do Super Admin lia todas as corretoras no fuso da instalação; a cotação das 23h de 30/09 em SP (02h UTC de 01/10) caía em outubro na fatura e em setembro na tela da corretora | `Medida#por_conta` enumera as corretoras com execução numa janela alargada (`FOLGA_DE_FUSO`, 26 h: a meia-noite da mesma data entre UTC-12 e UTC+14) e monta cada linha com `Medida.new(conta:).linha_da_conta` — o MESMO caminho do endpoint da conta, acordo por construção; a linha diz o fuso e a página o mostra por corretora (nada de "o da instalação") | `insurance_measurements_controller_spec` "le cada corretora no fuso dela e bate com a API da conta" (lê a página E a API no mesmo exemplo, SP + cotação às 23h de 30/09 → 1 e 17 nas duas); `medida_spec` "#por_conta le cada corretora no fuso dela, igual a medida da conta" | MX1 — voltar à consulta agrupada no fuso da instalação reprova os 2; MX2 — folga zero na enumeração reprova os 2 |
| **P3** `insurance_measurements_controller.rb:11` — `fim: nil` no controller passava por 6 exemplos (MX8 do verificador) | Exemplo com cotação em 15/09 e 01/10, `from=2026-09-01&to=2026-09-30` → células `1 17 0 0 0 0 0 0` | `insurance_measurements_controller_spec` "nao conta cotação feita depois do fim da janela" | MX8 — reprova (e o exemplo do fuso também, porque `to` nil lê até hoje) |
| **P3** `async_config.rb:99` — um teto por ATRASO (`interval_for` devolvendo 1 h acima de oito execuções na hora) passava pelas três guardas do termo 6 (MX3 do verificador): o exemplo do job só afirmava QUE reagendava | O exemplo mede `interval_for(agent, 0)` ANTES das vinte, exige o mesmo valor depois, e confere o `at` do job reagendado contra ele | `async_run_job_spec` "segue consultando e submetendo com vinte execuções na última hora" | MX3 — reprova |
| **P3** `medida.rb:102` — só `fim` pedido e a janela padrão ancorada em HOJE: `to=2026-06-30` voltava 422 culpando "a data inicial", que ninguém mandou | A janela padrão são os `DIAS_PADRAO` dias que TERMINAM em `fim` (`final - 30 dias`); com `fim` nil, `final = agora`, idêntico ao de antes | `medida_spec` "so fim: a janela padrao termina nele"; `measurement_spec` "so to: a janela padrao termina nele" | MX9 — reprova os 2 |
| **P3** `medida.rb:113` — `Date.iso8601` aceitava data-hora e descartava a hora em silêncio | `Date.strptime` com `FORMATO_DA_DATA` **também ignora a sobra** (conferido em Ruby puro: `strptime('2026-09-01T10:00:00', '%Y-%m-%d')` devolve 01/09) — a sugestão do verificador não bastava. A guarda é a ida e volta: `dia.strftime(FORMATO) == texto`, senão `PeriodoInvalido` | `medida_spec` "recusa data com hora em vez de descartar a hora em silencio"; `measurement_spec` "recusa data com hora em vez de descartar a hora" | MX10 — sem a ida e volta, reprova os 2 |

Varredura da classe na própria correção: `corretoras_com_execucao` ganhou `return [conta] if conta`
(a lista de uma instância COM conta é só a linha dela) — regra nova, sem exemplo até eu escrever um:
"#por_conta com a conta, so tem a linha dela" (MX11 reprova). E `first` numa relação agrupada
acrescenta `ORDER BY id`, que o `GROUP BY` recusa — `linha_da_conta` usa `take`, e os 38 exemplos que
quebraram na primeira tentativa são a prova de que a suíte vê isso.

### Mutações da rodada 4 (7) — aplicadas, rodadas, restauradas e conferidas por hash

| # | Mutação | Arquivo | Reprova |
|---|---|---|---|
| MX1 | `por_conta` volta à consulta única agrupada no fuso da instalação | `medida.rb` | 2 (Super Admin + serviço) |
| MX2 | `FOLGA_DE_FUSO = 0` (enumeração sem folga) | `medida.rb` | 2 (Super Admin + serviço) |
| MX8 | `fim: nil` no controller do Super Admin | `insurance_measurements_controller.rb` | 2 |
| MX3 | teto por atraso em `interval_for` (1 h acima de oito execuções na hora) | `async_config.rb` | "segue consultando e submetendo com vinte execuções na última hora" |
| MX9 | janela padrão ancorada em hoje em vez de no `fim` | `medida.rb` | 2 (serviço + API) |
| MX10 | data-hora aceita e truncada (sem a ida e volta) | `medida.rb` | 2 (serviço + API) |
| MX11 | `por_conta` com conta enumera todas as corretoras | `medida.rb` | "com a conta, so tem a linha dela" |

## Rodada 5 — a última passada de P3 (verificador cego)

Quatro achados, todos reais e reproduzidos antes de corrigir; nenhum P2. Três são a mesma classe das
rodadas anteriores — regra escrita em prosa sem exemplo que a sustente (a folga tinha magnitude só
no comentário; a página "por corretora" tinha oito exemplos com UMA corretora) — e um é a classe da
rodada 3 por outra porta (`linha_da_conta` pública fazendo o que `call` sem conta já não podia).

| Achado | Correção | Guarda | Mutação (reprova) |
|---|---|---|---|
| **P3** `medida.rb:156` — `linha_da_conta` pública: `Medida.new(inicio: nil, fim: nil).linha_da_conta` devolvia a linha de uma corretora qualquer (escopo sem conta + `take`), a mesma classe de M16 por outra porta | `protected`: `por_conta` a chama numa instância da MESMA classe, e de fora não existe | `medida_spec` "nao entrega a linha de uma conta por fora de call" (`NoMethodError` de método protegido) | MR1 — voltar a `public` reprova |
| **P3** `medida.rb:43` — `FOLGA_DE_FUSO = 3.hours` passava por 53 exemplos: só MX2 (zero) guardava a folga, e todos os fusos dos exemplos eram São Paulo (3 h). Com folga parcial, a corretora em UTC+14 com cotação na primeira hora do mês e a em UTC-12 na última somem da FATURA em silêncio enquanto a API delas responde 1/17 | Nenhuma mudança na constante (26 h continua sendo a distância entre UTC-12 e UTC+14). A guarda que faltava: exemplos nos dois extremos | `medida_spec` "#por_conta enumera a corretora em qualquer fuso, e a linha e a mesma da medida da conta" (Pacific/Kiritimati às 00:30 de 01/09; Etc/GMT+12 às 23:30 de 30/09; cada linha `eq` ao `call` da conta); `insurance_measurements_controller_spec` "le a corretora em qualquer fuso, e a linha e a medida da propria conta" (as 16 células da página = as de `call` de cada conta) | MR2 — `3.hours` reprova os 2 |
| **P3** `medida.rb:117` — `from=hoje` sem `to` à 01h UTC, corretora em São Paulo: a instância da página validava a janela no fuso da instalação e aceitava; a `Medida.new(conta:)` de São Paulo recalculava abertura (03h UTC) > final (01h UTC, "agora") e levantava `PeriodoInvalido` — e a página inteira respondia "a data inicial é posterior à final", sem linha para NENHUMA corretora, culpando uma final que ninguém mandou | A inversão só existe entre DUAS datas pedidas (`recusar_inversao!` em `periodo`). Com o fim em aberto, início > "agora" é decidido por quem PEDIU: `call` e `por_conta` recusam com "a data inicial está no futuro" (`recusar_data_inicial_no_futuro!`); a corretora enumerada por `por_conta` cujo dia não começou lê a janela vazia (`created_at: inicio..fim` com início depois do fim não casa linha) e é pulada como qualquer corretora sem execução | `medida_spec` "#por_conta pula a corretora cujo dia ainda nao comecou, em vez de derrubar a lista inteira" (travel_to 01h UTC; SP pulada, UTC na lista; `call` de SP recusa com /futuro/) e "recusa data inicial no futuro dizendo que ela esta no futuro"; `measurement_spec` "recusa data inicial no futuro dizendo que ela esta no futuro" (422, `detail` exato); `insurance_measurements_controller_spec` "nao derruba a pagina quando o dia de uma corretora ainda nao comecou" e "avisa quando a data inicial pedida ainda nao chegou" (a PÁGINA pedindo `from` amanhã é recusa, com a frase nova) | MR3 — voltar a levantar na construção reprova 5; MR3b — `call` sem a recusa reprova 3; MR3c — `por_conta` sem a recusa reprova 1 |
| **P3** `insurance_measurements_controller_spec.rb:43` — `@linhas = @medida.por_conta.first(1)` passava por 8/8: toda a superfície que FATURA tinha uma única corretora com execução; o termo 1 ("por corretora") só estava provado no serviço | Nenhuma mudança no controller. Exemplo com DUAS corretoras (dezessete e três), as duas linhas na ordem e as 16 células | `insurance_measurements_controller_spec` "mostra as duas corretoras, cada uma na sua linha" | MR4 — `.first(1)` reprova 2 (este e o dos fusos extremos) |

A decisão de desenho do terceiro achado fica dita: a recusa da "data inicial no futuro" saiu da
construção e foi para os dois pontos de entrada (`call`, `por_conta`) porque a MESMA janela é
inválida para quem pediu e vazia para a corretora derivada — o que separa os dois casos é quem
pergunta, não a data. `linha_da_conta` não tem retorno antecipado para a janela vazia: o intervalo
com início depois do fim já não casa linha no banco, e uma segunda implementação da mesma regra
seria linha que nenhuma mutação reprova.

### Mutações da rodada 5 (6) — aplicadas, rodadas, restauradas e conferidas por hash

| # | Mutação | Arquivo | Reprova |
|---|---|---|---|
| MR1 | `linha_da_conta` volta a ser pública | `medida.rb` | "nao entrega a linha de uma conta por fora de call" |
| MR2 | `FOLGA_DE_FUSO = 3.hours` (folga parcial) | `medida.rb` | 2 (serviço + Super Admin, fusos extremos) |
| MR3 | `periodo` volta a levantar a inversão com o fim em aberto (a corretora derivada levanta em `por_conta`) | `medida.rb` | 5 (serviço 2, API 1, Super Admin 2) |
| MR3b | `call` sem `recusar_data_inicial_no_futuro!` | `medida.rb` | 3 (serviço 2, API 1) |
| MR3c | `por_conta` sem `recusar_data_inicial_no_futuro!` | `medida.rb` | "avisa quando a data inicial pedida ainda nao chegou" |
| MR4 | `@linhas = @medida.por_conta.first(1)` no controller | `insurance_measurements_controller.rb` | 2 |

## Comandos rodados

```bash
# leitura real, sem gastar cotação (conta de teste)
set -a; . ~/dev/projetos.noindex/agger_full/env.local; set +a
export AGGER_TEST_EMAIL=$LOGIN_AGGER_TESTE AGGER_TEST_PASSWORD=$SENHA_AGGER_TESTE
npx tsx src/cli/main.ts agger quote result 'b0220871-e7da-4a84-adb7-bcff2641eb1e:1'   # 17 ofertas
npx tsx src/cli/main.ts agger quote result '91bef437-e764-41c9-b6e8-bcfcf8e62d15:1'   # 17
npx tsx src/cli/main.ts agger quote result '4c278fcf-a456-447a-a06e-e49f7a93baa8:1'   # 17

# chat2you (banco de teste próprio do trilho)
eval "$(rbenv init -)"; export POSTGRES_DATABASE=chatwoot_test_e7
RAILS_ENV=test bundle exec rails db:create db:schema:load
bundle exec rspec <specs do trilho> --format json --out r.json      # 67 exemplos, 0 falhas
bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia \
  --format json --out ampla.json                                    # suíte ampla
bundle exec rubocop --format json --out rubocop.json <arquivos tocados>   # 0 ofensas
uv run python3 mutacoes.py                                          # M1–M16 (919 na suíte ampla)
# rodada 3
bundle exec rspec <8 specs do trilho> --format json --out alvo.json # 97 exemplos, 0 falhas
uv run python3 mutacoes_r3.py                                       # MV1b–MV7, todas reprovam e restauram
# rodada 4
bundle exec rspec <6 specs do trilho> --format json --out alvo.json # 78 exemplos, 0 falhas
uv run python3 mutacoes_r4.py                                       # MX1–MX11 (7), todas reprovam e restauram
# rodada 5
bundle exec rspec <4 specs do trilho> --format json --out alvo.json # 62 exemplos, 0 falhas
uv run python3 mutacoes_r5.py                                       # MR1–MR4 (6), todas reprovam e restauram
```

## Arquivos

Novos: `app/services/autonomia/insurance/medida.rb`,
`app/controllers/api/v1/accounts/autonomia/insurance/measurement_controller.rb`,
`app/views/api/v1/accounts/autonomia/insurance/measurement/show.json.jbuilder`,
`app/controllers/super_admin/insurance_measurements_controller.rb`,
`app/views/super_admin/insurance_measurements/show.html.erb`, e cinco specs.

Tocados: `quote_offers.rb` (`#acionadas`), `insurance_quote.rb` (as duas chaves e a união),
`async_config.rb` (o comentário apontava para uma spec que não existia — agora existe),
`_navigation.html.erb`, `config/routes.rb`, `docs/insurance/README.md`, `bound_async_spec.rb`
(a hora explícita no exemplo do teto).

Rodada 3: `medida.rb` (as duas colunas de proposta, comentários), `show.json.jbuilder` e
`show.html.erb` (as duas colunas), `async_config.rb` (o que cada guarda cobre), `async_run_job_spec.rb`
(o exemplo do job), `async_config_sem_teto_de_execucoes_spec.rb` (regex), `bound_async_spec.rb`
(340 seguradoras), `medida_nao_e_freio_spec.rb` (`enterprise/app`), `medida_spec.rb`,
`measurement_spec.rb`, `insurance_quote_medida_spec.rb`, `insurance_measurements_controller_spec.rb`,
`docs/insurance/README.md`. Nenhum arquivo de instrução, `MOTIVOS` ou schema de função.

Rodada 4: `medida.rb` (`linha_da_conta`, `por_conta` por corretora no fuso dela, `FOLGA_DE_FUSO`,
`FORMATO_DA_DATA`, janela padrão que termina no `fim`, ida e volta da data),
`insurance_measurements_controller.rb` (comentário), `show.html.erb` (coluna Fuso; período em datas),
`async_config.rb` (comentário: o teto por atraso), `insurance_measurements_controller_spec.rb`,
`medida_spec.rb`, `measurement_spec.rb`, `async_run_job_spec.rb`, `docs/insurance/README.md`. Nenhum
arquivo de instrução, `MOTIVOS`, schema de função ou adapter.

Rodada 5: `medida.rb` (`linha_da_conta` protegida, `recusar_inversao!`, `recusar_data_inicial_no_futuro!`
em `call` e `por_conta`), `insurance_measurements_controller_spec.rb` (duas corretoras, fusos extremos,
dia que não começou, data inicial no futuro), `medida_spec.rb`, `measurement_spec.rb`,
`docs/insurance/README.md`. Nenhum arquivo de instrução, `MOTIVOS`, schema de função ou adapter;
controller e view do Super Admin intocados.
