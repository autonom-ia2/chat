# Fatia 1 do PDF rápido: a cotação fecha quando todas as seguradoras respondem (#420)

Data: 13/09/2026 · Branch `feat/cotacao-pdf-rapido` · base `origin/main` (`3f08e37c7c`).

## Objetivo

Toda cotação de auto com pelo menos uma seguradora que não cota rodava até o prazo de 7 minutos, e
o PDF do comparativo só chegava aí. Esta fatia faz quatro coisas, e só elas:

1. a execução encerra quando **toda seguradora listada tem desfecho** (preço ou recusa), sem esperar
   o portal declarar o negócio pronto;
2. o comparativo que não sai **ganha nova tentativa**, com teto;
3. o caminho `done` **publica o desfecho** do especialista, com a mesma idempotência do encerramento;
4. o **link cru do PDF não vai mais ao cliente**.

Fora desta fatia, de propósito: parar os lotes de preço, sinal de vida, ferramenta nova da Lia,
motivo de recusa, classificação da Sancor.

## O problema, medido (13/09/2026, portal real)

- O adapter (`autonomia-adapters`, `src/platforms/agger/http/quote.ts`, leitura) devolve status geral
  `partial` para "ainda chegando preço" e para "portal pronto, algumas recusaram". Com o portal pronto
  e qualquer recusa, nunca sai `completed`.
- O chat2you só encerrava com `completed` ou `failed` (`InsuranceQuote#finished?`), e as quatro
  cotações reais de 12/09 terminaram em `failed/prazo_esgotado`.
- Três cotações: todas as seguradoras com desfecho em 41 s, 98 s e 64 s; o portal só se declarou
  pronto em 188 s, 380 s e 316 s. O PDF pedido cedo tem o mesmo conteúdo do tardio; 1 de 5 pedidos
  de PDF voltou HTTP 504 do portal em 29 s.

Lido nos brutos da medição nesta fatia (só a FORMA; nada deles entrou no repositório):

- nas duas linhas do tempo completas, os 16 cálculos já estavam listados na primeira leitura, feita
  entre ~1 s e ~4 s depois de o `calcularV2` voltar;
- **cada pedido de PDF devolve uma URL diferente**: comparadas por igualdade (sem imprimir), as URLs
  do pedido cedo e do tardio de cada cotação diferem. Isto mudou o desenho do item 2 (ver decisão 6).

## O que mudou, por item

### 1. Encerrar quando todas têm desfecho

`InsuranceQuote#finished?(result, leitura, handle)` responde verdade com `completed`/`failed` OU com
`QuoteOffers#todas_com_desfecho?(handle[ACIONADAS_KEY])`, que exige, nesta ordem:

1. a lista de acionadas que as leituras ANTERIORES gravaram não está vazia;
2. todo código dessa lista aparece nesta leitura;
3. toda oferta desta leitura tem status em `DESFECHOS = quoted declined auth_required error`.

Leitura do adapter (`toOffer`, `quote.ts` ~990-1048) que sustenta a lista: com `calc.erros` a oferta
sai `declined`/`auth_required` na hora; com prêmio escolhível, `quoted`; sem prêmio e sem erro, `running`
enquanto o negócio está aberto e `error` depois. A oferta cujos `resultados[].erros` vêm todos com erro
cai em "sem prêmio" e sai `running` até o portal ficar pronto: ela **adia** o encerramento até lá, e
isso tem teste (`insurance_quote_fecha_sem_esperar_o_portal_spec`, "a seguradora running adia…").

### 2. Nova tentativa do comparativo

`fechar` saiu da classe para `InsuranceQuote::Comparativo` (a classe estava no teto de linhas) e passou
a decidir por `comparativo_por_tentar?`: há preço emitido, `comparativo_tentativas < 3` e o comparativo
não foi assumido. Cada pedido ao portal soma uma tentativa.

- geração que falha (504, sem URL, URL fora da forma): `running`, e a passada seguinte pede de novo;
  esgotado o teto, `done` sem comparativo — o comportamento de antes;
- comparativo gerado e **não aceito** pelo publicador (download que falha): o motor não encerra a
  passada `done` (`AsyncRunJob#arquivo_recusado?`) e a passada seguinte decide pelo mesmo predicado.

