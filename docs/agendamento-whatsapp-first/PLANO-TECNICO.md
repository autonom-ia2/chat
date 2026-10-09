# Plano técnico v2 — Agendamento WhatsApp-first

Épica #1187. PRD: `docs/agendamento-whatsapp-first/PRD.html` (fonte em `src/`, gerar com `node build.mjs`).
Contrato das PRs: escopo, arquivos, API, migrations e testes. Escrito a partir do código em `origin/main` (09/10/2026) e **revisado por um revisor independente, que apontou 22 problemas na v1 deste plano**; todos estão resolvidos abaixo (seção 11 lista cada achado e a decisão).

## 0. Princípios

1. **Aditivo.** Arquivo novo para tudo que é do fork. Em arquivo do upstream, só registro. Cada toque em arquivo do upstream é listado na PR com o motivo.
2. **Google/Microsoft não regride (RA-01).** Fluxo atual intacto com a flag desligada e para quem escolhe Meet/Teams como local.
3. **Flag por conta.** `crm_booking_v2` em `config/features.yml` (`feature_flags_ext_1`, próximo bit livre, `enabled: false`). `Crm::Config.booking_v2_enabled?(account)` = `calendar_meetings_enabled?` (ENV de instalação já existente; **dependência intencional**: se o calendário for desligado por incidente, o v2 também cai) **e** a flag da conta. Piloto por conta no Super Admin; liga e desliga na hora (é banco, sem restart). Desligada: rotas v2 respondem 404, página antiga é servida, tela nova some.
4. **Página e API v2 em arquivos próprios** (`Public::Api::V2::*`, entrada Vite `public_booking_v2`). v1 não muda, exceto a trava de agente (seção 2.1).
5. **Sem regex para interpretar texto de pessoa.** Telefone: `TelephoneNumber`. Substituição do convite: `String#gsub` com **string** literal. Rack::Attack v2 e ICS: `start_with?`, `end_with?`, `split`, `gsub` com string. A IA (F3) decide intenção com o modelo. Classificar `User-Agent` de crawler por `include?` em lista fechada é classificação de máquina, não de linguagem.
6. **Sem `<select>` nativo** (`ChoiceSelect`). Tailwind apenas. Cor da marca na página pública por variável CSS definida com `document.documentElement.style.setProperty` (sem atributo `style` no template) e usada como `bg-[var(--brand)]`.
7. **Migrations só aditivas**, versão única (conferida contra PRs abertas do **fork** no momento de abrir cada PR), sem coluna nova em tabela do Chatwoot. Só criar o que a PR usa (nada especulativo). FK nova em tabela quente: `validate: false` + `validate_foreign_key` em migration separada, e **índice na coluna da FK** antes de qualquer `on_delete`. `schema.rb` gerado pelo Rails.
8. **Um push por PR**, depois de rodar tudo que a CI barra (seção 9).

## 1. Ordem das PRs (corrigida)

A página pública precisa de perfil sem caixa, marca e convite, então a base vem primeiro:

1. **F1-A #1188** base: domínio sem inbox, policies, módulo de função, **API de páginas** (criar a partir de modelo, publicar, pausar, pessoas que atendem, prévia, marca), rótulos de reunião interna no calendário. Tudo backend + o mínimo de front (matriz de funções e rótulos).
2. **F1-D #1191** tela Configurações › Agendamento (consome a API de páginas), Guia, Central.
3. **F1-C #1190** link por cliente: convites, botão "Agendar", endpoints públicos de convite.
4. **F1-B #1189** página pública v2 (consome tudo acima).
5. F2-A #1192, F2-B #1193, F2-C #1194, F2-D #1195, F3 #1196.

Cada branch parte da anterior, cada PR tem como base a branch anterior (diff pequeno) e sobe em **ondas pela main**: F1-A com base `main`; ao mergear, a seguinte é retargetada para `main` (acordado com a Orquestração).

## 2. Backend

