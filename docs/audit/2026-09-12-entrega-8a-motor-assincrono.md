# Entrega 8a — o motor do encerramento assíncrono (sem a ferramenta da proposta)

Data: 12/09/2026 (rodadas 1 a 4, as três últimas depois de revisão). Issue: #396 (Part of
#291). Branch `feat/entrega-8a-motor-assincrono`, **rebaseada sobre `origin/main` `8bcafb0570`**
(era `261d7bb086`; a #405 entrou no meio — ver "Rodada 2", item 7). **Zero migration.** Sem merge,
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
afirma o que o publicador de fato assumiu entregar** — a pergunta é pelo ACEITE registrado na
linha (`Tools::EntregaAceita`), nunca pela emissão, que é o que a ferramenta tentou. Aceite inclui
a publicação ADIADA, que é aceita e ainda não é mensagem; recusa não registra nada.

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

**`434387788e`** `fix(tool): a chave do token da entrega publicada vem da constante` (rodada 3)
- `AsyncPublisher#build_message!` passa a gravar a chave por `EntregaPublicada::CHAVE`, e o hash
  inteiro de `content_attributes` passa a usar chaves de string (o `ActionController::Parameters`
  já as convertia; misturar as duas formas é ofensa de `Style/HashSyntax`).

**`7a811d8342`** `fix(cotacao): a execução em voo no deploy volta a receber comparativo e fecho` (rodada 3)
- `InsuranceQuote::Fecho#resultado_entregue?` cai para `entregues` (`prova_legada?`) quando
  `entregas_de_preco` está AUSENTE do handle — a guarda é o que impede a frase falsa de voltar.
- `InsuranceQuote#fechar` deixa de usar `.compact` sobre o handle mesclado; a ausência da
  identidade se resolve em `marcas_do_comparativo`.
- Os três escritores da identidade (`token_da_entrega`, `registrar_entrega_de_preco`,
  `marcas_do_comparativo`) mudam-se de `InsuranceQuote` para `InsuranceQuote::Fecho` — a classe
  bateu no teto de `Metrics/ClassLength` (177/175) e o módulo é quem lê as mesmas chaves.
- Specs: dois exemplos novos em `insurance_quote_ramo_auto_spec` e um em
  `async_run_job_encerramento_parcial_spec`; um exemplo existente do bloco do fecho perdeu a
  asserção que agora descreve a linha legada (ela virou o exemplo próprio).

**`f87d9abf9a`** `fix(tool): o fecho decide pelo ACEITE do publicador, não pela mensagem` (rodada 4)
- `Tools::EntregaAceita` (novo, 55 linhas): registra e lê a lista das identidades que o publicador
  ASSUMIU. `ToolRun::ENTREGAS_ACEITAS` e `ToolRun#registrar_entrega_aceita!` (um UPDATE, lista
  concatenada pelo banco, `@>` no `WHERE` para não duplicar); `AsyncPublisher::Result#aceita?`;
  `AsyncRunJob#deliver` e `Encerramento#publicar_uma` passam a registrar; a chave entra em
  `AsyncRunJob::MARCAS`.
- `InsuranceQuote::Fecho`: `resultado_entregue?` e `comparativo_pendente?` passam a cruzar as
  identidades EMITIDAS com a lista do aceite; `prova_legada?` passa a ser guardada por COBERTURA
  (`PRECO_LEGADO_KEY`, escrita por `marcar_preco_legado` na primeira emissão de preço).
- `EntregaPublicada.publicada?` deixa de contar a mensagem com envio pendente; o cabeçalho do
  módulo nomeia o único consumidor que sobrou (a idempotência do fecho).
- `Native::Base#initialize` perde `conversation:` (sem consumidor), e com ele o `#conversation`
  privado; as duas montagens do motor acompanham.
- Specs: cinco exemplos novos (quatro em `async_run_job_encerramento_parcial_spec`, um em
  `encerramento_spec`); o Arrange do preço recusado passou a ser a CORRENTE INTEIRA (consulta real
  + publicação que cai) em vez de handle montado à mão.

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
   tem preço na tela. **Superado na rodada 4**: a pergunta certa é pelo ACEITE do publicador, não
   pela mensagem — a entrega adiada é aceita e ainda não é uma. Ver "Rodada 4", item 1.

O fechamento do portal passa a se gravar por si (`portal_fechado`, no ramo `done` de
`build_progress`, independente do PDF) em vez de ser deduzido de `comparativo_enviado` — que
continua sendo lido como prova do fechamento, e só para isso, pelas execuções que atravessarem o
deploy (ver R11, corrigido na rodada 3).

**O que prova:** `insurance_quote_ramo_auto_spec`, bloco `'o fecho e o que ainda vale entregar'`
(dez exemplos na rodada 2, doze depois da rodada 3, com a ferramenta montada como o motor a monta
e a mensagem criada na conversa); e
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
  cada item — o CI roda no HEAD da PR, nunca commit a commit. Os números locais desta rodada estão
  em "Validação", e a fronteira é esta: as SETE partições e a repetição do nó 1 rodaram sobre o
  código de **`f372b3c095`**; o foco (497) e o rubocop (19 arquivos) rodaram depois de
  **`ea296886af`**, cujo único toque em `app/` são dois comentários (`base.rb` e `async_run_job.rb`
  deixaram de dizer que ninguém lê `conversation`/`run`). Nenhuma linha executável mudou entre os
  dois. O estado do CI é o que a PR #406 mostrar no HEAD
  do momento — e não está afirmado aqui, porque um documento não pode atestar o resultado de uma
  corrida que só começa quando ele é empurrado.

### 7. Conflito com a `main` (P3-4)

A #405 foi mergeada e corrigiu o MESMO `spec/controllers/slack_uploads_controller_spec.rb`. O ramo
foi **rebaseado sobre `origin/main` `8bcafb0570`** e o commit desta PR (`b68832d622`) foi
DESCARTADO: fica a versão da `main`. O arquivo não aparece mais no diff da PR.

Durante esta rodada a `main` andou de novo (`356333935b`, #408 — documento de terceiro vai ao
especialista). Ela toca só `quote_agent/instrucoes/principal.md` e o spec de promessas dele:
**zero interseção** com o diff desta PR, e por isso o ramo foi deixado em `8bcafb0570` — os
números de validação abaixo são todos dessa base.

## Rodada 3 — a janela do deploy, e o que foi medido em vez de afirmado

A rodada 2 foi reprovada pelo Codex e pelo verificador cego. O bloqueante era o inverso do da
rodada 1: em vez de afirmar demais, o fecho passou a **calar demais** — e calava exatamente para
quem o incidente de 08/09/2026 deixou sem resposta.

### 1. A execução em voo no deploy perdia o comparativo E o fecho (P1)

**O estado, executado:** linha `running` com o handle da versão anterior (`entregues`, e **sem**
`entregas_de_preco`), o preço já publicado na conversa, `delivered_count` positivo, prazo vencido.

| | mensagens ao cliente |
|---|---|
| `main` | preço · comparativo · frase parcial |
| rodada 2 | preço — **e nada mais**; a linha fecha em `failed` |
| rodada 3 | preço · comparativo · frase parcial |

`entregas_de_preco` é a identidade da mensagem, e quem a grava é a passada que EMITE o preço. A
execução que atravessa o deploy emitiu o dela na versão anterior: não há o que procurar, e o fecho
conclui "nenhum preço chegou". Durante toda a vida das execuções em voo (prazo da execução mais o
`GRACE` do varredor), o cliente que já tinha recebido preço ficava sem o PDF e sem uma palavra —
o incidente que esta entrega existe para eliminar, de volta.

**A correção é a que o arquivo já usava três métodos abaixo.** `portal_fechado?` lê a marca antiga
(`comparativo_enviado`) como prova LEGADA, guardada. `resultado_entregue?` passa a fazer o mesmo
com `entregues` (`prova_legada?`): cai para ela **somente quando `entregas_de_preco` está AUSENTE
do handle**.

**Por que a objeção do R11 não se aplica.** O que ela recusava era um fallback **incondicional** —
esse, sim, reabriria a frase falsa da rodada 1 (`entregues` avança mesmo com a publicação
recusada). Guardado, o fallback alcança só a linha legada: toda passada posterior ao deploy que
emite preço grava a chave, **inclusive quando a publicação é recusada**, porque ela é gravada na
emissão. Não é raciocínio — é a mutação **M19**, que torna o fallback incondicional e derruba
quatro exemplos, entre eles os dois que a rodada 2 escreveu contra a frase falsa.

**O que prova:** `async_run_job_encerramento_parcial_spec`, `'a execucao que atravessou o deploy
recebe o comparativo E o fecho'` (caminho real, porta do motor); e a unidade
`insurance_quote_ramo_auto_spec`, `` 'cai para `entregues` so quando a chave da identidade esta
AUSENTE do handle' ``. Mutações M18, M19 e M20.

**O que continua sendo dívida, agora menor:** dentro da janela do deploy, a linha legada cuja
publicação do preço foi RECUSADA lê `entregues` como prova e recebe a frase parcial sem ter preço
na tela. É o resíduo do P1 da rodada 1, confinado às execuções em voo no momento do deploy — antes
era o fecho inteiro que se perdia, para todas elas. Ver R11.

### 2. O entrelaçamento de duas passadas: TENTADO, NÃO FECHADO (P2-1) — issue #413

A marca `autonomia_closed` serializa o TRABALHO, não o fecho. Reproduzido de forma determinística
(passada B chamada de dentro do `closing_deliveries` de A, mesma ordem temporal, sem threads):

```
mensagens = ["não consegui concluir a consulta", "o comparativo em PDF"]
```

O cliente lê a frase de falha e, em seguida, recebe o comparativo que ela nega.

**Caminho tentado: pôr `fecho_publicado?` e a publicação do fecho sob o lock da conversa.** Não
foi adotado, por duas medições:

1. **O lock não fecha o defeito.** Com `publicar_fecho` inteiro dentro de
   `conversation.with_lock`, a reprodução devolve a saída byte a byte idêntica. É esperado: o
   problema é de ORDEM TEMPORAL (B publica em T+1 s, A entrega em T+60 s), não de leitura-e-escrita
   concorrente. Um lock serializa; não reordena.
2. **A transação de fora QUEBRA a reconciliação do publicador** (rodadas 7 a 9 da entrega 11).
   `Message#send_reply` é `after_create_commit`: com o `with_lock` externo, ele passa a disparar no
   commit de fora — fora do `VigiaDeEnvio.observar` e fora do `rescue` de `AsyncPublisher#post`.
   Medido com o despacho de `MESSAGE_CREATED` levantando `Redis::CannotConnectError` (a montagem de
   `async_publisher_spec`, bloco "quando a publicacao levanta depois do commit"):

   | | `SendReplyJob` enfileirado | marca `autonomia_envio_pendente` |
   |---|---|---|
   | hoje | **1** (reconciliado na hora) | — |
   | com o lock | **0** | **nenhuma** |

   A mensagem do fecho fica no banco, o cliente nunca a recebe, e o varredor não pode recuperá-la
   porque a marca que ele procura nunca foi gravada. Trocar um fecho fora de ordem por um fecho que
   não chega é pior.

É o caso de "se exigir redesenho do publicador, não force": **issue #413**, com as duas
reproduções e o caminho candidato (a marca vira LEASE — quem não a adquire só fecha quando ela está
velha; hoje não há carimbo utilizável, porque `ToolRun::ENCERRADA_EM` é gravado pelo `finish!`,
depois do encerramento). Registrado como R15. O exemplo do entrelaçamento vai junto com a correção,
na issue: um exemplo que documenta defeito não corrigido é um exemplo vermelho.

### 3. A dívida do comparativo é maior do que a rodada 2 declarou (P2-2) — issue #414

A rodada 2 escreveu que "o fecho passou a DIZER que sobrou". **Vale menos do que está escrito.**
`entrega_do_comparativo` só é gravada em `fechar`, e `fechar` só é alcançado pelo ramo `done` de
`build_progress` — ramo que termina em `finish_done` e **não passa pelo encerramento**. Logo
`comparativo_pendente?` só é consultado na janela da LINHA ABANDONADA. No caminho normal, o
comparativo emitido cuja publicação voltou `blocked` não gera aviso nenhum: o cliente não sabe que
faltou algo.

Corrigido no texto (ver "O que ficou de fora") e aberto como **issue #414**, com o exemplo que
falta ("comparativo emitido e recusado no caminho normal"). **Não é regressão**: o buraco existe na
`main`; o que esta PR fez foi torná-lo nomeável, ao separar "emitido" de "entregue".

### 4. Duas definições da chave do token (P3)

O publicador gravava o literal `autonomia_async_token:` e quem lê usava
`EntregaPublicada::CHAVE` — a mesma classe de defeito que esta PR corrigiu para o VALOR, intacta na
CHAVE. Agora os dois lados usam a constante.

A prova é um contraste de mutação, e o mutante que **sobrevive** é o lado certo:

| | `CHAVE` mutada para outro valor | resultado |
|---|---|---|
| M22a — como está agora (constante nos dois lados) | os dois lados se movem juntos | **0 falhas** em 24 exemplos |
| M22b — com o literal de volta no publicador | escritor e leitor divergem | **5 falhas** em 24 exemplos |

### 5. O `.compact` era mais largo que o comentário ao lado dele (P3)

`fechar` fazia `handle.merge(PDF_SENT_KEY => …, COMPARATIVO_KEY => …).compact`, e o comentário
dizia "`compact` porque sem execução não há identidade a gravar". O `compact` apagava QUALQUER
chave nula do handle da FERRAMENTA, não só a identidade ausente. Inerte hoje (nenhuma chave da
cotação é nula) e silencioso — que é como um apagamento de handle chega à produção. Agora a
ausência se resolve em `marcas_do_comparativo`, que monta só as duas marcas.

**O que prova:** `` 'o fecho nao apaga chave nula que o handle da ferramenta ja carregava' ``.
Mutação M21.

**Efeito colateral do conserto:** `InsuranceQuote` bateu no teto de `Metrics/ClassLength`
(177/175). Os TRÊS escritores da identidade (`token_da_entrega`, `registrar_entrega_de_preco`,
`marcas_do_comparativo`) mudaram-se para `InsuranceQuote::Fecho`, que é quem LÊ as mesmas chaves —
o mesmo corte de `Comparativo`, `Declaracao`, `Recusas`, `Envio` e `Veiculo`, e o oposto de manter
escritor e leitor separados (que foi como as duas definições do token nasceram). Movimentação pura,
sem mudança de comportamento; a classe voltou para dentro do teto.

### 6. A carga nova do varredor, medida (P3)

Por linha abandonada passaram a existir consultas por CONTEÚDO de mensagem
(`content_attributes::text LIKE`). Medido neste worktree, contando os `sql.active_record` de uma
varredura com uma linha:

| estado da linha | consultas por conteúdo | SQL total |
|---|---|---|
| abandonada com preço na tela | **5** | 45 |
| legada (janela do deploy) | **4** | 44 |
| abandonada sem preço nenhum | **4** | 73 |

As cinco do primeiro caso são: TRÊS de `fecho_publicado?` (uma por frase possível de fecho), UMA de
`resultado_entregue?` (um token de preço) e UMA do publicador ao postar o fecho. Na `main`, uma
linha com `delivered_count` positivo não produzia nenhuma — o varredor só falava quando o contador
era zero. **Delta: de 0 para 5 consultas por linha** no caso típico, e de 1 para 4 na linha sem
preço.

O que limita o custo: cada consulta é escopada por `conversation_id` e `sender_type` antes do
`LIKE`, então é uma varredura pequena por conversa, não da tabela. O que NÃO está medido é o lote
cheio: `BATCH_LIMIT` é 500 e o Sidekiq desta instalação tem 25 s de shutdown, o que põe o pior caso
em ~2.500 consultas por conteúdo numa varredura. Registrado como R16.

## Rodada 4 — o critério certo não é "existe mensagem", é "a publicação foi ACEITA"

A rodada 3 foi reprovada pelo Codex e pelo verificador cego, que **convergiram**. Perguntar à
mensagem parecia o oposto de confiar no handle, mas criou um terceiro estado invisível: **a entrega
aceita que ainda não virou mensagem**. O motor já distinguia isso (`deliver` conta `published` e
`deferred`, e não conta `blocked`); o fecho, não.

**A decisão do revisor final:** o token vai para o registro no momento do ACEITE, não no da
emissão. Publicação aceita — imediata ou adiada — registra; recusada não registra nada;
`resultado_entregue?` passa a ser "existe token aceito", sem consultar mensagem; e a prova legada
vira UNIÃO com cobertura, não exclusividade por presença de chave.

### 1. A entrega ADIADA não contava como resultado (P1) — permanente, não janela de deploy

**O estado, executado pela corrente inteira** (cadeia de entrega humanizada do turno aberta, que é
o caminho NORMAL enquanto ela drena — até 90 s; prazo estourando na passada seguinte):

| | mensagens que o cliente recebe |
|---|---|
| `main` | preço · comparativo · frase parcial |
| rodada 3 | preço (pelo job adiado) — **e nada mais** |
| rodada 4 | preço · comparativo · frase parcial |

A publicação volta `deferred`, `delivered_count` sobe, e a mensagem ainda não existe. No fecho,
`resultado_entregue?` respondia falso, `closing_deliveries` devolvia vazio, e o fecho devolvia nulo
(o ramo da falha exige contador zero; o parcial exige resultado). O gatilho é o adiamento normal do
publicador — não uma avaria.

**A correção:** `Tools::EntregaAceita` (novo), a lista das identidades que o publicador ASSUMIU,
gravada na LINHA no instante do aceite (`ToolRun#registrar_entrega_aceita!`, um UPDATE só, com a
lista concatenada pelo banco e `@>` no `WHERE` para não duplicar no retry). Quem registra é quem
publica: `AsyncRunJob#deliver` e `Encerramento#publicar_uma`. `AsyncPublisher::Result#aceita?`
passa a ser o nome do conceito (`published? || deferred?`), em um lugar só.

**Por que a lista mora nas MARCAS do motor** (`AsyncRunJob::MARCAS`): ela é escrita NO MEIO da
passada, e o handle que a ferramenta devolve foi lido ANTES. Fora das marcas, o `record_attempt!`
do fim da passada a regravaria com a cópia velha e o token recém-aceito sumiria — travado pelo
exemplo `'a lista do aceite acumula entre passadas e sobrevive ao handle da ferramenta'` (mutação
M28). A ferramenta a lê pela LINHA, nunca pelo handle.

**O handle continua guardando as identidades EMITIDAS** (`entregas_de_preco`,
`entrega_do_comparativo`), e isso é deliberado: quem aceita é o publicador, e ele não distingue um
preço de uma pergunta pelo dado que falta — para ele as duas são "uma entrega". Quem distingue é a
ferramenta, e só na passada que emite, porque é a única em que ela conhece o TEXTO de onde o token
nasce. As duas chaves são a TABELA DE CONSULTA ("por quais identidades perguntar"); a prova é o
cruzamento com a lista do aceite. **Nenhuma delas é lida sozinha** — é isso que mantém fechado o
defeito da rodada 1.

**O que prova:** `async_run_job_encerramento_parcial_spec`, `'a entrega ADIADA conta como
resultado: o cliente recebe preco, comparativo e fecho'` (corrente inteira: consulta real com a
cadeia aberta, prazo estourando, e o `AsyncPublishJob` drenado no fim). Mutações M23, M24, M28, M29.

### 2. Histórico misto: a prova legada era por PRESENÇA, não por COBERTURA (P1)

**O estado, executado pela corrente inteira:** linha que atravessou o deploy com preço na tela,
que emite um preço novo depois do deploy e tem essa publicação RECUSADA.

| | mensagens que o cliente recebe |
|---|---|
| `main` | preço antigo · comparativo · frase parcial |
| rodada 3 | preço antigo — **e nada mais** (nem comparativo, nem palavra) |
| rodada 4 | preço antigo · comparativo · frase parcial |

A guarda da rodada 3 era a PRESENÇA de `entregas_de_preco`: a emissão nova (recusada) criava a
chave, a linha passava a ser julgada só pelo token novo, e o preço antigo — que está na tela —
sumia da conta.

**Por que a união literal não bastava.** "Token aceito **ou** `entregues` não vazio" reabre o
defeito da rodada 1: a linha NASCIDA depois do deploy também tem `entregues` preenchido quando a
publicação é recusada, e os dois estados são idênticos no handle. O que os separa é COBERTURA —
havia preço emitido ANTES de esta versão passar a registrar o aceite? A resposta é gravada uma vez,
na primeira emissão de preço da execução (`preco_legado`, com o valor de `already.any?`), e é ela
que a prova legada consulta; sem a marca, a linha nunca emitiu nesta versão e `entregues` é toda a
prova que existe.

**O que prova:** `'a linha legada que emite um preco novo recusado nao perde o preco que ja esta na
tela'` (corrente inteira) e a unidade `` 'a prova legada vale por COBERTURA, e nao pela presenca da
chave nova' ``. Mutação **M26** devolve a guarda da rodada 3 e derruba as duas; **M30** grava a
cobertura sempre como `true` e derruba o exemplo do P1 da rodada 1.

### 3. Mensagem no banco com envio pendente contava como entregue (Codex e verificador)

`EntregaPublicada.publicada?` olhava só a existência da mensagem. O publicador deixa no banco,
MARCADA (`PendenciaDeEnvio`), a mensagem cujo `SendReplyJob` não entrou na fila: ela existe, o
cliente não a recebeu. Agora a pendência responde "ainda não" — e publicar de novo é o certo, não o
risco: a dedupe por conteúdo do publicador acha a mesma mensagem pelo token e RETOMA o envio dela,
sob o lock, sem duplicar.

Sobrou **um** consumidor para essa pergunta, e o cabeçalho do módulo agora diz qual: a idempotência
do fecho (`Encerramento#fecho_publicado?`). `para` continua sem filtrar a pendência, de propósito —
quem quer a mensagem para retomá-la precisa dela justamente quando está pendente.

**O que prova:** `encerramento_spec`, `'o fecho com envio pendente e retomado pela passada
seguinte, sem duplicar a mensagem'`. Mutação M27.

### 4. O resíduo declarado era maior que o texto (P2 do verificador)

A rodada 3 declarou o resíduo como "a frase parcial sem preço na tela". Ele era maior: na linha
julgada legada sem mensagem, o motor **ainda pedia o comparativo ao portal** (login + até 60 s) e
publicava a frase parcial, onde a `main` dizia a frase honesta de falha — `closing_deliveries` usa
o mesmo predicado.

Fechado junto com os itens 1 e 2: com o aceite como prova e a cobertura como guarda, a execução
nascida depois do deploy cuja publicação foi recusada não afirma nada, não pede comparativo, e lê a
frase de falha. **O resíduo que sobra** é só o da linha em voo NO deploy cujo preço da versão
anterior tinha sido recusado — ela carrega `entregues` e nenhuma outra prova possível. Ver R11.

### 5. `conversation:` deixou de ter consumidor, e saiu

Com o fecho perguntando ao aceite, `Native::Base#conversation` ficou sem ninguém lendo — o único
leitor era `Fecho#publicada?`. O parâmetro saiu do construtor e das duas montagens
(`AsyncRunJob#ferramenta`, `Encerramento#montar`): capacidade sem consumidor é custo puro, e foi
exatamente o P3-2 da rodada 1. `run:` fica, e agora com dois usos (montar a identidade e ler o
aceite).

### 6. O fecho ADIADO escapa da guarda de idempotência — extensão nomeada da issue #413

A guarda `fecho_publicado?` pergunta pela MENSAGEM. Quando a publicação do fecho volta `deferred`
(cadeia do turno aberta), a mensagem só nasce segundos depois, no `AsyncPublishJob` — e a passada
seguinte lê "ainda não saiu" e publica OUTRA frase.

**Reproduzido** (duas passadas de `Encerramento` sobre a mesma linha, com o publicador do motor e a
cadeia aberta; as adiadas drenadas no fim):

```
ADIADAS = ["o arquivo que ficou pronto",
           "Algumas consultas não responderam a tempo. O que chegou está aqui em cima.",
           "não consegui concluir a consulta"]
```

O cliente lê a frase parcial e, em seguida, a frase que a nega. É o MESMO defeito do
entrelaçamento (R15/#413) por outra porta — lá a ordem temporal, aqui o adiamento —, e a mesma
saída candidata o cobre: a marca `closed` virar LEASE, ou a guarda passar a perguntar pelo ACEITE
do fecho em vez da mensagem (o registro já existe desde esta rodada; não foi ligado ao fecho de
propósito, para não misturar correção e escopo novo na mesma rodada). Registrado em **#413** como
extensão nomeada, com esta reprodução. **Não é regressão, e é o outro lado de uma troca
consciente**: na `main` a marca `closed` cala a segunda passada INTEIRA, então segunda frase não
existe — e também não existe fecho nenhum para quem morreu entre a marca e a publicação, que é o
defeito que a rodada 2 corrigiu (item 2 de lá). Na rodada 3 o comportamento é idêntico ao desta: a
guarda pergunta pela mensagem, e a adiada ainda não é uma.

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
| R11 | **janela do deploy**: execução `running` que atravessa o deploy não tem identidade de entrega nenhuma no handle (as chaves nascem na passada que emite o preço) | na rodada 2 o fecho dela lia "nenhum preço chegou" e a linha perdia o comparativo E o fecho — o incidente de 08/09/2026 de volta para todas as execuções em voo | **era risco aceito, virou defeito e foi corrigido em duas etapas.** Rodada 3: `entregues` vale como prova LEGADA, guardada pela PRESENÇA da chave nova. Rodada 4: a guarda passa a ser por COBERTURA (`preco_legado`, gravada na primeira emissão desta versão), porque a presença perdia o preço antigo da linha de histórico MISTO — ver "Rodada 4", item 2. O fallback INCONDICIONAL, que é o que este risco recusava, continua recusado: M25/M26/M30 provam que o teste pega os três desvios. `comparativo_enviado` segue sendo lido como prova do fechamento pela mesma razão (`portal_fechado?`), travado em `'aceita o comparativo_enviado como prova do fechamento nas linhas que atravessam o deploy'`. **Resíduo declarado, agora menor**: dentro da janela, a linha em voo cujo preço da versão ANTERIOR foi recusado ainda lê `entregues` como prova — não há outra prova possível para ela |
| R12 | a frase parcial passa a exigir a FERRAMENTA montada (agente vivo) | `agente_indisponivel` com contador positivo lia a frase na `main` e agora cala | decisão declarada, com exemplo — ver "Rodada 2", item 4. O publicador recusa qualquer mensagem dessa execução, então o cliente não perde nada que recebesse |
| R13 | o handle ganha CINCO chaves: quatro da cotação (`entregas_de_preco`, `entrega_do_comparativo`, `portal_fechado`, `preco_legado`) e uma do motor (`autonomia_entregas_aceitas`) | leitor que itere o handle vê chaves novas; a coluna cresce | nenhum leitor itera o handle — os consumidores são `Fecho`, `Comparativo` e `EntregaAceita`, por chave. As quatro da ferramenta ficam fora de `AsyncRunJob::MARCAS`; a do motor entra nelas, e **precisa** entrar (ver "Rodada 4", item 1, e M28). Tamanho: por execução, dois tokens de 53 bytes, dois booleanos e a lista do aceite — um token de 53 bytes por entrega aceita, tipicamente 2 ou 3 |
| R14 | `AsyncPublisher` passa a montar o token por `EntregaPublicada.token_de` | um token diferente do de antes republicaria mensagem já publicada | é a MESMA conta (`run.delivery_token` sobre a `identidade` do arquivo ou o texto aparado), agora em um lugar só; `async_run_job_comparativo_arquivo_spec` e `async_publisher_spec` exercitam os dois caminhos, inclusive o retry que não republica |
| R15 | **entrelaçamento de duas passadas**: a marca `closed` serializa o TRABALHO, e `fecho_publicado?` é leitura sem lock | a passada que não tem a marca publica o fecho enquanto a que tem passa até 60 s no portal: o cliente lê "não consegui" e DEPOIS recebe o comparativo | **risco aceito, declarado — issue #413**, com as duas reproduções. O lock da conversa foi TENTADO e medido: não fecha o defeito (é ordem temporal, não contenção) e quebra a reconciliação do publicador (rodadas 7 a 9). Ver "Rodada 3", item 2. Na rodada 4 a issue ganhou uma **extensão nomeada**: o fecho ADIADO escapa da mesma guarda, porque a mensagem dele só nasce no `AsyncPublishJob` — reproduzido em "Rodada 4", item 6. **Não é regressão**: a `main` não publica fecho nenhum por este caminho quando `delivered_count` é positivo |
| R16 | **carga nova do varredor**: consultas por CONTEÚDO de mensagem por linha abandonada | até 500 linhas em sequência num cron com 25 s de shutdown do Sidekiq | **medido, e MENOR desde a rodada 4**: **4** consultas `content_attributes::text LIKE` por linha nos três estados (com preço, legada, sem preço) — 3 do `fecho_publicado?` (uma por frase possível) e 1 do publicador. Antes eram 5 no caso típico; a quinta era a do `resultado_entregue?`, que passou a ler o ACEITE na linha, em memória. Na `main` eram 0 e 1. Pior caso do lote cheio: ~2.000 por varredura. Cada uma é escopada por `conversation_id` + `sender_type` antes do `LIKE`, então é varredura por conversa, não de tabela. **Não medido**: o lote cheio contra volume real. Ver "Rodada 3", item 6 |

## Validação (números)

Ambiente: `PATH="$HOME/.rbenv/shims:$PATH"` — sem isso `bundle` resolve para `/usr/bin/bundle` e
rspec/rubocop "passam" sem executar nada. Todo exit code abaixo foi lido de `${pipestatus[1]}`.
Banco de teste PRÓPRIO (`chatwoot_test_8a_base`, criado com `db:schema:load`), nunca o
`chatwoot_test` compartilhado entre os worktrees deste repositório — ver a armadilha no fim.

### Rodada 4 (a que vale)

Código validado: **`f87d9abf9a`** — as OITO partições, as mutações e as duas reproduções rodaram
sobre ele. Depois dele vêm dois commits: `34977fbd59`, que toca **só comentários** em dois arquivos
(`git diff f87d9abf9a 34977fbd59` mostra apenas linhas iniciadas por `#`), e o commit desta
auditoria, que não toca `app/` nem `spec/`. O foco, a área inteira, o rubocop e a medição de carga
abaixo rodaram DEPOIS do commit de comentários.

- Foco: `bundle exec rspec spec/jobs/autonomia/agents/tools/ spec/services/autonomia/agents/tools/
  spec/models/autonomia/agents/tool_run_spec.rb` → **505 examples, 0 failures, exit 0**
  (500 na rodada 3; +5 exemplos novos).
- Área inteira: `bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`
  → **1180 examples, 0 failures, 3 pending, exit 0** (1175 na rodada 3).
- `bundle exec rubocop` na lista EXPLÍCITA dos **20** arquivos `.rb` do diff (18 na rodada 3, mais
  `entrega_aceita.rb` e `tool_run.rb`, que a 8a agora TOCA — ver "O que ficou de fora", corrigido)
  → **0 ofensas, exit 0**.
- **Reprodução dos dois P1, antes e depois**, pela corrente inteira (`AsyncRunJob#perform` de
  verdade, conector `mock`, publicador real; nenhum handle montado à mão para o estado que o
  defeito produz):

  | P1 | antes (`256706d6dd`) | depois (`f87d9abf9a`) |
  |---|---|---|
  | entrega ADIADA (cadeia do turno aberta, prazo estourando) | o cliente recebe o preço pelo job adiado e **nada mais**: `entregas.drop(1) == []` | preço · comparativo · frase parcial |
  | linha legada que emite um preço novo RECUSADO | `bot_contents == ["*Ezze* — R$ 2.050,40 no total"]` — nem comparativo, nem palavra | preço antigo · comparativo · frase parcial |

  Os dois exemplos foram escritos ANTES da correção e falharam contra o código da rodada 3 (RED),
  com exatamente as saídas da coluna "antes".
- **Partições do CI** (`find spec -name '*_spec.rb' | sort`, `i % 8`, como em `testes.yml`). As
  OITO rodadas aqui, na íntegra, **na primeira passada**, sem nenhuma escrita em `app/` ou `spec/`
  durante as corridas. O nó 0 entra na lista desta rodada porque ela **toca o model**
  (`tool_run.rb`), e é lá que está `tool_run_spec.rb`:

  | nó | arquivos | rodada 4 | rodada 3 |
  |---|---|---|---|
  | 0 | 142 | 1418 ex, **0 falhas**, 4 pending — exit 0 | não rodado |
  | 1 | 141 | 1365 ex, **0 falhas**, 12 pending — exit 0 | 1365 (só na repetição) |
  | 2 | 141 | 1188 ex, **0 falhas**, 3 pending — exit 0 | 1188 |
  | 3 | 141 | 1170 ex, **0 falhas**, 36 pending — exit 0 | 1166 |
  | 4 | 141 | 1333 ex, **0 falhas**, 2 pending — exit 0 | 1333 |
  | 5 | 141 | 1273 ex, **0 falhas**, 18 pending — exit 0 | 1273 |
  | 6 | 141 | 1611 ex, **0 falhas**, 18 pending — exit 0 | 1610 |
  | 7 | 141 | 1746 ex, **0 falhas**, 34 pending — exit 0 | 1746 |

  As diferenças são exatamente os exemplos novos: **+4 no nó 3** (as duas reproduções, a porta do
  varredor na janela do deploy e a acumulação da lista do aceite) e **+1 no nó 6** (o fecho com
  envio pendente). O nó 1 fechou em 0 na PRIMEIRA passada, sem repetição — ver a correção sobre as
  falhas fantasma, logo abaixo.
- **Carga do varredor, medida de novo** (contando `content_attributes::text LIKE` durante
  `ReapStaleRunsJob#perform`, um estado por vez): **4 por linha** nos três estados, contra 5 no
  caso típico da rodada 3. Ver R16.

### Rodada 3 (histórico)

Código validado: **`7a811d8342`** (o HEAD do branch antes do commit da auditoria da rodada 3).

- Foco: `bundle exec rspec spec/jobs/autonomia/agents/tools/ spec/services/autonomia/agents/tools/
  spec/models/autonomia/agents/tool_run_spec.rb` → **500 examples, 0 failures, exit 0**
  (497 na rodada 2; +3 exemplos novos).
- Área inteira: `bundle exec rspec spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`
  → **1175 examples, 0 failures, 3 pending, exit 0** (1167 na rodada 2). **Correção da rodada 4:**
  este número estava escrito como 1172, que é a contagem dos que PASSARAM — os 3 pending entram no
  total de examples. Conferido pela aritmética da rodada 4: 5 exemplos novos, 1180 no total.
- `bundle exec rubocop` na lista EXPLÍCITA dos arquivos `.rb` do diff → **0 ofensas, exit 0**.
  **Correção de um número da rodada 2:** ela diz "19 arquivos", e o diff tem **18** — o 19º era o
  `slack_uploads_controller_spec.rb`, descartado no rebase (item 7 da rodada 2 já dizia que o
  arquivo saiu do diff, mas a contagem do rubocop não foi atualizada junto.)
  Uma ofensa apareceu no caminho e foi corrigida, não silenciada: `Metrics/ClassLength` em
  `InsuranceQuote` (177/175), resolvida movendo os três escritores da identidade para
  `InsuranceQuote::Fecho` — mais `Style/HashSyntax` no hash de `content_attributes`, que passou a
  usar chaves de string em todas as entradas.
- **Partições do CI** (`find spec -name '*_spec.rb' | sort`, `i % 8`; os arquivos desta PR caem nos
  nós **1 a 7**, os mesmos da rodada 2). Todos rodados aqui, na íntegra, **na primeira passada**:

  | nó | arquivos | rodada 3 | rodada 2 |
  |---|---|---|---|
  | 1 | 141 | 1365 ex, **0 falhas**, 12 pending — exit 0 | 1365 (só na repetição limpa) |
  | 2 | 141 | 1188 ex, **0 falhas**, 3 pending — exit 0 | 1188 |
  | 3 | 141 | 1166 ex, **0 falhas**, 36 pending — exit 0 | 1165 |
  | 4 | 141 | 1333 ex, **0 falhas**, 2 pending — exit 0 | 1333 |
  | 5 | 141 | 1273 ex, **0 falhas**, 18 pending — exit 0 | 1273 |
  | 6 | 141 | 1610 ex, **0 falhas**, 18 pending — exit 0 | 1610 |
  | 7 | 141 | 1746 ex, **0 falhas**, 34 pending — exit 0 | 1744 |

  As diferenças são exatamente os exemplos novos: **+1 no nó 3** (a janela do deploy pelo caminho
  real) e **+2 no nó 7** (a guarda do fallback e o `.compact`).

- **A regra da rodada 2 foi obedecida, e o resultado a confirma.** Nenhuma escrita em `app/` ou
  `spec/` enquanto uma partição rodava, e o nó 1 — que na rodada 2 deu 10 falhas na primeira
  passada e 0 na repetição — fechou em **0 na primeira**. A causa daquelas falhas era mesmo o
  `config.cache_classes = false` recarregando o Rails no meio da corrida, não o código.

- **Armadilha de shell registrada (custou uma leitura errada).** `${pipestatus[1]}` no zsh é o
  status do PRIMEIRO comando do pipeline — mas só do ÚLTIMO pipeline executado. Envolver a corrida
  num subshell (`(bundle exec rspec … | tail)`) faz `pipestatus` valer para o subshell inteiro, e
  ele devolve o status do `tail`: **`EXIT=0` sobre um rspec que falhou**. A primeira corrida RED
  desta rodada foi lida assim. Todos os exit codes acima vieram de pipelines sem subshell.

### Rodada 2 (histórico)

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
  false` no ambiente de teste: o `data_imports_spec` — que é um request spec e vem logo antes do
  `responder_spec` na lista do nó — dispara o recarregamento do Rails no meio da corrida. As
  vítimas foram `responder_spec` (`:silenced` onde esperava `:replied`),
  `campaign_imports/validator_spec` e `whatsapp_api_campaigns/audience_resolver_spec`
  (`uninitialized constant …::Parser`, `…::CsvSanitizer` — Zeitwerk com o autoloader trocado sob os
  pés). O banco estava LIMPO nas duas passadas (`active_storage_blobs = 0`, `accounts = 0`), o que
  descarta a explicação da rodada 1 para o mesmo conjunto de falhas. Repetido: **1365 ex, 0 falhas,
  12 pending — exit 0**, exatamente o número da rodada 1.

  **Correção do texto (rodada 4).** A rodada 3 atribuiu essas falhas à edição concorrente de
  `app/` — eu estava corrigindo comentários enquanto o nó rodava. **A edição concorrente agrava,
  mas não é a causa única**: o verificador cego reproduziu **17 falhas no nó 1 sem escrever nada**,
  todas com a mesma assinatura de recarga de constante, e a repetição dele também fechou limpa. A
  causa é o recarregamento em si, que é não determinístico; escrever em `app/` no meio só aumenta a
  chance de ele acontecer. **A regra continua valendo** (nenhuma escrita em `app/` ou `spec/`
  enquanto uma partição roda), agora como redução de ruído, não como remédio — e um nó vermelho com
  essa assinatura pede repetição antes de virar diagnóstico.

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

### Rodada 3

| # | âncora | mutação | alvo | resultado |
|---|---|---|---|---|
| M18 | `insurance_quote/fecho.rb` `resultado_entregue?` | remove a guarda inteira (volta ao comportamento da rodada 2) | `insurance_quote_ramo_auto_spec` + `async_run_job_encerramento_parcial_spec` | **2 falhas** — a unidade e o caminho real da janela do deploy |
| M19 | `insurance_quote/fecho.rb` `resultado_entregue?` | torna o fallback INCONDICIONAL (`return prova_legada?(handle)` sem a guarda) — é exatamente o que o R11 recusava | idem | **4 falhas** — entre elas os DOIS exemplos que a rodada 2 escreveu contra a frase falsa (`'nao pede o comparativo quando o preco nunca chegou ao cliente'` e `'a cotacao cujo preco nunca chegou ao cliente fecha com a frase de falha…'`). É esta mutação que prova que a guarda é o que separa a correção do defeito antigo |
| M20 | `insurance_quote/fecho.rb` `prova_legada?` | `Array(handle[DELIVERED_KEY]).any?` → `true` (lista vazia contaria como preço) | idem | **2 falhas** |
| M21 | `insurance_quote.rb` `fechar` | volta o `.compact` largo sobre o handle mesclado | `insurance_quote_ramo_auto_spec` | **1 falha** — `'o fecho nao apaga chave nula que o handle da ferramenta ja carregava'` |
| M22a | `entrega_publicada.rb` `CHAVE` | muda o VALOR da constante, com o código como está | `encerramento_spec` + `async_run_job_encerramento_parcial_spec` | **0 falhas** em 24 exemplos — os dois lados se movem juntos. Aqui o mutante SOBREVIVER é a prova: há uma definição só |
| M22b | `entrega_publicada.rb` `CHAVE` **e** `async_publisher.rb` | muda o valor da constante **e** devolve o literal ao publicador (desfaz a correção) | idem | **5 falhas** em 24 exemplos — escritor e leitor divergem, e a pergunta "já chegou?" para de responder |

Todos os arquivos voltaram ao md5 de antes (conferido em cada mutação, inclusive nas duas de M22,
que tocam dois arquivos).

### Rodada 4

| # | âncora | mutação | alvo | resultado |
|---|---|---|---|---|
| M23 | `entrega_aceita.rb` `registrar` | remove o `&& resultado.aceita?` (registra também a publicação RECUSADA) | `async_run_job_encerramento_parcial_spec` | **1 falha** — `'a cotacao cujo preco nunca chegou ao cliente fecha com a frase de falha, e nao pede comparativo'`. É a mutação que prova que o defeito da rodada 1 não voltou pela porta nova |
| M24 | `async_publisher.rb` `Result#aceita?` | `published? \|\| deferred?` → `published?` | idem | **1 falha** — `'a entrega ADIADA conta como resultado…'`: o contador cai para 0 e o fecho volta a calar |
| M25 | `insurance_quote/fecho.rb` `resultado_entregue?` | remove `\|\| prova_legada?(handle)` | idem | **2 falhas** — as DUAS portas da janela do deploy (motor e varredor) |
| M26 | `insurance_quote/fecho.rb` `prova_legada?` | volta à guarda da rodada 3 (`return false if handle.key?(PRECOS_KEY)`) | idem + `insurance_quote_ramo_auto_spec` | **2 falhas** — o histórico misto pela corrente inteira e a unidade da cobertura |
| M27 | `entrega_publicada.rb` `publicada?` | remove a checagem de `PendenciaDeEnvio.pendente?` | `encerramento_spec` | **1 falha** — `'o fecho com envio pendente e retomado pela passada seguinte…'` |
| M28 | `async_run_job.rb` `MARCAS` | remove `ToolRun::ENTREGAS_ACEITAS` da lista | `async_run_job_encerramento_parcial_spec` | **1 falha** — `'a lista do aceite acumula entre passadas…'`: o `record_attempt!` regrava a lista com a cópia velha da ferramenta |
| M29 | `tool_run.rb` `registrar_entrega_aceita!` | a lista base vira `'[]'::jsonb` (não acumula: cada aceite apaga o anterior) | idem | **4 falhas** |
| M30 | `insurance_quote/fecho.rb` `marcar_preco_legado` | grava `true` em vez de `Array(already).any?` | idem + `insurance_quote_ramo_auto_spec` | **2 falhas** — o P1 da rodada 1 pela corrente inteira e a unidade que trava o valor gravado |

Todos os arquivos voltaram ao md5 de antes — conferido pelo próprio script de mutação, que
restaura o original e compara o digest, mesmo quando o rspec cai.

**Método da rodada 4, e por que ele mudou:** a rodada 3 usou `cp` + `trap`, e a armadilha do
`git checkout --` está registrada acima. Aqui o roteiro (`mutar.rb`, fora do repositório) guarda o
conteúdo original EM MEMÓRIA, recusa-se a rodar se o trecho âncora não for único no arquivo, exige
que o md5 MUDE depois de aplicar (senão a mutação não foi aplicada e o verde não significa nada) e
restaura no fim, imprimindo o digest dos três momentos. `BOOTSNAP_CACHE_DIR` próprio, como nas
rodadas anteriores.

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
- **`ToolRun` e `ToolRunPromocao`.** Até a rodada 3 a 8a **não tocava o model**; na rodada 4 ela
  passou a tocar, e só para isto: a constante `ENTREGAS_ACEITAS` e o método
  `registrar_entrega_aceita!`, o irmão de `record_delivery!` (aquele conta quantas, este diz
  quais). Nada do que segue mudou de status. `DEAD_STATUSES` só tem leitor na
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
  `portal_fechado` aparece quando o portal fecha; (5) NOVO na rodada 3 — no deploy, conferir que
  uma execução que estava `running` ANTES da subida (handle sem `entregas_de_preco`, com
  `entregues`) ainda recebe o comparativo e o fecho ao expirar. Evidência a coletar em cada uma: `run.id`,
  `status`, `failure_code`, `delivered_count`, o `handle` (com `entregues`, `entregas_de_preco`,
  `entrega_do_comparativo`, `portal_fechado`, `comparativo_enviado`, `autonomia_closed`), as
  mensagens `AgentBot` em ordem, e as linhas `[autonomia][tool]` do log.
- **O comparativo emitido e recusado — issue #414.** A rodada 2 escreveu que "o fecho passou a
  DIZER que sobrou (é o que `comparativo_pendente?` faz)". **Isso vale menos do que estava
  escrito, e o texto está corrigido:** `entrega_do_comparativo` só é gravada em `fechar`, `fechar`
  só é alcançado pelo ramo `done` de `build_progress`, e esse ramo termina em `finish_done` — que
  **não passa pelo encerramento**. Logo o aviso só acontece na janela da LINHA ABANDONADA; no
  caminho normal, o comparativo emitido cuja publicação voltou `blocked` não gera aviso nenhum.
  Somam-se a isso as duas pontas que já estavam nomeadas: ninguém REENVIA (`comparison_pdf` barra
  pela sentinela `comparativo_enviado`, que é intenção), e regerar significaria URL nova, token
  novo e um segundo comparativo para quem já tivesse recebido o primeiro por um caminho que não
  vemos (a publicação adiada). Tudo isso, mais o exemplo que falta ("comparativo emitido e recusado
  no caminho normal"), está na **issue #414**, com a decisão pendente: reemitir com a URL GRAVADA
  no handle, em vez de pedir outra ao portal. **Não é regressão** — o buraco existe na `main`.
- **O entrelaçamento de duas passadas — issue #413.** Ver R15 e "Rodada 3", item 2. O exemplo do
  entrelaçamento vai com a correção, na issue.

## Rollback

Não há migration. Rollback = `git revert -m 1 <sha do merge>` + o deploy padrão do projeto, ou
redeploy da imagem anterior pelo SHA anotado antes do merge. O comando de deploy do chat2you vem do
runbook de produção do repo/host; o que esta entrega garante é que o rollback é **só código**.

**Único efeito persistente:** chaves gravadas no `handle` — `autonomia_closed` nas execuções
encerradas durante a janela; desde a rodada 2, `entregas_de_preco`, `entrega_do_comparativo` e
`portal_fechado` nas cotações que consultaram o portal; e, desde a rodada 4, `preco_legado` (da
ferramenta) e `autonomia_entregas_aceitas` (do motor, uma marca como as outras cinco). Todas
inertes no rollback: o código antigo lê `autonomia_closed` pelo mesmo `merge_handle!(ausente:)`, e
as cinco novas simplesmente não têm leitor lá — o fecho antigo volta a perguntar ao handle, que
continua com `entregues` e `comparativo_enviado` intactos. Sem PII (o token é `execution_key` +
digest do conteúdo, nunca o texto), sem cleanup.

## Ordem

8a em produção → rodada real na conta 16 → só então abrir a 8b.
