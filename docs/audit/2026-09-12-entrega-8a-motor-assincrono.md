# Entrega 8a — o motor do encerramento assíncrono (sem a ferramenta da proposta)

Data: 12/09/2026. Issue: #396 (Part of #291). Branch `feat/entrega-8a-motor-assincrono`, de
`origin/main` `261d7bb086`. **Zero migration.** Sem merge, sem produção.

Esta é a PRIMEIRA METADE de um fatiamento. A entrega 8 nasceu como uma PR só (#399) — motor
assíncrono **mais** a ferramenta `proposta_da_seguradora` — e foi reprovada seis vezes seguidas. O
CEO decidiu cortar: o MOTOR (esta PR) entra sozinho, vai a produção e roda na conta 16; a
FERRAMENTA (8b) é reescrita sobre ele, depois. O critério do corte está em
`~/ops/agente-cotacao/entrega-8/plano-corte-8a-motor.md`.

**O que esta PR NÃO tem, de propósito:** `Native::InsuranceProposal` e seus seis módulos, o
`ToolRun#anotar_propostas!` e o `DEAD_STATUSES`, o concern `ToolRunPromocao` (e com ele o teto de
idade da promoção, que embarca um P1 sem nenhum leitor no motor — item "O que ficou de fora"), os
cinco motivos novos de `Recusa::MOTIVOS`, o `Registry`, o `principal.md`, o `NOMES_KEY` da cotação,
o `Comparativo.sufixo_do_arquivo` e os quatro ganchos de DECISÃO sem implementador
(`confirmar_publicadas`, `publicavel?`, `entrega_do_token`, `argumentos`).

## O desenho, em uma frase

Acabar sem fechar é um DESFECHO, acontece por duas portas, e as duas passam a fazer a mesma coisa:
`Tools::Encerramento` adquire a marca `closed`, pergunta à ferramenta o que ainda vale entregar,
publica, e só então publica um fecho que **só afirma o que a ferramenta confirmou**.

## Por que o motor entra sozinho

A cotação (`cotar_seguro`) está em produção e atravessa TODO o código que esta PR move. Cada
caminho que muda é, primeiro, um risco de regressão dela — e é por isso que o corte existe: um
motor pequeno, com a não-regressão provável linha a linha, vale mais que uma PR de 5.250 linhas em
que o motor e a ferramenta se escondem um atrás do outro.

## O que mudou (por commit)

**`c25e1e2e29`** `refactor(tool): a identidade da entrega publicada vira módulo`
- `Tools::EntregaPublicada.para(conversation, token)` — extração literal do método privado
  `AsyncPublisher#entrega_publicada`. Mesma consulta, mesmo `LIKE` como peneira, mesma comparação
  exata do atributo, mesmo e único chamador. Zero comportamento.
- Ficou de fora o `existe?` do ramo original: não tem chamador no motor. Quem o usa é a 8b.

**`8b6b1b7832`** `feat(tool): o encerramento é um só, e cada passo cai sozinho`
- `Tools::Encerramento` (novo, 167 linhas): adquire `closed` no banco (`merge_handle!(ausente:)`),
  oferece `closing_deliveries` à ferramenta, publica cada entrega, publica o fecho. Cada passo tem
  o seu `rescue`; **cada ENTREGA tem o seu** (ver "Os dois defeitos").
- `AsyncRunJob#fail_run` deixa de filtrar por `delivered_count` e delega a `Encerramento`;
  `AsyncRunJob#ferramenta` monta a nativa com `conversation:` e `run:`, sem `delivery`.
- `ReapStaleRunsJob#close` passa a encerrar pelo mesmo caminho, com `trabalho_novo: false`.
- `Native::Base`: `initialize` ganha `conversation:` e `run:` (padrão `nil`); `closing_deliveries`
  ganha `trabalho_novo:`; nascem `resultado_entregue?` e `resta_entregar?`, os dois com padrão
  `false`.
- Specs: `encerramento_spec` (novo), mais `async_run_job_spec`, `async_run_job_intencao_de_envio_spec`,
  `reap_stale_runs_job_spec`, `base_contrato_de_nivel_spec` e o dublê `async_tool_helper`.

**`d15f6dd14b`** `fix(cotacao): o fecho da cotação só afirma o que é verdade`
- `InsuranceQuote::Fecho` (novo): as três respostas da cotação ao encerramento saem da classe (que
  está no teto de linhas) para um módulo, como `Comparativo`, `Declaracao`, `Recusas`, `Envio` e
  `Veiculo`.
- `closing_deliveries` devolve `[]` sem `trabalho_novo`; `resultado_entregue?` é preço publicado
  (`entregues`), nunca o `pedido`; `resta_entregar?` **corrigido** (ver abaixo).

## Os dois defeitos que esta PR corrige antes de entrar

### 1. `resta_entregar?` fixo em `true` — a frase parcial saía para quem tinha tudo

`InsuranceQuote::Fecho#resta_entregar?` devolvia `true` sob o comentário "SEMPRE SOBRA, POR
CONSTRUÇÃO", com o raciocínio de que o encerramento só existe fora do caminho feliz. **A premissa é
falsa num estado alcançável hoje.** `PDF_SENT_KEY` (`comparativo_enviado`) só é gravada no ramo
`done` de `build_progress`, depois do `return … unless finished?(result)`: ela existir PROVA que o
portal respondeu `completed` (ou `failed`) e que o comparativo saiu. O que separa essa execução de
um desfecho feliz é só o `finish!('done')`, que vem DEPOIS do `record_attempt!` que persistiu o
handle — morto o worker entre os dois (deploy, hard shutdown do Sidekiq), a linha fica `running`
com a chave no banco e o varredor a encerra.

Resultado com a premissa antiga: `resultado_entregue?` verdadeiro (há `entregues`),
`resta_entregar?` verdadeiro por construção, e o cliente que recebeu **os preços E o comparativo**
lia "Algumas seguradoras não responderam a tempo. Os preços acima são os que chegaram."

Correção: `!handle.to_h[self.class::PDF_SENT_KEY]`. A chave sobrevive ao corte das marcas do motor
(`AsyncRunJob::MARCAS` não a lista), então chega à ferramenta pelo handle que o encerramento
entrega.

**Por que cai nesta PR e não na 8b:** é esta PR que liga o varredor ao `Encerramento` e que faz
`fail_run` sempre passar pela ferramenta. É ela que CRIA o caminho por onde a frase falsa sai. Entrar
sem a correção é entregar em produção, para `cotar_seguro`, uma mentira que hoje não existe.

**O que prova:**
- unidade — `insurance_quote_ramo_auto_spec`, `'nao afirma sobra quando o comparativo ja saiu — o
  portal tinha fechado'`;
- caminho real, porta do motor — `async_run_job_encerramento_parcial_spec`, `'a cotacao que ja
  entregou tudo fecha em silencio quando o prazo estoura'`;
- caminho real, porta do varredor — mesmo arquivo, `'o varredor tambem fecha em silencio a cotacao
  que ja entregou tudo'`.

Os dois exemplos de caminho real montam a execução no estado exato do defeito: `entregues`,
`comparativo_enviado`, prazo vencido, linha `running`.

### 2. O lote de entregas inteiro dentro de um tratamento só — a segunda apagava a primeira

Como veio do ramo, `entregar_o_que_resta` fazia `.map { |entrega| publicar(entrega) }` DENTRO de
`etapa('entregas')`. Exceção na segunda entrega ⇒ o passo devolve `false` ⇒ como as entregas do
encerramento **de propósito não contam em `delivered_count`**, o fecho publica a frase de FALHA logo
depois de uma publicação bem-sucedida. O cliente recebe o arquivo e, na mensagem seguinte, a
negação dele.

O caminho é real e é o do próprio motor: `AsyncRunJob#publish` re-agenda a entrega ADIADA com
`AsyncPublishJob.perform_later`, e enfileirar levanta com o Redis fora — que é uma das avarias que
levam a execução a acabar sem fechar, para começo de conversa. (`AsyncPublisher#publish` não
levanta: ele mesmo tem `rescue`. Quem levanta é o re-agendamento, no publicador do job.)

Correção: `publicar_uma`, com o `rescue` POR ENTREGA. O que uma entrega levantar vira log e `false`
("não sei", lido pelo lado conservador); as outras seguem. E o agregador é
`entregas.count { … }.positive?`, não `any?`: `any?` pararia na primeira aceita e a segunda nunca
sairia — não há passada futura para recuperá-la.

**Por que cai nesta PR:** o arquivo é 100% motor e é esta PR que o cria; o contrato diz que
`closing_deliveries` devolve um `Array`, e um motor que perde uma publicação porque a seguinte
levantou é defeito do motor, independentemente de quem tem duas entregas hoje (a cotação tem no
máximo uma). Deixar para a 8b faria a PR da ferramenta reabrir `encerramento.rb`, que é exatamente o
acoplamento que o fatiamento existe para matar.

**O que prova:** `encerramento_spec`, `'a entrega que levanta nao apaga a que ja foi publicada, nem
vira frase de falha'`, `'a entrega que levanta nao impede a seguinte'` e `'publica todas as entregas
do encerramento, e nao para na primeira'`.

## Não-regressão de `cotar_seguro`, item a item

A cotação é a única ferramenta assíncrona em produção e passa por todo o código movido. Cada risco,
e o exemplo que o fecha:

| # | risco | por que é risco | o que prova |
|---|---|---|---|
| R1 | `fail_run` deixa de filtrar por `delivered_count`: **toda** falha passa pela ferramenta | cotação que morreu sem preço nenhum poderia passar a pedir o comparativo ao portal | a cotação se protege sozinha: `comparison_pdf` faz `return if Array(handle[DELIVERED_KEY]).empty?`. `async_run_job_encerramento_parcial_spec`, `'a cotacao que morre sem preco nenhum nao passa a mandar comparativo'` — pelo caminho real, com o conector `mock` NÃO stubbado: se o portal fosse chamado, o exemplo cai (mutação M6) |
| R2 | o varredor passa a chamar a ferramenta | até `BATCH_LIMIT` linhas em sequência num cron × login + chamada de até 60 s; um deploy no meio mata o lote e deixa linhas com `closed` e sem fecho, para sempre | `trabalho_novo: false` no varredor + `return [] unless trabalho_novo` no fecho da cotação. `reap_stale_runs_job_spec`, `'diz a ferramenta que nao pode comecar trabalho novo, e entrega so o que ja esta pronto'`; e pelo caminho real, `async_run_job_encerramento_parcial_spec`, `'o varredor fecha a cotacao abandonada sem pedir o comparativo ao portal'` (mutações M4 e M5) |
| R3 | **mudança de frase visível ao cliente**: o varredor antes só falava com `delivered_count.zero?`; agora fecha sempre | quem já recebeu preço e era fechado em silêncio passa a receber a frase parcial | é intencional e está travado em `async_run_job_intencao_de_envio_spec` (`'recarrega antes de decidir…'`, que mudou de `bot_contents` vazio para `[tool.partial_message]`) e em `reap_stale_runs_job_spec` (`'fecha com a frase parcial…'`). **É aqui que o defeito 1 mordia**: sem a correção, a frase saía também para quem recebeu tudo |
| R4 | `delivered_count` pode estar inflado (issue #402: `deferred` reemite e o contador sobe) | contador inflado mudaria o que o cliente lê no fecho | o contador só é consultado quando `entregou` é falso, e a magnitude está travada (`delivered_count: 1`, não `be_positive`) em `async_run_job_intencao_de_envio_spec` e em `async_run_job_encerramento_parcial_spec`. **#402 fica como risco aceito** — ver "O que ficou de fora" |
| R5 | `CLOSED_KEY` passa a ser gravada em todo desfecho por falha | qualquer leitor que itere o handle vê chave nova | `MARCAS` já a inclui e `handle_da_ferramenta` a remove, então a ferramenta não a vê. Os três exemplos de `async_run_job_intencao_de_envio_spec` que passaram a usar `.except(encerrada, fechada)` são a prova de que só o teste a enxergava |
| R6 | mudança de aridade de `closing_deliveries` para `(handle, trabalho_novo:)` | uma ferramenta com a aridade velha levantaria `ArgumentError` dentro de `etapa('entregas')` e viraria log silencioso | só há dois implementadores (`Native::Base` e `InsuranceQuote::Fecho`), e os dois mudam juntos. `base_contrato_de_nivel_spec` percorre `Registry.all` |
| R7 | `Base#initialize` ganha dois kwargs | uma ferramenta que sobrescrevesse `initialize` quebraria | nenhuma nativa sobrescreve. Provado sobre o catálogo inteiro pelo exemplo novo `'toda ferramenta do catalogo aceita ser montada com a conversa e a linha da execucao'` |
| R8 | `Comparativo.sufixo_do_arquivo` — um `NameError` seria engolido pelo `rescue` de `comparison_pdf` e o comparativo sumiria em silêncio (já aconteceu uma vez no ramo) | perda silenciosa do comparativo em `cotar_seguro` | **mitigado por exclusão**: `comparativo.rb` não entra nesta PR. O arquivo está idêntico à `main` |
| R9 | o encerramento adquire `closed` ANTES de qualquer publicação | se a marca já existir, o cliente não recebe palavra nenhuma — onde antes recebia a frase de falha | só chegam aqui `fail_run` (que faz `finish!` logo depois, tornando a linha terminal) e o varredor (que só varre `running`). O comportamento está travado em `encerramento_spec`, `'a segunda passada na mesma linha nao adquire a marca e nao publica nada'` |
| R10 | o lote de entregas sem isolamento por entrega | perde a publicação bem-sucedida e nega o que já saiu | corrigido nesta PR; ver o defeito 2 |

## Validação (números)

Ambiente: `PATH="$HOME/.rbenv/shims:$PATH"` — sem isso `bundle` resolve para `/usr/bin/bundle` e
rspec/rubocop "passam" sem executar nada. Todo exit code abaixo foi lido de `${pipestatus[1]}`.

- Foco: `bundle exec rspec spec/jobs/autonomia/agents/tools/ spec/services/autonomia/agents/tools/
  spec/models/autonomia/agents/tool_run_spec.rb` → **486 examples, 0 failures, exit 0**.
- `bundle exec rubocop` nos 18 arquivos `.rb` do diff → **0 ofensas, exit 0**.
- CI da PR #406 no SHA `b68832d622`: **12 de 12 checks verdes**, incluindo os oito nós de RSpec.
- **Partições do CI.** O CI fatia por `find spec -name '*_spec.rb' | sort` com `i % 8`. Com
  `encerramento_spec.rb` entrando na lista ordenada, os arquivos tocados caem nos nós
  **1, 3, 4, 5, 6 e 7** — e a composição de cada nó MUDA em relação à `main`, porque um arquivo
  novo desloca todos os índices seguintes. Por isso o baseline foi rodado com a MESMA lista de
  arquivos, no worktree da `origin/main`:

  | nó | ramo 8a | `origin/main`, mesma lista |
  |---|---|---|
  | 1 | 1365 ex, **0 falhas**, 12 pending — exit 0 | 1363 ex, 0 falhas, 12 pending — exit 0 |
  | 3 | 1163 ex, **0 falhas**, 36 pending — exit 0 | — |
  | 4 | 1333 ex, **0 falhas**, 2 pending — exit 0 | — |
  | 5 | 1272 ex, **0 falhas**, 18 pending — exit 0 | — |
  | 6 | 1607 ex, **0 falhas**, 18 pending — exit 0 | — |
  | 7 | 1739 ex, **4 falhas**, 34 pending — exit 1 | 1736 ex, **as MESMAS 4 falhas**, 34 pending — exit 1 |

  As diferenças de contagem são exatamente os exemplos novos (+2 no nó 1, +3 no nó 7).

- **As 4 falhas do nó 7 são pré-existentes** e idênticas na `main`: os quatro exemplos de
  `spec/services/autonomia/agents/tools/entrega_de_arquivo_spec.rb` (`:111`, `:286`, `:321`,
  `:346`), todos de download/socket/armazenamento. Esta PR não toca esse arquivo nem
  `EntregaDeArquivo`.

- **Armadilha de ambiente, registrada porque custou uma investigação.** A primeira passada rodou no
  `chatwoot_test` compartilhado entre os worktrees deste repositório e deu 12 falhas espalhadas
  (`data_imports`, `campaign_imports`, `responder`, `whatsapp_api_campaigns`). Nenhuma reproduzia
  isolada. Causa: vários exemplos assertam `ActiveStorage::Blob.count == 0` GLOBALMENTE, e uma
  passada anterior que morreu no meio deixa blobs no banco. Num banco de teste criado do zero
  (`db:schema:load`), o mesmo nó 1 deu 0 falhas. Todos os números acima são do banco limpo. Quem
  for validar de novo: crie um banco próprio (`POSTGRES_DATABASE=…` + `rake db:create
  db:schema:load`) em vez de usar o `chatwoot_test` compartilhado.

## Mutações (aplicar → conferir que o md5 mudou → rodar o alvo → restaurar → conferir o md5)

Todas com `BOOTSNAP_CACHE_DIR` próprio, para o cache de ISeq não devolver a versão antiga.

| # | âncora | mutação | alvo | resultado |
|---|---|---|---|---|
| M1 | `insurance_quote/fecho.rb` `resta_entregar?` | `!handle.to_h[PDF_SENT_KEY]` → `true` (a premissa antiga) | `insurance_quote_ramo_auto_spec` + `async_run_job_encerramento_parcial_spec` | **3 falhas** — a unidade e as DUAS portas do caminho real; a saída do teste imprime a frase falsa literal |
| M2 | `encerramento.rb` `entregar_o_que_resta` | volta o `.map { publicar }` dentro do `etapa` (sem `rescue` por entrega) | `encerramento_spec` | **2 falhas** |
| M3 | `encerramento.rb` `entregar_o_que_resta` | `count { }.positive?` → `any? { }` (curto-circuito) | `encerramento_spec` | **1 falha** — a primeira passada deste mutante SOBREVIVEU, e foi o que obrigou a escrever `'publica todas as entregas do encerramento, e nao para na primeira'` |
| M4 | `insurance_quote/fecho.rb` `closing_deliveries` | remove `return [] unless trabalho_novo` | `insurance_quote_ramo_auto_spec` + `async_run_job_encerramento_parcial_spec` | **2 falhas** — uma delas é o WebMock barrando a chamada ao portal que o varredor não deve fazer |
| M5 | `reap_stale_runs_job.rb` | `trabalho_novo: false` → `true` | `reap_stale_runs_job_spec` + `async_run_job_encerramento_parcial_spec` | **2 falhas** |
| M6 | `insurance_quote/comparativo.rb` (arquivo NÃO tocado por esta PR) | remove `return if Array(handle[DELIVERED_KEY]).empty?` | `async_run_job_encerramento_parcial_spec` | **1 falha** — prova que a não-regressão R1 é exercitada de verdade, e não só afirmada |
| M7 | `encerramento.rb` `parcial` | `resultado_entregue? && resta_entregar?` → `||` | `encerramento_spec` + `reap_stale_runs_job_spec` | **3 falhas** |

Todos os arquivos voltaram ao md5 de antes; `comparativo.rb` está sem diff contra a `main`.

## O que ficou de fora, e por quê

- **A ferramenta `proposta_da_seguradora` inteira** (7 arquivos de app, 13 de spec) — é a 8b. Ela é
  o motivo do fatiamento: o CEO decidiu reescrevê-la sobre máquina de estados, então o diff da 8b
  não é o da #399.
- **Os quatro ganchos de DECISÃO sem implementador** — `confirmar_publicadas`, `publicavel?`,
  `entrega_do_token` e `argumentos`. Nenhum tem quem os sobrescreva hoje, e dois deles pesam: o
  `publicavel?` liga `AutorizacaoDaExecucao#ferramenta_publicaria?`, que remonta a ferramenta via
  `Registry.find` **a cada publicação, sob o lock da conversa**; o `entrega_do_token` acrescenta um
  caminho novo de exceção ao reenvio de mensagem pendente. Capacidade sem consumidor é custo puro.
- **O passo "anotar" do encerramento.** No ramo, o encerramento tinha QUATRO passos, e o terceiro
  chamava `confirmar_publicadas`. Como o gancho fica na 8b, o passo ficou junto — a alternativa era
  declarar um gancho no-op só para que a chamada não levantasse, e o cabeçalho documentar um passo
  que não faz nada para ninguém. **Isto é uma divergência consciente do plano de corte**, que
  mandava `encerramento.rb` inteiro E classificava `confirmar_publicadas` como ferramenta: os dois
  não cabiam juntos. A 8b acrescenta o gancho, o passo e o exemplo — uma adição, não uma
  reconciliação de hunks.
- **`ToolRun` e `ToolRunPromocao`.** A 8a **não toca o model**. `DEAD_STATUSES` só tem leitor na
  proposta, `anotar_propostas!` é da proposta, e o teto de idade da promoção (`PROMOCAO_ATE`)
  carrega um P1 aberto: `recusar_promocao_tardia!` devolve `false`, o dispatcher só não conta a
  linha, e o cliente — que já leu o `accepted_message` na mesma resposta — fica sem nada. Levar o
  teto sem leitor seria embarcar esse defeito de graça. A 8b o traz **já com a saída para o
  cliente**.
- **`Comparativo.sufixo_do_arquivo`** — existe para a proposta, e mexer em `nome_do_comparativo` é
  risco puro em `cotar_seguro` (ver R8).
- **Issue #402 (`deferred` reemite e infla `delivered_count`)** — não é desta PR e continua aberta.
  Fica como risco aceito: hoje o contador só decide o fecho quando NENHUMA entrega do encerramento
  foi aceita, e os exemplos travam a magnitude exata, não `be_positive`. O cenário em que ele
  mudaria a frase é uma execução cujo único item entregue foi reemitido e cuja ferramenta responde
  "houve resultado" — nenhuma o faz hoje.
- **A rodada real na conta 16.** Nenhuma das seis rodadas da #399 rodou contra o portal, e esta
  também não rodou. **Isto é uma lacuna, não uma pendência de forma.** Antes do merge, na conta 16:
  (1) cotação feliz completa — preços, comparativo, **nenhuma frase parcial**; (2) sem preço nenhum
  com prazo estourado — frase de falha e **zero** chamadas a `quote_proposal` no log do adapter;
  (3) o cenário do defeito 1 — deixar o portal fechar e matar o worker entre o `record_attempt!` e
  o `finish!('done')`, esperando **silêncio** no fecho. Evidência a coletar em cada uma: `run.id`,
  `status`, `failure_code`, `delivered_count`, o `handle` (com `entregues`, `comparativo_enviado`,
  `autonomia_closed`), as mensagens `AgentBot` em ordem, e as linhas `[autonomia][tool]` do log.

## Rollback

Não há migration. Rollback = `git revert -m 1 <sha do merge>` + o deploy padrão do projeto, ou
redeploy da imagem anterior pelo SHA anotado antes do merge. O comando de deploy do chat2you vem do
runbook de produção do repo/host; o que esta entrega garante é que o rollback é **só código**.

**Único efeito persistente:** chaves `autonomia_closed` gravadas no `handle` de execuções encerradas
durante a janela. São inertes no rollback — o código antigo lê a mesma chave pelo mesmo
`merge_handle!(ausente:)`, e as linhas afetadas já estão em estado terminal. Sem PII, sem cleanup.

## Ordem

8a em produção → rodada real na conta 16 → só então abrir a 8b.
