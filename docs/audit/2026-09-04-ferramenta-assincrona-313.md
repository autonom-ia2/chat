# Ferramenta assíncrona de agente (#313 · Onda 1.3)

## Objetivo

Permitir que uma ferramenta de agente que demora até ~90 segundos (a cotação no AGGER) responda na
conversa sem segurar worker e sem duplicar mensagem. Decisão de produto do PO: entrega PARCIAL —
o cliente recebe o que já chegou e as retardatárias vêm numa segunda mensagem.

## Decisão

Contrato em duas fases (`start` + `poll`) com uma linha de execução no banco, em vez de um `#call`
longo com bloco de entregas parciais.

Peças:

| Peça | Arquivo |
|---|---|
| Linha de execução | `app/models/autonomia/agents/tool_run.rb` |
| Contrato `async?`/`start`/`poll` | `app/services/autonomia/agents/tools/native/base.rb` |
| Resultado de uma consulta | `app/services/autonomia/agents/tools/progress.rb` |
| Contexto de entrega do turno | `app/services/autonomia/agents/tools/delivery.rb` |
| Aceitação no lugar da execução | `app/services/autonomia/agents/tools/bound.rb` |
| Parâmetros da espera | `app/services/autonomia/agents/tools/async_config.rb` |
| Promoção + enfileiramento | `app/services/autonomia/agents/tools/async_dispatcher.rb` |
| Publicação na conversa | `app/services/autonomia/agents/tools/async_publisher.rb` |
| Motor (submete, consulta, publica) | `app/jobs/autonomia/agents/tools/async_run_job.rb` |
| Republicação adiada | `app/jobs/autonomia/agents/tools/async_publish_job.rb` |
| Varredor de execução abandonada | `app/jobs/autonomia/agents/tools/reap_stale_runs_job.rb` |
| Autorização sem posse do turno | `app/services/autonomia/agents/operate.rb` |

## Divergências do desenho publicado na issue, e por quê

1. **O contexto de entrega desce por CHAMADA (`Bound#execute(call, delivery:)`), não pela
   construção.** `Tools::Bound.for_agent` tem dois chamadores; o segundo é `Specialist#tools`, que
   memoiza o catálogo na instância do model. Como o `Answerer` remove do principal todo slug
   reservado por especialista habilitado, a cotação só é alcançável pelo caminho do especialista —
   exatamente o que ficaria sem contexto se ele viesse na construção.
2. **Quem enfileira é o Responder, não o `Bound`.** A segunda chamada ao modelo (a que transforma a
   saída da ferramenta em resposta) não tem retry; um timeout ali devolve silêncio. Disparando no
   `Bound`, o cliente receberia uma cotação 60s depois sem nunca ter ouvido "vou cotar".
3. **`start` + `poll` em vez de `#call` com bloco.** `config/sidekiq.yml` tem `:timeout: 25` de
   shutdown e `:max_retries: 3`; um job de 90s é morto em todo deploy e reexecutado do zero, o que
   aqui significa cotar de novo na seguradora. É o desenho de `EmailCampaigns::Ai::PollJob`.
4. **A publicação assíncrona NUNCA carimba `autonomia_reply_to_message_id`.** O `already_replied?`
   do Responder é um regex sobre qualquer outgoing do bot com aquele id: herdá-lo faria o Responder
   descartar a resposta real do turno, em silêncio.
5. **O publicador relaxa UM predicado nomeado, não o contrato.** `Operate.authorized_agent_inbox`
   preserva kill-switch da conta, tenancy fail-closed, estado do agente e allowlist de piloto; só a
   exigência de conversa sem responsável é dispensada.
6. **A dedup é por `(conversa, ferramenta)` e SUPERSEDE**, não por argumentos. Chave por argumento
   deixaria "na verdade é 2019" gerar uma segunda cotação concorrente.

## Decisões de produto embutidas (precisam de confirmação do PO)

