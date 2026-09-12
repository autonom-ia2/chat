# Entrega 8a — o motor do encerramento assíncrono (sem a ferramenta da proposta)

Data: 12/09/2026 (rodada 1) e 12/09/2026 (rodada 2, depois da revisão). Issue: #396 (Part of
#291). Branch `feat/entrega-8a-motor-assincrono`, **rebaseada sobre `origin/main` `8bcafb0570`**
(era `261d7bb086`; a #405 entrou no meio — ver "Rodada 2", item 6). **Zero migration.** Sem merge,
sem produção.

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
`Tools::Encerramento` adquire a marca `closed` (que guarda o TRABALHO, não a palavra ao cliente),
pergunta à ferramenta o que ainda vale entregar, publica, e só então publica um fecho que **só
afirma o que chegou de fato ao cliente** — a pergunta é pela MENSAGEM na conversa, nunca pelo
handle, que é a intenção de quem publicou.

## Por que o motor entra sozinho

A cotação (`cotar_seguro`) está em produção e atravessa TODO o código que esta PR move. Cada
caminho que muda é, primeiro, um risco de regressão dela — e é por isso que o corte existe: um
motor pequeno, com a não-regressão provável linha a linha, vale mais que uma PR de 5.250 linhas em
que o motor e a ferramenta se escondem um atrás do outro.

## O que mudou (por commit)

**`c08122d040`** (era `c25e1e2e29`) `refactor(tool): a identidade da entrega publicada vira módulo`
- `Tools::EntregaPublicada.para(conversation, token)` — extração do método privado
  `AsyncPublisher#entrega_publicada`. Mesma consulta, mesmo `LIKE` como peneira, mesma comparação
  exata do atributo, mesmo e único chamador (na rodada 1).
- **Não é "zero comportamento", e a rodada 1 afirmou que era** (P3-5 do verificador cego): o módulo
  acrescentou `return nil if conversation.blank? || token.blank?`, que o método privado não tinha.
  Hoje é inerte — o chamador só entra com os dois presentes —, e na verdade fecha um latente: com
  token `''` (string vazia), o `LIKE '%%'` casava QUALQUER mensagem do bot e a comparação exata
  passava em toda mensagem SEM a chave (`nil.to_s == ''`), devolvendo uma mensagem alheia como "a
  entrega já publicada"; e com `conversation` nil era `NoMethodError`. Guarda, não refatoração
  pura.
- Ficou de fora o `existe?` do ramo original: não tem chamador no motor. Quem o usa é a 8b.

**`097a847119`** (era `8b6b1b7832`) `feat(tool): o encerramento é um só, e cada passo cai sozinho`
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

**`cc736ecf5c`** (era `d15f6dd14b`) `fix(cotacao): o fecho da cotação só afirma o que é verdade`
- `InsuranceQuote::Fecho` (novo): as três respostas da cotação ao encerramento saem da classe (que
  está no teto de linhas) para um módulo, como `Comparativo`, `Declaracao`, `Recusas`, `Envio` e
  `Veiculo`.
- `closing_deliveries` devolve `[]` sem `trabalho_novo`; `resultado_entregue?` é preço publicado
  (`entregues`), nunca o `pedido`; `resta_entregar?` **corrigido** (ver abaixo).

## Rodada 2 — o que a revisão derrubou, e o que passou a valer

A rodada 1 foi reprovada pelo Codex e pelo verificador cego, que convergiram no MESMO erro por
portas diferentes: **o fecho decidia pela INTENÇÃO registrada no handle, não pelo FATO de a
mensagem ter saído** — exatamente o contrário do que o cabeçalho do módulo que esta PR criou
(`entrega_publicada.rb`) diz com todas as letras.

**`9dcfeb62d3`** `fix(tool): a marca de encerramento não cala mais o cliente`
**`78ee5e6943`** `fix(cotacao): o fecho decide pela mensagem que chegou, não pelo handle`
**`da3f5336a0`** `test(cotacao): a corrente inteira, da consulta ao fecho, pelo caminho real`

### 1. Os predicados do fecho passam a olhar o FATO (P1 do verificador, P2 do Codex)

O estado, reproduzível e alcançável hoje: `handle['entregues'] = ['4']` com `delivered_count == 0`.
`deliver` roda ANTES de `record_attempt!` (é o que o comentário de `AVISO_SENT_KEY` já documentava),
então uma publicação recusada avança o handle com os códigos das ofertas sem que mensagem nenhuma
tenha entrado. Nesse estado a rodada 1 entregava o comparativo em PDF **mais** a frase "algumas
seguradoras não responderam a tempo, os preços acima são os que chegaram" — sem preço nenhum acima
— e ainda fazia uma chamada nova ao portal (login + até 60 s) para produzir o PDF. Na `main`, o
mesmo estado lia a frase honesta de falha.

Pelo outro lado, `PDF_SENT_KEY` prova que a leitura foi terminal e que o comparativo foi GERADO,
nunca que ele chegou: portal `completed` com geração sem URL não grava a chave (e a frase de atraso
saía para quem já tinha tudo), e publicação `blocked` grava (e o fecho calava sobre um comparativo
que faltou).

Correção, em três peças:

1. **A identidade de uma entrega vira uma definição só** — `EntregaPublicada.token_de(run, entrega)`
   (arquivo pela `identidade`, texto pelo texto aparado), usada pelo publicador E por quem pergunta.
   Duas definições divergiriam, e a pergunta passaria a ser sobre uma mensagem que nunca existiu.
2. **A passada que EMITE grava a identidade no handle** — `entregas_de_preco` (acumula, um token por
   lote de preços) e `entrega_do_comparativo`. O handle continua sendo a intenção: ele diz o que
   PROCURAR; quem responde é a conversa.
3. **Os predicados perguntam ao banco** — `resultado_entregue?` é "algum token de preço virou
   mensagem"; `resta_entregar?` é "o portal não fechou, ou o comparativo emitido não chegou". E
   `closing_deliveries` passa pela mesma pergunta: não se pede comparativo ao portal para quem não
   tem preço na tela.

O fechamento do portal passa a se gravar por si (`portal_fechado`, no ramo `done` de
`build_progress`, independente do PDF) em vez de ser deduzido de `comparativo_enviado` — que
continua sendo lido como prova do fechamento, e só para isso, pelas execuções que atravessarem o
deploy (ver R11).

**O que prova:** `insurance_quote_ramo_auto_spec`, bloco `'o fecho e o que ainda vale entregar'`
(dez exemplos, com a ferramenta montada como o motor a monta e a mensagem criada na conversa); e
pelo caminho real, `async_run_job_encerramento_parcial_spec`, `'a cotacao cujo preco nunca chegou ao
cliente fecha com a frase de falha, e nao pede comparativo'` e `'a consulta grava a identidade do
preco que publicou, e o fecho a usa'`. Mutações M11 a M17.

### 2. A marca de encerramento para de impedir o fecho (P1 do Codex, P2-1 do verificador)

A marca `closed` passou, na rodada 1, a ser adquirida também quando o contador é zero — caminho que
na `main` não a adquiria. Morto o processo entre adquirir a marca e publicar a frase (deploy, com
25 s de shutdown; a janela chega a 60 s no estado do item 1, porque ali o passo das entregas chama o
portal), nem o retry do Sidekiq nem o varredor tentavam de novo: o cliente ficava sem resultado e
sem desfecho, para sempre.

Correção: a marca guarda o TRABALHO, não a palavra. O fecho ficou idempotente como as entregas já
eram — ele pergunta à conversa se alguma das três frases desta execução já está lá
(`FRASES_DE_FECHO`, pela identidade de cada uma) e só publica o que falta. A pergunta é por TODAS as
frases porque duas passadas escolhem textos DIFERENTES (a segunda não refaz as entregas, então lê
`entregou` como falso), e aí a dedupe por token do publicador não salvaria: seriam duas mensagens,
uma contradizendo a outra.

**O que prova:** `encerramento_spec` — `'marca posta e fecho ausente: a passada seguinte fecha, e
nao refaz o trabalho'`, `'a segunda passada na mesma linha nao repete o fecho que ja saiu'` e `'a
passada seguinte nao contradiz o fecho que ja saiu'`. Mutações M9 e M10.

### 3. O mutante que sobrevivia em `publicar_uma` (P2-2 do verificador)

Trocar `resultado.published? || resultado.deferred?` por `true` não derrubava exemplo nenhum.
Faltava o caso: entrega do encerramento RECUSADA pelo publicador (`blocked` — ele não levanta,
devolve) não conta como entregue, e o fecho é o da falha. Exemplo novo em `encerramento_spec`;
mutação M8 agora reprova.

### 4. `agente_indisponivel`: decisão declarada (P3-1)

Com o agente ausente e o contador positivo, a `main` publicava a frase parcial (por
`delivered_count` sozinho) e a rodada 1 passou a calar, sem exemplo. **Decisão: fica o silêncio,
declarado e testado.** Sem agente não há ferramenta a quem perguntar se houve RESULTADO e se SOBROU
algo, e a frase afirma as duas coisas; `partial_message` continua de classe (entrega 4), o que mudou
é que ela precisa ser verdade.

E o que se perde já era recusado: apagado o agente, `agent_inboxes` cai com ele
(`dependent: :destroy`), `Operate.authorized_agent_inbox` não acha vínculo e o publicador recusa
tudo. O exemplo novo em `async_run_job_spec` (`'com o agente apagado, fecha em silencio — e nem a
frase da main chegaria'`) afirma as duas coisas na mesma corrida: o silêncio, e que uma publicação
qualquer daquela execução volta `blocked`.

### 5. `conversation:` e `run:` deixam de ser capacidade sem consumidor (P3-2)

Na rodada 1, removê-los do `AsyncRunJob#ferramenta` não derrubava exemplo nenhum — e a rodada 2
começou repetindo isso (M16 SOBREVIVEU na primeira passada). Agora eles são o que permite à
ferramenta montar a identidade da entrega e perguntar ao banco, e o exemplo novo `'a consulta grava
a identidade do preco que publicou, e o fecho a usa'` fecha o buraco: M16 reprova. Não é mais dívida.

### 6. Os textos que afirmavam o que não acontece (P3-3 e P3-5)

- O cabeçalho de `encerramento.rb` e o de `ReapStaleRunsJob#encerrar` diziam que o varredor passa a
  entregar "o arquivo pronto parado no handle". **Para a cotação isso nunca ocorre**: com
  `trabalho_novo: false` o `closing_deliveries` dela devolve `[]`, sempre, porque o comparativo só
  existe depois de uma chamada ao portal. Corrigido: a única mudança real do varredor hoje é a
  frase; o caminho da entrega existe para a ferramenta da 8b.
- A afirmação de "zero comportamento" na extração do `EntregaPublicada` está corrigida no item do
  commit (acima).
- O "CI verde" da rodada 1 era do HEAD do momento (`b68832d622`), não do commit citado ao lado de
  cada item. Os números desta rodada estão em "Validação", com o SHA exato.

### 7. Conflito com a `main` (P3-4)

A #405 foi mergeada e corrigiu o MESMO `spec/controllers/slack_uploads_controller_spec.rb`. O ramo
foi **rebaseado sobre `origin/main` `8bcafb0570`** e o commit desta PR (`b68832d622`) foi
DESCARTADO: fica a versão da `main`. O arquivo não aparece mais no diff da PR.

Durante esta rodada a `main` andou de novo (`356333935b`, #408 — documento de terceiro vai ao
especialista). Ela toca só `quote_agent/instrucoes/principal.md` e o spec de promessas dele:
**zero interseção** com o diff desta PR, e por isso o ramo foi deixado em `8bcafb0570` — os
números de validação abaixo são todos dessa base.

## Os dois defeitos que a RODADA 1 corrigiu antes de entrar

(Histórico. O item 1 abaixo foi superado pela rodada 2 — ver a nota no fim dele.)

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

Correção da rodada 1: `!handle.to_h[self.class::PDF_SENT_KEY]`. A chave sobrevive ao corte das
marcas do motor (`AsyncRunJob::MARCAS` não a lista), então chega à ferramenta pelo handle que o
encerramento entrega.

> **Superada na rodada 2.** `comparativo_enviado` prova que o comparativo foi GERADO, não que
> chegou — e não prova o fechamento do portal quando a geração não produziu URL. Hoje quem responde
> é `portal_fechado` mais a identidade da mensagem do comparativo; a chave antiga segue sendo lida
> só como prova de fechamento, e só pelas execuções que atravessam o deploy. Ver "Rodada 2", item 1.

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
| R2 | o varredor passa a chamar a ferramenta | até `BATCH_LIMIT` linhas em sequência num cron × login + chamada de até 60 s; um deploy no meio mata o lote e joga o resto das linhas para a varredura seguinte, 10 min depois (na rodada 1 era pior: elas ficavam com `closed` e sem fecho, para sempre — ver "Rodada 2", item 2) | `trabalho_novo: false` no varredor + `return [] unless trabalho_novo` no fecho da cotação. `reap_stale_runs_job_spec`, `'diz a ferramenta que nao pode comecar trabalho novo, e entrega so o que ja esta pronto'`; e pelo caminho real, `async_run_job_encerramento_parcial_spec`, `'o varredor fecha a cotacao abandonada sem pedir o comparativo ao portal'` (mutações M4 e M5) |
| R3 | **mudança de frase visível ao cliente**: o varredor antes só falava com `delivered_count.zero?`; agora fecha sempre | quem já recebeu preço e era fechado em silêncio passa a receber a frase parcial | é intencional e está travado em `async_run_job_intencao_de_envio_spec` (`'recarrega antes de decidir…'`, que mudou de `bot_contents` vazio para `[tool.partial_message]`) e em `reap_stale_runs_job_spec` (`'fecha com a frase parcial…'`). **É aqui que o defeito 1 mordia**: sem a correção, a frase saía também para quem recebeu tudo |
| R4 | `delivered_count` pode estar inflado (issue #402: `deferred` reemite e o contador sobe) | contador inflado mudaria o que o cliente lê no fecho | o contador só é consultado quando `entregou` é falso, e a magnitude está travada (`delivered_count: 1`, não `be_positive`) em `async_run_job_intencao_de_envio_spec` e em `async_run_job_encerramento_parcial_spec`. **#402 fica como risco aceito** — ver "O que ficou de fora" |
| R5 | `CLOSED_KEY` passa a ser gravada em todo desfecho por falha | qualquer leitor que itere o handle vê chave nova | `MARCAS` já a inclui e `handle_da_ferramenta` a remove, então a ferramenta não a vê. Os três exemplos de `async_run_job_intencao_de_envio_spec` que passaram a usar `.except(encerrada, fechada)` são a prova de que só o teste a enxergava |
| R6 | mudança de aridade de `closing_deliveries` para `(handle, trabalho_novo:)` | uma ferramenta com a aridade velha levantaria `ArgumentError` dentro de `etapa('entregas')` e viraria log silencioso | só há dois implementadores (`Native::Base` e `InsuranceQuote::Fecho`), e os dois mudam juntos. `base_contrato_de_nivel_spec` percorre `Registry.all` |
| R7 | `Base#initialize` ganha dois kwargs | uma ferramenta que sobrescrevesse `initialize` quebraria | nenhuma nativa sobrescreve. Provado sobre o catálogo inteiro pelo exemplo novo `'toda ferramenta do catalogo aceita ser montada com a conversa e a linha da execucao'` |
| R8 | `Comparativo.sufixo_do_arquivo` — um `NameError` seria engolido pelo `rescue` de `comparison_pdf` e o comparativo sumiria em silêncio (já aconteceu uma vez no ramo) | perda silenciosa do comparativo em `cotar_seguro` | **mitigado por exclusão**: `comparativo.rb` não entra nesta PR. O arquivo está idêntico à `main` |
| R9 | o encerramento adquire `closed` ANTES de qualquer publicação | se a marca já existir, o cliente não recebe palavra nenhuma — onde antes recebia a frase de falha | **era risco real e virou defeito: corrigido na rodada 2** (item 2). A marca guarda o trabalho; o fecho pergunta à conversa se já saiu e publica o que falta. `encerramento_spec`, `'marca posta e fecho ausente: a passada seguinte fecha, e nao refaz o trabalho'` e `'a passada seguinte nao contradiz o fecho que ja saiu'` (mutações M9 e M10) |
| R10 | o lote de entregas sem isolamento por entrega | perde a publicação bem-sucedida e nega o que já saiu | corrigido nesta PR; ver o defeito 2 |
| R11 | **janela do deploy**: execução `running` que atravessa o deploy não tem `entregas_de_preco` no handle (a chave nasce na passada que emite o preço) | o fecho dela lê "nenhum preço chegou": fecha em SILÊNCIO onde fecharia com a parcial, e não oferece o comparativo no encerramento | **risco aceito, declarado**. A janela é o tempo de vida de uma execução (prazo + `GRACE` do varredor, ordem de minutos) e o erro é para o lado conservador: o cliente fica com os preços que já leu, e nada falso é dito. A alternativa — cair para `entregues` quando a chave falta — reintroduziria a frase falsa do P1 para essa mesma janela. `comparativo_enviado` continua sendo lido como prova do fechamento do portal justamente para essa janela (`portal_fechado?`), e isso está travado em `'aceita o comparativo_enviado como prova do fechamento nas linhas que atravessam o deploy'` |
| R12 | a frase parcial passa a exigir a FERRAMENTA montada (agente vivo) | `agente_indisponivel` com contador positivo lia a frase na `main` e agora cala | decisão declarada, com exemplo — ver "Rodada 2", item 4. O publicador recusa qualquer mensagem dessa execução, então o cliente não perde nada que recebesse |
| R13 | o handle da cotação ganha três chaves (`entregas_de_preco`, `entrega_do_comparativo`, `portal_fechado`) | leitor que itere o handle vê chaves novas; a coluna cresce | são da FERRAMENTA (não entram em `AsyncRunJob::MARCAS`) e nenhum leitor itera o handle — os consumidores são `Fecho` e `Comparativo`, por chave. Tamanho: dois tokens de 53 bytes e um booleano por execução |
| R14 | `AsyncPublisher` passa a montar o token por `EntregaPublicada.token_de` | um token diferente do de antes republicaria mensagem já publicada | é a MESMA conta (`run.delivery_token` sobre a `identidade` do arquivo ou o texto aparado), agora em um lugar só; `async_run_job_comparativo_arquivo_spec` e `async_publisher_spec` exercitam os dois caminhos, inclusive o retry que não republica |

## Validação (números)

Ambiente: `PATH="$HOME/.rbenv/shims:$PATH"` — sem isso `bundle` resolve para `/usr/bin/bundle` e
rspec/rubocop "passam" sem executar nada. Todo exit code abaixo foi lido de `${pipestatus[1]}`.
Banco de teste PRÓPRIO (`chatwoot_test_8a_base`, criado com `db:schema:load`), nunca o
`chatwoot_test` compartilhado entre os worktrees deste repositório — ver a armadilha no fim.

### Rodada 2 (a que vale)

- Foco: `bundle exec rspec spec/jobs/autonomia/agents/tools/ spec/services/autonomia/agents/tools/
  spec/models/autonomia/agents/tool_run_spec.rb` → **497 examples, 0 failures, exit 0**
  (486 na rodada 1; +11 exemplos novos).
- Área inteira: `bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`
  → **1167 examples, 0 failures, 3 pending, exit 0**.
- `bundle exec rubocop` na lista EXPLÍCITA dos 19 arquivos `.rb` do diff → **0 ofensas, exit 0**.
  Duas ofensas apareceram no caminho e foram corrigidas, não silenciadas: `Metrics/AbcSize` em
  `build_progress` (28.62/26 — extraído o método `fechar`) e `RSpec/ContextWording` no bloco novo
  do spec de auto (virou `describe`).
- **Partições do CI** (`find spec -name '*_spec.rb' | sort`, `i % 8`). Com os arquivos desta PR, os
  tocados caem nos nós **1 a 7** (o nó 2 entrou nesta rodada, com
  `async_run_job_comparativo_arquivo_spec`). Todos rodados aqui, na íntegra:

  | nó | arquivos | rodada 2 | rodada 1 (para contraste) |
  |---|---|---|---|
  | 1 | 141 | 1ª passada: 1365 ex, 10 falhas — exit 1 (causa abaixo); repetição limpa: 1365 ex, **0 falhas**, 12 pending — exit 0 | 1365 ex, 0 falhas, 12 pending |
  | 2 | 141 | 1188 ex, **0 falhas**, 3 pending — exit 0 | não rodado (o nó não era tocado) |
  | 3 | 141 | 1165 ex, **0 falhas**, 36 pending — exit 0 | 1163 ex, 0 falhas |
  | 4 | 141 | 1333 ex, **0 falhas**, 2 pending — exit 0 | 1333 ex, 0 falhas |
  | 5 | 141 | 1273 ex, **0 falhas**, 18 pending — exit 0 | 1272 ex, 0 falhas |
  | 6 | 141 | 1610 ex, **0 falhas**, 18 pending — exit 0 | 1607 ex, 0 falhas |
  | 7 | 141 | 1744 ex, **0 falhas**, 34 pending — exit 0 | 1739 ex, **4 falhas** tidas como pré-existentes |

  As diferenças de contagem são exatamente os exemplos novos: +2 no nó 3 (caminho real do fecho),
  +1 no nó 5 (`agente_indisponivel`), +3 no nó 6 (encerramento) e +5 no nó 7 (o bloco do fecho no
  spec de auto). **E as 4 falhas do nó 7 da rodada 1 não existem aqui**: eram do
  `entrega_de_arquivo_spec` (download/socket/armazenamento), e no banco próprio desta rodada o nó
  fechou em 0 — mais uma razão para não tratar aquele número como "pré-existente e pronto".

- **A primeira passada do nó 1 deu 10 falhas, e a causa não era o código.** `config.cache_classes =
  false` no ambiente de teste: eu editei arquivos de `app/` (correções de comentário) ENQUANTO o nó
  1 rodava, e o `data_imports_spec` — que é um request spec e vem logo antes do `responder_spec` na
  lista do nó — disparou o recarregamento do Rails no meio da corrida. As vítimas foram
  `responder_spec` (`:silenced` onde esperava `:replied`), `campaign_imports/validator_spec` e
  `whatsapp_api_campaigns/audience_resolver_spec` (`uninitialized constant …::Parser`,
  `…::CsvSanitizer` — Zeitwerk com o autoloader trocado sob os pés). O banco estava LIMPO nas duas
  passadas (`active_storage_blobs = 0`, `accounts = 0`), o que também descarta a explicação da
  rodada 1 para o mesmo conjunto de falhas. Repetido sem edição concorrente: **1365 ex, 0 falhas, 12 pending — exit 0**, exatamente o número da rodada 1.
  **Regra para a próxima rodada: nenhuma escrita em `app/` ou `spec/` enquanto uma partição roda.**

### Rodada 1 (histórico)

- Foco: 486 examples, 0 failures, exit 0. `rubocop` nos 18 arquivos: 0 ofensas.
- CI da PR #406 verde no HEAD de então (`b68832d622`): 12 de 12 checks. **O texto da rodada 1
  atribuía esse verde ao commit citado em cada item, e isso estava errado** (P3-5): o CI roda no
  HEAD da PR, não em cada commit.

- **Armadilha de ambiente (rodada 1), mantida porque continua valendo em parte.** A primeira
  passada da rodada 1 rodou no `chatwoot_test` compartilhado e deu 12 falhas espalhadas
  (`data_imports`, `campaign_imports`, `responder`, `whatsapp_api_campaigns`) — o MESMO conjunto
  que a rodada 2 reproduziu com o banco limpo e edição concorrente. A conclusão de então (blobs
  vazados de uma passada morta) explicava as asserções `ActiveStorage::Blob.count == 0`, mas não
  os `NameError` de Zeitwerk: **as duas causas existem**, e a segunda é a de agora. Use banco
  próprio E não mexa nos arquivos durante a corrida.

## Mutações (aplicar → conferir que o md5 mudou → rodar o alvo → restaurar → conferir o md5)

Todas com `BOOTSNAP_CACHE_DIR` próprio, para o cache de ISeq não devolver a versão antiga.

### Rodada 1

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

**As âncoras de M1 e M4 mudaram na rodada 2** (`resta_entregar?` e `closing_deliveries` foram
reescritos): quem as substitui são M11, M12 e M13.

### Rodada 2

| # | âncora | mutação | alvo | resultado |
|---|---|---|---|---|
| M8 | `encerramento.rb` `publicar_uma` | `resultado.published? \|\| resultado.deferred?` → `true` | `encerramento_spec` | **1 falha** — `'a entrega recusada pelo publicador nao conta, e o fecho e o da falha'`. **Este mutante SOBREVIVIA na rodada 1** (P2-2 do verificador): o exemplo é novo |
| M9 | `encerramento.rb` `encerrar` | volta `return false unless adquiriu_o_trabalho?` (a marca calando a passada inteira) | `encerramento_spec` | **1 falha** — `'marca posta e fecho ausente: a passada seguinte fecha, e nao refaz o trabalho'` |
| M10 | `encerramento.rb` `publicar_fecho` | remove `return if fecho_publicado?` | `encerramento_spec` | **1 falha** — `'a passada seguinte nao contradiz o fecho que ja saiu'` (a dedupe por token NÃO pega: são textos diferentes) |
| M11 | `insurance_quote/fecho.rb` `resultado_entregue?` | volta a perguntar ao handle (`Array(handle[DELIVERED_KEY]).any?`) | `insurance_quote_ramo_auto_spec` + `async_run_job_encerramento_parcial_spec` + os dois de comparativo | **3 falhas** — a unidade, o `closing_deliveries` e o caminho real do P1 |
| M12 | `insurance_quote/fecho.rb` `resta_entregar?` | volta a `!handle[PDF_SENT_KEY]` (a resposta da rodada 1) | idem | **3 falhas** — os dois estados falsos do Codex mais o portal fechado sem comparativo |
| M13 | `insurance_quote/fecho.rb` `closing_deliveries` | remove `return [] unless resultado_entregue?(handle)` | idem | **2 falhas** — uma delas é o caminho real: o portal seria chamado e o cliente receberia o link de reserva no lugar da frase de falha |
| M14 | `insurance_quote.rb` `registrar_entrega_de_preco` | não grava o token do preço | idem | **1 falha** — `'grava a identidade do preco e do comparativo que emitiu'` |
| M15 | `insurance_quote.rb` `build_progress` | remove `FECHADO_KEY => true` | idem | **2 falhas** |
| M16 | `async_run_job.rb` `ferramenta` | remove `conversation:` e `run:` (a capacidade sem consumidor do P3-2) | `async_run_job_encerramento_parcial_spec` + `async_run_job_comparativo_arquivo_spec` + `base_contrato_de_nivel_spec` | **SOBREVIVEU na primeira passada** (23 exemplos, 0 falhas). Com o exemplo novo `'a consulta grava a identidade do preco que publicou, e o fecho a usa'`: **1 falha** |
| M17 | `encerramento.rb` `montar` | remove `conversation:` e `run:` na ferramenta do encerramento | `async_run_job_encerramento_parcial_spec` + `encerramento_spec` | **3 falhas** |

Método idêntico ao da rodada 1 (`BOOTSNAP_CACHE_DIR` próprio; md5 conferido antes, depois da
mutação e depois da restauração — igual ao de antes nas dez). Uma armadilha registrada porque
custou trabalho: `git checkout -- <arquivo>` para restaurar a mutação **apaga a alteração não
commitada** do arquivo. As mutações desta rodada rodaram com cópia de segurança
(`cp` + `trap`), e só depois de os commits estarem feitos.

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
  o `finish!('done')`, esperando **silêncio** no fecho; (4) NOVO na rodada 2 — conferir no handle de
  uma execução real que `entregas_de_preco` tem um token por mensagem de preço publicada e que
  `portal_fechado` aparece quando o portal fecha. Evidência a coletar em cada uma: `run.id`,
  `status`, `failure_code`, `delivered_count`, o `handle` (com `entregues`, `entregas_de_preco`,
  `entrega_do_comparativo`, `portal_fechado`, `comparativo_enviado`, `autonomia_closed`), as
  mensagens `AgentBot` em ordem, e as linhas `[autonomia][tool]` do log.
- **A dívida que a rodada 2 assume, nomeada:** a execução que atravessa o deploy sem
  `entregas_de_preco` fecha em silêncio em vez de parcial (R11), e o comparativo cujo PDF já foi
  emitido e teve a publicação recusada NÃO é regerado — `comparison_pdf` continua barrando pela
  sentinela `comparativo_enviado`, que é intenção. O fecho passou a DIZER que sobrou (é o que
  `comparativo_pendente?` faz), mas quem ainda não reenvia é a emissão. Regerar significaria uma
  URL nova, token novo, e um segundo comparativo para quem já tivesse recebido o primeiro por um
  caminho que não vemos (a publicação adiada). Fica registrado como o próximo passo natural do
  mesmo raciocínio, com a decisão pendente: reemitir com a URL GRAVADA no handle, em vez de pedir
  outra ao portal.

## Rollback

Não há migration. Rollback = `git revert -m 1 <sha do merge>` + o deploy padrão do projeto, ou
redeploy da imagem anterior pelo SHA anotado antes do merge. O comando de deploy do chat2you vem do
runbook de produção do repo/host; o que esta entrega garante é que o rollback é **só código**.

**Único efeito persistente:** chaves gravadas no `handle` — `autonomia_closed` nas execuções
encerradas durante a janela e, desde a rodada 2, `entregas_de_preco`, `entrega_do_comparativo` e
`portal_fechado` nas cotações que consultaram o portal. Todas inertes no rollback: o código antigo
lê `autonomia_closed` pelo mesmo `merge_handle!(ausente:)`, e as três novas simplesmente não têm
leitor lá — o fecho antigo volta a perguntar ao handle, que continua com `entregues` e
`comparativo_enviado` intactos. Sem PII (o token é `execution_key` + digest do conteúdo, nunca o
texto), sem cleanup.

## Ordem

8a em produção → rodada real na conta 16 → só então abrir a 8b.
