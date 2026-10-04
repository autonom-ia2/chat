# Guia visual das telas do Guia

Regra do Rodrigo (CLAUDE.md, 02/10/2026): **premium no visual, simples no uso**.
Para o Guia, "simples" vai além do normal: quem nunca usou um computador direito
precisa concluir a tarefa sem ajuda. Este documento junta o padrão que já existe
nas telas remodeladas, para as telas novas do Guia seguirem.

> Fonte: `origin/main` em 03/10/2026 (`149c6718f2`). O checkout local da `main`
> está 319 commits atrás; vários arquivos citados só existem no `origin/main`.
> Tudo o que está citado abaixo existe no repositório. O que ainda não existe
> está marcado como **(a criar)**.

## 1. Telas de referência

| Tela | Arquivo | Para copiar |
|---|---|---|
| Campanhas de e-mail (#801) | `app/javascript/dashboard/routes/dashboard/campaigns/pages/EmailCampaignsPage.vue` | herói, abas em pílula, linha de lista rica, menu "…", rodapé |
| Relacionamentos (#777) | `app/javascript/dashboard/routes/dashboard/relationships/RelationshipsHome.vue` | título com ícone grande, cartões em grid, dica em azul |
| Automações (#928) | `app/javascript/dashboard/routes/dashboard/automacoes/pages/AutomacoesPage.vue` e `automacoes/components/*.vue` | os 4 estados da página, modelos prontos, ensaio "veja o que aconteceria", selo "Criada pelo Guia" |
| Central de Ajuda (#603/#636) | `app/javascript/dashboard/routes/dashboard/centralDeAjuda/pages/CentralDeAjudaInicio.vue` | letra grande, "Comece por aqui", sanfona acessível |
| Painel do Guia | `app/javascript/dashboard/components/autonomia/guide/` (`AutonomiaGuideContainer`, `GuideHeader`, `GuideComposer`, `GuideExecucao`, `GuideHistorico`, `GuideConversas`, `GuideDot`) | painel estreito, alvo de 44 px, cartão "Feito pelo Guia" com Desfazer |

## 2. O padrão, peça por peça

### 2.1 Cabeçalho de página

- **Página cheia (Automações):** `header` com `flex flex-wrap items-start justify-between gap-4 px-6 pt-6 pb-4 border-b border-n-weak`;
  título `h1.text-xl.font-medium.text-n-slate-12`; subtítulo
  `mt-1 text-sm text-n-slate-11 max-w-2xl`; **um** botão primário à direita
  (`Button` com `icon="i-lucide-plus"` e `class="min-h-11"`).
- **Página vitrine (E-mail):** título `text-[1.75rem] font-semibold leading-tight tracking-tight`,
  migalha `text-xs text-n-slate-11` com `i-lucide-chevron-right size-3.5` e o
  trecho atual em `font-medium text-n-blue-11`. Botões `!min-h-11 !rounded-xl`.
- **Página de entrada (Relacionamentos):** ícone em bloco
  `flex size-20 items-center justify-center rounded-2xl bg-n-blue-4 text-n-blue-11`
  (ícone `size-10`), título `text-3xl md:text-4xl font-semibold tracking-tight`,
  subtítulo `text-base md:text-lg leading-relaxed text-n-slate-11`.
- **Herói com números (E-mail):** `section` `rounded-3xl border border-n-weak bg-n-solid-1 shadow-sm md:flex-row`,
  bloco escuro `bg-[#0D2344] text-white` com anel decorativo
  `rounded-full border-[1.5rem] border-n-blue-9 opacity-10`, números
  `text-3xl font-semibold tabular-nums`, divisórias `lg:border-s lg:border-n-weak lg:ps-5`.
  O hex fixo só serve nesse herói. No painel do Guia, use só tokens.

### 2.2 Superfícies, bordas, raios, sombra e espaço

| Uso | Classes reais |
|---|---|
| Fundo de página | `bg-n-surface-1` (Automações, Relacionamentos) ou `bg-n-slate-2` (E-mail) |
| Fundo do painel do Guia | `bg-n-surface-2` (`classeDoPainel` em `AutonomiaGuideContainer.vue`) |
| Cartão de página | `rounded-xl border border-n-weak bg-n-solid-1 p-4` (Automações) / `p-6` (estados) |
| Cartão vitrine | `rounded-xl border border-n-weak bg-n-solid-2 p-6 shadow-sm md:p-7` (Relacionamentos), `rounded-2xl ... shadow-sm` (lista de e-mail) |
| Cartão dentro do painel | `rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2` (`GuideExecucao`, cartão de ação) |
| Item interno | `rounded-lg bg-n-alpha-1 p-3` (`AutomacaoEnsaio`), hover `hover:bg-n-alpha-2` |
| Popover / balão | `rounded-xl bg-n-solid-2 outline outline-1 outline-n-container shadow-lg` (`GuideSidebarEntry`); menu `rounded-xl border border-n-weak bg-n-solid-1 p-1.5 shadow-lg` (E-mail) |
| Dica | `rounded-xl border border-n-blue-5 bg-n-blue-2 p-5` com ícone `bg-n-blue-4 text-n-blue-11` (Relacionamentos) |
| Grid de cartões | `grid grid-cols-[repeat(auto-fit,minmax(min(100%,18rem),1fr))] gap-5`; modelos: `grid gap-3 sm:grid-cols-3` |
| Largura de leitura | `max-w-4xl mx-auto` (Automações, Central), `max-w-7xl` (Relacionamentos) |

Raios: painel `rounded-lg`; página `rounded-xl`; vitrine `rounded-2xl` e `rounded-3xl`.
Sombra só em cartão de página (`shadow-sm`) e em flutuante (`shadow-lg`).

### 2.3 Cor e marca

- Tokens `n-*` vêm de `theme/colors.js` (`rgb(var(--…))`), com os valores em
  `app/javascript/dashboard/assets/scss/_next-colors.scss` (`:root` e `.dark`).
- Marca: `bg-n-brand` / `text-n-brand` (`brand: '#2781F6'`). Uso real: botão redondo
  de enviar e microfone (`GuideComposer`), CTA de Relacionamentos, ícone dos
  modelos (`AutomacaoModelos`), anel de foco `outline-n-brand`.
- Texto: `text-n-slate-12` (principal), `text-n-slate-11` (apoio), `text-n-slate-10/9` (ícone apagado).
- Significado: sucesso `text-n-teal-11`, atenção `text-n-amber-11`, erro `text-n-ruby-11`,
  link e seleção `text-n-blue-11` / `bg-n-blue-3`, "feito pelo Guia" `bg-n-iris-3 text-n-iris-11`.
- **Barra lateral com cor de marca:** `.sidebar-branded` em `components-next/sidebar/Sidebar.vue`
  repinta `bg-n-solid-*`, `bg-n-alpha-*`, `text-n-slate-*` e `bg-n-brand` de quem está
  dentro do `<aside>`. Balão que sai da barra vai por `TeleportWithDirection`
  (`components-next/TeleportWithDirection.vue`), como em `GuideSidebarEntry.vue`.

### 2.4 Tema escuro

- O tema escuro põe `.dark` no **`body`** (`dashboard/helper/themeHelper.js`), não no `<html>`.
  Os tokens mudam sozinhos.
- Nenhuma tela de referência usa `dark:`. **Regra:** só tokens `n-*`. Sem `bg-white`,
  sem `text-black` e sem hex (exceção: o herói da seção 2.1).

### 2.5 Tipografia

- Fonte padrão do sistema (`fontFamily.sans` em `tailwind.config.js`).
- No painel do Guia: base `text-sm leading-6 tracking-tight`, título de bloco `text-base font-medium`,
  rótulo de seção `text-xs font-medium text-n-slate-11`.
- Rótulo de etapa: `text-xs font-medium uppercase text-n-slate-11` (`AutomacaoResumo`: QUANDO, SE, ENTÃO).
- Página para leigo: a Central usa `text-base` e `text-lg` no corpo. Em tela nova
  do Guia que não fique no painel, o corpo é `text-base`.
- Números: `tabular-nums` sempre.

### 2.6 Ícones

- Lucide pelo plugin de ícones do Tailwind: `class="i-lucide-<nome> size-4"`, sempre com `aria-hidden="true"`.
  Exemplos: `i-lucide-sparkles`, `i-lucide-undo-2`, `i-lucide-history`, `i-lucide-x`, `i-lucide-flask-conical`, `i-lucide-shield-check`.
- No `Button`, use a prop `icon="i-lucide-…"`. Em bloco grande, use o
  `Icon` de `components-next/icon/Icon.vue`.
- Spinner em linha: `i-svg-spinner size-4`. Spinner de bloco: `components-next/spinner/Spinner.vue`.
- Phosphor só no composer (`i-ph-arrow-up-bold`, `i-ph-paper-plane-right-fill`). Não espalhe para outros lugares.

### 2.7 Estados (todos obrigatórios)

| Estado | Exemplo real |
|---|---|
| Carregando lista | 3 blocos `h-20 rounded-xl bg-n-alpha-2 animate-pulse` + `sr-only` + `aria-busy="true"` (`AutomacoesPage`) |
| Carregando conversa | balões-esqueleto `rounded-2xl bg-n-alpha-2 animate-pulse` com `role="status"` (`AutonomiaGuideContainer`, `data-esqueleto`) |
| Carregando no painel | `<span class="i-svg-spinner size-4">` + frase (`GuideConversas`, `GuideFeitos`) |
| Erro | cartão `role="alert"` com frase do que fazer + `Button` "Tentar de novo" `icon="i-lucide-refresh-cw" slate faded min-h-11` (`AutomacoesPage`) |
| Vazio que ensina | título `text-base font-medium` + texto + **modelos prontos** clicáveis (`AutomacoesPage` + `AutomacaoModelos`) |
| Vazio simples | ícone `size-8 text-n-slate-9` + título + texto, centralizado (`EmailCampaignsPage`) |
| Sucesso | frase `text-n-teal-11 font-medium` no próprio cartão (`GuideExecucao`: "UNDONE") |
| Parcial / aviso | `text-n-amber-11` (`GuideExecucao`, `AutomacaoEnsaio`) |
| Feedback passageiro | `useAlert(t('…'))` de `dashboard/composables` (toast) |

Cada estado é um ramo **nomeado** (`v-if` / `v-else-if` com a condição escrita). Não
use `v-else` para um estado: o comentário em `AutonomiaGuideContainer.vue` mostra o bug
"executando" que caiu em "cancelada".

### 2.8 Controles

- **Botão:** `components-next/button/Button.vue`. Variantes `solid | outline | faded | link | ghost`,
  cores `blue | ruby | amber | slate | teal`, tamanhos `xs (h-6) | sm (h-8) | md (h-10) | lg (h-12)`.
  O `md` tem 40 px: **sempre `class="min-h-11"`** (ou `lg`). Primário: `blue` sólido.
  Secundário: `slate faded`. Destrutivo dentro de menu: `ruby ghost`.
- **Botão só com ícone:** `ghost slate lg` + `aria-label` (não basta o tooltip) — `GuideHeader.vue`.
- **Escolha única:** `components-next/choice-select/ChoiceSelect.vue` (combobox WAI-ARIA, opção de 44 px, `compact` p/ filtros). **Nunca `<select>`.**
- **Liga/desliga:** `components-next/switch/Switch.vue` dentro de `label.flex.items-center.gap-2.min-h-11` com texto "Ligada/Desligada" ao lado (`AutomacaoLinha`) — o switch sozinho tem 16 px.
- **Abas:** dentro do painel, as abas próprias de `GuideHistorico.vue` (`role="tablist"`, setas, `min-h-11`, ativa `bg-n-solid-active text-n-blue-11 shadow-sm`).
  Em página, as pílulas de `EmailCampaignsPage` (`rounded-xl px-3 min-h-11`, ativa `bg-n-blue-3 text-n-blue-11`, `aria-pressed`).
- **Selo/etiqueta:** `inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-n-iris-3 text-n-iris-11` + `i-lucide-sparkles size-3` (`AutomacaoLinha`); ou `components-next/label/Label.vue` (`slate|amber|teal|ruby|blue|iris`).
- **Faixa de aviso:** `components-next/banner/Banner.vue` (`color`, `actionLabel`, `@action`).
- **Diálogo:** `components-next/dialog/Dialog.vue` (`type="alert"` para apagar, `width="sm"`, `confirm-button-label`, `cancel-button-label`, `is-loading`) — exemplo: confirmar apagar em `GuideConversas.vue`.
- **Barra de progresso:** não há componente; padrão real em `routes/dashboard/autonomia/components/panel/PanelKnowledge.vue`: `div.w-full.h-2.overflow-hidden.rounded-full.bg-n-alpha-2` com `role="progressbar"`, `aria-valuenow/min/max`, `aria-label` e filho `h-full rounded-full transition-all` com `width` em `%`.
- **Bolinha:** `GuideDot.vue` (`bg-n-amber-9`, `ring-2 ring-n-background`, `motion-safe:animate-[ping_…_3]`, pulsa 3 vezes).

### 2.9 Texto e i18n

- Chaves em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/crm.json`, sob `AUTONOMIA_GUIDE.*`
  (Guia) e `AUTOMACOES.*`. Atualize en e pt_BR juntos.
- Tom real: "Você ainda não tem automações", "Comece por um destes modelos. O Guia
  monta com você, e nada liga sem você mandar.", "Não consegui carregar suas
  automações. Confira a internet e tente de novo.", "Dá para desfazer até {quando}".
- Checklist: frase curta, voz de pessoa ("eu", "você"), verbo no botão ("Desfazer", "Tentar de novo"),
  erro diz **o que fazer**, nada em inglês, nada de "evento/payload/webhook/job".
- Data: `Intl.DateTimeFormat(locale.value.replaceAll('_', '-'), …)` — `pt_BR` cru lança erro (`GuideExecucao.vue`).

### 2.10 Acessibilidade

- Alvo de toque ≥ 44 px: `min-h-11`, `h-11 w-11`, `!size-11`.
- Foco visível: `focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand`
  (ou `outline-n-blue-11` no composer).
- Região viva: `role="status" aria-live="polite"` para o que muda (`AutomacaoEnsaio`, `GuideComposer`).
- `sr-only` dá nome a ícone de estado (✓/✗ em `GuideExecucao`).
- Movimento: só `motion-safe:` e animação curta.

## 3. Componentes a reusar

`components-next/button/Button.vue` · `dialog/Dialog.vue` · `choice-select/ChoiceSelect.vue` ·
`switch/Switch.vue` · `label/Label.vue` · `banner/Banner.vue` · `spinner/Spinner.vue` ·
`icon/Icon.vue` · `TeleportWithDirection.vue` · `textarea/TextArea.vue` · `input/Input.vue` ·
`copilot/CopilotAssistantMessage.vue` · `copilot/CopilotLoader.vue` ·
`components/policy.vue` (portão por permissão) · do Guia: `GuideHeader`, `GuideExecucao`,
`GuideDot`, `GuideHistorico` (abas).

## 4. Anti-padrões (achados no código)

- [ ] `SidebarActionsHeader` no painel: botões de 32 px colados e nome só no tooltip (motivo do `GuideHeader`).
- [ ] `TabBar` da casa no painel: alvo de 32 px (motivo das abas próprias do `GuideHistorico`).
- [ ] `<select>` nativo (#652) — use `ChoiceSelect`.
- [ ] `Switch` sem `label` de 44 px e sem texto do estado.
- [ ] `Button` `md` sem `min-h-11`.
- [ ] Formulário em branco como única entrada: `routes/dashboard/settings/automation/AutomationRuleForm.vue`, citado no CLAUDE.md como contraexemplo.
- [ ] `v-else` cobrindo mais de um estado.
- [ ] Hex fixo, `bg-white`, `dark:` — quebram o tema escuro e a marca.
- [ ] Balão dentro da barra lateral com marca (fica transparente) — use Teleport.
- [ ] Rótulo longo vindo do manual em botão do painel — frase curta e fixa + `[&>span]:truncate`.

## 5. As três telas-alvo

### (a) Painel "O que eu sei" — `GuideMemoria.vue` (a criar)

Abre pelo `GuideHeader` (botão novo `ghost slate lg`, `icon="i-lucide-notebook-pen"` (já usado no repo), com `aria-label` e `aria-pressed`, igual ao do histórico).
Ocupa o corpo do painel no lugar da conversa, como o `GuideHistorico`.

- Topo: uma frase `text-xs text-n-slate-11` ("Isto é o que eu lembro para te ajudar"), como `HISTORY.KEPT`.
- Duas seções, cada uma com `h3.text-xs.font-medium.text-n-slate-11` ("Sobre você", "Sobre a corretora")
  e uma lista `ul.flex.flex-col.gap-1.m-0.p-0.list-none`.
- Item: copie a linha de `GuideConversas` — `li.flex.items-stretch.gap-1.rounded-lg.hover:bg-n-alpha-1`,
  texto `text-sm text-n-slate-12 break-words`, e à direita dois `Button ghost slate lg`
  (`i-lucide-pencil`, `i-lucide-trash-2`) com `aria-label` que inclui o texto do item.
- Editar no lugar: o texto vira `TextArea` + `Salvar` (`blue`, `min-h-11`) e `Cancelar` (`slate faded`). Nada de modal para editar.
- Apagar: `Dialog type="alert" width="sm"`, como em `GuideConversas`. Depois, `useAlert` com "Esqueci".
- Corretora sem permissão de admin: itens sem botões e uma linha `text-xs text-n-slate-11` dizendo quem pode mudar.
- Vazio que ensina, por seção: título `font-medium text-n-slate-12` + texto `text-n-slate-11` +
  2 ou 3 exemplos clicáveis no estilo das sugestões do painel
  (`text-left text-sm bg-n-alpha-1 hover:bg-n-alpha-2 rounded-lg px-3 py-2 min-h-11`) que mandam
  a frase para o Guia (ex.: "Me chame de Zé", "Relatório é sempre do mês corrente").
- Carregando: spinner em linha + frase. Erro: frase `text-n-ruby-11` + "Tentar de novo".
- Chip "Anotei: … · Esquecer" sob a resposta: `inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-n-iris-3 text-n-iris-11 text-xs`
  + `i-lucide-sparkles size-3`. "Esquecer" é um `Button link` com `min-h-11`.

### (b) Etiqueta "Vendo: …" acima da caixa de texto

Fica dentro do bloco `mx-3 mt-px mb-2` de `AutonomiaGuideContainer.vue`, logo acima do `GuideComposer`.
Use o mesmo desenho do anexo pendente em `GuideComposer.vue`, que já fica nesse lugar:

- `div.flex.items-center.gap-2.max-w-full.rounded-lg.border.border-n-weak.bg-n-alpha-1.ltr:pl-3.rtl:pr-3.mb-2.text-sm`;
- ícone `i-lucide-eye size-4 text-n-slate-11` (`aria-hidden`);
- texto `truncate min-w-0 text-n-slate-12`: "Vendo: 12 cards selecionados";
- × igual ao de remover anexo: `button` `h-11 w-11 shrink-0 flex items-center justify-center rounded-lg text-n-slate-11 hover:text-n-ruby-11 focus-visible:outline-2 focus-visible:outline focus-visible:outline-n-blue-11`,
  `aria-label="Perguntar sem usar o que está na tela"`, ícone `i-lucide-x`.
- Ao tirar a etiqueta, avise o leitor de tela pela região `role="status"` que o composer já tem.
- Na pergunta seguinte a etiqueta volta (PRD, AC-CT). Isso é comportamento, não visual.
- O contexto vem do `useContextoDaTela` (a criar). O composer só mostra a etiqueta.

### (c) Cartões de tarefa longa e bolinha de aviso — `GuideTarefa.vue` (a criar)

Base de todos: o cartão de `GuideExecucao.vue` (`rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2`),
título `text-xs font-medium text-n-slate-11`, ações em `div.flex.flex-wrap.items-center.gap-2`.
Um cartão, uma ação primária.

1. **Amostra:** frase grande do que vai mudar (`text-sm text-n-slate-12`). Depois, a lista de pares
   antes/depois, cada um em `rounded-lg bg-n-alpha-1 p-3` como os itens do `AutomacaoEnsaio`:
   antes `text-n-slate-11 line-through`, seta `i-lucide-arrow-down size-4`, depois
   `text-n-slate-12 font-medium`. Linha `text-xs text-n-slate-11` com custo e tempo.
   Botões: `Começar` (`blue`, `min-h-11`) e `Agora não` (`slate faded`).
2. **Pausa de segurança:** `Banner color="amber"` no topo do cartão ("Parei depois dos primeiros 25 para você conferir"),
   contagens por tabela em `ul` com `tabular-nums`, e os botões `Seguir` (`blue`) e `Cancelar` (`slate faded`).
3. **Progresso:** "120 de 512" em `text-sm font-medium tabular-nums text-n-slate-12` + barra
   `role="progressbar"` (padrão do `PanelKnowledge`) com o filho `bg-n-brand`. A cor vem de
   token: com a barra lateral de marca, a tarefa continua azul, porque o painel não fica dentro do `<aside>`.
   Ações: `Pausar` (`slate faded`, `i-lucide-pause`) e `Cancelar` (`ruby` `ghost`).
   O texto muda numa região `role="status" aria-live="polite"`, sem anunciar a cada item.
4. **Relatório:** lista ✓/✗ igual à do `GuideExecucao` (`i-lucide-check text-n-teal-11`, `i-lucide-x`, `sr-only`),
   pulados agrupados por motivo (`text-n-amber-11`), e `Desfazer tudo` (`slate faded`, `i-lucide-undo-2`)
   com a frase "Dá para desfazer até {quando}".
5. **Bolinha com número:** estender `GuideDot.vue` (hoje sem número) para receber a contagem.
   Com número, a bolinha cresce para `min-w-5 h-5 px-1 rounded-full bg-n-amber-9 text-xs font-medium tabular-nums`,
   com o mesmo `ring-2 ring-n-background`. O nome acessível vai no botão: `aria-label` do launcher
   (`AutonomiaGuideLauncher.vue` / `GuideSidebarEntry.vue`) = "Guia da Plataforma, 2 avisos novos".
   Urgente não pisca para sempre: o `ping` dura só 3 ciclos, como hoje.

## 6. Checklist antes do PR

- [ ] Uma ação primária por tela ou cartão; o avançado fica escondido.
- [ ] Os 4 estados (carregando, erro com saída, vazio que ensina, cheio) com ramos nomeados.
- [ ] Só tokens `n-*`; testado no tema claro, no escuro e com a barra lateral de marca.
- [ ] Todo alvo ≥ 44 px; foco visível; `aria-label` em botão só com ícone.
- [ ] Sem `<select>`; escolha por `ChoiceSelect`.
- [ ] en + pt_BR; nenhuma palavra em inglês ou de sistema na tela.
- [ ] O que muda algo mostra antes (amostra/ensaio) ou dá Desfazer.
- [ ] Teste do leigo: alguém que nunca viu a tela termina a tarefa sem perguntar nada.
