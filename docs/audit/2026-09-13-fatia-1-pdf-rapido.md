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

**Rodada 2:** a regra mudou. `todas_com_desfecho?(ja_acionadas, assentada_anterior)` exige a leitura atual
com toda oferta com desfecho, com o MESMO conjunto de códigos da leitura imediatamente anterior, e cobrindo
as acionadas (ver "Rodada 2", item 5).

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

Toda passada que devolve `done` grava `conclusao_devolvida` no handle; se o processo morrer antes do
desfecho, o varredor lê a marca como sobra e publica o mesmo fecho (decisão 10).

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
   encerramento. Exigir uma leitura anterior custa um intervalo de consulta, o que segue a passada em que
   o desfecho completo apareceu: 3 s só quando ele aparece até a segunda consulta, e 13 a 21 s nas cotações
   medidas (rodada 2: "O intervalo real da estabilidade"; a regra virou a de duas leituras iguais). Efeito colateral medido: os exemplos
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
   seguidas acontecem em 0,8% das cotações; a independência das falhas não foi medida. O teto não garante
   tempo. A conta da rodada 1 (~101 s por tentativa) esquecia a leitura do portal e o pedido do
   comparativo, cada um até 65 s: o pior caso é ~171 s por passada de nova tentativa, e o prazo pode vencer
   no meio delas (rodada 2: "Conta de tempo"). E, vencido o prazo, `fail_run` NÃO encerra como antes desta
   fatia: o encerramento pede o comparativo mais uma vez quando sobra tentativa.
5. **O download que falha segura o `done` no motor, e só arquivo.** O download acontece no publicador,
   depois do `poll` e dentro da mesma passada do motor (desde a rodada 2, também antes de adiar); só o motor
   sabe na mesma passada que o arquivo não foi aceito. A regra é restrita a
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
10. **A marca de conclusão (`conclusao_devolvida`) fecha a janela da morte no `done`.** Toda passada que
    devolve `done` grava a marca no handle (`Comparativo#concluir_passada`), e `resta_entregar?` a conta
    como sobra. Sem ela, a passada que persistia o handle (portal fechado, comparativo aceito) e morria
    antes de `finish_done` publicar o desfecho deixava o varredor em silêncio — e essa janela era nova
    em relação à `main` no caminho comum, porque lá a cotação com recusa nunca ficava com o portal
    fechado. A linha gravada pela `main` não tem a marca e continua fechando em silêncio, como afirmam
    os specs existentes ("a cotação que já entregou tudo fecha em silêncio"), que não foram tocados. Tem
    teste pelo motor (o varredor publica o fecho; e não repete o que o `done` publicou antes de morrer)
    e no `nenhum_estado_mudo`.

## Riscos de regressão verificados, e como

| leitor / risco | o que foi feito |
|---|---|
| `ToolRun#conta_como_pedido?` / `pedido_repetido` | `done` e `failed` já eram tratados igual; exemplo pelo motor: linha `done` conta como pedido e é devolvida por `pedido_repetido` |
| `PedidoRepetido` (texto do especialista) | mesmo exemplo: "já terminou nesta conversa", "(concluída)", "2 resultados encaminhados para publicação" |
| `Insurance::Medida` (Super Admin) | não lê status; exemplo pelo motor: `cotacoes: 1, seguradoras_acionadas: 5, seguradoras_com_preco: 2` — `entregues` só avança em `precos`, que não mudou |
| `ReapStaleRunsJob` | rodada 1: código intocado; specs existentes verdes; exemplo novo da linha abandonada em nova tentativa. Rodada 2: o encerramento pelo varredor enfileira o fecho encadeado com a cadeia no teto (`publicar_forcado`); sonda V pelo motor |
| execução em voo no deploy | exemplo com o handle que a `main` grava depois da segunda consulta: um PDF, um desfecho; e com a frase parcial da versão anterior já publicada: nenhum fecho novo ao lado |
| nenhum estado mudo | `insurance_quote_nenhum_estado_mudo_spec` estendido: 6 estados novos × 4 desfalques do especialista |
| morte entre gravar o `done` e publicar o desfecho | exemplos pelo motor: o varredor publica o fecho pela marca de conclusão; e não repete o que o `done` publicou antes de morrer |
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
| GREEN (mesmo escopo da base) | idem base + 2 arquivos novos | 1078 exemplos, 0 falhas | 0 |
| RED da marca de conclusão (código do primeiro commit) | ferramenta, motor e `nenhum_estado_mudo` | 102 exemplos, 7 falhas | 1 |
| GREEN com a marca (mesmo escopo da base) | idem | 1087 exemplos, 0 falhas | 0 |
| final do primeiro commit (`347bbf7`, depois da rodada 1 de mutações) | `spec/services/autonomia`, `spec/jobs/autonomia`, `spec/models/autonomia`, `spec/requests/api/v1/accounts/autonomia`, `spec/controllers/super_admin` | 1650 exemplos, 0 falhas, 3 pendentes | 0 |
| final (código com a marca, depois da rodada 2 de mutações; md5 de `app/` igual antes e depois) | idem | 1658 exemplos, 0 falhas, 3 pendentes (quarentena anterior: `registration_checkout/provisioner_spec`, `sso/provisioner_spec`) | 0 |