### 2.1 F1-A — domínio sem caixa e sem Google/MS
**Migrations (só o que a F1-A usa):**
- `crm_meeting_guests`: `email` aceita NULL; `phone_number string`; índice único parcial `(account_id, meeting_id, phone_number) WHERE phone_number IS NOT NULL`. Validação: e-mail **ou** telefone; unicidade de e-mail com `allow_nil`.
- `crm_meetings`: `source string`. Enum `provider` ganha `internal: 2`; `online_meeting_type` ganha `whatsapp_video: 3`, `whatsapp_voice: 4`, `custom_link: 5`, `in_person: 6`. `inbox_id` já aceita NULL no banco.
- `crm_agent_booking_profiles`: `page_version integer default 1 not null` (1 legado, 2 nova), `locations jsonb default []`, `min_notice_minutes integer default 0`, `slot_durations jsonb default []`, `contact_phone string`, `template_key string`, `brand jsonb default {}`. Logo e foto: ActiveStorage (`has_one_attached`).
- `crm_agent_booking_links`: nada (colunas já nuláveis).

**Modelos:**
- `Crm::Meeting`: `belongs_to :inbox, optional: true`; validações de calendário (`inbox_must_have_calendar_enabled`, e-mail alcançável) só para `google`/`microsoft`; `internal` exige convidado alcançável por e-mail **ou** telefone; `email_channel` seguro com inbox nulo. `link` do local só `http`/`https`, até 500 caracteres.
- `Crm::MeetingGuest`: como acima.
- `Crm::AgentBookingProfile`/`Link`: inbox opcional; validação de calendário e de membro da caixa só **quando há inbox**; `locations[].url` só `http`/`https`; logo/foto: PNG/JPEG/WebP até 2 MB (SVG recusado).

**Serviços novos (`app/services/crm/booking_v2/`)**, para não mexer nos v1:
- `HostEligibility`: o responsável é elegível se for `AccountUser` da conta e (sem função personalizada ou com `crm_view`). Página/link com responsável inelegível se comporta como pausado e aparece no relatório de atenção.
- `Slots`: calcula horários sem depender de inbox: horário de trabalho do perfil, `min_notice_minutes`, `buffer_minutes`, janela, **duração validada** contra `[duration_minutes] + slot_durations`. Ocupação = freebusy do provedor **se** o perfil tiver caixa de calendário **+** reuniões `scheduled` do responsável (`created_by_id`, de qualquer caixa, inclusive `internal`). `strict:` para reservar (falha fechada). `next_slot` faz **uma** consulta de freebusy para até 14 dias (cache de 5 min) e varre localmente.
- `Booker`: reserva sob **lock de agente** (`pg_advisory_xact_lock(2, host_id)`) e, se o perfil tem caixa, também o lock de caixa (`1, inbox_id`), sempre nessa ordem. Reconfere o slot, resolve telefone, contato, card, cria a reunião pelo `InternalCreator`. Idempotente: mesmo telefone + mesmo `starts_at` + mesmo perfil nos últimos 5 minutos devolve a reunião existente.
- `PhoneLookup`: E.164 via `TelephoneNumber` (país padrão pelo fuso do perfil, BR); candidatos do nono dígito com `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer` (conferir assinatura real na implementação). Contato achado **não** tem o nome sobrescrito.
- `Crm::Meetings::InternalCreator`: Sanitizer, convidados, lembrete do agente (`Crm::FollowUp meeting`), atividade `meeting_scheduled`, invalidação de disponibilidade, `source`, consentimento em `metadata['consent']` (`accepted_at`, `text_key`). Sem provedor. `Crm::Meetings::Creator#perform` desvia para ele quando o local não é Meet/Teams (uma linha).
- `Crm::Meetings::IcsBuilder`: Ruby puro, **sem ORGANIZER/ATTENDEE com e-mail** (evento importável sem METHOD), `UID`, `SEQUENCE`, `DTSTAMP`, `DTSTART/DTEND` UTC, `SUMMARY`, `DESCRIPTION`, `LOCATION`/`URL`, escape e dobra de linha em 75 octetos, `gsub` com string.
- `Crm::BookingV2::Pauser` / `OrphanReport`: ao **remover um `AccountUser`** (módulo prepended por initializer, `after_destroy_commit`), reuniões futuras `scheduled` dele são reatribuídas ao responsável padrão da página ou ao primeiro administrador (evita reunião impossível de cancelar por `validate_created_by_account`), links individuais pausam, e gera atividade para o admin. Mudança de função não pausa: a elegibilidade é avaliada ao servir (`HostEligibility`).
- **Trava de agente no v1** (único toque em v1): `PublicBookingService#acquire_booking_lock!` passa a tomar também o lock de agente quando há `host_agent` (ordem: caixa, depois agente) e `PublicAvailableSlots#local_meeting_intervals` soma reuniões `internal` do mesmo agente. Spec de concorrência v1 × v2.
- Não é preciso mexer em `skip_provider_call?` (já pula com `external_event_id` vazio) nem em `SyncService`/`RsvpSyncService` (já são no-op por provider); um spec confirma.
- Contact merge: `ContactMergeAction` ganha o que existir nesta PR (nada). As tabelas novas registram o merge nas PRs que as criam.