### 3. O desfecho no caminho `done`

`AsyncRunJob#finish_done` chama `Tools::Encerramento#concluir` antes do `finish!('done')`:

- contador zero → frase de falha (o que `finish_done` já publicava);
- resultado confirmado pela ferramenta (`resultado_entregue?`) → fecho de quem tem resultado;
- entrega aceita que não é resultado (a pergunta pelo dado que falta) → nada.

Antes de publicar, a mesma pergunta à conversa do encerramento (`fecho_publicado?`, pelas frases de
`FRASES_DE_FECHO`, inclusive a constante parcial da versão anterior). A regra "pergunta, depois publica"
virou um método só (`publicar_se_nao_houver_fecho`), usado pelos dois caminhos.

### 4. Tirar o link cru do PDF

- `AsyncPublisher`: download, gravação ou anexo que falham não publicam nada (`sem_arquivo`) e voltam
  `blocked`, com o motivo no log (`; nao publicado`). `sem_arquivo` passa pelo mesmo `post` com corpo sem
  texto: se a mensagem com o token já está na conversa (retry de uma entrega que saiu), responde por ela.
- `Comparativo#entrega_do_comparativo`: a forma recusada devolve nil (antes, o texto com o link) e a
  reserva deixou de levar a URL. A chave `comparativo_reserva` do pedido e o campo `reserva` da forma
  continuam (schema e compatibilidade de rollback), sem publicação.

## Decisões onde o desenho não fechou sozinho

1. **A primeira leitura nunca encerra (além do enunciado).** O enunciado pede lista não vazia e número
   de ofertas não menor que o de acionadas. Na primeira leitura a união das acionadas É a leitura, e
   essa guarda não protege nada: uma seguradora ainda não listada pelo portal não seguraria o
   encerramento. Exigir uma leitura anterior custa, no pior caso, um intervalo de consulta (3 s) numa
   cotação em que todas responderam antes da segunda leitura. Efeito colateral medido: os exemplos
   existentes que consultam uma vez com status `partial`/`running` e todas as ofertas com desfecho
   continuam sem encerrar, como antes.
2. **Cobertura por códigos, não por contagem de ofertas.** "Todo código acionado antes está nesta
   leitura" é a mesma guarda do enunciado quando se conta código distinto, e não deixa uma oferta
   duplicada esconder uma seguradora que sumiu. A exigência "lista não vazia" fica implicada pelas
   guardas 1 e 2 (tem teste próprio); um `empty?` a mais seria mutante equivalente.
3. **Lista branca de desfechos.** `queued`, `timeout` e `not_configured` existem no contrato do adapter
   e o AGGER não os produz: ficam fora, e uma oferta com um deles segura o encerramento até
   `completed`/`failed`/prazo. O lado seguro é esperar.
4. **Teto de 3 pedidos do comparativo.** Com a taxa medida (1 em 5) e falhas independentes, três
   seguidas acontecem em 0,8% das cotações. O pior caso por tentativa é 21 s (intervalo) + 60 s (leitura
   do conector) + 20 s (download) ≈ 101 s; três somam ~303 s, que com os 98 s da cotação mais lenta
   chegam perto dos 420 s do prazo. Uma quarta passaria dele. Se o prazo chegar antes, `fail_run`
   encerra como antes. A independência das falhas não foi medida.
5. **O download que falha segura o `done` no motor, e só arquivo.** O download acontece no publicador,
   depois da passada; só o motor sabe na mesma passada que o arquivo não foi aceito. A regra é restrita a
   entrega de arquivo: a pergunta pelo dado que falta volta em toda passada, e reagendá-la repetiria a
   recusa até o prazo (tem teste de que ela encerra como antes).
6. **A mensagem na conversa conta como comparativo assumido.** Com o `SendReplyJob` recusado pela fila, o
   publicador deixa a mensagem do PDF no banco com a pendência e devolve `blocked`. Como cada pedido ao
   portal devolve outra URL (outra identidade), pedir de novo ali poria um segundo PDF na conversa. O
   predicado pergunta à conversa pelo token (`EntregaPublicada.para`, que acha também a pendente); o
   varredor retoma o envio. Tem teste com duas URLs.