- Com humano na conversa, a entrega vira **nota privada**: o corretor recebe o dado, o cliente não
  recebe o robô falando por cima de quem já está atendendo.
- Quando o turno fica em silêncio, **o código publica o aviso de espera** — o aviso não depende de o
  modelo lembrar de dar.
- Uma chamada nova **descarta** a anterior para a mesma ferramenta na mesma conversa.

## Correções vindas da revisão adversarial (4 lentes + fase de refutação)

Nenhuma era incidente hoje — não há ferramenta declarando `async?` ainda. Todas explodiriam na Onda 2.

1. **Desfecho contraditório.** `finish_done` usava `sequence.zero?` como "não entreguei nada", mas o
   aviso de espera já tinha avançado o contador e uma entrega ADIADA ainda não. O cliente receberia
   a cotação e "não consegui concluir" lado a lado — ou, do outro lado, ficaria sem desfecho nenhum.
   Coluna `delivered_count`, que só conta entrega da ferramenta.
2. **Entrega supersedida publicada.** O `AsyncPublishJob` só checava se a linha existia. Uma entrega
   adiada de uma cotação já corrigida pelo cliente saía até 90s depois. Guarda por `dead?` dentro do
   publicador — e NÃO por `running?`, que derrubaria a entrega final legítima (a linha é fechada
   logo depois de publicar).
3. **Kill-switch não parava o portal.** O job validava prazo e ferramenta, nunca o gate da conta.
   Desligar o agente no meio do voo não parava as chamadas — até 60 tentativas, cada uma uma
   cotação real. Agora `Operate.authorized_agent_inbox` é checado antes de cada passo.
4. **`expected_chunks == 1` ultrapassava a resposta do turno.** Um pedaço único não foi postado:
   está agendado com atraso de até 15s. A espera passou a valer para `>= 1`.
5. **Token de entrega era posicional.** `execution_key:sequence` identifica ONDE a mensagem entrou,
   não O QUE ela diz — uma consulta que reemitisse a mesma lista republicaria o texto noutro índice.
   Agora é `execution_key:sha256(texto)[0,16]`.
6. **Corrida entre publicadores.** A sequência era lida fora do lock e avançada depois dele: dois
   publicadores concorrentes liam o mesmo número e o segundo descartava o texto devolvendo sucesso.
   Leitura e avanço foram para dentro do lock.
7. **`pending` órfã matava o retry do turno.** Worker morto entre o aceite e o despacho (um deploy
   basta) deixava a linha parada, e ela bloqueava a nova tentativa — a cotação nunca aconteceria.
   `opened_for_turn?` passou a ignorar `pending`/`discarded`/`blocked`.
8. **Despacho parcial deixava execução presa.** Rescue por execução no dispatcher + varredor
   (`ReapStaleRunsJob`, a cada 10 min) que fecha o que passou do prazo e avisa o cliente uma vez.
   O varredor NÃO retoma a execução: retomar significaria cotar de novo no portal.

Refutado e não alterado: o texto da entrega no payload do Sidekiq. É a prática que já está na `main`
(`ChunkedDeliveryJob` carrega a resposta inteira ao cliente pelo Redis) — melhoria legítima, mas não
é exposição nova desta PR. Os ARGUMENTOS, esses, ficam na linha.

## Limites conhecidos

- Não há ferramenta assíncrona real no catálogo ainda (`Tools::Registry` segue com uma única
  nativa). Esta entrega é fundação; o consumidor é a Onda 2 (cotação de Auto).
- A entrega assíncrona é publicada em mensagem única, sem quebra humanizada — a cotação é uma lista,
  e uma cadeia de chunks concorrente é justamente a fonte de mensagem fora de ordem.

## Validação

- `bundle exec rails zeitwerk:check` — All is good.
- `bundle exec rubocop --force-exclusion <arquivos novos e alterados>` — zero ofensas.
- Specs: ver a suíte de `#313` (model, config, bound, publisher, job, responder).
- Nenhum secret, token, credencial ou dado de cliente foi registrado neste documento.