**Permissões:**
- `CustomRole::PERMISSIONS` + comentário: `agendamento_view`, `agendamento_manage`.
- **Policy nova** `Crm::BookingPagePolicy` (escrita: administrador ou `agendamento_manage`; leitura: `agendamento_view`). **`AgentBookingProfilePolicy` e o controller antigo continuam `administrator?`** e passam a filtrar `page_version: 1` (a gaveta antiga não vê páginas novas).
- `Api::V1::Accounts::Crm::BookingPagesController` (flag + `check_module_permission!('agendamento')` + policy): `GET` (lista com contagem de reuniões futuras e aviso de responsável inelegível), `GET :id`, `POST` (de `template_key`: `sales_30`, `consult_45`, `visit_60`, `blank`), `PATCH :id`, `POST :id/publish`, `POST :id/pause`, `DELETE :id` (só sem reuniões futuras), `POST :id/preview_token` (token assinado de 1 h, `purpose` próprio), `POST :id/logo`, `POST :id/photo`, `GET :id/people` (nomes e ids de quem pode atender, **sem e-mail**), `PUT :id/people` (define quem atende: 1 pessoa = modo `fixed`; várias = `per_agent` com um `Crm::AgentBookingLink` por pessoa, **sem exigir caixa**). **Não** altera canal de e-mail nem lista membros de caixa (J8-A5). Opções de caixa de avisos (F2-A) vêm de `policy_scope(::Inbox)`.
- FE mínimo na F1-A: `permissionMatrix.js` + `customRole.json` (en e pt_BR) + specs; `CrmMeetingDetail.vue` e `CrmCalendarMonthGrid.vue` mostram reunião interna com o rótulo do local (nunca "Google Meet"); serializer do `MeetingsController` expõe `location_type` (a gaveta manual de agendar continua só Google/MS).
- Factories novas (`crm_meetings`, `crm_meeting_guests`, `crm_agent_booking_profiles`, `crm_agent_booking_links`); specs de modelos, serviços, controller (matriz de permissão: administrador, só vê, gerencia, agente sem função, função sem o módulo × cada rota), concorrência, IcsBuilder, remoção de usuário, flag.

