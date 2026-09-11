# Entrega 16 — várias cotações ao mesmo tempo: a parte de código e de registro

Data: 11/09/2026. Plano: entrega 16 do Agente de Cotação. Issue-mãe: #291.
Escopo desta auditoria: termos 3, 4, 5, 6 e 7. O termo 2 (N cotações REAIS simultâneas pela mesma
corretora) custa dinheiro e fica com o orquestrador.

## A medição que manda nesta entrega

Nada aqui é opinião sobre concorrência: tudo se apoia em duas medições contra o portal real, com a
conta de teste, sem criar cotação (todas as chamadas são leitura gratuita).

| quando | o que foi feito | resultado |
|---|---|---|
| 05/09/2026 | sete logins da mesma conta **em sequência** | mesmo id de sessão nos sete; o token do primeiro continuou respondendo 200 depois de todos os outros; `derrubaSessao: true` devolveu o mesmo id |
| 10/09/2026 | seis logins **simultâneos** | coexistem · 6/6 avisaram "já existe sessão ativa" · 0 precisaram derrubar a anterior · **um único início de sessão para os seis** |
| 10/09/2026 | seis sessões sob carga, 45 s | 867 chamadas, 0 falhas · mediana 245 ms · p95 530 ms |
| 10/09/2026 | uma cotação em andamento + cinco clientes entrando | a sessão que acompanhava não caiu · 21 leituras seguidas, 0 falhas |
| 10/09/2026 | **doze sessões**, 30 s | **1.202 chamadas, 0 falhas** · mediana 252 ms — **igual à de seis** |
| 10/09/2026 | duas corretoras alternadas | 715 chamadas, 0 falhas |

Fontes versionadas: `autonomia-adapters/scripts/discovery/provar-sessoes-paralelas.ts` (o roteiro dos
quatro cenários) e `autonomia-adapters/test/contract/agger.sessao-unica.live.test.ts` (o canário que
reprova se o portal passar a invalidar).

**A latência não muda de seis para doze sessões: não há disputa.** O portal trata os logins da mesma
conta como a MESMA sessão. A premissa "entrar de novo derruba a sessão anterior" é falsa.

**Fronteira do que foi medido** (não afirmar além disto): conta de TESTE, não a de produção, que tem
`usuarioRestrito`; login pela API, não pelo fluxo da SPA; janela de minutos — expiração e limpeza
noturna não foram observadas; e nenhuma COTAÇÃO simultânea foi criada, só leitura.

## Termo 3 — a issue que propunha fila por corretora

`autonom-ia2/autonomia-adapters#8` ("Onda 2.7 · Sessão única do AGGER: fila por corretora") foi
escrita sobre a premissa contrária: *"o AGGER tem sessão única por login. Entrar de novo derruba a
sessão anterior (`derrubaSessao`)"*, e propunha **serializar cotação por corretora**. Fechada com a
evidência acima. A fila que ela pedia nos tornaria o gargalo que o portal não é: uma corretora tem
vários clientes cotando ao mesmo tempo, e isso é teto de negócio, não inconveniência técnica.

O que sobra de útil da issue — reaproveitar a sessão por corretora respeitando o `expires` — **já
está feito** e é o desenho atual de `connections/session.rb`.

## Termo 4 — o texto que faria o próximo engenheiro construir a fila

`app/services/autonomia/insurance/connections/session.rb` abria afirmando: *"O AGGER aceita uma
sessão viva por login: abrir outra invalida a anterior."* Corrigido, **sem mudar comportamento**: a
sessão continua morando na linha da conexão.

O motivo real é outro, e o comentário agora o diz: **compartilhar para não multiplicar login**. O
portal reusa a sessão e avisa isso em todo login; abrir uma sessão por chamador significaria pagar um
login de até 60 s (`Http::READ_TIMEOUT`) a cada consulta de polling (de 3 em 3 até 21 em 21 segundos,
por até 7 minutos) e a cada varredura do healthcheck, para receber de volta exatamente o que já
tínhamos. Guardar a sessão em um lugar só é também o que faz `session_expires_at` significar alguma
coisa.

`with_fresh_session` **continua existindo e continua chamado**, agora com o motivo honesto:
`session_live?` só conhece o prazo que nós gravamos, e prazo gravado não é prova — o portal pode
encerrar antes (validade encurtada, limpeza noturna, janelas que a medição não cobriu).

**A varredura foi por frase, e precisou de QUATRO passadas.** A rodada 1 corrigiu o `session.rb` e o
cabeçalho de `session_spec.rb`; a 2 achou a frase viva no ponto de ENTRADA do conector; a 3 achou as
paráfrases dela dentro dos arquivos que a 2 já tinha corrigido; a 4 achou mais nove pontos — de novo
dentro de arquivos corrigidos, incluindo o arquivo de CONTRATO de causas de falha do adapter. Não
dizer "estes são todos os pontos" é o que esta seção aprendeu: a lista abaixo é a lista do que foi
corrigido, e quem garante que não voltou é a guarda da subseção seguinte, não esta tabela.

