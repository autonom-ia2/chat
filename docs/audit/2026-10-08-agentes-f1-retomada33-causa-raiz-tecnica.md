# F1 — retomada33: causa raiz dos failures Axe

**Data:** 2026-10-08  
**Execução:** `retomada33`, matriz Playwright real F1  
**Evidência:** `.codex/preview/agents/screenshots/retomada33/playwright-f1.log` e os `error-context.md` da mesma pasta

## Resultado observado

A matriz carregou 28 casos: 8 passaram, 17 falharam e 3 foram pulados de forma
intencional. A execução terminou com código 1. Os 17 failures são explicados
por três causas técnicas, repetidas em tamanhos, temas e estados; não são 17
defeitos independentes.

## Causas

### R33-01 — botão mobile global sem nome acessível

**Evidência:** Axe `button-name` com impacto `critical`, alvo
`.\\!rounded-full`, HTML do botão sem texto, `aria-label` ou `title`. O mesmo
botão aparece nos seis cenários de 400 px claros e nos seis escuros que foram
executados. O snapshot aponta o elemento global do shell, e não um botão da
lista F1.

**Fonte:** `app/javascript/dashboard/components-next/sidebar/MobileSidebarLauncher.vue:48-56`,
onde o `Button` usa apenas `icon="i-lucide-menu"` e não informa estado nem nome
acessível.

**Classificação:** defeito preexistente do shell, exposto porque a retomada
executou a tela real em 400 px. Ele precisa ser corrigido para que a aceitação
do F1 não carregue uma violação crítica do ambiente que contém a tela.

**Correção mínima proposta:** reutilizar as chaves existentes
`HELP_CENTER.EDIT_HEADER.OPEN_SIDEBAR` e
`HELP_CENTER.EDIT_HEADER.CLOSE_SIDEBAR`, aplicando o texto ao `aria-label` e
`isMobileSidebarOpen` a `aria-expanded`. Não alterar o comportamento de toggle.

### R33-02 — CTA azul claro no tema escuro usa texto branco

**Evidência:** Axe `color-contrast` com impacto `serious`, foreground
`#ffffff`, background efetivo `#7eb6ff` (`n-blue-11` no tema escuro), razão
`2.09:1` para um mínimo de `4.5:1`. O problema aparece nos botões de criar,
continuar/conectar e confirmar quando o tema escuro é executado.

**Fontes F1:**

- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentsListPage.vue:138`;
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentRow.vue:252`;
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentsEmptyHero.vue:72`;
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/ConfirmDialog.vue:45-48`.

Todos usam `bg-n-blue-11` com `text-white` sem uma variante escura. É uma
regressão introduzida pelo kit F1, não um problema do contrato de dados.

**Correção mínima proposta:** preservar `bg-n-blue-11` e `text-white` no tema
claro e acrescentar apenas `dark:text-n-navy` nesses CTAs; preservar os hovers
existentes.

### R33-03 — textos secundários do hero usam tokens escuros sobre navy

**Evidência:** nos cenários escuros do vazio, Axe aponta `color-contrast` nos
textos do hero. `text-n-blue-3` e `text-n-slate-3` resolvem para cores escuras
(aproximadamente `#0f2748` e `#212225`) sobre `bg-n-navy`, sem contraste
suficiente. Isso inclui o eyebrow, a descrição e a mensagem para viewer.

**Fonte:** `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/AgentsEmptyHero.vue:54,65,79`.

É uma regressão de tokens do redesign; o H1 branco não está nessa causa.

**Correção mínima proposta:** usar `text-white/90` nos três textos, preservando
`bg-n-navy`, o H1 e a hierarquia visual. Não criar CSS global nem novas cores.

## Limites

Não executei nova matriz, build, teste pesado, banco ou produção após a falha.
Este RCA antecede a correção restrita autorizada para R33. A validação seguinte
deve ser única; qualquer failure residual encerra a rodada.