CI do fork ("Testes do fork": Rubocop, Brakeman e bundle-audit, ESLint, Vitest e RSpec em 8 partes, a
suíte inteira) no `70438d5` — primeiro commit mais a correção de comentários, sem a marca: 12 jobs
`success`.

Rubocop com lista explícita dos arquivos tocados (10 de `app/`, 11 de `spec/`): 0 ofensas, exit 0.
`rails zeitwerk:check`: "All is good!", exit 0.

### Mutações

Uma por vez, pelo driver em Ruby (original em memória, âncora conferida como única, restauração com md5
conferido), contra 11 arquivos de spec. Resultado em três estados: PEGA / SOBREVIVEU / ERRO (erro de
carga ou zero exemplos).

- **Rodada 1** (código do primeiro commit, 299 exemplos): 22 mutações, 22 PEGA.
- **Rodada 2** (código final, com a marca de conclusão, 307 exemplos): **24 mutações, 24 PEGA, 0
  sobreviventes, 0 erros; originais restaurados com md5 igual.** A tabela é a da rodada 2.

| id | mutação | resultado | exemplos que caíram (amostra) |
|---|---|---|---|
| M1 | `finished?` só com `completed`/`failed` | PEGA 39 | ferramenta :76 :102 :128 |
| M2 | sem a exigência de leitura anterior | PEGA 47 | quote_offers :206 :220; ferramenta :90 |
| M3 | sem a cobertura das acionadas | PEGA 3 | quote_offers :214 :220; ferramenta :119 |
| M4 | lista negra (só `running` segura) | PEGA 1 | quote_offers :199 |
| M5 | `error` fora dos desfechos | PEGA 2 | quote_offers :183; ferramenta :102 |
| M6 | PDF que não sai encerra sem nova tentativa | PEGA 13 | ferramenta :141 :164 :233 |
| M7 | sem teto de tentativas | PEGA 13 | ferramenta :164 :266 :276 |
| M8 | comparativo emitido conta como assumido sem aceite | PEGA 3 | ferramenta :184; motor :202 :273 |
| M9 | sem a busca da mensagem na conversa | PEGA 2 | ferramenta :212; motor :231 |
| M10 | `done` encerra com o arquivo recusado | PEGA 5 | motor :202 :231 :273 |
| M11 | qualquer entrega recusada segura o `done` | PEGA 1 | motor :496 |
| M12 | `done` sem o fecho de quem tem resultado | PEGA 24 | motor :132 :174 :202 |
| M13 | `done` sem a pergunta à conversa | PEGA 2 | motor :312; encerramento :416 |
| M13b | `concluir` engolindo a exceção | PEGA 2 | motor :468; encerramento :438 |
| M14 | fecho também para a pergunta pelo dado | PEGA 2 | encerramento :406 :438 |
| M15 | `finish_done` da `main` | PEGA 21 | motor :132 :174 :202 |
| M16 | download que falha publica a reserva | PEGA 11 | motor :202 :273 :448 |
| M17 | anexo que falha publica a reserva | PEGA 2 | publicador :685 :936 |
| M18 | falha sem procurar a mensagem no ar | PEGA 1 | publicador :487 |
| M19 | forma recusada vira texto com o link | PEGA 3 | ferramenta :233; comparativo :104; job comparativo :131 |
| M20 | reserva volta a carregar o link | PEGA 3 | ferramenta :246; comparativo :72; ramo_auto :440 |
| M21 | `resta_entregar?` sem o comparativo por tentar | PEGA 6 | ferramenta :276; motor :371; nenhum_estado_mudo :304 |
| M22 | `resta_entregar?` sem a marca de conclusão | PEGA 6 | ferramenta :266; motor :395; nenhum_estado_mudo :289 |
| M23 | `done` sem gravar a marca de conclusão | PEGA 6 | ferramenta :256; motor :395; nenhum_estado_mudo :289 |

"ferramenta" = `insurance_quote_fecha_sem_esperar_o_portal_spec`; "motor" =
`async_run_job_fecha_sem_esperar_o_portal_spec`. Linhas no estado do código em que a rodada rodou.

## O que NÃO foi verificado

- **Portal real.** Nada rodou contra o AGGER nesta fatia; o caminho foi exercitado com o conector
  `mock` respondendo, passada a passada, a forma medida (dados sintéticos).
