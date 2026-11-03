# Gatilhos: F6 + F8 numa fase só (#2499, épico #2414)

Desenho para a sessão Automação, a qualidade e Funções, em 03/11/2026. Nada de código de produção antes de o Rodrigo
aprovar o protótipo em tela real (kit `bin/demo`).

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
| `card.entrou_na_etapa` | card | evento | atividade `move` (Mover) e `create` (CardNaEtapa) | `etapa_id` | `atividade:<activity id>` |
| `card.saiu_da_etapa` | card | evento | atividade `move` | `etapa_id` | `atividade:<activity id>` |
| `card.ganho` / `card.perdido` | card | evento | atividade `won` / `lost` (Closer) | `funil_id` (opcional) | `atividade:<activity id>` |
| `reuniao.marcada` / `.remarcada` / `.cancelada` | card | evento | atividades `meeting_scheduled` / `_rescheduled` / `_canceled` | — | `atividade:<activity id>` |
| `card.parado` | card | tempo | `entered_stage_at` (índice `idx_crm_cards_entered_stage`) | `etapa_id`, `dias` | `parado:<card>:<entered_stage_at µs>` |
| `card.data` / `contato.data` | card / contato | tempo | `custom_attributes` (atributo de tipo data) | `campo`, `dias`, `antes`/`depois`, `hora` | `data:<alvo>:<campo>:<data>` |
| `recorrente` | card ou contato | tempo | relógio no fuso da conta | `frequencia`, `dia`, `hora`, `alvo`, filtros | `recorrente:<ocorrência local>:<alvo>` |

**Valores do evento**, que só o filtro do gatilho lê:
- troca de responsável: `evento.responsavel_anterior_id` e `evento.responsavel_novo_id`;
- troca de time: `evento.time_anterior_id` e `evento.time_novo_id`;
- saiu da etapa: `evento.etapa_para_id`;
- mensagem que falhou: `evento.erro`. É o código do canal, nunca o texto, que pode trazer dado do cliente.

## 3. A marca por evento vale para todos

A coluna `evento` e o índice único `(automacao_id, evento)` do #2494 já servem a qualquer gatilho, e não precisam de migration. Cada gatilho diz a sua marca. Assim, o mesmo evento entregue duas vezes (o `EventDispatcherJob` repete) abre uma execução só, mesmo depois de a primeira fechar.

- **Evento do despacho sem id próprio** (conversa, responsável, time): a marca usa o `timestamp` do despacho. O `EventDispatcherJob` guarda e repete o mesmo valor. Isso fecha o 🟡 dos gatilhos de conversa registrado na #2459.
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
  - O Spam vale para a conversa e para a conversa principal do card.