7. **`concluir` deixa a exceção subir; `encerrar` não.** Na `main`, uma publicação que levantava no
   `finish_done` subia até `advance`, que tentava a passada de novo. Engolir aqui fecharia a linha em
   `done` sem desfecho. Tem teste pelo motor.
8. **Fecho também no `completed`.** Antes, a cotação em que todas cotavam terminava em `done` sem frase
   nenhuma. Agora ela recebe o fecho de quem tem resultado, como o enunciado pede para "o `done` com
   resultado".
9. **O varredor fala no estado "comparativo por tentar".** `Fecho#resta_entregar?` ganhou
   `comparativo_por_tentar?`: a linha abandonada entre uma tentativa que falhou e a seguinte recebe o
   fecho de quem tem resultado (tem teste pelo motor e no `nenhum_estado_mudo`). Consequência declarada,
   por leitura de código e sem teste próprio: a linha gravada pela `main` com portal fechado, preço
   entregue, geração do PDF falha e morte antes do `finish!` também passa a receber essa frase pelo
   varredor, onde a `main` calava.

## Riscos de regressão verificados, e como

| leitor / risco | o que foi feito |
|---|---|
| `ToolRun#conta_como_pedido?` / `pedido_repetido` | `done` e `failed` já eram tratados igual; exemplo pelo motor: linha `done` conta como pedido e é devolvida por `pedido_repetido` |
| `PedidoRepetido` (texto do especialista) | mesmo exemplo: "já terminou nesta conversa", "(concluída)", "2 resultados encaminhados para publicação" |
| `Insurance::Medida` (Super Admin) | não lê status; exemplo pelo motor: `cotacoes: 1, seguradoras_acionadas: 5, seguradoras_com_preco: 2` — `entregues` só avança em `precos`, que não mudou |
| `ReapStaleRunsJob` | código intocado; specs existentes verdes; exemplo novo da linha abandonada em nova tentativa |
| execução em voo no deploy | exemplo com o handle que a `main` grava depois da segunda consulta: um PDF, um desfecho; e com a frase parcial da versão anterior já publicada: nenhum fecho novo ao lado |
| nenhum estado mudo | `insurance_quote_nenhum_estado_mudo_spec` estendido: 5 estados novos × 4 desfalques do especialista |
| specs de encerramento | `async_run_job_encerramento_parcial_spec`, `encerramento_spec`, `reap_stale_runs_job_spec`: sem alteração de exemplo existente, verdes |

## Specs existentes alterados, e por quê

Todos pelo comportamento que o enunciado muda; nenhuma asserção de encerramento foi tocada.

- `async_publisher_spec`: 7 exemplos afirmavam o link de reserva publicado (download, HTTP, armazenamento,
  tipo, anexo, commit, retry) → afirmam nada publicado, `blocked`, motivo no log e blob na limpeza; 2
  exemplos que afirmavam a causa na linha "publish failed" passam a achá-la na linha "anexo falhou"
  (sem a reserva não há segunda mensagem levantando). Exemplo novo: o retry que acha o arquivo no ar
  continua `published` mesmo com o download falhando.
- `async_run_job_comparativo_arquivo_spec`: 4 exemplos do link → sem link; na consulta, a execução
  segue para a nova tentativa.
- `insurance_quote_comparativo_arquivo_spec`: reserva sem link; forma recusada não entrega nada.
- `insurance_quote_ramo_auto_spec`: reserva sem link; PDF que não sai volta `running` (os preços continuam).
- `insurance_quote_fronteira_de_saida_spec` ("texto que não sobrevive à fronteira…"): consultava duas
  vezes a mesma oferta única `quoted` com status geral `running` — estado que o adapter não produz
  (`quoted` com o negócio aberto é `partial`). Pela regra nova a segunda consulta encerrava. O Arrange
  ganhou uma seguradora ainda `running`, e as asserções ficaram as mesmas.
- `progress_spec`: só o comentário de um exemplo.

## Testes