- **Primeira leitura com lista parcial de cálculos.** Não observada. A guarda da leitura anterior só
  protege se a seguradora faltante aparecer antes da segunda leitura.
- **Independência das falhas do 504.** O teto de 3 assume; uma instabilidade do portal que dure mais que
  três tentativas termina sem PDF (como antes, sem link).
- **Download que falha numa publicação ADIADA.** Era o defeito que reprovou a rodada 1, declarado aqui sem
  a gravidade dele. Corrigido na rodada 2: o publicador baixa e grava antes de adiar (item 1; sonda A).
- **A linha da `main` na janela da morte do `done`.** Uma linha gravada pela versão anterior com o portal
  fechado e o comparativo aceito, abandonada antes do `finish!`, fecha em silêncio pelo varredor (é o
  que os specs existentes afirmam, e não foram tocados). Só a linha desta versão tem a marca de
  conclusão (decisão 10). É decisão de produto se o varredor deve dizer o fecho também na linha antiga.
- **Morte entre a publicação ADIADA do desfecho e o `finish!` com o Redis fora.** O `AsyncPublishJob`
  não entra na fila, `concluir` levanta e a passada é tentada de novo; se o processo morrer antes, o
  varredor publica o fecho pela marca. Não há teste com o Redis fora nesse ponto.
- **Duas passadas concorrentes na mesma linha (R19/#418).** Podem pedir dois comparativos (URLs
  diferentes). A rodada 1 disse "risco anterior a esta fatia", e não é inteiro: na `main` a cotação com
  recusa gerava o comparativo sob `autonomia_closed`, e nesta fatia ela gera no `fechar`, sem a marca. Ver
  R2-4, que também responde se a marca deveria cobrir o `fechar` (não).
- **Ordem PDF × fecho com as duas publicações adiadas.** Corrigido na rodada 2: o fecho é encadeado ao PDF
  adiado (item 6; sonda V).
- **A frase `comparativo_reserva` continua sendo pedida ao especialista** e não sai mais. Na rodada 1 a
  descrição ainda dizia que o link vinha abaixo; na rodada 2 ela diz "Frase curta sobre o comparativo em
  PDF, guardada junto do arquivo. Não escreva link nem endereço de site." A chave continua no schema.
- **Instruções dos agentes** (`principal.md`, `especialista_auto.md`) não foram revistas para o fecho mais
  cedo.
- **Linhas de log mudaram** (`; vai como link` → `; nao publicado`; a dupla falha do anexo não gera mais
  "publish failed"). Não verifiquei se há alerta ou painel lendo essas strings.
- **Suíte completa do repositório** não foi rodada; os diretórios rodados estão em "Testes".

## Rodada 2 (13/09/2026): a reprovação da PR #422 em `29a5cf9c98`

### A causa raiz

A revisão adversarial reprovou a rodada 1 por uma causa: o download do comparativo acontecia no
publicador DEPOIS de o motor ler o adiamento como aceite. Com a cadeia humanizada do turno aberta (o
cliente escreveu no meio, o `ChunkedDeliveryJob` abortou), o publicador adiava a entrega de arquivo sem
baixar nada; o motor fechava `done` e publicava o fecho; no `AsyncPublishJob` o download falhava e ninguém
pedia outro PDF (sonda A). A sentinela `comparativo_enviado`, gravada na emissão, ainda impedia o
encerramento por prazo de pedir de novo (sonda B). Vieram junto: a lista de ofertas que cresce entre
leituras fechava com a lista parcial (C), o PDF aceito com os preços recusados fechava sem frase (E), o
fecho podia sair antes do PDF adiado (V) e o especialista lia "concluída" sem o PDF ter saído (U).

### O que mudou, por item

1. **Blob antes de adiar** (`AsyncPublisher::Arquivos#publicar_arquivo`). O publicador baixa (`SafeFetch`,
   20 s) e grava o blob, com a marca da execução, ANTES de decidir se adia. O download que falha volta
   `blocked` na mesma passada; `AsyncRunJob#arquivo_recusado?` reagenda e `fechar` pede outro comparativo
   (teto 3). O "PDF que não saiu" do download é o mesmo do 504: mesma nova tentativa, mesmo teto.
2. **URL fora do Sidekiq.** A publicação adiada carrega `Tools::ArquivoGravado` (id assinado do blob,
   legenda, token), sem a URL; motor, `AsyncPublishJob` e varredor enfileiram `Result#adiada`. O job só
   anexa (`publicar_gravado`), conferindo que o blob é desta execução e desta finalidade (metadata). Um job
   enfileirado pela versão anterior, com a URL, ainda é reconhecido: o publicador baixa e grava.