### 2.2 F1-C — link por cliente (convites)
**Migration:** `crm_booking_invites` — `account_id`, `booking_profile_id`, `booking_link_id` (null), `contact_id`, `card_id` (null), `conversation_id` (null), `created_by_id` (null), `meeting_id` (null), `code` (8 caracteres, alfabeto sem ambiguidade, único), `channel` (`conversation`, `copy`, `ai`, `public`), `expires_at`, `sent_at`, `first_opened_at`, `last_opened_at`, `open_count`, `scheduled_at`, `canceled_at`, `metadata`. FKs: `contact` cascade; `card`, `conversation`, `meeting`, `created_by` nullify; **índice em toda FK**. Perfil: `invite_text text`, `invite_ttl_days integer default 7`. `ContactMergeAction` passa a mover convites (e resolve o único de `notice_stops` na F2-A).
- `Crm::BookingInvite` = **capacidade de acesso** a (contato, perfil, reunião opcional). Reserva por convite usa o mesmo código para virar o **link de gestão** (J1-A9/J5-A2): depois de agendado, o mesmo link abre a reunião (remarcar, cancelar, confirmar). Reservas pelo link público também criam uma linha `channel: 'public'`, então só existe um mecanismo de acesso.
- `Api::V1::Accounts::Crm::BookingInvitesController`: `POST` `{ booking_page_id?, card_id?, conversation_id?, contact_id? }` — o contato só é aceito se vier de card/conversa que a pessoa **pode ver**; `contact_id` sozinho exige `ContactPolicy#show?`; `conversation_id` precisa pertencer ao mesmo contato; `POST :id/deliver` exige poder **responder** a conversa (`ConversationPolicy` de update/reply, não `show?`) e envia como o usuário com `LiteralMessageBuilder`; `DELETE :id`; `GET` (por card/conversa/contato; agente só os próprios, admin e `agendamento_view` todos).
- Texto: `profile.invite_text` ou padrão da conta (chave em catálogo do fork), `{nome}` e `{link}` por `gsub` de string.
- FE: `components-next/Booking/BookingInviteButton.vue` autocontido; registro de uma importação e uma tag em `ConversationHeader.vue` e `CrmCardDrawer.vue`. Estado enviado/aberto/agendado no card.
- Público (aqui, não na F1-B): `GET /public/api/v2/invites/:code` (perfil + estado; 404 **uniforme** para inexistente, expirado, cancelado e vencido), `POST /public/api/v2/invites/:code/viewed` (registra "abriu" após o primeiro render; ignora `User-Agent` de crawler por `include?` em lista fechada). Rack::Attack para ambas.

### 2.3 F1-D — configuração (backend já na F1-A; aqui o front)
Tela, passos, marca, prévia, QR (`qrcode` já no projeto), copiar link, "Abrir como cliente" (prévia por token) e, quando houver caixa de avisos, "Testar no meu WhatsApp" (envio em F2-A).

### 2.4 F1-B — página pública v2
Rotas (flag de conta pelo perfil do slug): `GET /public/api/v2/booking/:slug`, `.../slots`, `.../next_slot`, `POST .../:slug`, `POST .../:slug/contact_request`, `GET /public/api/v2/ics/:token`. Páginas: `/book/:slug` (serve v2 quando a flag da conta do perfil está ligada), `/b/:code`.
- `GET :slug` → `{ slug, title, description, agent_name, duration_minutes, durations, timezone, booking_window_days, paused, brand: { color, headline, logo_url, photo_url }, locations: [{ type, label }], contact_whatsapp_url, form_token, captcha_site_key, notices_enabled }`. `notices_enabled` só é verdadeiro quando a F2-A existe e o perfil tem caixa de avisos (o aviso de consentimento só aparece então). Nunca expõe e-mail, ids, URL privada de link.
- `form_token`: assinado pelo servidor (`purpose` próprio, contém slug e hora de emissão); o `POST` o exige e rejeita menos de 2 s e mais de 2 h. Honeypot + captcha (`ChatwootCaptcha`; **sem `HCAPTCHA_SERVER_KEY` não há captcha**, risco declarado na PR) + limite por telefone (2 reuniões abertas; 5 tentativas/h) + limite por IP.
- `POST :slug` `{ name, phone, email?, starts_at, duration?, location_type?, invite_code?, consent, company, form_token, captcha_token? }` → `Booker`. Com `invite_code`: o convite tem de ser do mesmo perfil, é travado com `SELECT ... FOR UPDATE`, e o telefone é o do contato (trocar o número exige confirmar e não reabre o convite). Resposta `{ confirmed, starts_at, location: { type, label, join_url? }, ics_url, manage_url, whatsapp_url }`.
- `POST contact_request` `{ name, phone, consent, company, form_token }` → contato + card (`source: 'contact_request'`) + `Crm::FollowUp` `call` para o responsável + atividade; limite por telefone e por IP.
- ICS: token **no caminho** (não na query), `purpose` próprio, 2 dias.
- Rack::Attack v2 (por IP, strings): create/contact_request/viewed/ics por hora, slots/next_slot por minuto, invites por minuto.
- Tokens: `Rails.application.message_verifier('crm_booking_v2_<purpose>')` distinto por finalidade (form, preview, ics); nunca o verificador do v1.
- FE: `app/javascript/public_booking_v2/` (entrada, `App.vue` pequeno, componentes por tela, `api.js`, i18n en/pt_BR com spec de paridade de chaves). hCaptcha só se `captcha_site_key` vier.

