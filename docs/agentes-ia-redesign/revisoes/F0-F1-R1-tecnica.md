# Revisão normal F0/F1 R1 — técnica, lista real

**Data:** 2026-10-07  
**Alvo:** implementação F1 da lista real no snapshot30 congelado pelo coordenador, em
`/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`.  
**Fontes:** `design/F1.md`, PRD CA-LISTA/CA-ESC, `mockup/src/screens-list.js`,
`mockup/src/data.js`, `mockup/src/styles.css` e `mockup/src/kit.js`.  
**Escopo:** AgentsListPage, AgentRow, resumo, vazio/modelos, kit de avatar/pill/switch/banner/dialog,
API/composable e i18n. Somente leitura; não executei testes, build, navegador, banco ou produção.

## Resultado

**PARADA — há resíduos concretos antes da aprovação da rodada.** A implementação respeita o gate de
permissão, o envelope account-scoped, os estados E1–E6 e a releitura após PATCH, mas ainda diverge de
critérios visuais e de comportamento explícitos da lista.

## Achados

### F1-R1-01 — P1 — aviso fixo sobre a pausa não existe na tela real

**Prova:** o PRD exige o aviso fixo (“Pausou um agente? ... vão para a equipe na hora”)
(`PRD.md:165`, CA-LISTA-11 em `PRD.md:895`). O mockup o renderiza depois da lista
(`mockup/src/screens-list.js:66-76`). Em `AgentsListPage.vue:232-260`, o sucesso só monta resumo,
cartões e, para viewer, a linha de bloqueio; não há esse aviso nem chave equivalente de i18n.

**Efeito:** depois de pausar, a pessoa vê apenas o novo estado do cartão e não recebe a explicação
obrigatória sobre a devolução das conversas à equipe. A captura real não fecha CA-LISTA-11.

**Correção mínima:** adicionar a frase em `AGENTS.V2.*` en/pt_BR e renderizar um callout fixo no sucesso
com lista, após os cartões (e após a linha de viewer quando aplicável), sem fazê-lo aparecer no vazio,
loading ou erro.

### F1-R1-02 — P1 — o interruptor não comunica “Atendendo/Pausado”

**Prova:** `AgentRow.vue:197-203` passa tanto o texto visível quanto o `aria-label` da ação genérica
`AGENTS.V2.actions.toggle` (“Mudar status de {name}”). `LabeledSwitch.vue:13-37` renderiza esse texto
sem acrescentar o estado atual. O contrato exige interruptor Atendendo/Pausado e `aria-label` com o estado
(`PRD.md:163`, CA-LISTA-08 em `PRD.md:888-891`); o mockup calcula “Atendendo”/“Pausado” em
`mockup/src/kit.js:77-80`.

**Efeito:** o controle não deixa claro se o clique vai pausar ou religar, e o leitor de tela não recebe o
estado humano do controle. O pill ao lado não corrige o rótulo do próprio switch.

**Correção mínima:** derivar o rótulo visível e acessível do código E5/E6, com as traduções “Atendendo” e
“Pausado” e o nome do agente, mantendo `role="switch"` e `aria-checked`.

### F1-R1-03 — P1 — a confirmação de pausa do ajudante interno usa efeito de cliente externo

**Prova:** `AgentRow.vue:261-281` escolhe a mesma descrição para todo agente. A tradução em
`agents.json:682-686` só diz “As conversas novas vão direto para a equipe e as conversas atuais serão
transferidas”. O PRD exige, para ajudante interno, “O {nome} some do painel das conversas até você ligar de
novo” (`PRD.md:308-310`, CA-LISTA-08 em `PRD.md:888-891`).

**Efeito:** a confirmação promete uma transferência de conversas que o agente interno nunca atende e não
explica o efeito real no painel da equipe.

**Correção mínima:** selecionar a cópia interna quando `actuation === 'internal'`; manter a cópia de
transferência apenas para agentes externos/ambos, com chaves en/pt_BR.

### F1-R1-04 — P1 — confirmação de excluir rascunho contradiz a exclusão lógica