3. **O blob da tentativa abandonada é limpo.** A forma gravada que chega a uma execução morta vai para a
   limpeza (`recusar_na_entrada`); o job adiado perdido (Redis) deixa o blob marcado e sem anexo, e o
   varredor o apaga depois de `BLOB_SEM_DONO_IDADE` (1 h) por `EntregaDeArquivo.blobs_sem_dono`. Os dois
   caminhos têm teste pelo motor.
4. **Sentinela só com blob.** `comparativo_enviado` deixou de ser gravada na emissão
   (`Fecho#marcas_do_comparativo` grava só a identidade). `Comparativo#concluir_passada` a grava na passada
   que encontra o comparativo assumido (identidade na lista do aceite ou numa mensagem da conversa).
   `closing_deliveries` decide por `comparativo_por_tentar?`: o encerramento por prazo pede de novo.
5. **Estabilidade da lista.** `QuoteOffers#assentada` (os códigos, quando toda oferta tem desfecho) é gravada
   a cada consulta em `leitura_assentada`; `todas_com_desfecho?(ja_acionadas, assentada_anterior)` exige a
   leitura atual assentada, com o MESMO conjunto da leitura imediatamente anterior, cobrindo as acionadas.
   Nenhuma das duas leituras pode ter oferta em andamento.
6. **Fecho depois do PDF.** `Tools::EntregaEncadeada` (texto e token de que ele depende). O encerramento
   encadeia o fecho à entrega que ele mesmo adiou (`@adiada`) ou à que a ferramenta diz estar aceita e sem
   mensagem (`entrega_a_caminho`: o comparativo adiado). O publicador adia a encadeada enquanto não houver
   mensagem com o token. O `AsyncPublishJob` tem dois tetos no mesmo contador de adiamentos: a cadeia do
   turno até 30 (90 s) e a dependência até 60 (180 s). O varredor (`publish!`) ignora a cadeia e continua
   esperando a dependência; o job que ele enfileira já começa em 30, e espera até 90 s. No teto, o fecho sai
   sem ela: fora de ordem, nunca em silêncio.
7. **Sonda E.** `Fecho#resultado_entregue?` conta o comparativo assumido.
8. **Reentrada depois de uma passada morta.** `Comparativo#fechar` grava a identidade e a contagem na linha
   antes de publicar o arquivo (`gravar_na_linha`). O `record_attempt!` só vem depois da publicação; morto o
   processo no meio, a mesma passada rodava de novo, pedia outro comparativo (outra URL, outra identidade) e
   o cliente recebia dois PDFs. Teste com a publicação imediata e com a adiada.
9. **Textos corrigidos.** `comparativo.rb` (cabeçalho e teto), `texto_ao_cliente.rb` (a reserva não leva
   URL), `async_run_job.rb` ("a adiada sai sozinha" era falso para arquivo), `encerramento.rb` (idem),
   `frases.rb` (a descrição de `comparativo_reserva` dizia ao modelo que o link vinha abaixo),
   `insurance_quote.rb` (`comparativo_enviado`, `comparison_pdf`), `fecho.rb` (comentário de
   `marcas_do_comparativo`, `comparison_pdf`, 60 s), e "`comparativo_enviado` impede nova emissão" em
   `reap_stale_runs_job.rb`, `retomada_de_envio.rb`, `async_publisher.rb` e em comentários de três specs
   (`reap_stale_runs_job_spec`, `async_run_job_encerramento_parcial_spec`, `insurance_quote_ramo_auto_spec`). Nesta auditoria:
   decisões 1 e 4, a nota de concorrência e o rollback.

### O intervalo real da estabilidade

A leitura a mais custa o intervalo que segue a passada em que o desfecho completo apareceu. Com a
progressão padrão `[3, 3, 5, 5, 8, 8, 13, 13, 21]` as consultas saem por volta de 3, 6, 11, 16, 24, 32, 45,
58 e 79 s, e depois de 21 em 21 s (sem somar a duração de cada consulta). O custo é 3 a 5 s até 16 s, 8 s até
32 s, 13 s até 58 s e 21 s depois. Nas três cotações medidas (desfecho completo aos 41, 64 e 98 s): mais 13,
21 e 21 s. Com `async_poll_intervals` do agente, até 60 s. A decisão 1 da rodada 1 dizia 3 s, e 3 s só vale
para o desfecho completo até a segunda consulta.

### Conta de tempo, com os números reais

- O prazo é 420 s e só é conferido no começo de uma passada (`AsyncRunJob#stop?`).
- Pior caso de uma passada de nova tentativa: 21 s de intervalo, até 65 s de `quote_result`
  (`READ_TIMEOUT` 60 + `OPEN_TIMEOUT` 5), até 65 s de `quote_proposal` e até 20 s de download: ~171 s. A
  renovação de sessão (`with_fresh_session`) pode somar um login por chamada e não está na conta.