### 2.5 F2-A — avisos, confirmação, remarcar/cancelar
**Migration:** `crm_meetings`: `confirmed_at`, `confirmation_status integer default 0` (`pending`, `confirmed`, `change_requested`), `reminders_stopped_at`, `conversation_id` (índice, FK nullify). `crm_meeting_notices` (`meeting_id` cascade, `kind`, `due_at`, `status`: `pending 0 / sending 1 / sent 2 / skipped 3 / failed 4`, `skip_reason`, `sent_at`, `message_id`, `attempts`, `error_code`; único `(meeting_id, kind)`; índice `(status, due_at)`). `crm_booking_notice_stops` (`contact_id` cascade, único `(account_id, contact_id)`; vira parte do `ContactMergeAction`). Perfil: `notice_inbox_id` (índice, FK nullify), `notice_preset`, `notice_templates`.
- Precedência de parada (qualquer uma bloqueia): `Contact#opted_out?`, `crm_booking_notice_stops`, `meeting.reminders_stopped_at`.
- `Notices::Scheduler` (cria linhas por preset, ajusta em cancelar/remarcar), `NoticeDispatchJob` (`*/1`, `scheduled_jobs`): sai na hora se `calendar_meetings_enabled?` for falso; senão 1 `SELECT` indexado `LIMIT 200`; **claim atômico** (`UPDATE ... SET status=sending WHERE id=? AND status=pending`), kill-switch por flag da conta no envio.
- `Notices::Sender` com regra própria: **Cloud/360dialog** → `MessagingWindow`; sem janela, modelo aprovado de `notice_templates`, senão `skipped: 'template_required'`. **WAHA** (`MessagingWindow` o libera sempre) → só com mensagem **recebida do cliente nas últimas 24 h** na conversa; senão `skipped: 'waha_outside_window'`. **`Channel::Api` não-WAHA** → modelo de API por id. Conversa: a do convite, ou `ContactInbox` + `ConversationBuilder` na `notice_inbox`. Tetos: por número 4 avisos/24 h e por conta/dia configurável (padrão 300). Falha ou skip avisam o agente e **nunca** alteram a reunião. Sem conversa prévia e sem modelo, o número digitado no link público não recebe mensagem automática (reduz abuso de número de terceiros); o cliente vê a confirmação na tela e no `.ics`.
- Página de gestão = o mesmo `/b/:code` do convite (reunião agendada): `GET/POST` `confirm`, `reschedule`, `cancel`, `stop_notices`; cancelar até `cancel_until_minutes` (120).
- "Testar no meu WhatsApp": `POST booking_pages/:id/test_invite { phone }` envia ao número informado pela caixa de avisos.

### 2.6 F2-B, F2-C, F2-D
- B: agenda de hoje (status do cliente), "Lembrar", "link para remarcar" (usa invites), `post_meeting` (`mode`, `stage_id`) em `RecordOutcomeService`; botão "Chamar no WhatsApp" em `CrmMeetingDetail`; `MeetingsController` serializa `confirmation_status`.
- C: `Crm::Reports::Booking` (cinco números, origem, "abriram e não marcaram") com escopo "meus" × equipe por permissão; endpoint `crm/booking_stats`; tela do painel.
- D: `Crm::Calendar::Holidays` (feriados nacionais fixos e móveis do Brasil em tabela de código), `close_holidays`, `Reassigner` (confere conflito por horário), `crm_agent_availabilities` + "Meus horários" (checar reuso do horário por agente do SLA v2 antes).