| rodada | repositório | arquivo | a frase, citada para poder ser refutada |
|---|---|---|---|
| 1 | chat2you | `connections/session.rb` (cabeçalho, `renew!`, `with_fresh_session`) | falso: "abrir outra invalida a anterior" |
| 2 | chat2you | `connector/http.rb` (`open_session`, e o parágrafo do defeito de `session_expires_at`) | falso: "o portal aceita uma sessão viva por login…" |
| 2 | chat2you | `connector/client.rb` (cabeçalho) | falso: a mesma frase |
| 2 | chat2you | `connections/sync.rb` (dois comentários) | falso: "cada um invalidava a sessão anterior" · "derrubada por um login feito no portal pelo navegador" |
| 3 | chat2you | `spec/…/connections/session_spec.rb` (relato da regressão) | falso: "o AGGER aceita uma sessão por login e derrubou a nossa" |
| 3 | chat2you | `insuranceContract.js`, `InsuranceConnectionsTab.spec.js` | falso: "uma sessão derrubada por login no navegador" |
| 3 | adapter | `platforms/agger/http/session.ts` (schema `message`, schema `createdAt`, nota de `postLogin`) | falso: "o portal avisando que a conta já está em uso" · "quem a abriu foi outro" |
| 3 | adapter | `platforms/agger/index.ts` (`openSession`) | falso: "Sobe até a tela: quem sabe distinguir… é o corretor" |
| 3 | adapter | `service/handler.ts` (`dispatch`) | falso: "convivem sem uma derrubar a outra" |
| 3 | adapter | `core/adapter.ts` (campo `alreadyActive`) | falso: "por outro ambiente nosso ou por uma pessoa no navegador… serve para a tela contar ao corretor" |
| 3 | adapter | `test/unit/falha-nao-culpa-o-corretor.test.ts` (bloco 1.5) | falso: "a conta em uso em outro lugar" |
| 3 | adapter | `scripts/discovery/provar-link-nao-derruba.ts` | falso: "duas leituras contraditórias no repositório" — a contradição acabou |
| **4** | adapter | `core/failure.ts` (parágrafo de 05/09 e a doc de `session_lost`) | falso: "o AGGER derrubou a nossa sessão (ele aceita uma por login)" · "login em outro lugar" |
| **4** | adapter | `core/adapter.ts` e `platforms/agger/http/session.ts` (campo `droppedPreviousSession`) | falso: "foi preciso derrubar a anterior" · "abrir esta sessão derrubou uma anterior" |
| **4** | adapter | `platforms/agger/index.ts` (`statusFor`) | falso: "mandar sessão derrubada para cá" |
| **4** | adapter | `test/unit/falha-nao-culpa-o-corretor.test.ts` (cabeçalho e o Arrange do 1.2) | falso: "alguém abriu o AGGER pelo navegador, o portal derrubou a nossa sessão" |
| **4** | adapter | `test/unit/service.test.ts` | falso: "reabrir a sessão aqui derrubaria a que já está cotando" |
| **4** | adapter | `test/integration/session-host.test.ts` (cabeçalho e o título) | falso: "um login a mais derruba a sessão de quem está cotando" |
| **4** | adapter | `test/unit/guardas-fecho.test.ts` | falso: "relogar derruba a sessão anterior e mata uma cotação em andamento" |
| **4** | adapter | `test/unit/cobertura-ultima.test.ts` | falso: "abrir um navegador, que derruba a sessão" |
| **4** | adapter | `test/unit/cobertura-final.test.ts` | falso: "derrubaria a sessão do corretor de novo" |
| **4** | adapter | `test/unit/session-host.test.ts` | falso: "derrubar a sessão logada da corretora" (era reiniciar o Chrome) |
| **4** | adapter | `test/unit/guardas-restantes.test.ts` | falso: "a retentativa de derrubar a sessão" |
| **4** | adapter | `test/unit/login-soluco-nao-e-senha-errada.test.ts` (2 títulos, 3 comentários) | falso: "ainda derruba a anterior" — o nome é do parâmetro `derrubaSessao`, não do efeito |
| **4** | adapter | `test/unit/agger-session-reuse.test.ts` | falso: "sem fazer login, que invalidaria uma cotação em andamento" — **achado pela guarda nova**, não por pessoa |
| **4** | adapter | `docs/implementation-gap-report.md` §7 (linha 5) e §8 | falso: "extrair os domínios que faltam sem derrubar sessão" · "resolve uma restrição real do portal" |
| **4** | adapter | `scripts/discovery/sondagem-lista.ts`, `scripts/probe-sessao-por-dispositivo.ts` | falso: o logout explícito confundido com login · hipótese registrada sem o resultado que a derrubou |
| **4** | chat2you | `spec/…/connections/session_spec.rb` (cabeçalho) | falso: "impede o healthcheck de encerrar a sessão de uma cotação em andamento" |
| **4** | chat2you | `spec/…/connector/http_spec.rb` | falso: "abriria uma sessão nova a cada chamada e invalidaria a que está cotando" |
| **4** | chat2you | `spec/…/connector/http_contrato_real_spec.rb` | falso: atribuía o 403 de "credencial recusada" ao defeito do camelCase |