Ambiente: `PATH="$HOME/.rbenv/shims:$PATH"` (ruby 3.4.4, bundler 2.5.16), `RAILS_ENV=test`,
`DISABLE_BOOTSNAP=1`. O stdout do rspec neste terminal é resumido por um wrapper; os números abaixo
foram lidos do JSON que o próprio rspec grava (`--format json --out`) e o exit code, de arquivo.

| rodada | escopo | resultado | exit |
|---|---|---|---|
| base (código intocado, `3f08e37c7c`) | `spec/jobs/autonomia/agents/tools`, `spec/services/autonomia/agents/tools`, `tool_run_spec`, `spec/services/autonomia/insurance`, `insurance_measurements_controller_spec`, `requests/.../autonomia/insurance`, `answerer_duvida_durante_cotacao_spec`, `responder_async_spec` | 1017 exemplos, 0 falhas | 0 |
| RED (specs novos e alterados, `app/` intocado) | 10 arquivos | 273 exemplos, 65 falhas (+1 ajustado e conferido depois: 66) | 1 |
| GREEN (mesmo escopo da base, código final) | idem base + 2 arquivos novos | 1078 exemplos, 0 falhas | 0 |
| final (depois das mutações, md5 de `app/` igual antes e depois) | `spec/services/autonomia`, `spec/jobs/autonomia`, `spec/models/autonomia`, `spec/requests/api/v1/accounts/autonomia`, `spec/controllers/super_admin` | 1650 exemplos, 0 falhas, 3 pendentes (quarentena anterior: `registration_checkout/provisioner_spec`, `sso/provisioner_spec`) | 0 |

Rubocop com lista explícita dos 21 arquivos tocados (10 de `app/`, 11 de `spec/`): 0 ofensas, exit 0.
`rails zeitwerk:check`: "All is good!", exit 0.

### Mutações

Uma por vez, pelo driver em Ruby (original em memória, âncora conferida como única, restauração com md5
conferido), contra 11 arquivos de spec (299 exemplos). Resultado em três estados: PEGA / SOBREVIVEU /
ERRO (erro de carga ou zero exemplos). **22 mutações, 22 PEGA, 0 sobreviventes, 0 erros; originais
restaurados com md5 igual.**

| id | mutação | resultado | exemplos que caíram (amostra) |
|---|---|---|---|
| M1 | `finished?` só com `completed`/`failed` | PEGA 36 | fecha_sem_esperar (ferramenta) :76 :102 :128 |
| M2 | sem a exigência de leitura anterior | PEGA 47 | quote_offers :206 :220; ferramenta :90 |
| M3 | sem a cobertura das acionadas | PEGA 3 | quote_offers :214 :220; ferramenta :119 |
| M4 | lista negra (só `running` segura) | PEGA 1 | quote_offers :199 |
| M5 | `error` fora dos desfechos | PEGA 2 | quote_offers :183; ferramenta :102 |
| M6 | PDF que não sai encerra sem nova tentativa | PEGA 12 | ferramenta :141 :164 :233 |
| M7 | sem teto de tentativas | PEGA 12 | ferramenta :164 :256; motor :257 |
| M8 | comparativo emitido conta como assumido sem aceite | PEGA 3 | ferramenta :184; motor :202 :273 |
| M9 | sem a busca da mensagem na conversa | PEGA 2 | ferramenta :212; motor :231 |
| M10 | `done` encerra com o arquivo recusado | PEGA 5 | motor :202 :231 :273 |
| M11 | qualquer entrega recusada segura o `done` | PEGA 1 | motor :448 |
| M12 | `done` sem o fecho de quem tem resultado | PEGA 23 | motor :132 :174 :202 |
| M13 | `done` sem a pergunta à conversa | PEGA 2 | motor :312; encerramento :416 |
| M13b | `concluir` engolindo a exceção | PEGA 2 | motor :420; encerramento :438 |
| M14 | fecho também para a pergunta pelo dado | PEGA 2 | encerramento :406 :438 |
| M15 | `finish_done` da `main` | PEGA 20 | motor :132 :174 :202 |
| M16 | download que falha publica a reserva | PEGA 11 | motor :202 :273 :400 |
| M17 | anexo que falha publica a reserva | PEGA 2 | publicador :685 :936 |
| M18 | falha sem procurar a mensagem no ar | PEGA 1 | publicador :487 |
| M19 | forma recusada vira texto com o link | PEGA 3 | ferramenta :233; comparativo :104; job comparativo :131 |
| M20 | reserva volta a carregar o link | PEGA 3 | ferramenta :246; comparativo :72; ramo_auto :440 |
| M21 | `resta_entregar?` sem o comparativo por tentar | PEGA 6 | ferramenta :256; motor :371; nenhum_estado_mudo :289 |