### 2.7 F3 — IA
Ferramentas nativas síncronas `horarios_disponiveis` e `agendar_reuniao` em `Autonomia::Agents::Tools::Native` (+ `Registry::TOOLS`). **A página vem da configuração do agente** (`config['booking_page_id']`), nunca de parâmetro do modelo. Reserva pelo mesmo `Booker`, sob lock, `source: 'ai'`. Sem `delivery` → recusa nomeada. Card via `Crm::Cards::FromConversationHandler`. Atualizar o esqueleto `scheduler` do `builder.rb` para agentes com a ferramenta. Sem lista de palavras.

## 3. Frontend
- Página pública v2 e botão Agendar: seções 2.2 e 2.4. Tela de Configurações: `routes/dashboard/settings/booking/` (`booking.routes.js`, `BookingSettingsPage.vue`, `components/`, `specs/`); rota com `meta.permissions: ['administrator', ...SCHEDULING_PERMISSIONS]`; `SETTINGS_LANDINGS`; item de menu; `useCanManage('agendamento_manage')` nos botões de escrita.
- Textos: catálogo novo `booking.json` do fork (en + pt_BR) em `config/fork_i18n.json` e `crowdin.yml`; rótulos de menu e função em catálogos compartilhados só en e pt_BR.
- Guia e Central: bloco em `porques.md`, `pnpm guia:build`, artigo novo + `mapa-de-artigos.json`, `pnpm central:check`; `rails autonomia:guia:formatos` quando controller muda; J8-A15 entra na F1-D.

## 4. Permissões (J8)
Tabela do PRD (administrador, gerencia, só vê, agente sem função, função sem o módulo). "Se vê o cliente" = `CardPolicy#show?`/`ConversationPolicy#show?`/`ContactPolicy#show?` do sistema; **entregar** exige poder de responder. Nada de agendamento delega: usuários, funções, integrações, conexão de caixas, conta, faturamento. O controller antigo não é aberto a funções.

## 5. Mapa dos termos de aceite

| PR | Termos |
|---|---|
| F1-A #1188 | RA-01, RA-03, RA-04, RA-05, RA-21; J8-A1 (lista, policy, matriz, i18n), A2, A4 a A9, A13, A14 |
| F1-D #1191 | J3-A1 a A10, A12; J8-A1 (rota, menu, `useCanManage`), A15; RA-06, RA-07, RA-10, RA-13 (roteiro), RA-14 |
| F1-C #1190 | J1-A1 a A13; J8-A3, A7; RA-19 (invites) |
| F1-B #1189 | J2-A1 a A5, A7, A8, A10 a A12; RA-02, RA-08, RA-14 a RA-18, RA-20; J2-A9 quando `notices_enabled` |
| F2-A #1192 | J5-A1 a A8; J2-A6, A9; J3-A11; RA-18 |
| F2-B #1193 | J4-A1 a A7 |
| F2-C #1194 | J7-A1 a A5; J8-A12; RA-19 |
| F2-D #1195 | J3-A13; J8-A10, A11; durações; feriados |
| F3 #1196 | J6-A1 a A5; RA-09 |

Sem prova possível por código (marcados como pendentes de humano em cada PR, com roteiro): RA-13 (5 pessoas leigas), RA-15 (aparelho real e navegador do WhatsApp/Instagram), aprovação de modelo na Meta, ligar `HCAPTCHA_SERVER_KEY`.

## 6. Migrations: regras
Aditivas; `Migration[7.2]`; índice em tabela existente com `disable_ddl_transaction!` + `algorithm: :concurrently`; FK nova com `validate: false` e índice; relaxar NOT NULL de `crm_meeting_guests.email` volta **só enquanto não houver e-mail nulo gravado** (rollback real = desligar a flag da conta). `schema.rb` e a linha `version:` serão tocados em cada PR: ao retargetar para `main`, regenerar pelo Rails.

## 7. Rollback
Desligar a flag `crm_booking_v2` da conta no Super Admin: página, tela e menu antigos voltam na hora, sem restart nem deploy. Reuniões `internal` já criadas continuam no calendário com rótulo correto. Para voltar imagem: redeploy da anterior (migrations aditivas dispensam reverter banco). O cron de avisos sai sem consultar quando `calendar_meetings_enabled?` é falso.

