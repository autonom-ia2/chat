# #3101 · F5 do épico #3095 — Reenvio a quem não respondeu, intervalo mínimo e melhor horário

Onda 1: desenho e telas reais, sem backend. Nada aqui foi commitado; a captura dos prints é a próxima etapa.

## 1. Mapa do código que a fase toca (lido antes de desenhar)

| O quê | Onde | Como a F5 usa |
|---|---|---|
| Passo 3 da campanha ("Revisar e agendar", com "Quando começa") | `app/javascript/dashboard/components-next/CampaignJourney/StepReview.vue` | Recebe as duas peças novas: o melhor horário dentro de "Quando começa" e a linha "Mandar de novo" logo abaixo. |
| Linha fechada com "Alterar" na revisão (F2) | `components-next/CampaignJourney/MedirVendas.vue` | Modelo visual e de comportamento da linha "Mandar de novo" (entra fechada, resumo + Alterar). |
| Rascunho da campanha | `components-next/CampaignJourney/campaignDraft.js` | Ganha `melhorHorario` e `reenvio`. |
| Página da campanha | `routes/dashboard/campaigns/journey/NewCampaignPage.vue` | **Não tocada na onda 1.** No PR, passa ao StepReview `reenvio` e `melhorHorario` e manda os dois no pedido de criação. Os modelos do reenvio saem da mesma ponte do passo 2 (ver §3.1). |
| Fuso e "agora / data e hora" | `components-next/CampaignJourney/scheduleTime.js`, `dashboard/helper/fusoDaConta` | Sem mudança; o melhor horário só usa `draft.when`. |
| Tela "Limite de mensagens" (o Porteiro, #3063/#3072) | `routes/dashboard/campaigns/journey/RitmoDeEnvioPage.vue`, `components-next/CampaignJourney/ritmo/ritmoDeEnvio.js`, `api/ritmoDeEnvio.js` | Ganha "Intervalo entre mensagens". |
| Porteiro no servidor | `app/services/autonomia/ritmo_de_envio/{config,porteiro,varredura}.rb`, `app/models/autonomia/envio_ao_cliente.rb` (tabela `envios_ao_cliente`), `app/controllers/api/v1/accounts/ritmo_de_envio_controller.rb` | `Config` ganha `intervalo`; `Porteiro.quando` passa a respeitar a última mensagem + X horas. |
| Adiar destinatário de campanha | `app/services/campaign_journey/recipient_tracking.rb` (`adiado_ate`), `app/jobs/campaign_journey/retomar_adiados_job.rb`, `config/schedule.yml` (`autonomia_ritmo_de_envio_varredura_job`) | O melhor horário reaproveita: o destinatário fica `queued` com `adiado_ate` = a hora dele, e a varredura que já existe manda. |
| Destinatários e leitura | `campaign_recipients` (WhatsApp Oficial e SMS: `sent_at`, `delivered_at`, `read_at`), `whatsapp_api_campaign_recipients` (sem `read_at`), `email_campaign_recipients` | "Não leu" só no WhatsApp Oficial (`read_at`). |
| "Respondeu" | `app/services/campaign_journey/reply_marker.rb` (mensagem do contato na mesma caixa até 72 h depois) | Mesma regra para saber quem não respondeu antes do reenvio. |
| Automação: passo que manda ao cliente | `app/services/autonomia/automacao/ritmo_no_executor.rb` (`aguardar`, `MOTIVO`), `routes/dashboard/automacoes/livre/components/LivreAlterar.vue` (painel por `campo.peca`) | Passo "Mandar mensagem"/"Mandar e-mail" ganha a peça `quando`. |
| Escolha sem `<select>` | `components-next/choice-select/ChoiceSelect.vue` | Usado no intervalo e no modelo da segunda mensagem. |
| Interruptor 44 px | `components-next/toggle-switch/ToggleSwitch.vue` | Usado no melhor horário e no reenvio. |

O passo da mensagem (`StepMessage.vue` e vizinhos) é da F3 (teste com duas versões) e não foi tocado.

## 2. A jornada como a pessoa leiga vive

Personagem: dona de uma loja de roupa que manda campanhas pelo WhatsApp.

### 2.1 Campanha com reenvio e melhor horário (passo 3, "Revisar e enviar")

1. Ela chega ao passo 3 como hoje: público, canal e mensagem já escolhidos.
2. Em **Quando começa**, escolhe **Agora** (ou data e hora). Logo abaixo aparece um cartão novo: **No melhor horário de cada cliente**, desligado, com uma linha: "Cada pessoa recebe na hora em que costuma responder, nas 24 horas depois do início."
3. Ela liga. O cartão mostra duas caixas grandes: **312 pessoas** "recebem no melhor horário" (já responderam antes) e **138 pessoas** "recebem no início" (nunca responderam). Embaixo: "Sempre dentro do horário permitido da conta: de segunda a sexta, das 8h às 20h."
4. Abaixo de "Quando começa", a linha **Mandar de novo** diz "Não mandar de novo — Quem não responder recebe só esta mensagem." Ela toca em **Alterar**.
5. Liga **Mandar uma segunda mensagem**. Já vem pronto o mais comum: **Quem não respondeu**, **3 dias depois**. No SMS e no WhatsApp API o texto da segunda mensagem já vem escrito (um lembrete curto, que ela pode mudar); no e-mail, o assunto novo já vem escrito.
6. No WhatsApp Oficial, em **Segunda mensagem**, escolhe outro modelo aprovado pelo nome que ela deu ao modelo (o mesmo do passo 2, nunca o nome técnico). Logo abaixo aparece **De onde vem cada parte da mensagem**, já preenchido: o que a primeira mensagem usava (o nome do cliente, a coluna do desconto) vem igual, e o que é do catálogo vem ligado sozinho. Só o que sobrar ela escolhe; enquanto sobra, a lateral diz "Falta dizer de onde vem cada parte da segunda mensagem." Vê o balão **Como o cliente vê**. No e-mail, o bloco se chama **Segundo e-mail**.
7. Se a caixa não tem outro modelo aprovado, o interruptor fica apagado e diz: "Esta caixa não tem outro modelo aprovado, então não dá para mandar de novo. Crie um em Modelos do WhatsApp e volte aqui." A campanha sai normal, sem reenvio (mesmo padrão do melhor horário quando ninguém respondeu).
8. Enquanto falta a segunda mensagem, o botão **Enviar agora** fica apagado e a lateral diz o que falta. O campo do modelo só fica vermelho depois que ela passa por ele. **Pronto** fecha o bloco e volta ao resumo ("Manda de novo 3 dias depois, para quem não respondeu" e o começo da segunda mensagem).
9. Na lateral escura ("Vão receber 450"), aparecem duas linhas pequenas: "Cada um no seu melhor horário, em até 24 horas" e "Manda de novo 3 dias depois".
10. Ela toca em **Enviar agora**. A confirmação diz: "O envio começa agora. Quem já respondeu antes recebe no seu melhor horário, em até 24 horas. Os outros recebem agora. 3 dias depois, quem não respondeu recebe a segunda mensagem." A frase do reenvio aparece sempre que ele está ligado, com ou sem o melhor horário.

Uma ação principal por tela continua sendo **Enviar agora**; as duas opções são linhas da revisão, como "Quem comprou depois" (F2).

### 2.2 Intervalo mínimo (Campanhas > Limite de mensagens)

1. Ela abre **Limite de mensagens**. Entre **Limite por cliente** e **Horário de envio** há um cartão novo: **Intervalo entre mensagens**, "Quanto tempo, no mínimo, entre duas mensagens para a mesma pessoa."
2. Escolhe **Pelo menos 4 horas**. Embaixo: "Se alguém recebeu uma mensagem agora, a próxima espera pelo menos 4 horas."
3. O resumo azul passa a dizer: "No máximo 3 mensagens por cliente a cada 7 dias. Pelo menos 4 horas entre duas mensagens. As mensagens saem de segunda a sexta, das 8h às 20h."
4. **Salvar**. Quem só vê campanhas vê o resumo com o intervalo, sem os campos.

### 2.3 Automação (passo "Mandar mensagem")

1. No editor da automação, ao abrir o passo **Mandar mensagem**, abaixo do texto há **Quando mandar** com dois cartões: **Assim que chegar aqui** (o de hoje) e **No melhor horário do cliente** ("Espera a hora em que ele costuma responder, no máximo 24 horas. Quem nunca respondeu recebe na hora.").
2. Escolhido o melhor horário, aparece: "Sempre dentro do horário permitido da conta: … Se o cliente acabou de escrever, a resposta sai na hora."
3. No histórico da execução, o passo mostra "Esperando o melhor horário do cliente: amanhã às 14h" (linha nova do histórico, no PR).

## 3. Telas (componentes reais, com dados vindos de fora)

| Peça | Arquivo | Props / eventos |
|---|---|---|
| Melhor horário na campanha | `components-next/CampaignJourney/melhorHorario/MelhorHorarioDaCampanha.vue` + `melhorHorario.js` | `v-model` (Boolean), `conhecidos` (Number ou null = contando), `total`, `horarioPermitido` (texto; vazio = qualquer hora), `quando` ('now'/'later'). Estados: desligado, contando, parte, todos, ninguém (interruptor apagado). |
| Mandar de novo | `components-next/CampaignJourney/reenvio/ReenvioDaCampanha.vue` + `reenvio.js` | `v-model` (null ou `{ quem, dias, modeloId, ligacoes, texto, assunto }`), `canal`, `modelos` (`[{ value, label, disabled, corpo, variaveis, ligacoes }]`), `colunas`, `gruposDeCampos`, `maximoDoTexto`. Estados: fechado desligado, fechado ligado (com o que falta em vermelho), aberto por canal (modelo com as ligações, texto, assunto), sem outro modelo na caixa (interruptor apagado com o motivo). |
| Revisão | `components-next/CampaignJourney/StepReview.vue` | Props novas opcionais `reenvio` (`{ canal, modelos, colunas, gruposDeCampos, maximoDoTexto }`) e `melhorHorario` (`{ conhecidos, horarioPermitido }`). Sem elas (o caso de hoje), nada muda na tela. Bloqueia o envio enquanto falta a segunda mensagem ou uma ligação dela; a confirmação fala do reenvio. |
| Intervalo | `components-next/CampaignJourney/ritmo/RitmoIntervalo.vue` + `ritmoDeEnvio.js` (`INTERVALOS`, `SEM_INTERVALO`, `intervalo` em `formularioDe`/`pedidoDe`) | `v-model` (horas; 0 = sem intervalo). Montado em `RitmoDeEnvioPage.vue`, que também põe o intervalo no resumo azul. |
| Automação | `routes/dashboard/automacoes/livre/components/LivreMelhorHorario.vue` | `v-model` ('na_hora'/'melhor_horario'), `rotulo`, `horarioPermitido`. Ainda não ligado ao `LivreAlterar.vue` (o campo depende do esquema do servidor; ver §4.4). |

### 3.1 Como a página monta os modelos do reenvio (no PR)

A página já tem a ponte dos Modelos do WhatsApp (`useModelosNaCampanha`). Para cada modelo de `ponte.opcoesDeModelo(caixa)`, **menos o modelo da primeira mensagem**:

- `value`, `label` e `disabled`: os mesmos do passo 2 (nome amigável; o que não vai aparece apagado com o motivo).
- `variaveis`: `ponte.rotular(templateVariables(template), id)`, como o passo 2.
- `ligacoes`: `ponte.ligacoesIniciais(id)` (o catálogo), mais as ligações da primeira mensagem (`draft.bindings`) para a variável de mesmo nome. Ao escolher o modelo, o reenvio guarda essas ligações em `reenvio.ligacoes`; a pessoa só escolhe o que sobrou, no mesmo `TemplateVariableBindings` do passo 2.
- `corpo`: o corpo do modelo preenchido com a primeira pessoa do público usando `reenvio.ligacoes` (a mesma conta do "Como o cliente vê" do passo 2), recalculado quando ela muda uma ligação.
- `colunas` e `gruposDeCampos`: as colunas do público e `ponte.gruposDeCampos`, as mesmas do passo 2.

Sem nenhum modelo que vá, o interruptor do reenvio fica apagado e a campanha sai sem ele. O servidor recebe `reenvio_mensagem = { modelo_id, ligacoes }` (§4.3) e monta os parâmetros do modelo com o mesmo `buildTemplateParams` da primeira mensagem.

Textos: catálogo novo do fork `reenvioHorario.json` (en + pt_BR, `REENVIO_HORARIO.*`), registrado nos índices, em `config/fork_i18n.json` e no ignore do `crowdin.yml`; o intervalo em `campaignJourney.json` (`CAMPAIGN_JOURNEY.RITMO.INTERVALO` e `RESUMO.INTERVALO`). `pnpm i18n:fork:check` passa.

Prints: harness em `tmp-prints/` (porta 6193); cenas em `cenas3101.json` (19 telas × 1440 e 390). Os estados iniciais do reenvio (06, 10, 11) saem do toque no interruptor, não de um rascunho montado no roteiro.

## 4. O que o backend vai precisar

### 4.1 Intervalo mínimo (sem migration)

- `Autonomia::RitmoDeEnvio::Config`: chave `intervalo` em `accounts.settings['ritmo_de_envio']` = `{ 'horas' => 4 }` ou nil; faixa `INTERVALOS = [1, 2, 4, 8, 12, 24, 48]` (mesma do front). `normalizar` valida.
- `Porteiro#quando`: `livre = [vaga_do_limite, vaga_do_intervalo].max`, com `vaga_do_intervalo = último enviado_em do contato + horas + FOLGA` (uma consulta a `envios_ao_cliente`, já indexada por conta, contato e data). Destinatário sem ficha continua fora do limite e do intervalo.
- `RitmoDeEnvioController`: `permit` ganha `intervalo: [:horas]`; o GET devolve `intervalo`. Regerar os formatos do Guia (`bundle exec rails autonomia:guia:formatos`) porque o strong params muda.
- `Varredura`: o período de retenção das linhas de `envios_ao_cliente` passa a considerar o maior entre 30 dias e 48 h (já coberto pelos 30 dias).

### 4.2 Melhor horário (1 migration)

- **Tabela `horarios_de_resposta`**: `account_id`, `contact_id` (único por conta), `por_hora` (integer[24], contagem de mensagens do cliente por hora no fuso dele), `respostas` (integer), `hora` (smallint, nula enquanto não há o mínimo), `calculado_em`. Índice único `(account_id, contact_id)`. FK para contato com `on_delete: :cascade`.
- **Job `Autonomia::MelhorHorario::AprenderJob`** (cron diário, de madrugada, `config/schedule.yml`): pega os contatos com mensagem recebida nas últimas 24 h e recalcula os últimos 180 dias deles em lote; fuso pelo `Crm::Timezone::Resolver` (o mesmo do Porteiro). A hora escolhida é a de mais mensagens, somando a hora vizinha de cada lado (alisa o ruído). Sem o mínimo (decisão D4), `hora` fica nula.
- **Serviço `Autonomia::MelhorHorario.proximo(account:, contact:, a_partir_de:, janela: 24.hours)`**: a próxima vez em que a hora do contato acontece dentro da janela, num minuto fixo por contato (espalha a carga). Se a hora cai fora do horário permitido da conta, usa a hora permitida com mais mensagens. Sem hora, nil.
- **Campanha**: tabela própria do fork **`campanha_opcoes_de_envio`** (construção aditiva: não altera `campaigns`): `account_id`, `campanha_type`/`campanha_id` (polimórfica: `Campaign`, `WhatsappApiCampaign`, `EmailCampaign`; única), `melhor_horario` (boolean, padrão false) e as colunas do reenvio (4.3). A mesma migration cria as duas tabelas.
- **Envio**: nos quatro motores, ao registrar o destinatário, se `melhor_horario` e `proximo` devolve hora, grava `adiado_ate` (WhatsApp Oficial, SMS, WhatsApp API já têm a coluna; o e-mail usa o mecanismo de `email_campaigns/ritmo_do_destinatario.rb`). A varredura que já existe manda na hora, e o Porteiro continua decidindo na saída. A campanha fica "enviando" até a última hora (no máximo 24 h).
- **Contagem para a tela**: `POST campaign_journey/recipient_previews` passa a devolver `melhor_horario: { conhecidos: N }` (contatos do público com `hora` não nula). A página monta `horarioPermitido` com o GET de `ritmo_de_envio` (o mesmo texto do resumo da tela do limite).
- **Criação**: os endpoints que criam/agendam campanha da jornada aceitam `melhor_horario: true|false`.
- **Automação**: o passo `mensagem` e `email` da receita ganha o campo `quando` (`na_hora` | `melhor_horario`) no esquema (`catalogo_do_esquema.rb`) e a peça `quando` no catálogo do front; no executor, antes de mandar e fora da resposta a quem está esperando, `aguardar(passo, ate)` com motivo novo `adiado_pelo_melhor_horario` (mesmo caminho do `RitmoNoExecutor`); o histórico ganha a linha "Esperando o melhor horário do cliente: …".

### 4.3 Reenvio (na mesma migration de `campanha_opcoes_de_envio`)

- Colunas: `reenvio_quem` (`nao_respondeu` | `nao_leu`, nula = sem reenvio), `reenvio_dias` (1, 2, 3, 5, 7), `reenvio_mensagem` (jsonb: `modelo_id` + ligações das variáveis, ou `texto`, ou `assunto`), `reenvio_status` (`aguardando` | `enviado` | `sem_ninguem` | `cancelado`), `reenvio_em` (datetime: fim do envio da primeira + dias), `reenvio_campanha_type`/`reenvio_campanha_id` (a campanha que nasceu). Índice `(reenvio_status, reenvio_em)`.
- **Job `CampaignJourney::ReenvioVarreduraJob`** (cron a cada 15 min): pega os vencidos e, para cada um, monta quem recebe = destinatários que receberam (status enviado/entregue/lido), menos quem respondeu (mesma regra do `ReplyMarker`), menos quem leu (se `nao_leu`), menos quem saiu da lista ou foi bloqueado; o grupo de controle da F2 nunca recebeu e fica fora. Se ninguém sobra, `sem_ninguem`.
- **Como a segunda mensagem sai**: decisão D1. Recomendado: uma campanha nova do mesmo canal, criada sozinha, com um público derivado só com essas pessoas, nome "<campanha> · segunda mensagem", herdando caixa, remetente e o melhor horário. Passa pelo Porteiro como qualquer campanha.
- **Cancelar**: editar/cancelar a campanha antes do reenvio cancela o reenvio (`cancelado`).
- **Resultado** (PR seguinte ou mesmo PR, decidir pelo tamanho): a página de resultado da primeira campanha mostra "Segunda mensagem: N receberam, M responderam" com link para a campanha nova.

### 4.4 Permissões e flag

- Nenhuma chave nova: criar e mudar continua com `campaign_manage`; ver o limite, com `campaign_view`; automação, com o que já vale para editar automação. Sem parecer da Funções.
- Sem flag nova: as três opções nascem desligadas em cada campanha/automação e o intervalo nasce "sem intervalo mínimo". Quem não mexe não vê diferença de comportamento.

## 5. PRs

Um PR para a fase (regra do épico), em três commits na ordem: (1) intervalo mínimo; (2) melhor horário (migration das duas tabelas, job, serviço, motores, automação); (3) reenvio (varredura, campanha derivada, tela ligada na página). Se passar de ~1.500 linhas úteis, o intervalo (pequeno, sem migration) sai num PR à frente. A migration cria tabelas novas sem tocar em tabela do Chatwoot; não enfileira job (lição do blue/green: o aprendizado e o reenvio rodam por cron).

## 6. O que o Guia e a Central vão explicar

- `lib/operator_guide/porques.md`:
  - `limite_de_mensagens_por_cliente`: passo novo do intervalo; gotchas: o intervalo soma ao limite; vale também para o reenvio e para o melhor horário; fora do intervalo a mensagem espera.
  - bloco novo `mandar_de_novo_para_quem_nao_respondeu` (rota `campaigns_journey_new`): onde fica (Revisar > Mandar de novo > Alterar), passos, gotchas (só quem recebeu; quem respondeu em qualquer momento antes não recebe; "não leu" só no WhatsApp Oficial; no WhatsApp Oficial precisa de outro modelo aprovado; no e-mail muda só o assunto; aparece na lista como campanha própria; cancelar a primeira cancela a segunda; passa pelo limite).
  - bloco novo `mandar_no_melhor_horario_de_cada_cliente` (rota `campaigns_journey_new`): como a hora é aprendida (mensagens dos últimos 180 dias, no fuso do cliente), quem não tem hora recebe no início, janela de 24 h, horário permitido manda, a campanha fica enviando até o fim da janela.
  - `montar_automacao_no_editor` (ou bloco próprio): a peça **Quando mandar**, a espera de até 24 h e a resposta a quem escreveu que sai na hora.
  - Rodar `pnpm guia:build` e `pnpm guia:check`; formatos regenerados (4.1).
- Central de ajuda: `lib/central_de_ajuda/13/13.35-…` (intervalo; atualizar as evidências) e artigo novo para reenvio e melhor horário; rodar o `central:check`. O texto "Se passar do limite ou do horário…" (`RITMO.ESPERA`) é citado como evidência no 13.35; trocar para incluir "intervalo" junto com o artigo.

## 7. Decisões em aberto para o Rodrigo

**D1 · Como a segunda mensagem nasce no servidor.**
Contexto: as campanhas da jornada saem por quatro motores com tabelas de destinatários diferentes.
- (a) Campanha nova automática do mesmo canal, com público derivado só de quem não respondeu. Reaproveita motores, Porteiro, lista e resultado; na lista aparece como "<nome> · segunda mensagem". Custo: duas linhas na lista, e o resultado junta as duas por link.
- (b) Segunda rodada dentro da mesma campanha. Resultado único, mas mexe nos quatro motores e nas tabelas de destinatários (inclusive `campaign_recipients`, do Chatwoot).
- Recomendação: (a).

**D2 · "Não leu" em quais canais.**
- (a) Só WhatsApp Oficial, onde a leitura é confirmada (`read_at`). (b) Também e-mail pela abertura: engana, porque o celular abre sozinho para proteger a privacidade. (c) Não oferecer "não leu": mais simples, mas a Issue pede.
- Recomendação: (a). Nos outros canais a opção nem aparece.

**D3 · Reenvio no e-mail.**
- (a) Mesmo conteúdo, assunto novo (tela pronta). (b) E-mail inteiro novo no editor: duplica o fluxo do editor dentro da revisão. (c) Sem reenvio no e-mail por enquanto.
- Recomendação: (a).

**D4 · O que conta para aprender a hora e quanto basta.**
- (a) Qualquer mensagem que o cliente escreveu, mínimo 3 nos últimos 180 dias. (b) Só respostas a mensagens da empresa: mais preciso, menos gente com hora. (c) Mínimo 1: mais gente com hora, mais chute.
- Recomendação: (a).

**D5 · Janela do melhor horário.**
- (a) Até 24 h depois do início. (b) Só no mesmo dia: quem tem a hora já passada recebe no início e a opção vale menos. (c) Até 48 h: mais gente na hora certa, campanha mais lenta e o "Respondeu em 72 h" fica mais curto para os últimos.
- Recomendação: (a).

## 8. Riscos

- **F3 ao mesmo tempo**: esta fase mexe em `StepReview.vue` e `campaignDraft.js`; a F3 pode acrescentar campos no mesmo `emptyDraft`. Conflito pequeno de texto; quem entrar depois traz a main.
- **Reenvio com duas versões (F3)**: a segunda mensagem é uma só, para todos; se a primeira tiver duas versões, o reenvio não divide. Combinar com a F3 se o resultado precisar separar.
- **Custo no WhatsApp Oficial**: a segunda mensagem é outro modelo pago para quem não respondeu. A tela não mostra custo hoje; avaliar uma linha "até N pessoas a mais" quando o servidor souber estimar.
- **Campanha "enviando" por mais tempo**: com melhor horário, até 24 h; com reenvio, a campanha derivada aparece dias depois. O Guia precisa dizer isso.
- **Limite + intervalo + horário juntos** podem empurrar a segunda mensagem para dias depois do previsto; é o comportamento certo (mensagem espera, não some), mas precisa estar no Guia.
- **Spec que depende do fuso da máquina**: `journeyHelpers.spec.js > reads date and time in the account zone and sends UTC` falha com o fuso local (America/Sao_Paulo) e passa com `TZ=UTC` (como na CI). Já era assim; não é desta fase.