Onde a frase antiga está CITADA (`"aqui se lia …"`), ela fica: apagar a frase errada apagaria também
o registro de por que a correção existe.

**O grep que achou a rodada 4**, registrado para ser repetido:

```
grep -rnEi 'derrub|segundo login|login novo|login a mais|uma por login|uma sessão por login|invalida a anterior|sessão única' \
  <src|scripts|test|docs do adapter> <app/…/insurance, spec/…/insurance, docs/audit do chat2you>
```

e, sobre o resultado, uma allowlist de NEGAÇÃO/CITAÇÃO: `medido`, `falso`, `aqui se lia`,
`correção de`, `corrigido`, `canário`, `reconciliado`, `não derruba`, `não é invalidado`, `coexist`.
Um minuto de execução, nove pontos vivos — contra três rodadas de leitura humana.

### A guarda textual que a rodada 3 declarou impossível

Esta auditoria dizia, na rodada 3: *"não há guarda textual contra a volta da frase… toda correção
cita a frase falsa para poder refutá-la, e um varredor de prosa não distingue a afirmação da
citação"*. **O argumento estava errado, e a rodada 4 é a prova**: o grep acima distinguiu as duas
coisas em um minuto, com uma allowlist de dez palavras.

O que desfaz o argumento é a forma da própria correção: **quem refuta escreve a refutação por
perto**. Então a regra não é "a frase não aparece" — é **a frase nunca aparece longe da sua
refutação**. Isso é mecanicamente verificável, e agora é verificado:

- adapter: `test/unit/premissa-de-sessao-nao-volta.test.ts`, sobre `src/`, `scripts/`, `test/` e
  `docs/` (`.ts` e `.md`);
- chat2you: `spec/services/autonomia/insurance/premissa_de_sessao_spec.rb`, sobre o namespace de
  seguros (`app`, `spec`, a aba em `app/javascript`) e `docs/audit` (`.rb`, `.js`, `.vue`, `.md`).

As duas leem PROSA (comentário, título de exemplo e markdown), casam "algo caindo" + "uma sessão" na
mesma frase — inclusive quebrada em duas linhas —, e reprovam quando não há refutação em até doze
linhas. Cada uma tem um exemplo de CONTRAPROVA com amostra sintética, porque varredor que não pega o
que promete passa elogiando o próprio silêncio.

