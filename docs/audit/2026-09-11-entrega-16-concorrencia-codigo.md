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

Dois outros trechos afirmavam o mesmo e foram corrigidos junto: o comentário de `with_fresh_session`
(dizia que "alguém entrou pelo navegador e derrubou a nossa") e o cabeçalho de `session_spec.rb`.
`with_fresh_session` **continua existindo e continua chamado**, agora com o motivo honesto:
`session_live?` só conhece o prazo que nós gravamos, e prazo gravado não é prova — o portal pode
encerrar antes (validade encurtada, limpeza noturna, janelas que a medição não cobriu).

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
- comparar esse instante com o nosso último login foi considerado e descartado: nós abrimos sessão o
  tempo todo e não guardamos o início de cada uma, então a comparação produziria a mesma afirmação
  sem prova, agora com aritmética por cima;
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
  `INSURANCE.CONNECTION.ALREADY_ACTIVE` saiu do `en/insurance.json`.

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
teste e duas docs. Todas corrigidas; o relatório datado (`implementation-gap-report.md`) ficou como
estava, com uma nota de rodapé — reescrever um retrato do passado seria apagar o erro em vez de
registrá-lo. Junto foi consertado um teste que só passava no clone com nome de pasta
`autonomia-adapters` (`test/unit/destino-seguro.test.ts`): em worktree ele ficava vermelho sem que
nada estivesse errado, e portão que depende do nome do diretório não é portão.

## Termo → guarda

| termo | guarda | evidência |
|---|---|---|
| 3 · issue #8 reescrita ou fechada | não é código: a issue foi fechada com a evidência | comentário + fechamento em `autonom-ia2/autonomia-adapters#8` |
| 4 · o texto de `session.rb` corrigido | comentário; o FATO tem canário vivo | `connections/session.rb` (cabeçalho, `with_fresh_session`), `session_spec.rb` (cabeçalho); canário `agger.sessao-unica.live.test.ts` |
| 5 · o alerta para de mentir | `session_spec.rb` (3 exemplos) + `connection_spec.rb` (1) + `InsuranceConnectionsTab.spec.js` (1) | mutações M1–M5 abaixo |
| 6 · concorrência medida e registrada | a seção acima, com origem de cada número no código | `sidekiq.yml`, `async_run_job.rb:17`, `async_config.rb`, workflow de deploy |
| 7 · medição versionada | este arquivo + a PR do adapter | — |

## Mutações (a regra desligada tem de derrubar um teste)

Cada uma foi aplicada de verdade, com o teste rodado, e o arquivo restaurado com conferência de
checksum (sha256 antes = sha256 depois em todas).

| # | o que foi desligado | resultado |
|---|---|---|
| M1 | `open!` volta a GRAVAR `account_already_active` | 3 falhas em `session_spec.rb` (não grava / apaga / apaga só o aviso) |
| M2 | tira a chamada de `esquecer_aviso_de_conta_em_uso!` de `open!` | 2 falhas em `session_spec.rb` (apaga / apaga só o aviso) |
| M3 | `diagnostico_publico` volta a publicar `account_already_active` | 1 falha em `connection_spec.rb` |
| M4 | `forget_metadata!` grava `nil` em vez de usar `except` | 2 falhas em `session_spec.rb` — a chave sobrevive com `null` |
| M5 | reintroduz a seção do aviso no `InsuranceConnectionsTab.vue` | 1 falha em `InsuranceConnectionsTab.spec.js` |

## Comandos rodados

```
# banco próprio do trilho
POSTGRES_DATABASE=chatwoot_test_e16 RAILS_ENV=test bundle exec rails db:create db:schema:load

# alvo (vermelho antes, verde depois)
POSTGRES_DATABASE=chatwoot_test_e16 bundle exec rspec \
  spec/services/autonomia/insurance/connections/session_spec.rb \
  spec/models/autonomia/insurance/connection_spec.rb --format json

# frente
TZ=UTC npx vitest run --no-coverage app/javascript/dashboard/routes/dashboard/autonomia/insurance/

# suíte ampla
POSTGRES_DATABASE=chatwoot_test_e16 bundle exec rspec \
  spec/services/autonomia spec/jobs/autonomia spec/models/autonomia --format json

# lint
bundle exec rubocop <arquivos tocados> --format json
npx eslint <arquivos tocados>
```

Resultado, lido do JSON (nunca do resumo do terminal) e com o exit code conferido:

| o que | resultado |
|---|---|
| alvo, ANTES de implementar | 4 falhas — as guardas novas reprovando, como têm de reprovar |
| alvo, depois | 21 exemplos, **0 falhas**, `errors_outside_of_examples_count: 0` |
| frente (pasta `insurance`) | 233 testes, **0 falhas** |
| suíte ampla (`spec/services/autonomia spec/jobs/autonomia spec/models/autonomia`) | **883 exemplos, 0 falhas**, 3 pendentes (pré-existentes), exit 0 |
| rubocop nos 4 arquivos Ruby tocados | 0 ofensas |
| eslint nos 3 arquivos de frente | 0 erros (os avisos de i18n são pré-existentes: 51 na versão de `origin/main`, 50 aqui — a diferença é exatamente a chave removida) |
| prettier | todos os arquivos tocados já no formato |

No adapter, `pnpm verify` inteiro: typecheck, prettier, honestidade da suíte, portão de ferramentas,
**769 testes, 0 falhas**, cobertura **100%** em statements, branches, functions e lines.

## O que NÃO foi feito, de propósito

- **Não se conclui que funciona porque as sessões coexistem.** Coexistência de sessão foi medida sob
  leitura; cotação simultânea é outra coisa e é o termo 2;
- não se mexeu em `SIDEKIQ_CONCURRENCY` nem na ordem das filas;
- não se tocou em produção, não se gastou cotação, e nenhum `quote start` foi disparado.