"ferramenta" = `insurance_quote_fecha_sem_esperar_o_portal_spec`; "motor" =
`async_run_job_fecha_sem_esperar_o_portal_spec`. Linhas no estado do código em que a rodada rodou.

## O que NÃO foi verificado

- **Portal real.** Nada rodou contra o AGGER nesta fatia; o caminho foi exercitado com o conector
  `mock` respondendo, passada a passada, a forma medida (dados sintéticos).
- **Primeira leitura com lista parcial de cálculos.** Não observada. A guarda da leitura anterior só
  protege se a seguradora faltante aparecer antes da segunda leitura.
- **Independência das falhas do 504.** O teto de 3 assume; uma instabilidade do portal que dure mais que
  três tentativas termina sem PDF (como antes, sem link).
- **Download que falha numa publicação ADIADA.** Com a cadeia humanizada do turno aberta, o comparativo
  é aceito no adiamento e o motor encerra; se o download falhar depois, no `AsyncPublishJob`, ninguém
  pede outro. O cliente fica sem PDF e sem link (antes recebia o link). Não há teste de nova tentativa
  para esse caminho, porque ela não existe.
- **Morte do worker entre `record_attempt!` e a publicação do desfecho no `done`.** Com o portal fechado
  e o comparativo aceito, o varredor fecha em silêncio — os specs existentes afirmam esse silêncio
  ("a cotação que já entregou tudo fecha em silêncio") e não foram afrouxados. Nesse intervalo, o
  cliente fica com preços e PDF e sem a frase de fecho. É decisão de produto se o varredor deve dizer o
  fecho ali; ela muda a asserção desses specs.
- **Duas passadas concorrentes na mesma linha (R19/#418).** Podem pedir dois comparativos (URLs
  diferentes). Risco anterior a esta fatia; as novas tentativas acrescentam passadas no fim.
- **Ordem PDF × fecho com as duas publicações adiadas.** Os dois `AsyncPublishJob` podem sair em ordem
  trocada. Anterior a esta fatia (o encerramento por prazo tinha o mesmo desenho).
- **A frase `comparativo_reserva` continua sendo pedida ao especialista** com a descrição "apresenta o
  LINK do comparativo" e não sai mais. Mantida para não mudar md5 e contagem do schema.
- **Instruções dos agentes** (`principal.md`, `especialista_auto.md`) não foram revistas para o fecho mais
  cedo.
- **Linhas de log mudaram** (`; vai como link` → `; nao publicado`; a dupla falha do anexo não gera mais
  "publish failed"). Não verifiquei se há alerta ou painel lendo essas strings.
- **Suíte completa do repositório** não foi rodada; os diretórios rodados estão em "Testes".

## Deploy e rollback

- Sem migration, sem env var, sem mudança de schema de ferramenta.
- Rollback: reverter o commit. Linhas `running` com `comparativo_tentativas` no handle voltam a esperar
  `completed`/`failed`/prazo (a chave é ignorada pela versão anterior). Entregas de arquivo serializadas
  por esta versão continuam válidas na anterior (a `reserva` segue na forma, só sem o link).
- Ponta do rollback, por leitura de código e sem teste: a linha que estava entre duas tentativas do
  comparativo no instante do rollback tem `portal_fechado` gravado e nenhum comparativo emitido. A
  versão anterior, no prazo, emite o comparativo pelo encerramento, mas o `resta_entregar?` dela lê o
  portal fechado e não publica frase de fecho. Janela: as linhas em nova tentativa no minuto do rollback.
- O link volta ao cliente com o rollback (é o comportamento da versão anterior).