**O que elas não prometem** (2.3 — nunca dizer "100% mapeado"): afirmação escrita dentro de uma
string de código escapa; paráfrase sem nenhuma das palavras da lista passa (por exemplo "um navegador
a mais é um segundo login", que aliás é verdade); e o prefixo cru `invalid` foi trocado por formas
verbais depois de acusar "corpo inválido" numa sonda — guarda que acusa o inocente é guarda que
alguém desliga. Elas fecham a reincidência MEDIDA, não a criatividade. Quem guarda o FATO continua
sendo o canário vivo `agger.sessao-unica.live.test.ts`.

## Termo 5 — o alerta falso morreu

### O defeito

O portal devolve "Já existe uma sessão ativa com esse usuário" **no mesmo 201 do login
bem-sucedido**, em TODO login (6 de 6 nos logins simultâneos; também nos sete em sequência). Nós
gravávamos isso em `metadata['account_already_active']` e a aba Conexões exibia ao corretor: *"Esta
conta AGGER já estava em uso quando conectamos… outro ambiente cotando pela mesma conta"*.

Depois do primeiro login da conta o aviso ficava ligado **para sempre**, e a "outra pessoa" era,
quase sempre, a nossa própria sessão anterior — o healthcheck passa de 30 em 30 minutos e o polling
de cotação abre sessão quando a guardada vence.

É o inverso do padrão de sempre: aqui o consumidor existia e **o produtor é que mentia**.

### Por que remover em vez de refinar

O termo permitia manter o aviso *"com evidência que discrimine"*. Nada no payload discrimina:

- `already_active` é a presença do texto na mensagem, e a mensagem vem sempre;
- `session_started_at` é o `createdAt` da sessão **compartilhada** — nos seis logins simultâneos foi
  **um único valor para os seis**. Diz quando a sessão começou, nunca quem a abriu;
- comparar esse instante com o nosso último login foi considerado e **descartado por decisão, não
  por falta do dado**: o instante fica dentro do blob **opaco** da sessão — `openSession` devolve o
  `AggerSession` inteiro em `data`, e `session_payload` guarda o blob como veio, de modo que ele
  está gravado em toda conexão. Usá-lo exigiria interpretar o blob (contra o contrato, que diz que
  quem entende o que há lá dentro é o adapter) e ainda assumir que `createdAt` só muda quando a
  sessão do portal expira — e expiração nunca foi observada. Sem essa segunda suposição a comparação
  seria a mesma afirmação sem prova, agora com aritmética por cima;
- o portal não expõe (no catálogo que conhecemos) nenhuma listagem de sessões por dispositivo, IP ou
  usuário. Os testes de 05/09 com `device=desktop`, `device=mobile` e User-Agent de Chrome
  devolveram o mesmo id de sessão.

Alarme que não discrimina é alarme falso, e alarme falso permanente treina o corretor a ignorar a
tela inteira.

### O que mudou

- `Connections::Session#open!` deixa de gravar o aviso e passa a **apagar** o que uma versão anterior
  gravou (`Connection#forget_metadata!`, novo). Não é limpeza cosmética: enquanto a chave existir no
  banco ela é uma afirmação falsa esperando o próximo leitor. `merge` não apaga — gravar `nil`
  deixaria a chave com `null` dentro;
- `Connection#account_already_active` e a chave em `diagnostico_publico` saíram: a API não publica
  mais o campo;
- a aba Conexões perdeu o computed e a seção; `insuranceContract.js` perdeu o campo; a chave
  `INSURANCE.CONNECTION.ALREADY_ACTIVE` saiu do `en/insurance.json`;
- no adapter nada mudou de comportamento: `alreadyActive` e `sessionStartedAt` continuam
  atravessando a fronteira como o portal os deu. O que mudou foi o texto que os descrevia — eles são
  dado para quem MEDE concorrência, nunca afirmação para uma pessoa.

### O que acontece com a chave que já está gravada

**Correção de um relato inexato das rodadas anteriores**, que dizia que "o primeiro login de cada
conexão depois do deploy limpa a linha, e o healthcheck de 30 em 30 minutos cobre todas sozinho". O
healthcheck **não faz login quando a sessão guardada está viva**: `Connections::Sync` chama
`with_fresh_session`, que só reabre quando `session_live?` é falso, e a sessão vale horas. A chave
velha pode portanto ficar no `metadata` até a sessão vencer, ou até alguém clicar em **Reconectar**.

Isso é inofensivo, e é por isso que não há migration: **nada mais lê a chave** — ela saiu de
`diagnostico_publico`, do contrato do frontend e da aba —, e `connection_spec.rb` guarda exatamente
isso, exigindo que a linha COM a chave publique o mesmo payload da linha SEM ela. A limpeza é
oportunista de propósito: um UPDATE por conexão para retirar um dado que ninguém lê seria escrita em
produção sem consumidor.

### Consequência de produto, que não é minha para decidir

O **critério 1.5** ("a mesma conta AGGER usada em dois lugares ao mesmo tempo — avisar, não
bloquear", decisão do Rodrigo em 06/09) fica **sem implementação**, porque o sinal em que ele se
apoiava não sustenta a afirmação. Não é um esquecimento: é o que sobra quando a medição desmente a
premissa. Se o aviso for requisito, ele precisa de outra fonte de verdade (por exemplo, um registro
NOSSO de quais ambientes usam a mesma credencial), e isso é escopo novo.

## Termo 6 — a concorrência efetiva do NOSSO lado

### O que a premissa do plano dizia, e o que o código diz

O enunciado supunha "concurrency da fila `low`". Duas correções, lidas no código:

1. **`AsyncRunJob` está na fila `medium`**, não `low` (`app/jobs/autonomia/agents/tools/async_run_job.rb:17`).
   `AsyncPublishJob` também. Quem está em `low` é o turno de conversa (`Operate::ReplyJob`,
   `ChunkedDeliveryJob`);
2. **Sidekiq não tem concorrência por fila.** `config/sidekiq.yml` declara UM `:concurrency:`
   (`ENV["SIDEKIQ_CONCURRENCY"]`, default **10**) para o processo inteiro, e as 16 filas são uma
   lista **sem pesos** — ou seja, prioridade estrita: nada de `medium` é despachado enquanto houver
   trabalho em `critical` ou `high`, e nada de `low` enquanto houver trabalho em `medium`.

### O job não segura thread entre as consultas

`AsyncRunJob#reschedule` faz `set(wait: …).perform_later` — cada passada é uma execução curta que
termina e volta para o Redis com atraso. Não há `sleep` dentro do job (e há um comentário no arquivo
explicando por quê: com `:timeout: 25` de shutdown, todo deploy mataria a espera no meio e o
`max_retries: 3` refaria o `start`, que é cotação paga).

### A conta

Com os parâmetros de `AsyncConfig` (`DEFAULT_INTERVALS = [3,3,5,5,8,8,13,13,21]`, último valor
repetido; `DEFAULT_DEADLINE_SECONDS = 420`), uma cotação que vai até o prazo faz:

- **26 passadas** no total (1 `start` + 25 consultas), a última em t = 415 s;
- o teto de tentativas (`MAX_ATTEMPTS = 60`) não é alcançado: quem encerra é o relógio, como o
  comentário do arquivo afirma.

Thread-segundos por cotação, em função do custo de uma passada (chamada ao Lambda + AGGER):

| custo por passada | thread-s por cotação | fração de 1 thread na janela de 420 s | cotações simultâneas que 10 threads sustentam |
|---|---|---|---|
| 0,3 s | 7,8 | 1,9 % | ~538 |
| 1,0 s | 26,0 | 6,2 % | ~162 |
| 3,0 s | 78,0 | 18,6 % | ~54 |

A mediana medida contra o portal foi 252 ms; o nosso caminho acrescenta o invoke do Lambda, que não
foi medido ponta a ponta — por isso a tabela tem três colunas em vez de um número.

### O veredito, e o que realmente aperta

**O pool de threads não é o gargalo.** Em produção roda **um** processo Sidekiq por instância —
`docker run --name chatwoot-worker … bundle exec sidekiq -C config/sidekiq.yml`, um container único
no user-data da EC2 verde (`.github/workflows/deploy-autonomia-blue-green.yml`), e o deploy é
blue-green (uma instância servindo por vez). Logo: **10 threads no total**, a menos que
`SIDEKIQ_CONCURRENCY` esteja definido no SSM (ausente nos workflows; o default do arquivo é 10).

O que aperta antes disso, em ordem:

1. **`medium` tem prioridade sobre `low`.** Sob fila cheia, o polling de cotação é despachado antes
   do turno de conversa. Cotações em excesso atrasam a resposta da Lia ao cliente — e não o
   contrário. É o efeito que merece observação assim que houver volume;
2. **as 10 threads são compartilhadas com o resto do Chatwoot** (webhooks, e-mail, reindex,
   housekeeping), não reservadas para cotação;
3. **o `start` é a passada cara**: pode segurar a thread até `Http::READ_TIMEOUT` = 60 s. As
   consultas são curtas; a submissão não;
4. **a instância**: o tipo default do workflow é `t3.small` (2 vCPU), e ela roda web e worker juntos.
   Para trabalho de espera de rede isso é adequado; memória é o limite mais provável antes da CPU.

**Nada foi alterado na configuração.** Aumentar `SIDEKIQ_CONCURRENCY` antes de medir o custo real de
uma passada seria trocar um número por outro sem evidência, e mexer em prioridade de fila afeta o
Chatwoot inteiro, não só a cotação.

### O que fica para prova real / produção

- **quanto dura uma passada nossa ponta a ponta** (Rails → Lambda → AGGER → Rails). Sem isso a tabela
  acima é uma faixa, não um número;
- **o valor efetivo de `SIDEKIQ_CONCURRENCY`** no SSM da instância de produção e o tipo real da
  instância em serviço;
- **N cotações reais simultâneas** pela mesma corretora (termo 2), que é o único jeito de ver o
  portal sob cotação concorrente — e não só sob leitura concorrente;
- o efeito da prioridade `medium` > `low` sobre a latência da conversa, com volume de verdade.

## Termo 7 — a medição versionada

Este arquivo. No adapter, a correção dos comentários que afirmavam a sessão única viaja numa PR
própria (`autonomia-adapters`); os dois artefatos de medição (`provar-sessoes-paralelas.ts` e o
canário `agger.sessao-unica.live.test.ts`) já estavam versionados lá.

A varredura no adapter foi por CLASSE, não por caso: a mesma frase aparecia em `src/core/adapter.ts`,
`src/service/handler.ts`, `src/browser/session-host.ts`, `src/cli/program.ts`, quatro arquivos de
teste e duas docs. O relatório datado (`implementation-gap-report.md`) ficou como estava, com uma
nota de rodapé — reescrever um retrato do passado seria apagar o erro em vez de registrá-lo.

**E "por classe" não bastou em passada nenhuma, o que é o achado mais útil desta entrega.** A rodada
2 procurou a frase inteira e deixou passar as PARÁFRASES dentro dos mesmos arquivos já tocados; a 3
corrigiu as paráfrases e deixou passar mais nove pontos, entre eles o arquivo de CONTRATO de causas
de falha do adapter — o primeiro que alguém lê para tratar um 403. Três rodadas de leitura humana,
três listas que se declararam completas e não eram.

A lição só vale escrita em código, e agora está: **a varredura virou teste** nos dois repositórios
(subseção "a guarda textual que a rodada 3 declarou impossível", no termo 4), com a regra "a frase
nunca aparece longe da sua refutação" e contraprova própria. A quarta rodada é a última em que essa
lista dependeu de alguém prestar atenção. Junto foi consertado um teste que só passava no clone com nome de pasta
`autonomia-adapters` (`test/unit/destino-seguro.test.ts`): em worktree ele ficava vermelho sem que
nada estivesse errado, e portão que depende do nome do diretório não é portão.

## Termo → guarda

| termo | guarda | evidência |
|---|---|---|
| 3 · issue #8 reescrita ou fechada | não é código: a issue foi fechada com a evidência | comentário + fechamento em `autonom-ia2/autonomia-adapters#8` |
| 4 · o texto de `session.rb` corrigido | **guarda textual executável nos dois repositórios** (`premissa-de-sessao-nao-volta.test.ts` e `premissa_de_sessao_spec.rb`); o FATO tem canário vivo | os 30 pontos da tabela do termo 4; mutações MA1–MA3 e MC1–MC3; canário `agger.sessao-unica.live.test.ts` |
| 5 · o alerta para de mentir | `session_spec.rb` (3 exemplos) + `connection_spec.rb` (3, sendo 2 novos) + `InsuranceConnectionsTab.spec.js` (1, por EFEITO) | mutações M1–M8 abaixo |
| 6 · concorrência medida e registrada | a seção acima, com origem de cada número no código | `sidekiq.yml`, `async_run_job.rb:17`, `async_config.rb`, workflow de deploy |
| 7 · medição versionada | este arquivo + a PR do adapter | — |

## Mutações (a regra desligada tem de derrubar um teste)

Cada uma foi aplicada de verdade, com o teste rodado, e o arquivo restaurado com conferência de
checksum (sha256 antes = sha256 depois em todas).

| # | o que foi desligado | resultado |
|---|---|---|
| M1 | `open!` volta a GRAVAR `account_already_active` | 3 falhas em `session_spec.rb` (não grava / apaga / apaga só o aviso) |
| M2 | tira a chamada de `esquecer_aviso_de_conta_em_uso!` de `open!` | 2 falhas em `session_spec.rb` (apaga / apaga só o aviso) |
| M3 | `diagnostico_publico` volta a publicar `account_already_active` | 1 falha em `connection_spec.rb` (rodada de novo na rodada 3, contra a guarda nova: continua reprovando) |
| M4 | `forget_metadata!` grava `nil` em vez de usar `except` | 2 falhas em `session_spec.rb` — a chave sobrevive com `null` |
| M5 | reintroduz a seção do aviso no `InsuranceConnectionsTab.vue` | 1 falha em `InsuranceConnectionsTab.spec.js` |
| M6 | `diagnostico_publico` republica o MESMO retrato com OUTRO nome (`conta_em_uso: metadata['account_already_active']`) | 1 falha em `connection_spec.rb` — "publica o mesmo payload com e sem o aviso". Antes da rodada 3 esta mutação passava |
| M7 | `forget_metadata!` sem a leitura antes do lock (tira o `return unless metadata.to_h.key?(key)`) | 1 falha em `connection_spec.rb` — "não pega lock de linha quando não existe a chave". Antes da rodada 3 esta mutação passava |
| M8 | a seção do aviso volta ao `InsuranceConnectionsTab.vue` sob OUTRA chave i18n (`CONTA_EM_USO`), lendo o mesmo `account_already_active` | 1 falha em `InsuranceConnectionsTab.spec.js` — "renderiza exatamente a mesma tela com e sem o aviso". Antes da rodada 3 esta mutação passava |
| MC1 | o cabeçalho de `connections/session.rb` volta ao texto de antes da PR, que é falso ("o AGGER aceita uma sessão viva por login: abrir outra invalida a anterior"), e sem a correção por perto | 1 falha em `premissa_de_sessao_spec.rb`. **Antes da rodada 4 não havia teste nenhum a reprovar** |
| MC2 | a guarda do chat2you deixa de ler a frase quebrada em duas linhas (`par = linhas[i]`) | 1 falha — a contraprova deixa de achar o caso de `agger-session-reuse` |
| MC3 | a guarda do chat2you deixa de exigir a refutação por perto (vira "a frase não aparece") | 2 falhas — acusa as próprias correções, que é a armadilha que a rodada 3 temia e esta guarda evita |
| MA1 | o parágrafo de 05/09 volta ao texto de antes da PR em `adapter/src/core/failure.ts` | 1 falha em `premissa-de-sessao-nao-volta.test.ts` |
| MA2 | a guarda do adapter deixa de ler a frase quebrada em duas linhas | 1 falha — a contraprova |
| MA3 | a guarda do adapter deixa de exigir a refutação por perto | 2 falhas |

## Comandos rodados

```
# banco próprio do trilho
POSTGRES_DATABASE=chatwoot_test_e16 RAILS_ENV=test bundle exec rails db:create db:schema:load

# alvo (vermelho antes, verde depois)
POSTGRES_DATABASE=chatwoot_test_e16 bundle exec rspec \
  spec/services/autonomia/insurance/premissa_de_sessao_spec.rb \
  spec/services/autonomia/insurance/connections/session_spec.rb \
  spec/services/autonomia/insurance/connector/http_spec.rb \
  spec/services/autonomia/insurance/connector/http_contrato_real_spec.rb \
  spec/models/autonomia/insurance/connection_spec.rb --format json

# frente
TZ=UTC npx vitest run --no-coverage app/javascript/dashboard/routes/dashboard/autonomia/insurance/

# suíte ampla
POSTGRES_DATABASE=chatwoot_test_e16 bundle exec rspec \
  spec/services/autonomia spec/jobs/autonomia spec/models/autonomia \
  spec/requests/api/v1/accounts/autonomia --format json

# lint
bundle exec rubocop <arquivos tocados> --format json
npx eslint <arquivos tocados>
```

Resultado, lido do JSON (nunca do resumo do terminal) e com o exit code conferido:

| o que | resultado |
|---|---|
| alvo, ANTES de implementar | 4 falhas — as guardas novas reprovando, como têm de reprovar |
| alvo, depois da rodada 1 | 21 exemplos, **0 falhas**, `errors_outside_of_examples_count: 0` |
| alvo, depois da rodada 3 | 23 exemplos, **0 falhas**, `errors_outside_of_examples_count: 0`, exit 0 |
| alvo, depois da rodada 4 (com a guarda textual e os dois specs do conector) | **42 exemplos, 0 falhas**, `errors_outside_of_examples_count: 0`, exit 0 |
| frente (pasta `insurance`) | 233 testes, **0 falhas**, exit 0 — nenhum arquivo de frente foi tocado na rodada 4 |
| suíte ampla (rodada 3) | 1.014 exemplos, 0 falhas, 3 pendentes (pré-existentes), exit 0 |
| suíte ampla (rodada 4) | **1.016 exemplos, 0 falhas**, 3 pendentes (pré-existentes), `errors_outside_of_examples_count: 0`, exit 0 |
| rubocop nos arquivos Ruby tocados (7 na rodada 3, 4 na rodada 4) | 0 ofensas |
| eslint nos 2 arquivos de frente tocados | 0 erros, 0 avisos |
| prettier | todos os arquivos tocados já no formato |

No adapter, `pnpm verify` inteiro (typecheck, prettier, honestidade da suíte, portão de ferramentas,
unitários, integração e cobertura): na rodada 3, 769 testes; na rodada 4, **771 testes (759 unitários
+ 12 de integração), 0 falhas**, cobertura **100%** em statements, branches, functions e lines, exit
0. Os dois testes a mais são a guarda textual nova e a contraprova dela.

## Rodada de correção 3 — o que um verificador cego achou, e o que foi feito

Seis achados, todos P3, nenhum de comportamento em runtime. Achado → correção → guarda → mutação:

| # | achado | correção | guarda | mutação |
|---|---|---|---|---|
| 1 | a frase falsa sobrevivia no PONTO DE ENTRADA do conector (`connector/http.rb:31-33`, `connector/client.rb:13-15`): quem lê o conector antes do `session.rb` saía com a premissa falsa | comentários reescritos no padrão do cabeçalho novo (motivo = economia de login; frase medida e falsa em 05/09 e 10/09; canário nomeado). Junto, `connections/sync.rb`, que dizia o mesmo em dois pontos | o FATO tem o canário `agger.sessao-unica.live.test.ts` | — (comentário; ver "por que não há guarda textual", no termo 4) |
| 2 | `session_spec.rb:14-16` afirmava a premissa falsa três linhas depois de o cabeçalho do MESMO arquivo declará-la falsa | reescrito com a causa PROVADA do 403 de 05/09 (o handler do adapter redigia o corpo e o token viajava como a palavra `<REDACTED>` em `Authorization`, `autonomia-adapters` c9b88bd) e o motivo honesto de `with_fresh_session` existir | os três exemplos do `describe` não mudaram | — |
| 3 | no adapter, cinco trechos contradiziam os blocos que a própria PR tinha corrigido, dentro dos mesmos arquivos | alinhados; e a varredura achou um SEXTO que ninguém tinha listado — `core/adapter.ts`, o campo `alreadyActive` do contrato `OpenSession`, que ainda mandava "a tela contar ao corretor" | `pnpm verify`: 769 testes, 0 falhas, cobertura 100 % | — |
| 4 | a justificativa de remover o aviso dizia "não guardamos o início de cada uma" — inexato: `openSession` devolve o `AggerSession` inteiro em `data` e `session_payload` guarda o blob como veio, então o instante ESTÁ gravado | trocado pelo fato certo, dito como DECISÃO e não como impossibilidade: o instante está dentro do blob opaco, usá-lo exigiria interpretar o blob (contra o contrato) e assumir que `createdAt` só muda quando a sessão expira — expiração nunca foi observada. Corrigido na auditoria e em `session.rb:135-137` | — (é texto; importa porque é sobre ele que se decide se o critério 1.5 volta com outra fonte) | — |
| 5 | as guardas do termo 5 estavam presas ao NOME: republicar o mesmo retrato como `conta_em_uso` passava em `connection_spec.rb`, e a seção voltar à tela sob outra chave i18n passava em `InsuranceConnectionsTab.spec.js` (que só conferia a ausência de uma chave que já não existe em lugar nenhum — quase tautológico) | as duas guardas passaram a olhar o EFEITO: `public_payload` tem de ser IDÊNTICO com e sem a chave em `metadata` (exceto `updated_at`, que é a própria escrita); a aba é montada DUAS vezes e o `html()` tem de sair igual caractere a caractere | `connection_spec.rb` "publica o mesmo payload com e sem o aviso"; `InsuranceConnectionsTab.spec.js` "renderiza exatamente a mesma tela com e sem o aviso" | **M6** e **M8** — as duas passavam antes desta rodada |
| 6 | `forget_metadata!` declarava no comentário a regra "leitura sem lock primeiro, porque o caso comum é a chave não existir e esse caso não pode custar um lock de linha a cada login", e a regra não tinha guarda — este é o caminho que roda em TODO login | dois exemplos: sem a chave, `not_to receive(:with_lock)`; com a chave, `receive(:with_lock).once.and_call_original`, e o resto do `metadata` intacto | `connection_spec.rb`, os dois exemplos de lock | **M7** — passava antes desta rodada |

Cada mutação foi aplicada de verdade, com o teste rodado e o arquivo restaurado com conferência de
`sha256` (antes = depois nas três).

## Rodada de correção 4 — o que um verificador cego achou, e o que foi feito

Quatro achados, todos P3, todos de TEXTO — nenhuma linha de comportamento mudou em nenhum dos dois
repositórios. Achado → correção → guarda → mutação:

| # | achado | correção | guarda | mutação |
|---|---|---|---|---|
| 1 | `adapter/src/core/failure.ts:8-11` e `:20` — o arquivo de CONTRATO de causas de falha ainda atribuía o 403 de 05/09 a "alguém entrou no portal pelo navegador, o AGGER derrubou a nossa sessão (ele aceita uma por login)", e documentava `session_lost` como "login em outro lugar". É o primeiro arquivo que alguém lê para tratar um 403 | reescrito no padrão "aqui se lia … medido e falso", com a causa PROVADA (token redatado pelo handler, c9b88bd) e o canário nomeado; `session_lost` passa a ser "acabou ANTES do prazo que o portal informou" | `premissa-de-sessao-nao-volta.test.ts` | **MA1** — antes da rodada 4 não havia teste a reprovar |
| 2 | contradição DENTRO de arquivos que a rodada 3 tinha corrigido: `falha-nao-culpa-o-corretor.test.ts:10-12` e `service.test.ts:123` | alinhados ao texto medido; e a varredura achou os demais da tabela do termo 4 (`agger-session-reuse.test.ts` foi achado pela guarda, não por pessoa) | idem | **MA2** (frase quebrada em duas linhas) |
| 3 | cinco trechos afirmando a premissa sem citação (`test/integration/session-host.test.ts:14-15` e o título da 124, `guardas-fecho.test.ts:344`, `cobertura-ultima.test.ts:27`, `cobertura-final.test.ts:42`) e `docs/implementation-gap-report.md:236`, fora do alcance da nota posta na §6 | corrigidos; o relatório datado ganhou nota na §7 (linha 5 da tabela) e na §8, em vez de ser reescrito; a auditoria trocou "estes são todos os pontos" pela lista real e pelo grep usado | idem + o grep registrado no termo 4 | **MA3** (a exigência de refutação por perto) |
| 4 | `chat2you spec/…/connections/session_spec.rb:3-8` — o cabeçalho reescrito pela própria PR terminava dizendo que o contrato "impede o healthcheck de encerrar a sessão de uma cotação em andamento": a premissa refutada, em paráfrase, três linhas abaixo da correção | trocado por custo — healthcheck e polling REUSAM um login em vez de abrir um por passada —, com a segunda correção datada ao lado. Junto, `http_spec.rb` ("invalidaria a que está cotando") e `http_contrato_real_spec.rb` (atribuía o 403 ao defeito do camelCase) | `premissa_de_sessao_spec.rb` | **MC1**, **MC2**, **MC3** |

Cada mutação foi aplicada de verdade, com o teste rodado e o arquivo restaurado com conferência de
`sha256` (antes = depois nas sete, incluindo a re-execução de **M1**).

**O que esta rodada mudou de método**: a lista de pontos deixou de ser a garantia. Ela é o registro
do que foi corrigido; quem garante que não volta é a guarda executável, e ela achou sozinha um ponto
(`agger-session-reuse.test.ts`) que nem o verificador cego tinha listado.

## O que NÃO foi feito, de propósito

- **Não se conclui que funciona porque as sessões coexistem.** Coexistência de sessão foi medida sob
  leitura; cotação simultânea é outra coisa e é o termo 2;
- não se mexeu em `SIDEKIQ_CONCURRENCY` nem na ordem das filas;
- não se tocou em produção, não se gastou cotação, e nenhum `quote start` foi disparado.