- Três tentativas no pior caso passam de 500 s: o prazo vence no meio delas. A passada em curso termina (nada
  a interrompe); a seguinte encontra o prazo vencido e vai a `fail_run`, cujo encerramento pede o comparativo
  mais uma vez quando sobra tentativa (até ~85 s a mais). O total de pedidos ao portal continua limitado a 3.
- Pior caso de relógio até o fecho: uma passada que começa aos ~419 s dura até ~150 s, mais 21 s de
  intervalo, mais o encerramento: ~675 s. É o caso em que toda chamada ao portal bate no timeout.
- Testes (`async_run_job_pdf_antes_do_adiamento_spec`): o prazo que vence durante a passada cujo download
  falha (o encerramento pede de novo; um fecho, depois do PDF); o prazo com o teto esgotado (não pede; um
  fecho); o prazo com tentativa sobrando e o portal fora (pede uma vez; fecho sem PDF); o mesmo com a cadeia
  aberta (o PDF do encerramento sai adiado e o fecho depois dele); e, sem prazo, o teto esgotado encerra
  `done` sem o PDF, com um fecho.

### Decisões onde o desenho não fechou sozinho (rodada 2)

R2-1. **O download antes de adiar alonga a passada do motor** em até 20 s, fora do lock da conversa. A
      alternativa, baixar no job e fazer o job reabrir a execução, exigiria o job decidir nova tentativa com a
      linha já `done`.

R2-2. **A publicação adiada ainda pode ser recusada depois do aceite** (autorização caída entre a passada e o
      job, erro de banco ao anexar). O blob existe, ninguém pede outro PDF e o cliente fica sem ele. O que saiu
      desse caminho foi o download, que é a falha medida.

R2-3. **O fecho encadeado espera no máximo 180 s pela dependência** (90 s quando quem o enfileira é o
      varredor), e depois sai sem ela.

