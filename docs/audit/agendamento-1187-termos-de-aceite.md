# Agendamento WhatsApp-first (#1187): conferência dos 21 termos de aceite

Data: 12/10/2026. Base: `origin/main` em `4d690953e4`. Auditoria só de leitura: nenhum código de produto alterado,
nada em produção.

Fonte dos termos: `docs/agendamento-whatsapp-first/src/PRD.src.html` (seção "Termos de aceite globais", linhas
241-262), com o mapa termo → PR de `docs/agendamento-whatsapp-first/PLANO-TECNICO.md` §5 (linhas 110-122).

## Decisões do Rodrigo (12/10/2026, depois da auditoria)

Respostas dadas no chat do Agendamento, em escolha entre opções:

- **RA-13** (teste com 5 pessoas leigas): "Dispensar o termo". Sai do fechamento do épico.
- **RA-14** (letra mínima de 16 px): "Só na página pública". O painel segue o padrão do sistema (14 px). Continua
  valendo para o fechamento: AA, alvo de 44 px, zoom de 200% e leitor de tela.
- **RA-07 e RA-18** (revisão dos textos) e **RA-15** (prints em aparelho real): "Dispensar". Os textos ficam como estão
  e os prints em aparelho real não são exigidos. A parte de código do RA-18 (aviso antes de confirmar, "Parar avisos",
  só nome e WhatsApp) segue conferida na tabela.

- **RA-16** (3 s em 4G): "Aceitar a mediana". Conta como cumprido com a mediana de 2,9 s; a página mais leve fica para
  a continuação no #1402.
- **RA-17** (sem beco sem saída): "Pedido de contato". A página pausada passa a oferecer o pedido de contato que já
  existe no "Nenhum horário serve?", mesmo pausada; o link inexistente ganha um botão genérico para o WhatsApp. Em #1401.

**RA-12** resolvido neste PR: `docs/agendamento-whatsapp-first/ROLLBACK.md` (uma conta, todas as contas, imagem
anterior; caminho, comando e ETA de cada um).

Ficam para fechar o épico: RA-17 e RA-21 (código e spec, issue própria), RA-06, RA-11,
RA-14 e RA-20 (conferência no navegador, com prints) e RA-16 (tempo de carga medido).

## Conferência no navegador e medição (12/10/2026, produção, conta 16)

Página pública `https://chat.hub2you.ai/a/hub2you/chat2you/chat2you` e telas do painel do Agendamento, conferidas pelo
gestor da sessão do Agendamento com Chrome (extensão e headless via DevTools Protocol). Só leitura: nada foi marcado.

**Página pública (RA-06, RA-14, RA-20)**
- Letra: menor tamanho 16 px; 0 de 39 textos abaixo de 16 px.
- Contraste: 0 textos abaixo de AA (4,5:1), nos temas claro e escuro, com logo e foto.
- Leitor de tela: 13 controles, todos com nome acessível; `lang="pt-BR"`, 1 `main`, 1 `h1` (que recebe o foco ao
  trocar de passo, `tabindex=-1`). Nenhum `<select>`.
- Toque: todos os controles com 44 px ou mais (o único item abaixo é o `h1`, que não é botão).
- Teclado: Tab percorre "Quero este", os 10 dias e "Nenhum horário serve?" na ordem da tela; foco visível com contorno
  de 2 px (`:focus-visible`).
- Zoom 200% (largura de 320 px, critério de refluxo do WCAG): nada rola de lado e nenhum botão ou texto cortado, nos
  dois temas. Prints: `img/agendamento-1187-pagina-320-light.jpg` e `img/agendamento-1187-pagina-320-dark.jpg`.

**Painel (RA-06)** — Páginas e links, Meus horários, Meus números e Resultados: todos os controles com nome acessível,
nenhum `<select>`. Abaixo de 44 px: só os campos "Das" e "Até" de Meus horários (40 px), corrigidos no #1401. O
Calendário tem botões de 32 px, mas a tela é anterior ao épico; fica registrado, fora deste fechamento.