**Prova:** D34 exige que rascunho “sai da lista”, sem afirmar apagamento dos materiais
(`PRD.md:115,336-338`). A chave atual `AGENTS.V2.dialog.deleteDescription` diz “Isso remove o rascunho
de {name} e os materiais guardados” (`agents.json:685-686`), e `ConfirmDialog` a usa diretamente
(`AgentRow.vue:267-271`).

**Efeito:** o texto sugere perda dos materiais guardados, embora o backend preserve o rascunho arquivado,
e omite o resultado que a pessoa precisa entender: ele apenas deixa de aparecer na lista. Isso é uma
informação destrutiva incorreta na confirmação.

**Correção mínima:** usar a cópia de D34 para rascunho (“O rascunho sai da lista.”), sem mencionar
apagamento dos materiais e sem prometer uma recuperação que ainda não tem tela.

### F1-R1-05 — P1 — o menu de rascunho não fecha com Escape nem fecha antes do diálogo

**Prova:** o menu é aberto/fechado apenas por clique em `AgentRow.vue:231-257`; não há handler de
teclado para Escape. O clique em “Excluir rascunho” chama `openDialog('delete')` na linha 253, mas não
define `isMenuOpen = false`. O contrato exige `aria-haspopup="menu"`, `aria-expanded`, item de
exclusão e “Esc fecha” (CA-LISTA-10, `PRD.md:893-894`).

**Efeito:** usuário de teclado fica preso com o menu aberto; ao abrir a confirmação, o menu permanece atrás
dela e pode reaparecer depois de cancelar, quebrando a ordem/foco da ação.

**Correção mínima:** tratar Escape no botão/menu e fechar o menu antes de abrir a confirmação, preservando
`aria-expanded` e devolvendo o foco ao gatilho após fechar o diálogo.

### F1-R1-06 — P2 — o aviso de “sem canal” não tem o tratamento visual de alerta

**Prova:** o mockup usa ícone de alerta e cor âmbar para “Sem canal” (`mockup/src/screens-list.js:10-13`);
o PRD também o define como aviso âmbar (`PRD.md:156-159`). No cartão, porém, a mensagem passa por uma
única linha neutra `text-n-slate-11` e um ícone informativo fixo (`AgentRow.vue:179-183`); o ramo sem
canal em `AgentRow.vue:84-92` só monta o texto.

**Efeito:** a condição que impede o agente externo de atender parece uma informação comum, sem a hierarquia
visual que orienta a pessoa a corrigir o canal.

**Correção mínima:** devolver junto da linha um tipo de contexto/ícone; no caso sem canal aplicar o token
âmbar e `alert-triangle`, mantendo os demais contextos no tratamento neutro.

### F1-R1-07 — P2 — cabeçalho ignora a coluna de 72 rem e a escala aprovada

**Prova:** o cabeçalho real ocupa a largura inteira com `px-4 ... sm:px-6` em
`AgentsListPage.vue:134-155`; o conteúdo abaixo começa em `max-w-6xl` e padding separado em
`AgentsListPage.vue:203-205`. O mockup coloca cabeçalho, resumo e cartões dentro de
`.page { max-width:72rem; padding-inline:2rem }` e usa H1 de até 2.25 rem/subtítulo de 1.0625 rem
(`mockup/src/styles.css:62-66`). O H1 real é `text-2xl` e o subtítulo `text-sm`
(`AgentsListPage.vue:138-143`), enquanto F1 exige a mesma faixa de 72 rem em 1440 px
(`design/F1.md:158-161`).

**Efeito:** em desktop o título e o botão ficam colados às bordas do viewport, enquanto os cartões ficam
centralizados, e a hierarquia tipográfica fica menor que a referência. A página perde o alinhamento premium
entre cabeçalho e conteúdo.

**Correção mínima:** colocar o conteúdo do cabeçalho no mesmo `max-w-6xl/mx-auto` e espaçamento de 32 px
do corpo; ajustar a escala do H1/subtítulo aos tokens/tamanho da fonte aprovada, preservando a quebra em
400 px.

### F1-R1-08 — P2 — os cartões exibem uma segunda linha de métricas que não existe no mockup