## 8. Cron
`NoticeDispatchJob` `*/1` nas 2 stacks: 1 `SELECT` indexado `LIMIT 200` por minuto, só há linhas para contas com a flag; por linha vencida: 1 claim + 1 envio. Medir e informar na PR da F2-A.

## 9. Validação antes do push (por PR)
1. `rt.sh <worktree> <banco> <redis_db> rspec <arquivos>` + `spec/models/account_spec.rb` + `spec/services/autonomia/guide/formatos_spec.rb` + `spec/configs/schedule_spec.rb` (se `schedule.yml`) + `spec/enterprise/policies/custom_role_module_permissions_spec.rb`.
2. `rubocop` nos `.rb` alterados; `eslint` + `prettier --check` nos `.js/.vue`; `vitest` (TZ=UTC).
3. `pnpm guia:build`, `guia:check`, `central:check`, `i18n:fork:check`; `rails autonomia:guia:formatos` + check.
4. Se tocar `routes.rb`, `db/schema.rb`, `spec/support`, lockfiles ou `crm.json`: lint do e-mail protection com `FEATURE_BASELINE` = merge-base da branch e as specs de baseline.
5. `vite build --mode test` e Chrome real: print de cada tela renderizada.
6. Revisão independente (reviewer + tester com asserts rígidos) **antes** do primeiro push.
7. Ler a saída inteira de cada comando; nunca encadear teste e commit.

## 10. Riscos que permanecem
Modelo de WhatsApp aprovado na Meta; WAHA só com janela de 24 h (decisão do PRD); sem `HCAPTCHA_SERVER_KEY` a barreira pública é honeypot + `form_token` + limites; contato existente achado por telefone recebe a reunião de quem digitou o número (sem verificação, risco aceito e visível no card pela origem); cron novo nas duas stacks; conflito de `schema.rb` entre PRs empilhadas.

## 11. Achados da revisão independente e decisão
1. Inbox nulo em `AvailabilityService`/`PublicAvailableSlots`/`PublicBookingService` → serviços v2 novos (`Slots`, `Booker`) + trava de agente no v1. 2. Dupla reserva internal × Google → ocupação soma freebusy e reuniões do agente de qualquer caixa; lock de caixa + agente. 3. Controller antigo aberto → policy própria, antigo fica admin e filtra `page_version`. 4. Ordem das PRs → F1-A, F1-D, F1-C, F1-B. 5. Convite sem rate limit/enumeração → 404 uniforme, `viewed` por POST, throttles. 6. `next_slot` amplifica provedor → uma consulta para 14 dias com cache. 7. Spam a números de terceiros → sem aviso automático a número sem conversa e sem modelo, tetos, captcha documentado. 8. Time-trap fraco → `form_token` assinado e obrigatório. 9. Policy do convite → `contact_id` por policy, entrega exige responder, convite ↔ perfil, lock na linha. 10. WAHA × `MessagingWindow` → regra própria no `Sender`. 11. Merge de contatos e FKs → `on_delete` definido e merge cobrindo as tabelas novas. 12. Reuniões órfãs → reatribuição ao remover usuário. 13. `MeetingGuest` e-mail nulo → `allow_nil` e índice parcial de telefone. 14. `inbox` obrigatório em `Meeting` → opcional + serializer e rótulos + `page_version`. 15. `min_notice`/duração → implementados no `Slots`. 16. FE de reunião interna → rótulos na F1-A. 17. Tokens → convite = capacidade única, `purpose` por token, ICS sem e-mail, token no caminho. 18. Migrations → só o necessário, FK com índice, `validate: false`. 19. Consentimento e kill-switch → consentimento em `metadata`, flag no cron e no envio, claim atômico, precedência de parada. 20. Idempotência, URL, upload, QR, "Testar no meu WhatsApp" → tratados nas seções 2.1, 2.4, 2.5. 21. Cobertura dos termos → tabela da seção 5. 22. Regras do repo → strings no lugar de regex, `setProperty`, sem escopo redundante.