**Tempo de carga (RA-16)** — Chrome headless, perfil "4G lento" do Lighthouse (150 ms de latência, 1,6 Mbps) e CPU 4x
mais lenta, sem cache, 6 rodadas. "Pronta" = primeiro botão clicável na tela.
- Pronta em 2,7 / 2,7 / 2,7 / 3,1 / 4,0 / 4,4 s: **mediana 2,9 s**, acima de 3 s em 2 das 6 rodadas.
- Transferido: 366 KB. Os maiores: CSS 146 KB (é o CSS inteiro do sistema, 1,85 MB sem compressão), fonte Inter 109 KB,
  Vue 61 KB, vue-i18n 20 KB, código da página 9 KB. O logo é baixado com 1254 px para aparecer pequeno.
- Biblioteca pesada: nenhuma (só `vue` e `vue-i18n`; hCaptcha sob demanda).

## Como ler

- **CUMPRIDO**: código e spec existem **e** a prova que o PRD pede para o termo está registrada.
- **PARCIAL**: falta parte do código, ou o código está pronto mas falta a prova exigida pelo PRD.
- **NÃO CUMPRIDO**: sem evidência de que foi feito.
- **NÃO VERIFICÁVEL SEM PRODUÇÃO**: a prova depende de aparelho real, rede real ou ambiente publicado.
- **Fechamento**: `fecha no épico` (tem de ser resolvido antes de fechar o #1187), `fica de fora → issue #N`, ou
  `fica de fora → sem issue (precisa abrir)`.

Origem do código: as ondas foram mescladas em três PRs, que absorveram os PRs por fase (#1202-#1204, #1206-#1208,
#1210): **#1205** (F1: #1188, #1189, #1190, #1191), **#1209** (F2: #1192-#1195) e **#1215** (F3/F4: #1196, #1212).
Depois vieram #1255, #1266, #1268, #1275, #1279, #1280, #1287, #1292-#1294, #1296, #1302, #1304, #1308, #1312-#1314,
#1347, #1353, #1356, #1358, #1363, #1372, #1378, #1381.

## Specs rodados nesta auditoria

Banco isolado `chatwoot_ag_ra` (apagado no fim), um arquivo por vez, saída lida inteira.

| Spec | Resultado |
|---|---|
| `spec/services/crm/meetings/creator_dispatch_spec.rb` | 5 exemplos, 0 falhas |
| `spec/requests/public/api/v1/booking_v2_isolation_spec.rb` | 5 exemplos, 0 falhas |
| `spec/requests/public/api/v2/booking_end_to_end_spec.rb` | 1 exemplo, 0 falhas |
| `spec/requests/public/api/v2/booking_spec.rb` | 64 exemplos, **1 falha** (`:105`), que passa ao rodar de novo. Ver "Achados" |
| `spec/policies/crm/booking_page_policy_spec.rb` | 6 exemplos, 0 falhas |
| `spec/enterprise/policies/crm/booking_page_policy_spec.rb` | 6 exemplos, 0 falhas |
| `spec/config/rack/attack_booking_v2_spec.rb` | 6 exemplos, 0 falhas |
| `spec/services/crm/booking_v2/slots_spec.rb` | 16 exemplos, 0 falhas |
| `spec/services/crm/booking_v2/tokens_spec.rb` | 9 exemplos, 0 falhas |
| `spec/requests/api/v1/accounts/crm/booking_pages_spec.rb` | 62 exemplos, 0 falhas, 2 pendentes (`:505`, `:512`: libvips não existe nesta máquina) |
| `spec/requests/api/v1/accounts/crm/booking_invites_spec.rb` | 22 exemplos, 0 falhas |
| `spec/requests/api/v1/accounts/crm/booking_stats_spec.rb` | 15 exemplos, 0 falhas |
| `spec/requests/api/v1/accounts/crm/booking_page_meetings_spec.rb` | 18 exemplos, 0 falhas |
| `spec/services/crm/booking_v2/notices/text_spec.rb` | 15 exemplos, 0 falhas |
| `spec/services/crm/booking_v2/results_spec.rb` | 12 exemplos, 0 falhas |
| `spec/services/autonomia/agents/tools/native/agenda_sem_regex_spec.rb` | 2 exemplos, 0 falhas |
| `spec/services/crm/booking_v2/booker_spec.rb` | 36 exemplos, 0 falhas |

Não rodados aqui (máquina com pouca memória): suíte completa, specs de JS (vitest). A CI dos PRs #1205 (24 checks) e
#1209 (21 checks) passou inteira; no #1215 a única falha é o job `Fila - painel` (cancelado; é da fila de deploy, não
de teste).

## Tabela

| RA | Termo (resumo) | Status | Evidência no código | Evidência em spec | Origem | O que falta | Fechamento |
|---|---|---|---|---|---|---|---|
| RA-01 | Google/MS não regride | CUMPRIDO | `app/services/crm/meetings/creator.rb:24` (só desvia para `InternalCreator` com local pedido que não é Meet/Teams) e `:50-53`; a v1 recusa página nova (isolamento) | `spec/services/crm/meetings/creator_dispatch_spec.rb:27,40,48,59`; `spec/requests/public/api/v1/booking_v2_isolation_spec.rb:18`; `spec/services/crm/calendar/public_booking_service_agent_lock_spec.rb:20,32,41` (verdes nesta auditoria) | #1188 → PR #1205 | Nada. A suíte inteira do Google/MS não foi rodada aqui; vale a CI verde do #1205 | fecha no épico (já fechado) |
| RA-02 | Conta sem Google/MS publica e recebe, de ponta a ponta | CUMPRIDO | `app/services/crm/meetings/internal_creator.rb`; `app/services/crm/booking_v2/booker.rb`; `app/controllers/public/api/v2/booking_controller.rb` | `spec/requests/public/api/v2/booking_end_to_end_spec.rb:54` (conta sem nenhuma caixa: cria pela API, publica, cliente marca só com nome e WhatsApp, reunião interna no card) — verde | #1188/#1189 → PR #1205 | Nada no nível da API. Não há E2E no navegador (o PRD pede "E2E em ambiente isolado", que o request spec atende) | fecha no épico (já fechado) |
| RA-03 | Flag volta às telas antigas | CUMPRIDO | `app/services/crm/config.rb:19-23` (`booking_v2_enabled?` = calendário da instalação + flag da conta); `config/features.yml:322`; `before_action :ensure_booking_v2_enabled` nos controllers (ex.: `app/controllers/api/v1/accounts/crm/booking_invites_controller.rb:63-64`); `app/controllers/public/api/v2/invites_controller.rb:71` | `spec/requests/public/api/v2/booking_spec.rb:231,237`; `spec/requests/api/v1/accounts/crm/booking_page_meetings_spec.rb` ("answers 404 on every route when the account flag is off"); `app/javascript/dashboard/routes/dashboard/settings/booking/specs/booking.routes.spec.js:104,113`; `app/javascript/dashboard/components-next/Booking/specs/BookingInviteButton.spec.js:78` | #1188 → PR #1205 | Nada | fecha no épico (já fechado) |
| RA-04 | Migrations aditivas e reversíveis, versão única | CUMPRIDO | 24 migrations do épico (`db/migrate/20261011091723` … `20261017100100`): colunas/tabelas novas, índices `concurrently`, FK com `validate: false` validada à parte. Nenhuma versão repetida em `db/migrate` (conferido). Rollback escrito no corpo de #1205, #1209, #1296 e no `PLANO-TECNICO.md:127` | Sem spec (é conferência). `schema.rb` em `2026_10_21_100000` | PRs #1205, #1209, #1296, #1313 | Ressalvas, não pendências: `20261011091723#down` recusa reverter se já houver convidado sem e-mail (documentado: o rollback real é desligar a flag); `20261017100000` troca o índice único global de `short_name` pelo índice por conta (reversível, mas não puramente aditiva); `20261017100100` é backfill com `down` vazio. "Aplicar em produção só com OK" não é verificável por código | fecha no épico (já fechado) |
| RA-05 | Segurança do público | CUMPRIDO | Slug `SecureRandom.uuid` (`app/models/crm/agent_booking_profile.rb:155-156`); código do convite aleatório (`app/models/crm/booking_invite.rb:43`); tokens com `purpose` e expiração, `.ics` cifrado (`app/services/crm/booking_v2/tokens.rb:18-30`); rate-limit v2 e `/a/` (`config/initializers/rack_attack.rb:510-557`); limite de 2 reuniões abertas por número (`app/services/crm/booking_v2/booker.rb:33,153`) e de 2 pedidos de contato por dia (`contact_request.rb:20,38`); payload público sem dado interno (`public_page_serializer.rb`) | `spec/services/crm/booking_v2/tokens_spec.rb:18,27,35,46,65`; `spec/config/rack/attack_booking_v2_spec.rb:15-63`; `spec/requests/public/api/v2/booking_spec.rb:105,299,785,830`; `spec/services/crm/booking_v2/booker_spec.rb:171` | #1188/#1189 → PR #1205; #1282/#1299/#1303 | Revisão independente registrada em commits (`eb6b0d0493` "correções da revisão independente da F1-A", `afc8f09820`, `e7a20e96a6`) e nos audits `docs/audit/agendamento-endereco-por-conta-1299.md:84`, `agendamento-previa-teto-tipo-real-1303.md:65`. Achado: o spec `booking_spec.rb:105` é frágil (ver Achados) | fecha no épico (já fechado); spec frágil → fica de fora → sem issue (precisa abrir) |
| RA-06 | Sem `<select>` nativo; 44 px, teclado, leitor de tela | PARCIAL | Página pública só com cartões e botões (`app/javascript/public_booking_v2/components/ActionButton.vue:32`, `min-h-12` = 48 px); telas do painel com `ChoiceSelect`/cartões. Nenhum `<select>` no escopo (busca feita em `public_booking_v2`, `settings/booking`, `components-next/Booking`, `crm/components/calendar`, `AgentBookingForm.vue`) | `app/javascript/dashboard/routes/dashboard/settings/booking/specs/noNativeSelect.spec.js:21-38`; `app/javascript/public_booking_v2/specs/static.spec.js:41`; `app/javascript/public_booking_v2/specs/App.spec.js:294` | #1191/#1189 → PR #1205; #1215 (PanelTune) | A prova do PRD é "conferência no navegador real" (teclado e leitor de tela). Sem registro dela | fecha no épico |
| RA-07 | Linguagem simples | PARCIAL | Textos em `app/javascript/public_booking_v2/i18n/pt_BR.json` e `app/javascript/dashboard/i18n/locale/pt_BR/booking.json`; estado vazio e telas de recado com 1 frase + 1 ação (ex.: `components/NoSlot.vue`, `ErrorPage.vue`) | Sem spec possível | #1191 → PR #1205 | A prova do PRD é "revisão de textos pelo Rodrigo no protótipo". Sem registro dessa revisão nas issues/PRs da onda 1-3 | fecha no épico |
| RA-08 | Fuso correto; fuso inválido falha explícito | CUMPRIDO | Página pública levanta `InvalidTimeZone` em vez de trocar de fuso (`app/services/crm/booking_v2/public_page.rb:15-17,73`); validação ao gravar (`app/models/concerns/crm/booking_page_settings.rb:58,65`); cliente vê no fuso dele (`app/javascript/public_booking_v2/helpers/datetime.js:7-24`) | `spec/requests/public/api/v2/booking_spec.rb:175,724-741,745`; `spec/services/crm/booking_v2/slots_spec.rb` (verde); `app/javascript/public_booking_v2/specs/App.spec.js:255,546`; `specs/helpers.spec.js:162,208` | #1189 → PR #1205; #1362 → PR #1363 | Ressalva: fora da página pública (painel, IA, gestão) o fuso vem de `resolved_timezone` (`agent_booking_profile.rb:129-131` → `Crm::Timezone::Resolver#name_or_default`), que troca um fuso gravado inválido pelo da conta sem avisar; e `slots.rb:91` ainda tem `|| TimeZone['UTC']` (inalcançável hoje, porque o resolvedor sempre devolve fuso válido). Só afeta dado gravado antes da validação | fecha no épico (já fechado); ressalva → fica de fora → sem issue (precisa abrir), se o Rodrigo quiser |
| RA-09 | Sem regex para texto de pessoa | CUMPRIDO | Telefone pela biblioteca (`app/services/crm/booking_v2/phone_lookup.rb:21`, `TelephoneNumber`); no front, só métodos de string (`app/javascript/public_booking_v2/helpers/phone.js:1-2`); a IA decide a intenção pelo modelo (`app/services/autonomia/agents/tools/native/agenda*.rb`, `horarios_disponiveis.rb`, `agendar_reuniao.rb`). Busca por `=~`, `match?`, `Regexp`, `%r{`, `.test(` no escopo: nada | `spec/services/autonomia/agents/tools/native/agenda_sem_regex_spec.rb:58,62` (varre a árvore Prism, com autoteste) | #1196 → PR #1215 | Nada | fecha no épico (já fechado) |
| RA-10 | i18n pt_BR/en, Guia, artigo 10.11 | CUMPRIDO | Paridade conferida: `booking.json` 511/511 chaves, `public_booking_v2/i18n` 136/136. Guia: `lib/operator_guide/porques.md:509,514-535` (blocos do agendamento novo, com `feature: crm_booking_v2`). Central: `lib/central_de_ajuda/10/10.11-calendario-do-crm-e-agendar-reuniao.md:100-143` (conferido 10/10) e artigo novo `10.17-pagina-de-agendamento-pelo-whatsapp.md` | `app/javascript/public_booking_v2/specs/static.spec.js:24,28`; CI `guia:check`/`central:check` (`.github/workflows/relationships.yml:140`) e `i18n:fork:check` (`.github/workflows/fork-i18n.yml:24`) verdes no #1205/#1209 | PRs #1205, #1209, #1215, #1358 | Nada | fecha no épico (já fechado) |
| RA-11 | Qualidade antes de "pronto" (suíte lida, tester, revisor, prints) | PARCIAL | Revisão feita e corrigida em commits por fase: `eb6b0d0493`, `e7a20e96a6`, `b61562b78c`, `afc8f09820`, `a886f59ad9`, `511e29027f`, `d336666a83`, `14af2044f5`, `6350a2a915`, `67abdbf91d`; PRs posteriores têm audit com revisão (`docs/audit/agenda-ia-pessoas-1307.md:30`, `agendamento-avisos-com-ia-1354.md:52`, `agendamento-link-curto-previa-1282.md:34`) | — | todas | O PRD pede "relatório anexado à PR". Os PRs #1205, #1209 e #1215 não têm comentário, review nem relatório de tester, e nenhum print de tela. Os audits de #1282 e #1299 dizem que não houve conferência em navegador real | fecha no épico (relatório consolidado + prints das telas) |
| RA-12 | Rollback escrito antes do deploy | PARCIAL | Rollback no corpo de #1205, #1209, #1215 ("desligar a opção, sem deploy; migrations só acrescentam") e em `PLANO-TECNICO.md:127-129` | — | PRs #1205, #1209, #1215 | O PRD pede "comando e ETA no PR" e a volta da imagem anterior. Os PRs não trazem o caminho exato no Super Admin, a ETA nem o comando de redeploy da imagem anterior | fecha no épico (runbook curto de rollback no épico) |
| RA-13 | 5 pessoas leigas: 4 concluem sozinhas | NÃO CUMPRIDO | — | — | #1191 (roteiro previsto no `PLANO-TECNICO.md:113,122`) | Sem evidência do teste nem do roteiro. Nenhum relatório em `docs/` nem nas issues | fecha no épico (ou decisão explícita do Rodrigo de mover para continuação) |
| RA-14 | Leitura e toque: 16 px, AA, 44 px, zoom 200%, leitor de tela | PARCIAL | Página pública: nenhum `text-xs`/`text-sm` em `public_booking_v2/components`, alvos `min-h-12`/`min-h-14`, contraste da marca calculado (`helpers/brand.js:4-29`) | `app/javascript/public_booking_v2/specs/brandLook.spec.js:47,63` (AA no botão e na borda, claro e escuro) | #1189/#1191 → PR #1205 | (1) Telas do painel do Agendamento usam `text-sm` (14 px) em 43 pontos de `routes/dashboard/settings/booking` (ex.: `results/OpenedNotBookedList.vue:154,182`). (2) Sem prova de zoom 200% e leitor de tela ("conferência no navegador e em aparelho") | fecha no épico |
| RA-15 | Abre no navegador do WhatsApp/Instagram, Safari e Chrome | NÃO VERIFICÁVEL SEM PRODUÇÃO | SPA sem login, sem app e sem pop-up (`app/javascript/entrypoints/public_booking_v2.js`); prévia Open Graph do link (#1282) | — | #1189 → PR #1205; #1282 → PR #1296 | "Print em aparelho real". Sem registro; o audit `agendamento-link-curto-previa-1282.md:32` diz que não foi conferido no WhatsApp real | fecha no épico (prints em aparelho) |
| RA-16 | Rápida: pronta em até 3 s em 4G, sem biblioteca pesada | NÃO VERIFICÁVEL SEM PRODUÇÃO | Dependências da página pública: só `vue` e `vue-i18n`; o hCaptcha é carregado sob demanda (`components/CaptchaField.vue:13`) | — | #1189 → PR #1205 | A metade "sem biblioteca pesada" está cumprida. Falta a medição registrada (3 s em 4G) | fecha no épico (medição) |
| RA-17 | Sem beco sem saída | PARCIAL | Erro de carga: "Tentar de novo" + WhatsApp (`components/ErrorPage.vue:8-22`); dia vazio: outro dia + pedido de contato (`NoSlot.vue`); gestão com erro: WhatsApp (`ManageError.vue:21`) | `app/javascript/public_booking_v2/specs/App.spec.js:511,526,534,681,704,714` | #1189 → PR #1205 | `contact_phone` é opcional (`app/models/concerns/crm/booking_page_settings.rb:148-149`). Sem ele, a página pausada (`Paused.vue:14-35`, texto `PAUSED.BODY_NO_WHATSAPP`) e o link inexistente (`NotFound.vue:19`) mostram só texto, sem nenhuma ação. Falta oferecer uma saída nesses casos (ex.: pedido de contato na página pausada, ou exigir o WhatsApp da empresa ao publicar) | fecha no épico (correção pequena; precisa abrir issue) |
| RA-18 | LGPD: aviso antes de confirmar, "Parar avisos", só nome e WhatsApp | PARCIAL | Aviso antes de confirmar quando há avisos (`components/FormFooter.vue:42-47`); consentimento gravado só com aceite e texto conhecido (`booker.rb:45-46,231-240`); linha de parar sempre acrescentada pelo sistema (`app/services/crm/booking_v2/notices/text.rb:2-3,18,31,44,50`) e proibida no texto do dono (`notices/custom_text.rb`); e-mail só quando o local exige (`booking_input.rb:18`) | `spec/requests/public/api/v2/booking_spec.rb:358,372`; `spec/services/crm/booking_v2/notices/text_spec.rb:86,103`; `notices/custom_text_spec.rb:33`; `App.spec.js:608` | #1189/#1192 → PRs #1205, #1209; #1354 → PR #1358 | O teste existe. Falta a "revisão de texto" pedida pelo PRD (sem registro). "Os dados não servem a outra finalidade" não se prova por código | fecha no épico (junto com a revisão do RA-07) |
| RA-19 | Medição: enviado, aberto, agendado, confirmou, compareceu, faltou | CUMPRIDO | `app/services/crm/booking_v2/results.rb:1-49` (`sent_at`, `first_opened_at`, `source`, `confirmed_at`, `outcome_recorded_at`; só contagens) | `spec/services/crm/booking_v2/results_spec.rb:55,76,109,162`; `spec/requests/api/v1/accounts/crm/booking_stats_spec.rb:79,132,146` | #1190/#1194 → PRs #1205, #1209; #1271 → PR #1279 | Ressalva: a "linha de base de faltas" é a contagem do período; não há comparação com o antes do épico | fecha no épico (já fechado) |
| RA-20 | Marca sem quebrar, contraste corrigido sozinho | PARCIAL | `app/javascript/public_booking_v2/helpers/brand.js:4-29`; logo por tema e versão escura gerada (`app/services/crm/booking_v2/logo_dark.rb`) | `app/javascript/public_booking_v2/specs/brandLook.spec.js:40,47,177,281,290,403`; `specs/previewFidelity.spec.js:150-267`; `spec/requests/api/v1/accounts/crm/booking_pages_logo_dark_spec.rb` | #1189 → PR #1205; #1289/#1295/#1298 → PRs #1302, #1304 | Código e testes cobrem com e sem logo/foto. Falta a prova do PRD: "print com e sem logo" | fecha no épico (prints) |
| RA-21 | Permissões por pessoa, matriz de testes | PARCIAL | Policies: `app/policies/crm/booking_page_policy.rb`, `booking_invite_policy.rb`, `booking_page_meeting_policy.rb`, `booking_stats_policy.rb`, `agent_booking_profile_policy.rb`; chaves `agendamento_view`/`agendamento_manage` em `enterprise/app/models/custom_role.rb:45,90-91` | Matriz completa (admin, gerencia, só vê, agente sem função, função sem o módulo) em `spec/requests/api/v1/accounts/crm/booking_pages_spec.rb:43-80`, `booking_invites_spec.rb:47`, `booking_stats_spec.rb:57,79`; policies verdes | #1188 → PR #1205 e seguintes | Rotas novas sem a matriz dos 5 perfis, só casos soltos: `booking_page_meetings` (`booking_page_meetings_spec.rb:204-240`: função sem CRM e agente sem card), `meeting_actions` (`meeting_day_spec.rb:127`), `my_booking_hours` (`my_booking_hours_spec.rb:47,117`), `short_name` (`booking_pages_short_name_spec.rb:90`), avisos/modelos/textos, identidade, reatribuição, foto | fecha no épico |

## Achados fora dos termos

- `spec/requests/public/api/v2/booking_spec.rb:121` é frágil: verifica que nenhum id interno (conta, página,
  responsável, funil) aparece entre os valores do payload, mas `booking_window_days` vale 14. Quando algum desses ids
  é 14, o teste falha sem haver vazamento. Aconteceu nesta auditoria (`expected [...] not to include 14`) e o exemplo
  passou ao rodar sozinho. **Corrigido no #1396** (já na main, 12/10/2026): a checagem passou a comparar os nomes das
  chaves (`internal_id_keys`), não os valores. A auditoria rodou numa base anterior a ele.

## Resumo

- **CUMPRIDO: 9** — RA-01, RA-02, RA-03, RA-04, RA-05, RA-08, RA-09, RA-10, RA-19
- **PARCIAL: 9** — RA-06, RA-07, RA-11, RA-12, RA-14, RA-17, RA-18, RA-20, RA-21
- **NÃO CUMPRIDO: 1** — RA-13
- **NÃO VERIFICÁVEL SEM PRODUÇÃO: 2** — RA-15, RA-16

Nenhum dos termos depende das issues abertas do épico (#1355, #1359, #1309, #1277, #1361). Elas são continuação
de escopo (IA escrevendo o aviso por cliente, limite do "Escrever com IA", remarcar pela IA, lembrete por e-mail,
portão de confiança dos agentes) e não fecham nenhum RA.

## O que falta para fechar

### Bloqueia o épico (fecha no épico)

Código:
1. **RA-17**: dar uma saída na página pausada e no link inexistente quando a página não tem WhatsApp da empresa
   (pedido de contato, ou exigir o WhatsApp ao publicar). Precisa de issue.
2. **RA-21**: matriz dos 5 perfis nas rotas que ainda não têm (`booking_page_meetings`, `meeting_actions`,
   `my_booking_hours`, `short_name`, avisos/modelos/textos, identidade, reatribuição, foto). Só spec.
3. **RA-14**: decidir se o texto de 16 px vale também para as telas do painel; se vale, trocar os 43 `text-sm` de
   `settings/booking`.

Prova humana ou de aparelho (sem código):
4. **RA-13**: teste com 5 pessoas leigas (cliente e admin), com relatório curto.
5. **RA-07 e RA-18**: revisão dos textos pelo Rodrigo (página pública, avisos e tela do Agendamento), registrada.
6. **RA-06, RA-14, RA-20 e RA-11**: conferência no navegador (teclado, leitor de tela, zoom 200%) e prints de cada
   tela, com e sem logo, num relatório anexado ao épico.
7. **RA-15**: prints em aparelho real (navegador do WhatsApp e do Instagram, Safari no iPhone, Chrome no Android).
8. **RA-16**: medição do tempo até a página ficar pronta em 4G, registrada.
9. **RA-12**: rollback com o caminho exato no Super Admin, a ETA e o comando de redeploy da imagem anterior.

### Pode ir para continuação (fica de fora)

- **Spec frágil** `spec/requests/public/api/v2/booking_spec.rb:121`: compara os ids internos com todos os valores do
  payload, e `booking_window_days` vale 14; quando algum id cai em 14 o teste falha sem vazamento nenhum. Falhou uma
  vez nesta auditoria e passou ao rodar de novo. → **resolvido no #1396** (na main).
- **RA-08 (ressalva)**: fora da página pública, fuso gravado inválido vira o da conta sem aviso; `slots.rb:91` com
  `|| UTC` morto. Só dado antigo. → fica de fora → sem issue (precisa abrir), se o Rodrigo quiser.

### Termos que ficam de fora

Nenhum RA fica de fora com esta proposta: todos os pendentes estão marcados "fecha no épico". Se o Rodrigo decidir
mover algum (o candidato natural é o RA-13, que depende de recrutar pessoas), ele precisa de issue própria antes de o
#1187 fechar. As duas ressalvas acima não são termos.
