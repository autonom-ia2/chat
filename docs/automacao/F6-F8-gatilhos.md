# Gatilhos: F6 + F8 numa fase só (#2499, épico #2414)

Desenho para a sessão Automação, a qualidade e Funções, em 03/11/2026. Liberado pela qualidade e por Funções; o
protótipo em tela real (kit `bin/demo`) foi aprovado pelo Rodrigo em 03/11.

**Entrega em PRs, nesta ordem:**
1. núcleo: o alvo genérico (`Contexto`), o registro `Gatilhos` com os gatilhos de hoje e a marca em µs (#2508);
1b. quem começou a conversa (#2527): `conversa.iniciada_por` e `mensagem.primeira` (ver 14);
2. gatilhos novos de conversa, a flag e o editor com o catálogo do servidor;
3. card: o emissor, os eventos de card e reunião, os passos de card e os painéis da etapa e do card;
4. a varredura de tempo (`TempoJob`);
5. o passo webhook.

- **Branch:** `feat/2499-gatilhos`, sobre a main c548aec836 (com #2494 e #2495).
- **Migration:** nenhuma (ver 9). **Flag:** uma nova, `automacao_gatilhos`; a posição quem dá é a Orquestração.

## 0. Escopo

**Entra:**
- card do CRM: entrou na etapa, saiu da etapa, ganho, perdido, parado há X dias na etapa e N dias antes ou depois de uma data do card ou do contato;
- o retorno como passo, os painéis da etapa e do card, e as receitas por pacote;
- mais gatilhos: recorrente, mensagem que falhou na entrega, troca de responsável e de time da conversa, e reunião (marcada, remarcada ou cancelada).

**Entra também (Rodrigo, 03/11):** o passo **webhook de saída** (F8.4), com as travas da seção 7.1.

**Fica fora:** as IAs do CRM.

**Do termo de aceite, mas fora da lista da Automação** (perguntas P1 e P2):
- card criado;
- card arquivado;
- campo do card mudou;
- etiqueta posta ou tirada (F8.7);
- troca do responsável do card.

## 1. Um jeito só de acrescentar gatilho

Hoje cada gatilho é uma linha do listener, o enum do esquema e a frase do i18n, e o alvo é sempre a conversa.

**Proposta:** um registro declarado, `Autonomia::Automacao::Gatilhos`, com uma entrada por tipo. Cada entrada diz:

| Campo | O que é |
|---|---|
| `alvo` | `Conversation`, `Crm::Card` ou `Contact`: em quem a execução roda |
| `origem` | `:evento` (o despacho assíncrono entrega) ou `:tempo` (a varredura de tempo acha) |
| `marca` | como o evento vira a marca única da coluna `evento` (ver 3) |
| `parametros` | o que a pessoa escolhe no gatilho (etapa, dias, campo, hora, frequência) |
| `valores_do_evento` | o que só o filtro do gatilho lê, como hoje `mensagem.tipo` (ex.: `evento.etapa_anterior_id`) |
| `requer` | a flag e a permissão a mais (`crm_manage_pipelines` nos de card) |

Quem lê o registro:
- **o esquema** (`automacao-receita.schema.json`): o `gatilho` vira `oneOf` por tipo, com os parâmetros de cada um. O spec do CI falha se o enum e o registro divergirem.
- **a escuta** (`Escuta`): os métodos do listener só traduzem o evento em `Escuta.comecar(alvo, tipo, evento:)`. O `evento` carrega a marca e os valores do evento. Não há mais um caminho por gatilho.
- **a varredura de tempo** (`TempoJob`, novo): para cada gatilho `:tempo`, o registro diz como achar os alvos da janela.
- **o catálogo** (`Catalogo.gatilhos`): gera, para o editor e o Guia, o tipo, o alvo, os parâmetros com a peça da tela e a frase. O spec cobra a frase em pt_BR e en, como nos passos.

**Acrescentar um gatilho depois** fica assim:
- uma entrada no registro;
- o `oneOf` do esquema;
- a frase;
- e, se for evento, um método de uma linha no listener.

Nada muda na Partida, no Executor nem na varredura.

## 2. Os gatilhos

| Tipo | Alvo | Origem | De onde vem | Parâmetros | Marca (`evento`) |
|---|---|---|---|---|---|
| `conversa.criada` / `.aberta` / `.resolvida` | conversa | evento | já existe | — | `conversa.<tipo>:<id>:<timestamp do evento>` (novo, fecha o 🟡 da #2459) |
| `mensagem.criada` | conversa | evento | já existe | — | `mensagem:<id>` (já existe) |
| `mensagem.falhou` | conversa | evento | `MESSAGE_UPDATED` com `status` mudando para `failed` | — | `falhou:<mensagem id>` |
| `conversa.responsavel_trocado` | conversa | evento | `ASSIGNEE_CHANGED` | — | `responsavel:<conversa>:<timestamp>` |
| `conversa.time_trocado` | conversa | evento | `TEAM_CHANGED` | — | `time:<conversa>:<timestamp>` |
| `card.criado` | card | evento | atividade `create` (Creator e CardNaEtapa) | `funil_id` (opcional) | `atividade:<activity id>` |
| `card.responsavel_mudou` / `card.time_mudou` (G9, #2707) | card | evento | o próprio card, no gancho único `Crm::CardAvisaAutomacao` (`owner_id` ou `team_id` mudou; `Autonomia::Automacao::TrocaNoCard`): a Lista do CRM grava a atividade `update` só com o dono novo, e a saída da triagem nem grava atividade | `funil_id` (opcional) | `<tipo>:<card>:<anterior ou 0>:<updated_at µs>` |
| `conversa.etiqueta_posta` / `.etiqueta_tirada` | conversa | evento | `CONVERSATION_UPDATED` com `label_list` em `changed_attributes` | `etiqueta` | `etiqueta:<conversa>:<etiqueta>:<timestamp>` |
| `contato.etiqueta_posta` / `.etiqueta_tirada` | contato | evento | `CONTACT_UPDATED` com as etiquetas mudando | `etiqueta` | `etiqueta:<contato>:<etiqueta>:<timestamp>` |
| `card.entrou_na_etapa` | card | evento | atividade `move` (Mover) e `create` (CardNaEtapa) | `etapa_id` | `atividade:<activity id>` |
| `card.saiu_da_etapa` | card | evento | atividade `move` | `etapa_id` | `atividade:<activity id>` |
| `card.ganho` / `card.perdido` | card | evento | atividade `won` / `lost` (Closer) | `funil_id` (opcional) | `atividade:<activity id>` |
| `reuniao.marcada` / `.remarcada` / `.cancelada` | card | evento | atividades `meeting_scheduled` / `_rescheduled` / `_canceled` | — | `atividade:<activity id>` |
| `card.parado` | card | tempo | `entered_stage_at` (índice `idx_crm_cards_entered_stage`) | `etapa_id`, `dias` | `parado:<card>:<entered_stage_at µs>` |
| `card.data` / `contato.data` | card / contato | tempo | `custom_attributes` (atributo de tipo data) | `campo`, `dias`, `antes`/`depois`, `hora`, `repete` (opcional: `todo_ano`) | `data:<alvo>:<campo>:<data>` |
| `recorrente` | card ou contato | tempo | relógio no fuso da conta | `frequencia`, `dia`, `hora`, `alvo`, filtros | `recorrente:<ocorrência local>:<alvo>` |

**Valores do evento**, que só o filtro do gatilho lê:
- troca de dono do card (G9): `gatilho.responsavel_anterior_id`, `gatilho.responsavel_anterior_nome` e `gatilho.responsavel_anterior_ausente`, lidos da marca no filtro e em qualquer passo desse gatilho; quem cuida agora é `card.responsavel_id` e `card.responsavel_nome`;
- troca de time do card (G9): `gatilho.time_anterior_id` e `gatilho.time_anterior_nome`; o time de agora é `card.time_id`. Na conversa (`conversa.responsavel_trocado`, `conversa.time_trocado`) ainda não: nenhum termo pede;
- saiu da etapa: `evento.etapa_para_id`;
- mensagem que falhou: `evento.erro`. É o código do canal, nunca o texto, que pode trazer dado do cliente.

## 3. A marca por evento vale para todos

A coluna `evento` e o índice único `(automacao_id, evento)` do #2494 já servem a qualquer gatilho, e não precisam de migration. Cada gatilho diz a sua marca. Assim, o mesmo evento entregue duas vezes (o `EventDispatcherJob` repete) abre uma execução só, mesmo depois de a primeira fechar.

- **Evento do despacho sem id próprio** (conversa, responsável, time): a marca usa o `timestamp` do despacho, serializado com microssegundos (`iso8601(6)`), nunca `to_i`: reabrir e resolver no mesmo segundo são dois fatos. O `EventDispatcherJob` guarda e repete o mesmo valor. Isso fecha o 🟡 dos gatilhos de conversa registrado na #2459.
- **Card e reunião:** usam o id da atividade (`Crm::Activity`). Ele é único e nasce no mesmo commit da mudança.
- **Tempo:** a marca é o próprio fato. "Entrou na etapa em tal instante" e "a data do campo vale tal dia" disparam uma vez só (F6.1). Se a pessoa mover o card e ele voltar, `entered_stage_at` muda, e conta de novo.

## 4. Alvo card e contato

Hoje o Executor e o `Valores` supõem a conversa (`Valores.new(conversa: alvo)`). A F6 troca isso por um **contexto do alvo**, com pontes:

| Alvo | conversa | card | contato |
|---|---|---|---|
| conversa | ela | — | `conversa.contact` |
| card | `card.primary_conversation` (pode faltar) | ele | `card.contact` |
| contato | — | — | ele |

- **`Valores`** ganha `card.*`:
  - `etapa_id`, `funil_id`, `status`, `valor`, `responsavel_id`, `time_id`, `titulo`, `dias_na_etapa`, `motivo_da_perda`;
  - `card.atributos.<chave>`, do modelo `card_attribute`.
  - `conversa.*` e `contato.*` passam a ler pela ponte.
- **Ao salvar**, a Receita recusa um caminho que o alvo do gatilho não tem. O motivo é a frase `valor_fora_do_alvo`: por exemplo, `card.*` num gatilho de conversa. Mesmo jeito do `mensagem_so_no_gatilho`.
- **Ponte vazia ao rodar:** a ação cujo caminho pede `conversa.id`, num card sem conversa, já pula com `faltou_valor`, como hoje. A mensagem e o avisar pulam com `sem_conversa`.
- **Acesso:**
  - `Acesso#alcanca?` já trata o card: `CardPolicy`, mais a conversa principal (#2494).
  - O contato passa pela `ContactPolicy#show?`.
  - O Spam vale para a conversa, para a conversa principal do card e para o contato: o contato cuja única conversa está no Spam é pulado, como a conversa.
- **O alvo é genérico** (regra da Automação entre frentes):
  - a execução guarda `alvo_type` `Conversation`, `Crm::Card` ou `Contact`, e o `alvo_id` do banco;
  - o histórico e o ensaio da F2 (#2498) leem esse alvo pelo mesmo contexto. Card aparece como "Card #<id> · <título> · <funil> › <etapa>", com o link do card; contato aparece pelo nome. O nome vem do registro, nunca é gravado;
  - contrato combinado com a F2 (#2498):
    - `Contexto.de(alvo)` expõe `rotulo`, `link` e `visivel_para?(usuario)`;
    - `Contexto.de_varios(alvos, usuario)`: lote para o histórico (20 por página), com preload por tipo (conversa com caixa e contato; card com funil e etapa) e uma checagem de visibilidade por lote, sem consulta por linha;
    - `Contexto.recentes(conta:, usuario:, tipo:, limite: 10)`: os candidatos do ensaio, só o que a pessoa enxerga (conversa pelo filtro da lista de conversas; card pelo escopo do funil). Até o card entrar, só conversa;
    - o rótulo sai do i18n, em en e pt_BR.
  - O agregado da lista ("Rodou 12 vezes") conta todas as execuções, sem nome; não expõe ninguém (F2, com OK da Automação).
- **Visibilidade do histórico e do ensaio:** valem a caixa e o funil de quem olha. O card passa pela `CardPolicy#show?` (o escopo visível) e a conversa pela `ConversationPolicy#show?`. A execução que a pessoa não alcança não aparece; não aparece nem como "escondida".
- **Ensaio:**
  - o webhook de saída nunca é chamado; o passo mostra "aqui chamaria o webhook" e o host, nunca a URL completa;
  - os gatilhos de tempo não gravam nada: nem execução, nem marca, nem registro. O ensaio só mostra quais alvos a janela de hoje pegaria.

## 5. Os eventos do card

Hoje o `crm.card.*` só sai pelo dispatcher quando há webhook assinante ou sincronia Meta/Google (`Crm::Webhooks::Emitter`, linha 51).

O ADR 2.5 já previa: *"o emissor passa a sair também quando há automação assinante"*. Proposta:
- **O emissor confere uma coisa a mais:** a conta tem o motor e `automacao_gatilhos`, e alguma automação ligada com gatilho daquele evento? É uma consulta indexada por conta, a mesma da escuta.
- **Eventos novos no `EVENT_MAP`:** `meeting_scheduled`, `meeting_rescheduled` e `meeting_canceled`.
  - Eles só vão para quem assina automação.
  - O webhook da conta continua recebendo só o que já recebia: o assinante escolhe evento por evento. Confiro o `WebhookListener` no PR.
- **Payload:** só ids, como hoje (card, atividade, `changed_attributes`). A escuta relê o card do banco.
- **Cadeia:** a atividade nasce na rodada que moveu o card. O `CadeiaNoDespacho` já leva as origens no evento. Então mover pela automação A não dispara A de novo (`:auto_disparo`), e conta na profundidade 3.

**Caminhos que não disparam** "entrou" ou "saiu", hoje e depois (F6.4):
- o arquivamento em massa (`pipelines/archiver.rb`) e o apagar etapa (`destroyer.rb`, com `update_all`);
- o **upsert do card com `stage_id`** (`cards_controller.rb:291`): ele faz `update!` direto, não passa pelo Mover, não grava `entered_stage_at` e não roda as automações de etapa antigas.

A tela da etapa avisa o que não dispara. Ver a pergunta P5 sobre o upsert.

**Mensagem que falhou:** o `MESSAGE_UPDATED` já chega ao listener assíncrono, com `previous_changes`. Só dispara quando o `status` muda para `failed`.
- **Laço (🔴 da qualidade):** a falha chega assíncrona, em outro job, sem a cadeia na thread. Reconstruir só `automacao:<id>` recomeçaria a cadeia a cada salto: com o canal fora, A manda e falha, C manda e falha, A de novo, sem fim.
  - A marca da mensagem já leva `automacao_id` e `execucao_id` (`na_conversa.rb`, `marca`).
  - No `falhou`, a escuta lê a execução de origem e retoma a **cadeia inteira dela**: as `origens` gravadas na coluna `cadeia`, mais `automacao:<id>` da própria, por `Cadeia.retomar`. A partida nova fica com a profundidade de lá + 1.
  - Assim, A → C → A cai em `:laco` (A já está nas origens) e qualquer caminho para na profundidade 3. A → A cai em `:auto_disparo`.
  - A raiz não fica gravada na execução (vai no `AvancarJob`). A retomada usa uma raiz nova; quem barra é a lista de origens e a profundidade, que estão gravadas.
  - Mensagem sem a marca (pessoa, robô antigo) começa sem cadeia, como hoje.
  - Spec: A ↔ C com o canal fora do ar para na profundidade 3.

## 6. A varredura de tempo (`TempoJob`)

- **Ritmo:** a cada 15 minutos, no `config/schedule.yml`. A hora do gatilho é cheia (8h, 9h…). Só passam as contas com motor e `automacao_gatilhos` e com alguma automação de tempo ligada.
- **Por automação**, acha os alvos da **janela**, enfileira um job por lote e, para cada alvo, chama a Partida com a marca. A janela é de 1 dia para trás.
- **Tudo no SQL, em lote** (`find_each`): o filtro da janela, da etapa, da data e dos filtros simples vai na consulta. Nunca se carrega a conta inteira no Ruby. Contatos passam de 100 mil por conta, e a varredura roda a cada 15 minutos. É proteção contra defeito, não teto. O PR leva um spec com volume e o `EXPLAIN` de cada consulta.
  - **parado:** `entered_stage_at` entre `agora − dias − janela` e `agora − dias`, na etapa escolhida, com o card aberto. Usa o índice `idx_crm_cards_entered_stage`.
    - O card que chegou ao prazo antes de a automação ser ligada **nunca dispara**: ligar não age no passado (`ligada_em`, ou a hora da versão ativa, o que for mais recente). A tela do gatilho diz isso.
  - **data:** a data-alvo é calculada no Ruby (hoje no fuso da conta ∓ `dias`) e entra no SQL como igualdade: `custom_attributes->>'<campo>' = '<AAAA-MM-DD>'`. Vale para card e contato.
    - #2678: no card, entram o aberto e o que **deu certo**: ganho, resolvido (o ganho do funil que não conta como venda) e o arquivado depois de fechado assim (`Crm::Card.com_desfecho`). A festa, a revisão e a renovação vêm depois da venda. O perdido, o cancelado e o arquivado sem desfecho ficam de fora.
    - #2678: com `repete: todo_ano`, compara só mês e dia (`substr(campo, 6, 5)`), com o formato ISO conferido antes. Em ano que não é bissexto, o dia 28/02 também pega quem tem 29/02. A marca leva o dia-alvo com o ano: uma vez por ano.
    - Só se lê data ISO (`AAAA-MM-DD`). O valor em outro formato não casa com a igualdade e é ignorado. A varredura conta quantos alvos da conta têm o campo em formato inválido e põe isso no histórico da automação, sem o valor.
    - "Já passou da `hora`" é conferido antes da consulta. A ocorrência anterior a ligar (ou a salvar a versão ligada) não roda: ligar às 8h um "às 9h" começa pela de hoje às 9h, nunca pela de ontem.
  - **recorrente:** a última ocorrência (`frequencia`, `dia`, `hora`, no fuso da conta) que é ≤ agora e cabe na janela. Age em cada card ou contato que passa nos filtros, uma vez cada (F8.6). Os filtros do recorrente vão no SQL.
    - A ocorrência entra na marca em **UTC ISO** (`iso8601`), nunca na hora local: no fuso com horário de verão, a hora local ambígua não repete nem pula. Spec com um fuso que tenha horário de verão.
- **Deploy no meio** (F8.1): nada mora em memória. A janela e a marca fazem a varredura seguinte achar a ocorrência perdida, e ela não repete a que já rodou.
- **Janela de 1 dia:** o que ficou mais de 1 dia sem varredura não roda depois. Assim, uma pane longa não faz o cliente receber de uma vez tudo o que estava atrasado. A janela é proteção contra defeito, não freio de uso.
- **Fuso:** o da conta (`settings['reporting_timezone']`, que o CRM e os relatórios já leem, #954), nunca "Brasília".

## 7. Passos novos

- **Retorno:** proponho liberar `POST crm/follow_ups` como **ação do catálogo** no `automacao-recursos.yml`, com o caminho `card_id: card.id`. A F3 o tinha guardado para "virar passo nativo na F6".
  - Com isso, o retorno entra com o formato completo do Guia, inclusive `automation_mode: auto_send_message` ("criar retorno com envio automático"), e sem código novo no motor.
  - Fica nativo só se o texto do envio precisar dos valores em chip (`{"$valor": "contato.nome"}`), que o corpo de uma ação não lê. Ver a pergunta P3.
- **Card:**
  - "Mover de etapa" (`POST crm/cards/:id/move`) e "Alterar o card" (`PATCH crm/cards/:id`), que já estão liberados, ganham entradas no `automacao-passos.yml`, no grupo novo `CARD`.
  - "Ganhar ou perder" (`POST crm/cards/:id/close`) precisa ser liberado no `automacao-recursos.yml`. Ver a pergunta P4.
- **Gatilho ou passo de funil exige `crm_manage_pipelines`** (D2/D4). Ajustado pelo parecer de Funções (#2499, comentário 6610737672):
  - a conferência é `CrmPermissions#crm_permission?('crm_manage_pipelines')`, como na `StageAutomationPolicy`: ela conta o `crm_admin` e nega o agente comum. O `permission_granted?` cru recusaria o `crm_admin`;
  - vale em três momentos, sempre junto com `automation_manage`: ao salvar (quem salva), ao ligar e a cada rodada (`ligada_por`);
  - sem a permissão: o salvar recusa (`sem_permissao_funil`); na rodada, a automação pausa com o motivo no histórico, nunca `erro_inesperado`.
- **Os passos de card rodam como `ligada_por`, pelas policies do card:**
  - mover pede `crm_move_cards` ou `crm_manage_cards`, e o funil;
  - ganhar ou perder e alterar pedem `crm_manage_cards` e o funil;
  - o retorno pede `crm_manage_cards` e o `ensure_card_funnel!`.
  - O `crm_manage_pipelines` não implica nada disso (só com `crm_admin`). Então a Receita recusa ao salvar o passo que quem salva não poderia fazer. Ao rodar, a recusa da policy pausa a automação com motivo claro.
- **CRM desligado na conta:** o servidor recusa gatilho e passo de card ao salvar (`crm_desligado`); não basta o seletor esconder. Ao rodar, a execução fecha parada.

### 7.1 Passo `webhook` (F8.4)

```json
{ "id": "p4", "tipo": "webhook", "url": "https://n8n.exemplo.com/webhook/abc", "campos": ["card.titulo", "contato.nome"] }
```

- **Nativo**, não ação do catálogo: o motor monta o corpo com os `campos` escolhidos (os mesmos caminhos do Valores, só os que o alvo do gatilho tem) e manda um POST JSON.
- **Quem monta ou muda**, no mesmo padrão do #2449 (`AutomationExternalActionGuard`): criar, mudar, copiar ou ligar uma automação que tem ou vai ter o passo `webhook`, ou tirar o passo, pede `integration_manage`, além de `automation_manage`. O administrador sempre pode.
  - **Desligar não pede** `integration_manage`: desligar só corta o envio para fora, e "desligar sempre funciona" (Funções).
  - `integration_manage` é a chave que já existe, uma chave de delegação (`DELEGATION_KEYS`, `custom_role.rb`): só o admin a entrega, mas uma função pode tê-la.
  - Na rodada, o Executor reconfere `integration_manage` de `ligada_por`. Sem ela, pausa (`sem_permissao_integracao`).
- **Quem só vê não vê a URL** (#2450): para quem não é admin nem tem `integration_manage`, a URL sai mascarada (só o host) em **toda** saída:
  - o show e a lista da automação;
  - a resposta do create e do update (`para_tela`, com a receita);
  - a lista e o diff de versões, inclusive as antigas;
  - o histórico, o ensaio da F2 (#2498), a leitura do Guia como a pessoa, o catálogo, os formatos do Guia e qualquer exportação.
  - Spec: quem só vê chama cada endpoint que devolve receita ou versão, e nem o caminho nem a query da URL aparecem.
  - Como o guarda vale para a automação inteira, quem só vê nem salva. "Salvar a URL mascarada mantém a gravada" fica de reserva: casa pelo `id` do passo, compara com a máscara exata (não por prefixo), e um `id` novo com a URL mascarada é recusado.
- **SSRF:**
  - **só `https`**: o `http` mandaria o token da URL em claro. O salvar recusa (`so_https`);
  - ao salvar **e ao chamar** (DNS rebinding), o host é resolvido pelo resolver do `ssrf_filter`, e IP privado, loopback, link-local e metadata (169.254.169.254) são recusados (`endereco_proibido`);
  - **host da própria instalação** (o de `FRONTEND_URL` e os domínios da conta) também é recusado, ao salvar e ao chamar: o webhook que bate na nossa API criaria mensagem ou moveria card fora da cadeia;
  - a chamada vai pelo `SafeFetch` (`lib/safe_fetch.rb`) com `max_redirects: 0` (um redirect reenviaria o corpo, com dados do cliente, a outro host), timeout curto e `allowed_content_types` com JSON e texto (o padrão aceita só imagem e vídeo, e toda resposta JSON viraria falha). Corpo da resposta lido até um limite pequeno;
  - o passo ignora `SAFE_FETCH_ALLOW_PRIVATE_NETWORK`. Spec: a variável ligada não abre rede privada para o passo.
- **Laço pelo outro sistema** (um n8n que chama de volta a nossa API): além de recusar o host da instalação, o pedido leva o cabeçalho `X-Automacao-Cadeia` (raiz e profundidade, sem dado do cliente). A nossa API, ao receber um pedido com esse cabeçalho, retoma a cadeia (`Cadeia.retomar`), e o que esse pedido mudar entra na profundidade. Spec dos dois.
  - O cabeçalho vem de fora e não é confiável: **só restringe, nunca amplia**. Vale só com o token da própria conta; a profundidade tem de ser inteiro ≥ 0, e valor inválido é ignorado; a profundidade final é o maior entre a do cabeçalho e a interna; a raiz do cabeçalho entra com prefixo próprio (`externa:<raiz>`), para nunca casar com uma raiz interna no SETNX nem gastar a contagem diária dela; nunca baixa a profundidade nem pula o `:auto_disparo`. Leitura estruturada (JSON), sem regex, com teto de tamanho; acima do teto, o cabeçalho é ignorado. Spec: cabeçalho forjado com profundidade -1, texto ou uma raiz interna não mexe na cadeia interna.
  - Ele leva só raiz e profundidade, sem as origens. Então A → n8n → nossa API → A não cai em `:auto_disparo`: para só na profundidade 3, ou seja, 3 voltas. Aceito como proteção contra defeito, não como freio de uso.
- **Segredo e URL fora de tudo:** a URL completa, a query e qualquer segredo nunca vão para log, exceção, registro, histórico ou Sentry. O histórico guarda o host, o código HTTP e o tempo. O `body_excerpt` do `SafeFetch::HttpError` fica fora do registro. O log de erro leva a classe e a linha, nunca a mensagem.
  - Assinatura do corpo: não no 1º PR (P11, de acordo da qualidade e de Funções, com só `https`). Segredo nunca na receita.
- **Dados que saem:** o selo "manda dados para fora" lista os campos escolhidos; os campos ficam presos aos que o alvo do gatilho tem.
- **Falha de entrega aparece no histórico:**
  - 4xx: `falhou`, sem repetir;
  - 5xx ou timeout: tenta 3 vezes (ADR 2.4.6) e depois `falhou`;
  - endereço proibido na hora de chamar: `falhou` com `endereco_proibido`.
  - Em todos os casos a automação segue para o próximo passo (P10, recomendação; de acordo da qualidade).
- **Ensaio:** nunca chama (seção 4).
- **Fica para depois:** usar a resposta do outro sistema nos passos seguintes (F8.5). Ver a pergunta P10.

## 8. Telas

O protótipo é em tela real: componentes Vue do fork, kit `bin/demo`, dados do seed.
1. **Editor, gatilho:**
   - o seletor agrupa os gatilhos em Conversa, Mensagem, Card do funil, Tempo e Reunião;
   - cada um mostra os seus parâmetros: etapa, dias, campo de data, antes ou depois, hora, frequência;
   - os de card aparecem só para quem tem `crm_manage_pipelines` e o CRM ligado.
2. **Configurar › Editar funil › etapa, "Automações desta etapa":**
   - as antigas, com o selo "jeito antigo" (F6.5), e as novas desta etapa;
   - "Nova automação" abre o editor com o gatilho já preenchido;
   - o aviso do que não dispara (F6.4), inclusive o upsert até a #2501;
   - acesso (Funções): `crm_manage_pipelines` + `automation_view` para ver; `automation_manage` para "Nova".
3. **Card, "Automações deste cartão":**
   - o que está rodando, com o passo e a espera;
   - o histórico em frases;
   - "Parar para este cartão" (F6.3). Ver a pergunta P6;
   - acesso (Funções): ver pede `automation_view` + `CardPolicy#show?`; parar pede `automation_manage` + `CardPolicy#update?`.
   Cada endpoint novo leva o parecer de Funções no PR.
4. **Receitas por pacote:** "30 dias antes do vencimento → Renovação + mensagem + retorno em 5 dias" e "card parado 3 dias em Orçamento enviado". Usam o formato de receitas da F2 (#2498, decisão da Automação na P7).
5. **Passo webhook:** a URL, os campos escolhidos e o selo "manda dados para fora". Quem não tem `integration_manage` vê o passo com a URL mascarada e não edita.

## 9. Migration e flag

- **Migration: nenhuma.**
  - A coluna `evento` e o índice dela servem de marca para todos os gatilhos.
  - O alvo já é polimórfico.
  - A janela de tempo não guarda estado.
  - O índice `idx_crm_cards_entered_stage` já existe.
  - Muda se a P6 decidir que "Parar para este cartão" também barra o que vier depois. Aí entra uma tabela de exclusão, com uma versão pedida à Orquestração.
- **Flag `automacao_gatilhos`:** vale só com `automacao_motor`.
  - **Bit:** registrada pela Orquestração sem número fixo; a posição na `feature_flags_ext_2` é a ordem de entrada na main. A entrada vai no `features.yml` logo depois de `automacao_mensagens` (23). Hoje seria a 24 (8388608), disputada com as duas flags do #2442 e a do #1430 assíncrono. Antes da fila: merge da main e acerto do bit, do comentário e do spec pela posição real; a Orquestração confirma o número ao enfileirar.
  - **Desligada:** o salvar recusa os gatilhos novos (`gatilho_desligado`); a escuta e o `TempoJob` não olham a conta; a execução aberta de gatilho novo fecha parada. Esse é o rollback.
  - **Contas:** nasce ligada no piloto 1, 16 e 18 (D11), salvo decisão contrária.

## 10. Arquivos que vou tocar

**Só meus (novos):**
- `app/services/autonomia/automacao/gatilhos.rb`
- `app/services/autonomia/automacao/contexto.rb`
- `app/jobs/autonomia/automacao/tempo_job.rb`
- `app/services/autonomia/automacao/tempo/{parado,data,recorrente}.rb`
- o componente do gatilho no editor (`LivreGatilho.vue`) e os painéis novos (`EtapaAutomacoes.vue`, `TelaAutomacoesDoCard.vue`)
- os specs desses arquivos

**Do motor, sem outra frente conhecida:**
- `escuta.rb`
- `partida.rb`
- `valores.rb`
- `acesso.rb`
- `automacao_listener.rb`
- `automacao-receita.schema.json`
- `app/services/autonomia/automacao/passo_de_webhook.rb` (novo)

**Do motor, com ordem (decisão da Automação):**
- `receita.rb`: a F1 (#2500) entra PRIMEIRO com a travessia única de todos os ramos. O meu código vai em cima.
- `executor.rb`: eu entro primeiro, com o alvo genérico (contexto). A F7 acrescenta o passo de IA depois.

**Compartilhados com outras frentes:** cada frente põe o seu bloco em método ou chave própria; quem entra depois traz a main antes do push; ninguém mexe no bloco de outra frente.
- `catalogo.rb`: o método `gatilhos`;
- `automacao-passos.yml`: o grupo `CARD` e as entradas de card;
- `automacao-recursos.yml`: `POST crm/follow_ups` e, se a P4 for sim, `POST crm/cards/:id/close`;
- o guarda do #2449 (`automation_external_action_guard.rb`) ou o equivalente da Automação livre: o passo `webhook` pede `integration_manage`;
- `automacaoLivre.json` (en e pt_BR);
- `LivreEditorPage.vue`: troca o seletor de gatilho pelo `LivreGatilho`;
- `LivreAlterar.vue`: só se o gatilho aparecer no resumo.

**CRM** (avisar o Multifunnel):
- `app/services/crm/webhooks/emitter.rb`: o gate;
- `CrmStageAutomationsPanel.vue`;
- o painel do card (`routes/dashboard/crm/components/card/telas/`).

**Configuração:** `config/schedule.yml` (o `TempoJob`) e `config/features.yml` (a flag).

**Funções:** a dica da linha Automações na matriz (`customRole.json`, en e pt_BR): gatilho e passo de card pedem também "Funil: Editar"; os passos de card pedem "Cards: Editar"; o passo webhook pede "Integrações".

## 11. Perguntas abertas

- **P1. Decidido (Rodrigo, 03/11):** card criado entra; arquivado e "campo mudou" ficam para depois.
- **P2. Decidido (Rodrigo, 03/11):** etiqueta posta ou tirada (conversa e contato) e troca do responsável do card entram.
- **P3. Decidido (Automação):** retorno pela ação do catálogo `POST crm/follow_ups`.
- **P4. Decidido (Rodrigo, 03/11):** o passo ganhar/perder (`POST crm/cards/:id/close`) entra; na perda, o motivo é obrigatório.
- **P5. Decidido (Automação):** Issue #2501 para o Multifunnel (upsert pelo Mover). Até lá, a tela avisa.
- **P6. Decidido (Rodrigo, 03/11):** "Parar para este card" para só o que está rodando. Sem migration.
- **P7. Decidido (Automação):** o dono do formato das receitas é a F2, no #2498. As receitas por pacote usam o formato dela.
- **P8. Decidido (Rodrigo, 03/11):** a lista agregada fica para depois.
- **P9. Decidido (Rodrigo, 03/11):** a #2428 entra antes do PR do card.
- **P10. Decidido (Rodrigo, 03/11):** depois de um webhook que falhou, a automação segue. Usar a resposta do outro sistema (F8.5) fica para um PR depois.
- **P11. Decidido (Rodrigo, 03/11):** sem assinatura no 1º PR ("sem senha ou no próprio link"). O link pode trazer o token, então a URL inteira conta como segredo: mascarada para quem só vê e nunca em log nem no histórico.

## 12. Como vou provar (specs que devem falhar antes)

- **Evento entregue 2 vezes:** card movido, ganho, responsável e falha geram 1 execução e 1 efeito, mesmo com a primeira já fechada.
- **F6.1:** card parado 3 dias dispara uma vez em 10 varreduras seguidas; se ele mudar de etapa e voltar, dispara de novo.
- **F6.2:** "30 dias antes" numa conta com fuso UTC−3 e outra com UTC+9 dispara no dia local certo, e na hora.
- **F8.1:** "toda segunda às 8h" com o `TempoJob` parado das 7h45 às 9h15 roda uma vez, às 9h15. Com a janela vencida, não roda.
- **F6.4:** arquivar em massa não dispara "saiu da etapa".
- **Cadeia:** a automação que move o card não dispara a si mesma; duas automações em cadeia param na profundidade 3.
- **Laço:** a mensagem de automação que falhou, reenviada pela mesma automação, cai em `auto_disparo`.
- **Acesso:**
  - quem não tem `crm_manage_pipelines` não salva um gatilho de card;
  - quem perde a permissão no meio pausa a automação, sem `erro_inesperado`.
- **Flag desligada:** o salvar recusa, e a execução aberta fecha parada.
- **Webhook:**
  - sem `integration_manage`, criar, mudar, copiar, ligar ou tirar o passo recusa; com a função personalizada que só tem `automation_manage`, também recusa;
  - quem só vê recebe a URL mascarada, e salvar com a mascarada mantém a gravada;
  - URL com host privado (127.0.0.1, 10.x, 169.254.169.254, nome que resolve para rede interna) recusa ao salvar e, se o DNS mudar, falha ao chamar com `endereco_proibido`;
  - o log, o registro e o histórico não contêm a URL completa nem a query (spec procura a string);
  - 500 do outro lado tenta 3 vezes e fica `falhou` no histórico; 400 falha sem repetir;
  - o ensaio não faz nenhuma chamada HTTP (spec com WebMock sem stub).
- **Marca µs:** o retry do `EventDispatcherJob` com o mesmo timestamp abre 1 execução; reabrir e resolver no mesmo segundo abrem 2.
- **Laço da falha:** A ↔ C com o canal fora do ar para na profundidade 3.
- **Volume:** a varredura de data e de recorrente em contato, numa conta com muitos contatos, consulta em lote no SQL; o PR traz o `EXPLAIN`.
- **Data inválida:** o campo fora de ISO é ignorado e contado no histórico.
- **Horário de verão:** o recorrente num fuso com horário de verão roda uma vez na troca de hora.
- **Gate do emissor:** conta só com automação não chama Meta, Google nem webhook não assinante; `meeting_*` não chega ao webhook da conta.
- **Spam do contato:** o contato cuja única conversa está no Spam é pulado.
- **Webhook:** `http` recusa; o host da instalação recusa ao salvar e ao chamar; um redirect não é seguido; resposta JSON não vira falha; o `body_excerpt` não vai ao registro; o cabeçalho `X-Automacao-Cadeia` faz o pedido de volta entrar na profundidade.
- **Visibilidade:** o histórico e o ensaio não mostram a execução de card ou conversa fora do funil ou da caixa de quem olha.

## 13. Notas da revisão do PR 1 (qualidade, 03/11) — para os PRs seguintes

- **Lote de visibilidade para a F2.** `Contexto.de_varios` entra no PR do primeiro gatilho de card ou contato, que é
  quando o histórico (#2498) precisa dele. Contrato combinado com a F2: entrada em pares `[alvo_type, alvo_id]`
  (carregados em lote, uma consulta por tipo); saída `{ [alvo_type, alvo_id] => contexto }` só com os visíveis; uma
  constante pública `alvo_type → chave i18n do tipo`, para a tela dizer "Uma conversa" sem rótulo nem link quando o
  alvo não é visível. Sem `account_users.find_by` por alvo (o `visivel_para?` de hoje faz um por chamada).
- **Contato do card.** Num alvo card, `contato.*` lê `card.contact` (e só sem ele o contato da conversa principal).
  Quando os dois forem pessoas diferentes, vale o do card; spec disso no PR dos gatilhos de card.
- **`card.valor` sem valor lê 0**, nunca vazio (`value_cents` é not null, padrão 0): a condição "valor está vazio"
  nunca casa. Decidir no PR dos gatilhos de card entre ler nil quando for 0 ou deixar isso claro na frase.

## 14. Quem começou a conversa (#2527)

Em produção (30 dias, uma stack), a primeira mensagem às vezes é gravada segundos depois da conversa, e no WhatsApp
há mensagens com data anterior à da conversa (histórico importado). Por isso `conversa.criada` pode ver a conversa
ainda sem mensagem, e "quem começou" não sai do gatilho: sai da primeira mensagem de verdade.

- `Autonomia::Automacao::PrimeiraMensagem`: a primeira mensagem sem atividade nem nota (`Message.chat`), por
  `created_at` e, no empate, por `id`.
- `conversa.iniciada_por` (valor fechado, base conversa): `cliente` quando a primeira é `incoming`; `equipe` quando é
  `outgoing` ou `template` (resposta, privado do comentário, campanha, ligação feita); vazio sem mensagem.
- `mensagem.primeira` (só no filtro de `mensagem.criada`): `true` quando a mensagem do gatilho é essa primeira.
- Conversa resolvida que o cliente reabre continua de quem a começou. Histórico importado: a mensagem antiga diz
  quem começou, e a nova não é a primeira.
- O catálogo dá ao valor fechado do alvo as opções e os operadores, como aos da mensagem (frases em
  `VALOR_DA_MENSAGEM`).
- A Boas-vindas (F5, #2526) passa para `mensagem.criada` com `mensagem.primeira = true` e
  `conversa.iniciada_por = cliente`, num PR da F5 depois deste.

## 15. A conversa lê o card dela, e a mensagem diz se tem anexo (#2716)

Achado na auditoria dos exemplos 14 e 18 (Issue #2716): uma automação de mensagem precisa saber em que etapa está o
card da conversa e se chegou um documento; sem isso, uma IA no passo roda (e cobra) em toda mensagem da conta. O 18 só
começa com o currículo, em PDF ou foto. Esta é a capacidade (G45). Ela não fecha o ex.14: à risca, o ex.14 é UMA
automação, que começa quando o card entra em "Documentação" e faz o laço dos documentos dentro dela. Partir o passo 2
numa segunda automação de `mensagem.criada` adapta o termo; o laço dentro de uma automação só vira lacuna nova, e o
ex.14 continua no `pendentes_spec`.

- `card.*` vale no gatilho de conversa (`Valores::BASES_DO_ALVO`). O card é o assunto atual da conversa, a mesma regra
  do selo da lista (`Crm::Cards::ConversationCardFinder`: o aberto antes do encerrado, depois o foco mais recente).
  Mora em `Autonomia::Automacao::CardDaConversa`.
- Só para ler: no filtro do gatilho, no "Só se", na condição da espera, nos textos e copiando um campo dele no corpo
  de uma ação (o título do card num atributo da conversa). O que apontaria a ação para o card o salvar recusa
  (`card_da_conversa_so_le`): `card.*` no caminho e `card.id` no corpo. Mexer no card é uma automação que começa no
  card (o passo "em outro registro", G18, ainda não existe). O `Contexto` não muda: os passos continuam sem card na conversa. O card lido é o da hora do passo: um card
  criado pelo passo "card" num passo anterior já aparece.
- Ler o card pede a chave de funis (`crm_manage_pipelines` ou `crm_admin`), como o gatilho de card: o salvar recusa sem
  ela (`sem_funil`), e a automação pausa (`sem_permissao_funil`) quando quem ligou a perde, em vez de ler vazio e
  deixar o "Só se" falso em silêncio. A pausa olha a versão ativa e a das execuções em andamento (cada uma segue a
  versão em que começou). Ao rodar, os cards que quem ligou não vê (o escopo do `Crm::CardPolicy`) saem antes de
  escolher o assunto atual; sem card visível na conversa, lê vazio.
- O editor oferece os valores do card no gatilho de conversa só a quem tem a chave de funis (`doAlvoDoGatilho`).
- **Valor protegido: a IA nunca escreve o valor; o texto que a pessoa escreve pode levar** (decisão 9 do Rodrigo,
  09/11, PR #2780, que revê a 3). Os valores de `Valores::PROTEGIDOS` (hoje `card.valor`) valem no filtro do gatilho,
  no "Só se" e nas condições, e também no texto que a pessoa escreve (mensagem, aviso, e-mail, retorno, corpo de
  ação), em qualquer automação, de conversa ou de card, como na main desde o #2605 (termo F4). Ler pede a permissão
  (`sales_value_view`) de quem salva e de quem ligou: sem ela, o salvar recusa (`valor_de_venda`) e a execução lê
  vazio (o passo pula com `faltou_valor`). O editor oferece o valor a quem pode lê-lo.
  A IA nunca recebe o valor para escrever (`ComIa.leva_o_valor?`, também no "Testar este passo"): em qualquer
  automação, o `le: card` do escrever, do resumir e do extrair vai sem o valor; o decidir o recebe, com a permissão.
  Essa brecha existia na main desde o #2679; fechada aqui. No "Testar este passo", o valor só vai (ao decidir) se quem
  testa e quem ligou a automação já salva (`automacao_id`) podem vê-lo.
- `mensagem.tem_anexo` (sim ou não, só no filtro de `mensagem.criada`): a mensagem traz foto ou PDF (a régua do
  ex.14: "a cada foto ou PDF que chega"). Foto é o anexo `image` com arquivo; PDF é o `file` com `application/pdf`.
  Áudio, vídeo, figurinha e outro arquivo não contam. A figurinha do WhatsApp chega como `image`
  (`file_content_type` junta image e sticker); a marca dela é `meta.is_sticker`, gravada no recebimento por
  `ConversaCanal::FigurinhaRecebida` (Cloud, 360dialog e Híbrido, com a flag `conversa_cara_do_canal`) e por
  `Waha::RichNative::Inbound::Media` (caixa WAHA, com `whatsapp_rich_native`). Sem a flag, a marca não é gravada e a
  figurinha conta como foto. Mora em `Autonomia::Automacao::FotoOuPdf`; o valor `conversa.cliente_mandou_documento`
  do "esperar até" (G46, o laço dos documentos) usa a mesma régua em SQL (`FotoOuPdf.escopo`). Lê o anexo no instante do evento `mensagem.criada`. Valem os canais que gravam o anexo junto com a mensagem:
  WhatsApp Cloud (`Whatsapp::IncomingMessageBaseService`), o conector WAHA/Híbrido, a API e o widget
  (`messages#create` → `Messages::MessageBuilder`) e o e-mail: a caixa cria a mensagem e grava os anexos na mesma
  transação (`Imap::ImapMailbox#process` e `ReplyMailbox#process`, com o `MailboxHelper`), e o `message.created` sai
  no commit (`after_create_commit`), com os anexos já gravados (#2729, prova em `imap_mailbox_automacao_spec.rb`).
- Cuidado conhecido (parecer da qualidade): uma execução aberta de versão antiga que lê o card pausa a automação
  inteira quando quem ligou perde a chave, mesmo com a versão ativa sem card. É de propósito: a execução segue a versão
  em que começou.
- Decisão da Automação: id fixo de card numa ação de uma automação de conversa continua permitido. Age com os direitos
  de quem ligou, como a pessoa faria à mão.
- Provas: `spec/fechamento/automacao/g45_card_da_conversa_spec.rb`,
  `spec/fechamento/automacao/exemplo_18_curriculo_comeco_spec.rb` e
  `spec/services/autonomia/automacao/card_da_conversa_spec.rb`.