- **O alvo é genérico** (regra da Automação entre frentes):
  - a execução guarda `alvo_type` `Conversation`, `Crm::Card` ou `Contact`, e o `alvo_id` do banco;
  - o histórico e o ensaio da F2 (#2498) leem esse alvo pelo mesmo contexto. Card aparece como "Card #<id> · <título> · <funil> › <etapa>", com o link do card; contato aparece pelo nome. O nome vem do registro, nunca é gravado;
  - combino o contrato com a F2 antes do código. O contexto expõe `rotulo`, `link` e `visivel_para?(usuario)`.
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
- **Laço:** a mensagem que falhou foi mandada por uma automação? Sim quando `content_attributes.automacao_id` está preenchido.
  - Nesse caso, a partida entra na cadeia com `automacao:<id>` como origem.
  - Se a mesma automação tentar de novo e falhar de novo, cai em `:auto_disparo`, em vez de girar.

## 6. A varredura de tempo (`TempoJob`)

- **Ritmo:** a cada 15 minutos, no `config/schedule.yml`. A hora do gatilho é cheia (8h, 9h…). Só passam as contas com motor e `automacao_gatilhos` e com alguma automação de tempo ligada.
- **Por automação**, acha os alvos da **janela**, enfileira um job por lote e, para cada alvo, chama a Partida com a marca. A janela é de 1 dia para trás:
  - **parado:** `entered_stage_at` entre `agora − dias − janela` e `agora − dias`, na etapa escolhida, com o card aberto.
  - **data:** o dia de hoje no fuso da conta é `data ± dias`, e já passou da `hora`. O atributo de data é lido do `custom_attributes`; com o filtro por conta e card aberto, não precisa de índice.
  - **recorrente:** a última ocorrência (`frequencia`, `dia`, `hora`, no fuso da conta) que é ≤ agora e cabe na janela. A ocorrência entra na marca. Ela age em cada card ou contato que passa nos filtros, uma vez cada (F8.6).
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
- **Quem monta ou muda**, no mesmo padrão do #2449 (`AutomationExternalActionGuard`): criar, mudar ou copiar uma automação que tem ou vai ter o passo `webhook` pede `integration_manage`, além de `automation_manage`. Ligar, desligar ou tirar o webhook também conta como mexer na integração. O administrador sempre pode.
  - `integration_manage` não se delega por função personalizada para isso: é a chave que já existe, não uma nova.
  - Na rodada, o Executor reconfere `integration_manage` de `ligada_por`. Sem ela, pausa (`sem_permissao_integracao`).
- **Quem só vê a automação não vê a URL** (#2450): para quem não é admin nem tem `integration_manage`, a resposta da API e a tela trazem a URL mascarada (só o host). Salvar sem mexer na URL mascarada mantém a gravada.
- **SSRF:**
  - ao salvar, a URL tem de ser `https` (ou `http`), com host público. O host é resolvido pelo mesmo resolver do `ssrf_filter`, e endereço privado é recusado (`endereco_proibido`);
  - ao chamar, vai pelo `SafeFetch` (`lib/safe_fetch.rb`), o mesmo do `Webhooks::Trigger`. Ele revalida o endereço a cada redirecionamento, o que cobre o DNS que muda depois do salvar;
  - timeout curto (o do `SafeFetch`) e corpo da resposta lido até um limite pequeno.
- **Segredo e URL:** a URL completa, a query e qualquer segredo nunca vão para log, registro ou histórico. O histórico guarda o host, o código HTTP e o tempo. O log de erro segue a regra da escuta: a classe e a linha, nunca a mensagem.
  - Assinatura do corpo (como o `Webhooks::Trigger` faz com o `secret` do webhook da conta): ver a pergunta P11. Guardar segredo na receita não serve, porque a receita é versionada e lida por quem só vê.
- **Falha de entrega aparece no histórico:**
  - 4xx: `falhou`, sem repetir;
  - 5xx ou timeout: tenta 3 vezes (ADR 2.4.6) e depois `falhou`;
  - endereço proibido na hora de chamar: `falhou` com `endereco_proibido`.
  - Em todos os casos a automação segue para o próximo passo? Ver a pergunta P10.
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

- **P1.** Card criado, card arquivado e campo do card mudou estão no termo da F6, mas não na lista da Automação. Entram? Recomendo **criado sim** (já sai como atividade `create`) e os outros dois depois.
- **P2.** Etiqueta posta ou tirada (F8.7) e troca do responsável do card estão no termo, mas não na lista. Entram? Recomendo **sim** para os dois. O da conversa já tem evento. O do card sai da atividade `update` com `owner_id`, que precisa de um tipo próprio no `EVENT_MAP`.
- **P3. Decidido (Automação):** retorno pela ação do catálogo `POST crm/follow_ups`.
- **P4.** Liberar `POST crm/cards/:id/close` (ganhar ou perder) como passo? Recomendo sim, com o motivo da perda obrigatório quando for perder.
- **P5. Decidido (Automação):** Issue #2501 para o Multifunnel (upsert pelo Mover). Até lá, a tela avisa.
- **P6.** "Parar para este cartão" (F6.3) para só o que está rodando, ou barra também o que começar depois? Recomendo **só o que está rodando**: sem migration, e a pessoa religa a qualquer hora. Barrar o futuro pede uma tabela de exclusão.
- **P7. Decidido (Automação):** o dono do formato das receitas é a F2, no #2498. As receitas por pacote usam o formato dela.
- **P8.** O exemplo da F8 "cada corretor recebe a lista dos seus cards parados" é **um aviso com a lista de vários cards**. O recorrente age em cada alvo, um por vez (F8.6). A lista agregada pede um passo novo. Fica para depois?
- **P9.** A F6.7 depende da #2428 (IA do funil respeita o card movido por automação), ainda aberta. Ela entra antes do PR do card?
- **P10.** Webhook: depois da falha, a automação segue para o próximo passo ou para ali? Recomendo **seguir**, com a falha no histórico, porque o resto da automação (avisar, mover) não depende do outro sistema. Usar a resposta do outro sistema (F8.5) fica para um PR depois deste?
- **P11.** Webhook: o corpo vai assinado? O `Webhooks::Trigger` assina com o `secret` do webhook da conta. Para o passo, o segredo não pode morar na receita (versionada e lida por quem só vê). Recomendo **sem assinatura no primeiro PR**: a URL do n8n ou da planilha já leva o token, e a URL fica protegida pelo #2450 e pela regra de nunca logar. A assinatura entra depois, com segredo guardado fora da receita, se um caso pedir.

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
- **Visibilidade:** o histórico e o ensaio não mostram a execução de card ou conversa fora do funil ou da caixa de quem olha.