**Prova:** `AgentRow.vue:185-193` renderiza `statsLine` e também `monthStatsLine` sempre que houver
qualquer número no mês. Para Clara, com semana e mês, isso mostra duas linhas. O mockup escolhe uma única
parte: semana se há respostas, senão mês, senão “Ainda sem conversas”
(`mockup/src/screens-list.js:10-18`); o PRD especifica uma linha equivalente
(`PRD.md:158-160`). O payload continuar contendo os quatro valores para o contrato ListStats não exige
mostrar os quatro simultaneamente.

**Efeito:** o cartão cresce e repete informação (“Esta semana...” e “30 dias...”), afastando ações e
divergindo da densidade aprovada em 1440/400.

**Correção mínima:** manter a prioridade de `statsLine` como única linha visual; preservar
`week/month.replies/handoffs` no payload e nos testes de projeção.

### F1-R1-09 — P2 — em 400 px o cartão quebra avatar, corpo e ações em três blocos

**Prova:** `AgentRow.vue:159-160` usa uma grade de uma coluna abaixo de `sm`; o avatar fica em uma
linha, o corpo em outra e as ações em uma terceira. A fonte aprovada usa flex-wrap: avatar e corpo
continuam juntos, e só as ações descem quando necessário (`mockup/src/styles.css:95-105`). F1 descreve no
mobile o cartão empilhando corpo e ações, não separando a identidade do corpo
(`design/F1.md:158-161`).

**Efeito:** a tela de 400 px fica mais alta e perde a leitura imediata “avatar + nome”; listas com muitos
agentes exigem rolagem excessiva e deixam a ação distante do cartão.

**Correção mínima:** preservar avatar/corpo na primeira linha em telas estreitas e ocupar a linha seguinte
com ações (por exemplo, uma grade de duas colunas com ações abrangendo as duas), sem criar CSS próprio.

### F1-R1-10 — P2 — cartões de modelo perderam a diferenciação visual da fonte

**Prova:** `AgentModelCard.vue:36-45` usa sempre tile `bg-n-teal-3` e ícone
`i-lucide-sparkles`; `AgentsEmptyHero.vue:13-34` só varia a cor do ícone. A fonte aprovada define
ícones e tons por modelo (life-buoy/teal, target/blue, concierge-bell/amber) em
`mockup/src/data.js:86-89`, tile de 3.25 rem e exemplos alinhados ao fundo em
`mockup/src/styles.css:133-142`. O PRD ainda exige quadrado colorido `size-14 rounded-2xl`
(CA-ESC-01, `PRD.md:917-918`).

**Efeito:** os três pontos de partida parecem o mesmo cartão e não ajudam uma pessoa leiga a reconhecer a
diferença entre os trabalhos; o ícone fica menor (2.5 rem) e a hierarquia dos exemplos varia entre colunas.

**Correção mínima:** passar o nome do ícone e o token de fundo por modelo, usar o tile de 3.25/3.5 rem
previsto e ancorar o exemplo no final do cartão com utilitários Tailwind.

## Pontos conferidos sem novo achado

- A porta de entrada mantém o nome de rota e o gate novo aditivo ao gate antigo; `AgentsIndexPage` escolhe
  a lista nova apenas quando a conta está marcada, mantendo o Hub legado fora desse caso.
- E2m ramifica para a rota legada; E1/E2 usam a retomada guiada; E3/E4 seguem as etapas correspondentes.
- O PATCH da lista envia somente `status/enabled` e faz GET posterior, preservando a projeção quando a
  releitura falha.
- O perfil só ver recebe “Abrir” em E1–E4 e não recebe switch/menu/escrita.
- O cartão interno não exibe métricas; o envelope e a API permanecem account-scoped.
- A cópia “liga em um canal que já existe” diverge literalmente do texto antigo do mockup, mas é coerente
  com D7/CA-GERAL-12: a conexão continua em Canais; não trato isso como defeito nesta rodada.
- Nenhuma alteração de produto foi feita; o parecer é estático e não substitui a captura real nos quatro
  tamanhos/temas e cenários do aceite.


