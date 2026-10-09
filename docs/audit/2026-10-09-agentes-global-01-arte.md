# Auditoria global — direção de arte e QA visual

**Data:** 2026-10-09  
**Especialista:** 01/10 — direção de arte e QA visual  
**Escopo:** lista, gestão, criação, painel, temas, responsividade, compositor e fronteira de Canais  
**Modo:** somente leitura. Não alterei produto, specs, runtime, banco, snapshots, Git, PR, fila, deploy ou produção.

## Fonte e método

Usei a fonte80 da aplicação no worktree `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`, branch `docs/agentes-ia-prd`, HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`. O manifesto
`.codex/preview/agents/screenshots/gestao/source80-final/manifest.json` registra 196 PNG originais, correspondentes a 49 estados em 1.440/400 px e claro/escuro. O manifesto local do mockup em `.codex/preview/gestao56-refs/manifest.json` registra 72 entradas e 40 referências visuais vinculadas. A página e os critérios comparados foram `docs/agentes-ia-redesign/mockup/jornada.html` e PRD §11.6.

O subconjunto efetivamente visto foi representativo e está nomeado abaixo: lista `retomada35/screenshots/lista-real-chromium-1440-light.png` e `lista-real-chromium-400-dark.png`; gestão `gestao-01-painel-abas` (1.440/400, claro/escuro), `gestao-02-conhecimento-estados` (1.440, claro/escuro), `gestao-03b-conhecimento-vazio` (400 claro), `gestao-04a-conhecimento-carregando` (400 claro), `gestao-08a-canais-multiplos` (1.440/400 claro), `gestao-09c-canais-sem-permissao` (400 claro/escuro), `gestao-11a-interno-teste` (1.440 claro), `gestao-14-ajustes-identidade-fala` (1.440/400 claro), `gestao-20-teste-imagem-metadados` (400 claro/escuro), `gestao-23a`, `23c`, `23f` e `23h` (400); compositor `composer54/composer-mobile-light-row.png` e `composer-desktop-light-row.png`; criação `creation54/criacao-05-teste-invalidado-chromium-400-light.png`, `criacao-06-ligue-chromium-400-light.png` e `criacao-06-ligue-chromium-1440-light.png`. As referências correspondentes do mockup que vi incluem `gestao56-refs/ajustes-normal-light-1440.png`, `conhecimento-estados-light-1440.png`, `canais-normal-light-1440.png` e `f4refs/m2-output/painel-clara-carregando-light-1440.png`.

As capturas `creation54` são históricas, com proveniência nos snapshots 53/54 em `.codex/preview/check54/capture-provenance.json`; a porta de criação não estava disponível nesta auditoria. Portanto, não afirmo navegação nova da criação. Também não tratei as etiquetas de tempo no topo de algumas capturas de `retomada35` como parte do produto: são overlay de medição da captura.

## Veredito delimitado

A direção geral está coerente com o padrão Chat2You: títulos, cartões, estados, abas, ações principais e tema escuro mantêm uma hierarquia legível; a lista e a gestão não exibem QR ou cadastro de WhatsApp; e o compositor observado tem os controles alinhados. A comparação com o mockup preserva a estrutura essencial. A barra de protótipo, o mapa de telas e o seletor de perfil ausentes no produto são diferenças intencionais previstas pelo PRD §6.4.

Este parecer não aprova o gate visual global. Há quatro problemas P2 observáveis em capturas atuais da gestão, além de dois riscos que exigem reconferência limitada na criação/compositor. Não observei P0 neste subconjunto; isso não significa ausência universal. O empilhamento de quatro mensagens `Salvo.` é visualmente real, mas não pode ser homologado como P1 do redesign sem separar evento transitório e baseline global.

## Achados

### ART-01 — P2 — barra de conhecimento mistura confiança com quantidade

**Gatilho:** abrir `O que sabe` com nenhum ou poucos materiais.

**Efeito:** `gestao-03b-conhecimento-vazio-chromium-400-light.png` mostra `0 de 30 materiais` com a barra preenchida em cerca de 70%. `gestao-02-conhecimento-estados-chromium-1440-light.png` e a variante escura mostram `7 de 30 materiais` com praticamente o mesmo preenchimento. A pessoa não consegue saber se a barra representa capacidade ocupada ou qualidade da base.

**Causa e caminho:** `PanelKnows.vue:43-46` calcula `knowledgeConfidence` a partir de `agent.config.knowledge_confidence`; `PanelKnows.vue:227-251` exibe o contador de materiais na mesma faixa e usa `knowledgeConfidence` para `aria-valuenow` e largura do preenchimento. O mockup explicita a diferença: `conhecimento-estados-light-1440.png` mostra `7 de 30` separado de `71% · boa` e o helper `mockup/src/kit.js:90-94` rotula a métrica.

**Correção mínima:** escolher uma só semântica para a barra que acompanha o contador (`count / 30`) ou exibir a confiança como métrica separada e rotulada, seguindo o padrão do mockup. Não deixar a largura sem explicação.

**Confiança:** alta; o conflito está no PNG e no código atual.

### ART-02 — P2 — abas de gestão ficam cortadas em 400 px

**Gatilho:** abrir uma aba profunda, especialmente `Onde atende`, em viewport de 400 px.

**Efeito:** `gestao-01-painel-abas-chromium-400-light.png`/`-dark.png`, `gestao-08a-canais-multiplos-chromium-400-light.png` e `gestao-09c-canais-sem-permissao-chromium-400-light.png` mostram `Onde a` na borda direita. O texto da aba ativa fica incompleto e não há indicação visível de que o conjunto continua horizontalmente.

**Causa e caminho:** `AgentPanelShell.vue:228-248` usa `overflow-x-auto`, botões `shrink-0` e rótulos sem quebra. O `scrollIntoView` está no caminho de teclado (`AgentPanelShell.vue:71-78`); as capturas não provam o mesmo ajuste ao abrir a rota diretamente.

**Correção mínima:** levar a aba ativa para a área visível ao montar/trocar a rota, ou usar um controle compacto de abas no celular, preservando foco e teclado.

**Confiança:** alta para o corte; média para a frequência fora dos estados capturados.

### ART-03 — P2 — carregamento de desempenho não tem sinal visível

**Gatilho:** abrir `Como está indo` enquanto a análise ainda carrega.

**Efeito:** `gestao-01-painel-abas-chromium-1440-light.png`/`-dark.png` mostra dois grandes blocos vazios; `gestao-01-painel-abas-chromium-400-light.png` mostra os mesmos blocos sem texto. No estado de materiais, `gestao-04a-conhecimento-carregando-chromium-400-light.png` deixa apenas o spinner. Visualmente, a pessoa não distingue carregamento, vazio e travamento.

**Causa e caminho:** `PanelHowItsGoing.vue:315-325` mantém `aria-busy` e um `span.sr-only`, mas nenhum rótulo visível acompanha o skeleton.

**Comparação com o mockup:** `f4refs/m2-output/painel-clara-carregando-light-1440.png` também usa skeleton sem rótulo visível. Portanto, isto é uma lacuna de clareza da experiência, não uma divergência estrutural do padrão aprovado. Se o requisito de produto aceitar skeleton silencioso, reclassificar como decisão visual; se a tela precisa ensinar o estado para uma pessoa leiga, manter P2.

**Correção mínima:** acrescentar `Carregando desempenho…`/`Carregando materiais…` visível, sem remover `aria-busy`.

**Confiança:** alta para a ausência visual; média para a severidade, porque o mockup repete o padrão silencioso.

### ART-04 — P2 candidato — `Sair e continuar depois` truncado no celular

**Gatilho:** abrir `Teste`, `Conte` ou `Ligue` em 400 px.

**Efeito:** nas capturas históricas `creation54/criacao-05-teste-invalidado-chromium-400-light.png` e `creation54/criacao-06-ligue-chromium-400-light.png`, a ação aparece como `Sair e continuar de...`/`Sair e co...`. É possível tocar no botão, mas a frase da ação de preservar e retomar a montagem fica incompleta.

**Causa e caminho:** `AgentBuildTellPage.vue`, `AgentBuildGoLivePage.vue` e `AgentTestPhone.vue:318-337` colocam título e botão numa linha `justify-between`; `Button.vue:257-259` aplica `truncate` ao rótulo. O catálogo pt-BR mantém a frase completa em `app/javascript/dashboard/i18n/locale/pt_BR/agents.json:1338`.

**Limite da evidência:** estas imagens são snapshots 53/54 e não uma navegação nova desta auditoria. O código presente mantém o padrão de truncamento, mas não atribuo a captura à fonte80 sem uma reexecução da criação.

**Correção mínima:** permitir segunda linha para a ação em 400 px ou usar um rótulo curto e completo, por exemplo `Salvar e sair`, conservando o nome acessível completo.

**Confiança:** alta para o corte histórico e média para a permanência na fonte atual.

### ART-05 — P2 — Guia cobre controles no celular

**Gatilho:** deixar o launcher do Guia visível junto ao compositor ou às ações inferiores de canais.

**Efeito:** `creation54/criacao-05-teste-invalidado-chromium-400-light.png` mostra a bolinha do Guia sobre a área do botão de envio do compositor; `gestao-09c-canais-sem-permissao-chromium-400-light.png` e a variante escura mostram o launcher sobre a região de `Colocar`. A captura prova sobreposição; não prova sozinha que todo toque seja interceptado.

**Causa e caminho:** `AutonomiaGuideLauncher.vue:57-72` fixa o botão em `right-4 bottom-4 z-50`. O deslocamento especial só considera `isFixedPanelOpen`; não há reserva de área para o compositor nem para as ações de canais. O comentário do componente reconhece o risco, mas a posição permanece sobre o conteúdo.

**Correção mínima:** reservar área segura ou reposicionar/recolher o launcher quando compositor, rodapé ou ações de canais estiverem presentes. Revalidar em 400 px claro/escuro e testar o toque no controle que fica atrás.

**Confiança:** alta para a sobreposição visual; média para a interceptação efetiva.

### ART-06 — P1 candidato global — quatro `Salvo.` sobre o cabeçalho, ainda não homologado

**Gatilho observado:** `gestao-14-ajustes-identidade-fala-chromium-1440-light.png` e `gestao-14-ajustes-identidade-fala-chromium-400-light.png` contêm quatro mensagens `Salvo.` empilhadas sobre o cabeçalho e as abas. `gestao-16-ajustes-manual-guiado-chromium-1440-light.png` contém duas mensagens durante outro estado de Ajustes.

**Efeito:** quando essa pilha está visível, perde-se a referência do agente e da aba atual. O efeito seria P1 se quatro salvamentos válidos dentro da janela de exibição fossem reproduzíveis em uma ação normal.

**Causa aparente:** `SnackbarContainer.vue:31-45` faz `push` sem deduplicar, remove cada item após `duration`, e o padrão é 2.500 ms (`SnackbarContainer.vue:8-11`). A posição é fixa no topo (`SnackbarContainer.vue:57-61`).

**Baseline e severidade:** não classifiquei como P1 confirmado do redesign. `git diff -- app/javascript/dashboard/components/SnackbarContainer.vue` não mostra mudança; `git show HEAD:app/javascript/dashboard/components/SnackbarContainer.vue` tem o mesmo enfileiramento e a mesma duração. O componente é compartilhado e preexistente. A captura demonstra o estado visual, mas não informa o intervalo entre eventos nem o relógio no momento da imagem.

**Fechamento necessário:** reproduzir quatro salvamentos consecutivos com o intervalo registrado, verificar a permanência de cada toast por 2.500 ms e comparar a mesma ação no baseline anterior. Se for o mesmo comportamento global, abrir a correção como dívida compartilhada; se a fonte atual introduzir a pilha ou uma ação normal produzir quatro eventos, corrigir/deduplicar antes do gate. Até lá: P1 candidato, não aprovação nem reprovação definitiva.

**Confiança:** alta para a imagem e para a leitura do componente; baixa para atribuição ao lote e para a severidade P1.

## O que passou no subconjunto

- **Hierarquia e espaçamento:** `lista-real-chromium-1440-light.png` e `lista-real-chromium-400-dark.png` mantêm título, contadores, cartões de estado e ação principal em ordem compreensível. `gestao-01` e `gestao-11a` apresentam cabeçalho, abas, conteúdo e painel de leitura sem desalinhamento evidente.
- **Compositor:** `composer-mobile-light-row.png`, `composer-desktop-light-row.png`, `gestao-11a-interno-teste-chromium-1440-light.png` e `gestao-20-teste-imagem-metadados-chromium-400-light.png` mostram ícone de anexo, campo e botão de envio no mesmo eixo. Não encontrei botão cortado ou diferença de centro que justificasse achado visual neste subconjunto.
- **Temas:** os pares claro/escuro de `gestao-02`, `gestao-09c`, `gestao-20` e `gestao-23f` preservam a hierarquia de superfície, texto, estado e alerta. Não observei contraste visual evidentemente quebrado ou componente ilegível; isso não substitui axe, leitor de tela ou teste de toque.
- **Padrões do mockup:** abas e ordem de gestão, cartões de materiais, escolha única e resumo permanecem reconhecíveis. O protótipo tem barra de protótipo, mapa, seletor de perfil e barra de estado; esses elementos foram corretamente omitidos do produto conforme PRD §6.4.
- **WhatsApp e caixas:** `gestao-08a-canais-multiplos-chromium-1440-light.png` afirma na própria tela que números de WhatsApp e QR Codes são conectados em Canais. `creation54/criacao-06-ligue-chromium-1440-light.png` mostra a seleção de duas caixas existentes e instrução para abrir Canais para criar conexão. Não vi QR, token ou cadastro de WhatsApp em Agentes.
- **Diferenças de preferência:** a largura menor dos cartões de gestão, opções de rádio verticais em algumas telas reais e diferenças de cor/ícone do shell em relação ao mockup não foram marcadas como bug isolado: não produziram corte, perda de ação ou ambiguidade além dos achados acima. Se a exigência for paridade geométrica pixel a pixel, Rodrigo precisa decidir isso como direção de arte, pois o PRD fixa o contrato estrutural e as divergências autorizadas, não cada medida do shell.

## Lacunas e próxima verificação limitada

1. Repetir somente a matriz dos achados: zero e sete materiais; abertura direta de `Onde atende` em 400 px; carregamento de desempenho; `Sair e continuar depois` na fonte atual em 400 px; compositor e `Ligue` sem canal; canais sem permissão.
2. Para o Guia, clicar no controle que fica atrás em claro/escuro e confirmar ou refutar interceptação.
3. Para `Salvo.`, medir quatro salvamentos, os intervalos e os 2.500 ms, e comparar baseline antes de atribuir P1 ao redesign.
4. Depois de qualquer ajuste, recapturar somente os estados afetados nos quatro perfis relevantes. Não declarar zero regressão a partir deste subconjunto.

Não houve navegador pessoal, acesso a produção, banco, CI, merge, deploy, PR ou alteração de implementação. Este é um parecer visual delimitado pelas capturas locais e pela leitura estática citada; encerra-se aqui sem exploração indefinida.