R2-4. **`autonomia_closed` NÃO deve cobrir o `fechar`.** Na `main`, a cotação com recusa (que nunca vira
      `completed`) gerava o comparativo no encerramento por prazo, sob `autonomia_closed`, adquirida no banco
      antes do trabalho: duas passadas concorrentes não geravam dois comparativos (e uma passada morta depois
      da marca não gerava nenhum). Nesta fatia ela gera no `fechar`, sem essa marca, e isso é novo. A
      marca é de uma vez só ("quem não adquire não repete o trabalho"): cobrindo o `fechar`, a primeira
      tentativa que falhasse a adquiriria e nenhuma nova tentativa aconteceria, nem a do encerramento por
      prazo, que adquire a mesma marca. O que fica:
      - a reentrada SEQUENCIAL (o mesmo job de novo, depois de o processo morrer) está fechada pela escrita
        imediata do item 8, com uma janela de milissegundos: entre o `perform_later` do PDF adiado e o
        registro do aceite;
      - duas passadas SIMULTÂNEAS da mesma linha continuam podendo pedir dois comparativos. Há dois caminhos:
        o hard shutdown do Sidekiq (o job reenfileirado roda enquanto o antigo ainda vive por milissegundos) e
        uma corrente de jobs duplicada (o `perform_later` do reagendamento levanta depois de o Redis aceitar,
        e `retry_or_fail` reagenda de novo). Uma aquisição por tentativa antes do pedido não bastaria sozinha:
        o `record_attempt!` de uma passada regrava o handle da outra com a cópia em memória, identidade do
        comparativo incluída (R19, #418). Não medido; a proposta é tratar junto da #418.

R2-5. **A sonda E muda a frase**: preços recusados e PDF aceito recebem o fecho de quem tem resultado (na
      rodada 1, nenhuma frase). A `main` publicava a frase parcial por `delivered_count` nesse estado.

R2-6. **O pedido repetido enquanto o PDF não saiu**: a linha está `running`, e o especialista lê que a
      consulta está em andamento (sonda U), não "concluída".

R2-7. **A nova tentativa pede outra URL ao portal, e não reemite uma URL gravada.** É a decisão que a #414
      deixou pendente ("reemitir com a URL GRAVADA no handle"). A URL não tem assinatura e leva o nome do
      segurado no caminho: gravá-la no handle poria esse dado na linha. O risco que a #414 aponta para a URL
      nova, o segundo PDF para quem recebeu o primeiro por um caminho que não se vê (a publicação adiada),
      fica coberto porque o aceite de arquivo só existe com o blob gravado e a mensagem é procurada pelo
      token. A outra metade da #414, dizer ao cliente que o comparativo não chegou quando o teto se esgota,
      continua aberta: o fecho que sai é o de quem tem resultado, sem falar do PDF.

### Sondas do revisor, antes e depois

O arquivo do revisor (`probe_revisor_spec.rb`, fora do repositório) rodado sem mudança no código da rodada 2:
10 exemplos, 6 falhas (exit 1): A, C, E, K, O e V. Só C cai com certeza pela correção; nas outras cinco a
passada que a sonda trata como a que fecha passou a ser a primeira leitura assentada, e a falha mede o
intervalo, não o defeito. Por isso rodei também uma cópia com UMA leitura a mais, igual, antes da passada
que cada sonda tratava como a que fecha (exceto C, em que a leitura a mais é a própria correção), sem tocar
nas afirmações: 10 exemplos, 3 falhas (exit 1).

| sonda | em `29a5cf9c98` | rodada 2 (cópia com a leitura a mais) | estado impresso na rodada 2 |
|---|---|---|---|
| A: PDF adiado, download falha | passa | **cai** (`running`) | preços; sem fecho; tentativas 1; a passada seguinte pede outro |
| B: prazo depois do download recusado | passa | **cai** (2 pedidos) | preços, PDF, fecho |
| B2: contraste, geração falha | passa | passa | preços, PDF, fecho |
| C: lista que cresce | passa | **cai** (`running`) | o preço da 47 sai; a cotação segue aberta |
| D: varredor em linha da `main` | passa | passa | preços, um fecho (decisão 9 da rodada 1) |
| E: preços recusados, PDF aceito | passa | passa (afirma só `done`) | PDF, fecho |
| K: varredor depois do download recusado | passa | passa | preços, um fecho, sem pedido novo (`trabalho_novo: false`) |
| O: linha da `main` com o link | passa | passa | nenhum segundo comparativo |
| V: fecho adiado e varredor | passa | passa | preços, PDF, fecho, nesta ordem |
| U: pedido repetido | passa (afirma `conta_como_pedido?`) | passa | "consulta que já está em andamento" |

As sondas viraram testes do repositório com a afirmação do avesso em `async_run_job_pdf_antes_do_adiamento_spec`.

### Specs alterados na rodada 2

- Novos: `async_run_job_pdf_antes_do_adiamento_spec` (16 exemplos) e `async_publish_job_spec` (3).
- `async_publisher_spec`: o exemplo "espera a cadeia humanizada como qualquer entrega, sem baixar nada antes da
  hora" afirmava o defeito (adiar sem baixar) e foi substituído por "baixa e grava antes de adiar, e a entrega
  adiada carrega o blob, sem a URL"; mais 3 exemplos de arquivo e 3 do texto encadeado.
- `quote_offers_spec`: o bloco de `todas_com_desfecho?` virou `#assentada e #todas_com_desfecho?` (9 exemplos).
- `insurance_quote_fecha_sem_esperar_o_portal_spec` e `async_run_job_fecha_sem_esperar_o_portal_spec`: os
  exemplos que fechavam com uma leitura assentada passam a fazer duas (helpers e renumeração das passadas); o
  `comparativo_enviado` passa a ser afirmado em branco na emissão e gravado quando assumido.
- `insurance_quote_nenhum_estado_mudo_spec`: o helper grava a leitura assentada.
- `insurance_quote_fronteira_de_saida_spec`, `insurance_quote_ramo_auto_spec`, `async_run_job_comparativo_arquivo_spec`:
  a identidade sem a sentinela na emissão.
- `builder_instrucao_do_especialista_spec` (`gerar_comparativo`) e `base_contrato_de_nivel_spec`
  (`entrega_a_caminho`).
- `async_run_job_encerramento_parcial_spec` e `reap_stale_runs_job_spec`: só comentários. Nenhuma asserção de
  encerramento foi afrouxada.

### Testes da rodada 2

Mesmo ambiente da rodada 1; números lidos do JSON do rspec e exit code de arquivo.

| rodada | escopo | resultado | exit |
|---|---|---|---|
| RED: as sondas viradas em spec, contra o código de `29a5cf9c98` | `async_run_job_pdf_antes_do_adiamento_spec` (9 exemplos na época) | 9 exemplos, 9 falhas, pelos defeitos: `done` onde se afirma `running`, fecho antes dos adiados, fecho antes do PDF, blob inexistente antes de adiar | 1 |
| GREEN do mesmo arquivo, código da rodada 2 | idem | 9 exemplos, 0 falhas | 0 |
| primeira ampla da rodada 2, antes de adaptar os specs existentes | escopo da base da rodada 1 | 1096 exemplos, 49 falhas | 1 |
| ampla intermediária | escopo final | 1685 exemplos, 1 falha: `async_run_job_comparativo_arquivo_spec` afirmava a sentinela gravada na emissão (troquei pela identidade gravada e a sentinela em branco) | 1 |
| base das mutações | 14 arquivos de spec | 347 exemplos, 0 falhas | 0 |
| **final** (md5 de `app/` e `spec/` igual antes e depois) | `spec/services/autonomia`, `spec/jobs/autonomia`, `spec/models/autonomia`, `spec/requests/api/v1/accounts/autonomia`, `spec/controllers/super_admin` | **1685 exemplos, 0 falhas, 3 pendentes** (quarentena anterior: `provisioner_spec`) | **0** |
| sondas do revisor, arquivo sem mudança | 10 exemplos | 6 falhas (ver acima) | 1 |
| sondas do revisor, cópia com a leitura a mais | 10 exemplos | 3 falhas: A, B, C | 1 |

Rubocop com lista explícita dos 32 arquivos Ruby tocados (18 de `app/`, 14 de `spec/`): 0 ofensas, exit 0.
`rails zeitwerk:check`: "All is good!", exit 0.

### Mutações da rodada 2

Mesmo driver da rodada 1, com as âncoras do código da rodada 2, contra 14 arquivos de spec (347 exemplos).
**39 mutações. Na rodada completa, 38 PEGA e 1 SOBREVIVEU (F6); 0 erros; originais restaurados, md5 de
`app/` e `spec/` igual antes e depois.** F6 sobreviveu porque o exemplo que devia pegá-la ("com a cadeia
aberta, o PDF do encerramento sai adiado…") usava a mesma URL nas duas tentativas, e com a mesma URL a
identidade gravada no handle já apontava para o PDF do encerramento. Na produção cada pedido devolve outra
URL: o exemplo passou a usar duas, e F6 re-rodada sozinha: PEGA. Linhas no estado em que cada rodada rodou.

"motor-pdf" = `async_run_job_pdf_antes_do_adiamento_spec`; "ferramenta" =
`insurance_quote_fecha_sem_esperar_o_portal_spec`; "motor" = `async_run_job_fecha_sem_esperar_o_portal_spec`;
"job" = `async_publish_job_spec`; "job comparativo" = `async_run_job_comparativo_arquivo_spec`.

| id | mutação | resultado | exemplos que caíram (amostra) |
|---|---|---|---|
| B1 | blob antes de adiar: adia a entrega de arquivo sem baixar (o desenho da rodada 1) | PEGA 8 | motor-pdf :126 :152 :190 |
| B2 | URL fora do Sidekiq: o motor enfileira a entrega com a URL | PEGA 2 | motor-pdf :288 :445 |
| C1 | blob órfão: a forma gravada recusada na entrada não vai para a limpeza | PEGA 1 | motor-pdf :445 |
| C2 | blob repassado ao adiamento vai para a limpeza | PEGA 1 | publicador :709 |
| S1 | sentinela: comparativo emitido conta como assumido | PEGA 11 | ferramenta :189; motor :206 :277 |
| S2 | sentinela gravada na emissão | PEGA 3 | ferramenta :189; job comparativo :173; fronteira :149 |
| S3 | encerramento não pede de novo o comparativo já emitido | PEGA 3 | motor-pdf :166 :190 :346 |
| M6 | PDF que não sai do portal encerra sem nova tentativa | PEGA 14 | ferramenta :146 :169 :239 |
| M7 | sem teto de tentativas | PEGA 15 | ferramenta :169 :272 :282 |
| M9 | sem a busca da mensagem na conversa | PEGA 2 | ferramenta :218; motor :235 |
| M10 | done encerra com o arquivo recusado | PEGA 12 | motor :206 :235 :277 |
| M11 | qualquer entrega recusada segura o done | PEGA 1 | motor :503 |
| L1 | estabilidade: sem comparar com a leitura anterior | PEGA 74 | quote_offers :212 :220; ferramenta :90 |
| L2 | estabilidade: compara a leitura consigo mesma | PEGA 72 | ferramenta :90 :103; motor :136 |
| M1 | finished? só com completed/failed | PEGA 54 | ferramenta :77 :103 :133 |
| M3 | sem a cobertura das acionadas | PEGA 1 | quote_offers :228 |
| M4 | lista negra (só running segura) | PEGA 1 | quote_offers :205 |
| M5 | error fora dos desfechos | PEGA 2 | quote_offers :190; ferramenta :103 |
| F1 | fecho sem encadear | PEGA 3 | motor-pdf :190 :263 :288 |
| F2 | publicador não espera a dependência | PEGA 6 | motor-pdf :190 :263 :288 |
| F3 | um teto só no job | PEGA 3 | motor-pdf :190 :288; job :39 |
| F4 | publish! (varredor) não espera a dependência | PEGA 2 | motor-pdf :263; publicador :305 |
| F5 | sem a entrega a caminho da ferramenta | PEGA 2 | motor-pdf :263 :288 |
| E1 | resultado sem o comparativo assumido | PEGA 1 | motor-pdf :236 |
| I1 | sem a escrita imediata da identidade e da contagem | PEGA 2 | motor-pdf :313 |
| M12 | done sem o fecho de quem tem resultado | PEGA 30 | motor :136 :178 :206 |
| M13 | done sem a pergunta à conversa | PEGA 3 | motor :316; motor-pdf :288; encerramento :416 |
| M13b | concluir engolindo a exceção | PEGA 2 | motor :475; encerramento :438 |
| M14 | fecho também para a pergunta pelo dado | PEGA 2 | encerramento :406 :438 |
| M15 | finish_done da main | PEGA 27 | motor :136 :178 :206 |
| M21 | resta_entregar? sem o comparativo por tentar | PEGA 7 | ferramenta :282; motor :378; motor-pdf :407 |
| M22 | resta_entregar? sem a marca de conclusão | PEGA 9 | ferramenta :272; motor :402; motor-pdf :166 |
| M23 | done sem gravar a marca de conclusão | PEGA 9 | ferramenta :262; motor :402; motor-pdf :166 |
| M16 | download que falha publica a reserva | PEGA 19 | motor :206 :277 :455 |
| M18 | sem_arquivo não procura a mensagem no ar | PEGA 1 | publicador :537 |
| U1 | corpo sem texto vira mensagem | PEGA 22 | motor :206 :277 :455 |
| M19 | forma recusada vira texto com o link | PEGA 3 | ferramenta :239; comparativo :104; job comparativo :131 |
| M20 | reserva volta a carregar o link | PEGA 3 | ferramenta :252; comparativo :72; ramo_auto :440 |
| F6 | sem a entrega adiada pelo próprio encerramento | PEGA 1 | motor-pdf :192 |

### O que NÃO foi verificado (rodada 2)

- **Portal real**, de novo: conector `mock` com dados sintéticos.
- **Duas passadas simultâneas** (R2-4): sem teste.
- **Rollback com publicações adiadas no ar**: ver "Deploy e rollback". Por leitura de código.
- **Publicação adiada recusada depois do aceite** (R2-2): sem teste de nova tentativa, porque ela não existe.
- **Renovação de sessão** fora da conta de tempo.
- **As sondas** rodaram numa cópia minha do arquivo do revisor, com a leitura a mais descrita acima.

## Deploy e rollback

- Sem migration, sem env var, sem chave nova ou removida no schema da ferramenta (na rodada 2 mudou a
  descrição de `comparativo_reserva`).
- **Deploy com execuções em voo** (por leitura de código, e com o exemplo da linha em voo pelo motor):
  - o handle gravado pela `main` não tem `leitura_assentada`: a primeira consulta desta versão a grava, e a
    cotação fecha na leitura assentada seguinte;
  - a linha da `main` com `comparativo_enviado` e a identidade: `comparativo_assumido?` pergunta pela
    identidade (aceite ou mensagem, inclusive a reserva com o link que a `main` publicou) e não pede outro;
  - `AsyncPublishJob` enfileirado pela `main` com a entrega de arquivo (URL): esta versão ainda baixa e grava
    no job. Se o download falhar ali, nada é publicado (a `main` publicaria o link) e ninguém pede outro PDF,
    porque a linha da `main` já fechou. Janela: os jobs adiados no minuto do deploy.
- **Rollback: reverter os commits da PR.**
  - `AsyncPublishJob` enfileirados por esta versão carregam `ArquivoGravado` ou `EntregaEncadeada`, e a `main`
    não reconhece nenhum dos dois: descarta, com o log "entrega descartada" (`skipped`). O PDF e o fecho
    desses jobs se perdem, com a execução já fechada. Janela: o que foi adiado até ~90 s (cadeia do turno) e
    ~180 s (fecho encadeado) antes do rollback. Por leitura de código.
  - A rodada 1 dizia que as entregas de arquivo serializadas por ela "continuam válidas na anterior (a
    `reserva` segue na forma, só sem o link)" e omitia a consequência: com o download falhando, a `main`
    publica essa reserva, e sem o link o cliente leria "Comparativo com todas as opções:" sem nada depois. Na
    rodada 2 nenhuma entrega de arquivo desta versão vai para os argumentos do job (vai o `ArquivoGravado`,
    item acima), e a rodada 1 não foi para produção.
  - Linhas `running` com `comparativo_tentativas`, `leitura_assentada` e `conclusao_devolvida`: a `main` ignora
    as chaves e volta a esperar `completed`/`failed`/prazo. A linha entre duas tentativas depois de um
    DOWNLOAD recusado tem `portal_fechado` e a identidade não aceita: no prazo, a `main` pede o comparativo e
    publica o fecho. A linha entre duas tentativas depois de uma GERAÇÃO que falhou (504) tem `portal_fechado`
    e nenhuma identidade: no prazo, a `main` pede e publica o comparativo, e o `resta_entregar?` dela lê o
    portal fechado e não publica o fecho. Janela: as linhas em nova tentativa no minuto do rollback. Por
    leitura de código, sem teste.
  - O link volta ao cliente com o rollback (é o comportamento da `main`).
