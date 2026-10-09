# Auditoria global — simplicidade e UX

**Data:** 2026-10-09  
**Especialista:** 02/10 — UX/UI e simplicidade
**Escopo:** área Agentes de IA, lista, criação e gestão  
**Modo:** somente leitura; nenhuma alteração de código, runtime, dados, produção, PR ou Git foi feita nesta frente.

## Conclusão executiva

A jornada principal está compreensível nas capturas reais: a pessoa consegue identificar o próximo passo na lista, na criação, no teste e na associação de uma ou mais caixas de entrada. Os textos `pt-BR` auditados têm cobertura estrutural completa em relação ao catálogo inglês (1.091 chaves em cada catálogo).

Há seis problemas objetivos de percepção que merecem correção antes de apresentar a área como pronta em telas pequenas. O mais grave é a pilha de quatro mensagens iguais `Salvo.` cobrindo o cabeçalho e as abas de Ajustes. Os demais são: carregamento sem texto visível, barra de conhecimento contraditória quando há poucos materiais, ação `Sair e continuar depois` truncada no celular, abas de gestão cortadas sem indicação clara de rolagem e o botão flutuante do Guia cobrindo controles em alguns estados móveis. Este último é um achado global do componente, embora não seja específico da jornada de agentes.

Não há P0 nesta frente. O P1 abaixo foi observado em artefato real e precisa de uma confirmação rápida com quatro salvamentos consecutivos antes de ser considerado encerrado. Os demais achados são P2, com evidência visual e de código suficiente para correção dirigida.

## Critério usado

Separei falha objetiva de preferência visual. Considerei falha objetiva quando o estado deixa de comunicar progresso, ação, contexto ou controle disponível, ou quando um elemento cobre outro. “Fácil para uma pessoa com pouca familiaridade tecnológica” foi tratado como requisito de clareza observável — uma ação principal, texto completo, estado compreensível e próximo passo identificável — e não como inferência sobre capacidade da pessoa.

## Achados

### P1 — mensagens `Salvo.` duplicadas cobrem o contexto de Ajustes

**Gatilho observado:** quatro salvamentos rápidos ou um artefato capturado após múltiplas seções terem salvo.  
**Efeito:** em desktop, quatro toasts empilhados cobrem o título, o cabeçalho e parte das abas; em 400 px, cobrem praticamente todo o topo da tela. A pessoa perde a referência de onde está e pode não enxergar a próxima ação.

**Evidência:**

- Capturas reais: `.codex/preview/agents/screenshots/gestao/source80-final/gestao-14-ajustes-identidade-fala-chromium-1440-light.png` e `gestao-14-ajustes-identidade-fala-chromium-400-light.png`.
- Salvamento emitido nas seções: `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/panel/SettingsIdentity.vue:70-73`, `SettingsInstructions.vue:111-114,160-163` e `SettingsSpeech.vue:72-75`.
- Enfileiramento sem deduplicação: `app/javascript/dashboard/components/SnackbarContainer.vue:31-45,57-71`; `useAlert` apenas emite cada mensagem em `app/javascript/dashboard/composables/index.js:17-24`.

**Correção mínima:** coalescer mensagens idênticas em uma única notificação (ou substituir a existente por outra igual) e limitar a uma mensagem `Salvo.` visível por vez. Manter a mensagem acessível e testar quatro salvamentos em sequência em 400 px e 1.440 px.

**Confiança:** média-alta. O empilhamento está comprovado nas capturas e a causa no código; falta apenas reproduzir o intervalo exato que gerou a captura.

### P2 — carregamento de desempenho não comunica o que está acontecendo

**Gatilho:** abrir a aba `Como está indo` enquanto os dados de desempenho estão carregando.  
**Efeito:** aparecem dois grandes blocos vazios. Há apenas um texto `sr-only`; visualmente, a pessoa não sabe se o painel está carregando, se está sem dados ou se travou.

**Evidência:**

- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/panel/PanelHowItsGoing.vue:315-326` renderiza dois retângulos `animate-pulse` e `aria-busy`, mas o rótulo é somente para leitor de tela.
- Capturas reais: `gestao-01-painel-abas-chromium-1440-light.png`, `gestao-01-painel-abas-chromium-400-light.png` e versões escuras em `.codex/preview/agents/screenshots/gestao/source80-final/`.

**Correção mínima:** exibir `Carregando desempenho…` junto de um skeleton identificável, ou uma mensagem equivalente no primeiro bloco, preservando `aria-busy`.

**Confiança:** alta.

### P2 — barra da base de conhecimento contradiz o contador de materiais

**Gatilho:** abrir `O que sabe` com zero ou poucos materiais.  
**Efeito:** a tela mostra, por exemplo, `0 de 30 materiais` enquanto a barra está preenchida em aproximadamente 70%; com `7 de 30`, a barra também fica em aproximadamente 75%. A pessoa recebe dois sinais incompatíveis e não sabe se precisa adicionar materiais.

**Evidência:**

- `PanelKnows.vue:43-46` usa `agent.config.knowledge_confidence` para calcular a barra.
- `PanelKnows.vue:227-254` coloca essa barra junto de `0 de 30 materiais`/`7 de 30 materiais` sob `Base de conhecimento`.
- `app/javascript/dashboard/i18n/locale/pt_BR/agents.json:295-300` rotula a área como base e contador de materiais, sem explicar que a barra é confiança.
- Capturas reais: `gestao-03b-conhecimento-vazio-chromium-400-light.png` e `gestao-02-conhecimento-estados-chromium-1440-light.png`.

**Correção mínima:** usar `count / 30` para a barra que acompanha o contador; se a intenção for mostrar confiança, separar a métrica e rotulá-la explicitamente. Com zero materiais, a barra de quantidade deve estar vazia.

**Confiança:** alta.

### P2 — ação de salvar e sair fica truncada em 400 px

**Gatilho:** abrir `Conte` ou `Ligue` no celular.  
**Efeito:** a ação de continuidade aparece como `Sair e contin...` ou `Sair e continuar de...`. É uma ação importante para retomar o agente; o texto truncado reduz a segurança de que a configuração será preservada e de que a pessoa poderá continuar depois.

**Evidência:**

- `AgentBuildTellPage.vue:71-90` e `AgentBuildGoLivePage.vue:107-126` colocam título e botão na mesma linha; `AgentTestPhone.vue:318-337` repete o padrão.
- `Button.vue:257-259` aplica `truncate` ao rótulo.
- Capturas reais: `creation54/criacao-02-conte-retomada-chromium-400-light.png`, `criacao-06-ligue-chromium-400-light.png` e `criacao-07-falha-transporte-na-publicacao-chromium-400-light.png`.

**Correção mínima:** em telas estreitas permitir que o botão ocupe uma segunda linha ou usar um rótulo curto e completo, como `Salvar e sair`, mantendo o nome acessível completo quando necessário. Revalidar 400 px e desktop.

**Confiança:** alta.

### P2 — aba ativa fica cortada no celular

**Gatilho:** abrir a gestão em 400 px, especialmente em `Onde atende`.  
**Efeito:** o conjunto de abas tem rolagem horizontal, mas a captura mostra somente `Onde a` na borda direita. A pessoa pode não reconhecer a aba, não perceber que há mais opções ou não entender que o conteúdo atual corresponde ao item cortado.

**Evidência:**

- `AgentPanelShell.vue:228-249` usa `overflow-x-auto`, `shrink-0` e texto sem uma indicação visual de rolagem.
- O código só traz a aba para a área visível em navegação por teclado (`AgentPanelShell.vue:71-78`); não há garantia equivalente ao abrir diretamente uma aba profunda em viewport estreito.
- Captura real: `gestao-08a-canais-multiplos-chromium-400-dark.png` (e estados equivalentes em `gestao-09c...400-light.png`).

**Correção mínima:** garantir que a aba ativa seja trazida para a área visível na montagem/ao trocar de rota, ou oferecer um controle compacto de abas no mobile. Preservar o foco e uma indicação de que há mais abas.

**Confiança:** média-alta.

### P2 — botão flutuante do Guia cobre controles da jornada no celular

**Gatilho:** visualizar criação ou gestão em estados com compositor, rodapé ou ações de canais.  
**Efeito:** o botão de ajuda fica sobre o compositor, o botão de envio ou ações inferiores; em canais sem permissão, encosta sobre o segundo botão `Colocar`. Isso pode interceptar o toque e torna uma ação principal parcialmente ilegível.

**Evidência:**

- O componente reconhece o risco no próprio comentário e usa posição fixa: `app/javascript/dashboard/components/autonomia/guide/AutonomiaGuideLauncher.vue:11-18,56-75` (`fixed`, `bottom-4`, `z-50`).
- Capturas reais: `creation54/criacao-04-teste-valido-chromium-400-dark.png`, `criacao-05-teste-invalidado-chromium-400-light.png`, `criacao-10-sem-canal-chromium-400-light.png` e `gestao-09c-canais-sem-permissao-chromium-400-light.png`.

**Correção mínima:** reservar uma área segura para o launcher nos estados que têm compositor/rodapé de ação, reposicioná-lo quando esses controles estão visíveis ou oferecer recolhimento persistente. Revalidar sem retirar o acesso ao Guia.

**Confiança:** média-alta. A sobreposição é visível; a interceptação efetiva do toque ainda precisa de teste interativo.

## Verificações positivas

- A lista apresenta uma ação principal clara por estado: criar, continuar, abrir, escolher onde atende ou ativar/pausar. Estados vazio, erro e confirmação de exclusão/pausa têm texto e ação identificáveis nas capturas `retomada33`.
- A criação mostra progressão, permite sair e retomar e, no estado observado, associa duas caixas de entrada existentes. `AgentBuildGoLivePage.vue` emite todos os IDs selecionados; não encontrei regressão da associação múltipla.
- A tela `Teste` comunica que a simulação é privada e apresenta legenda/estado de resposta nos artefatos de criação e gestão.
- A tela de canais mantém o WhatsApp/QR na área central de Canais; a jornada de agente associa caixas existentes. Não há QR embutido nas telas examinadas.
- Estados de erro de materiais exibem mensagem e `Tentar de novo` (`gestao-04b-conhecimento-erro-chromium-400-light.png`).
- Não encontrei `<select>` nativo nas telas examinadas; a escolha de modelo/canal usa os componentes da jornada.
- A comparação estrutural dos catálogos `en/agents.json` e `pt_BR/agents.json` encontrou 1.091 chaves em cada um, sem chave ausente ou extra.

## Cenários cobertos

Examinei, por código e pelas capturas reais disponíveis:

- lista em desktop/mobile, claro/escuro, vazio, carregando, erro, viewer e diálogos de pausa/exclusão;
- criação em `Escolha`, `Conte`, `Teste` válido/inválido, `Ligue`, sem canal, erro de transporte e seleção de múltiplas caixas;
- gestão em `Como está indo`, `O que sabe` vazio/com materiais/erro, adicionar/remover material, FAQ, `Onde atende` com múltiplos canais e sem permissão, `Teste` viewer, `Ajustes` em agente cliente/interno/cotação;
- estados mobile de 400 px e desktop de 1.440 px, nos temas claro e escuro onde havia artefato;
- código dos componentes de lista, criação, painel, abas, configurações, composer, Guia, alertas e catálogos.

## Lacunas e controle da próxima rodada

Esta auditoria não substitui teste com pessoa real, leitor de tela, toque em dispositivo ou prova de backend/frontend. A porta de criação `59720` estava indisponível no momento; a criação foi avaliada pelas capturas reais `creation54`. Também não foi possível reproduzir o intervalo dos quatro toasts nem verificar interativamente se o launcher intercepta o toque.

Depois das correções, a revisão deve ser uma única rodada delimitada nos seguintes cenários: (1) quatro salvamentos rápidos em Ajustes; (2) zero e sete materiais; (3) abertura direta de `Onde atende` em 400 px; (4) carregamento inicial de desempenho; (5) criação com `Salvar e sair`; (6) teste com compositor e `Ligue` sem canal; (7) canais sem permissão. Em cada caso, conferir 400/1.440 px, claro/escuro, texto completo, foco/teclado e ausência de sobreposição. Se algum achado voltar nessa rodada, parar a revisão mecânica, registrar a causa raiz e retornar apenas com a correção dessa causa; não abrir uma nova sequência de ajustes cosméticos.

## Arquivos e fontes consultados

- `docs/agentes-ia-redesign/HANDOFF-CODEX.md`
- `docs/agentes-ia-redesign/PRD.md` (comportamentos de lista, criação, teste, ligação e gestão)
- `docs/audit/2026-10-05-agentes-prd-r2-causa-raiz.md`
- `app/javascript/dashboard/routes/dashboard/autonomia/agentes/` (páginas e componentes citados acima)
- `app/javascript/dashboard/i18n/locale/en/agents.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/agents.json`
- `.codex/preview/agents/screenshots/creation54/`
- `.codex/preview/agents/screenshots/gestao/source80-final/`
- `.codex/preview/agents/screenshots/retomada33/`
