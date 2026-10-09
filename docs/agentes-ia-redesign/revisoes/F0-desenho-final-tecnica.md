# F0 — revisão técnica final do desenho

**Estado: STOP — não aprovado.** A revisão final encontrou um residual concreto na origem do fluxo de conexão. Conforme o protocolo registrado na causa raiz, não há nova correção nem nova rodada: o achado deve retornar ao Rodrigo.

**Alvo revisado:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`  
SHA-256: `38649eb14b909eae5628b82ac2275f88858cc2d291b4c8eaa3df1eddca9f8755` (250 linhas).

**Registro de decisões conferido:** `docs/audit/2026-10-07-agentes-f0-desenho-decisoes.md`  
SHA-256: `5b336f4aa5fb1e55d2052d9c373c2a0cd204d22e4d73c01f275edb48a56142b2`.

**Referência de código:** baseline fixo `6242e31695fd1c6b8b088f2fcb819c027fc5083c`; ele não é uma afirmação sobre o `origin/main` atual. A revisão foi estática, confrontando o F0, a causa raiz/checagem anterior, o PRD, as rotas e o mockup. Não houve teste, build, navegador, M2, banco, produção, autenticação real, merge, fila ou deploy.

## Resultado dos cinco residuais anteriores

| Residual | Resultado |
|---|---|
| path/query e representação de origem | **Residual final — F0-FINAL-01 abaixo.** |
| leitor escopado da thread | Fechado no desenho: B3/BE-05, conta/agente, última thread `guided`, 401/404/422, hidratação antes de `PanelTune` e proibição de `start` (`F0-mapeamento.md:24,142,148,168,241`). |
| inventário D4 | Fechado no desenho: 18 usos em 12 caminhos do dashboard, busca case-insensitive e exceção pública nomeada (`F0-mapeamento.md:99-116,243`). A conferência estática encontrou os 18 usos. |
| duplicata de locale | Fechado no desenho: 15 consumidores produtivos enumerados, `CampaignOverviewPage` migra obrigatoriamente e a cópia é removida (`F0-mapeamento.md:56-65,244`). |
| ownership do foco | Fechado no desenho: SidePanel concentra abertura/fechamento, Escape, scroll, gatilho, foco inicial e restauração; o composable fica limitado ao trap Tab/Shift+Tab (`F0-mapeamento.md:67-71,245`). |

## F0-FINAL-01 — P1 — origem válida de Ligue não está representada

**Prova no contrato:** o PRD define a origem do BE-13 como as rotas **Ligue** e **Onde atende** (`docs/agentes-ia-redesign/PRD.md:526`). A jornada aprovada coloca “Conectar um WhatsApp novo” em ambos: `mockup/src/screens-build.js:198` na etapa Ligue e `mockup/src/screens-panel.js:163` na aba Onde atende. No mapa de rotas, essas superfícies são distintas: `autonomia_agent_build` com `step=live` (`F0-mapeamento.md:132`) e `autonomia_agent_panel` com `tab=channels` (`F0-mapeamento.md:134`).

**Defeito no desenho final:** `F0-mapeamento.md:145` fixa o único helper de `from` em `RouteLocationRaw` nomeado exclusivamente `autonomia_agent_panel`, com `tab = channels`. O texto não define redirecionamento prévio de Ligue para esse painel, nem uma representação que preserve `autonomia_agent_build`/`live`. Portanto, um clique iniciado em Ligue precisa sair como se tivesse vindo de Onde atende; depois da conexão, o retorno exigido “à origem” (`PRD.md:323-327`) não é preservado.

**Risco:** a implementação pode passar as provas de URL estática, allowlist e conjunto de canais e ainda quebrar a jornada real: a pessoa que pediu a conexão dentro de Ligue volta para outra tela, perde o contexto da etapa ou recebe o retorno em uma aba que não corresponde ao ponto de partida.

**Correção mínima para o autor:** fechar no F0 uma única política verificável para as duas origens: aceitar e validar as duas rotas nomeadas (`autonomia_agent_build`/`live` e `autonomia_agent_panel`/`channels`) preservando a origem, ou declarar e implementar antes da conexão um redirecionamento explícito que explique por que a origem é substituída e como o retorno mantém etapa, agente e canais. A matriz de specs deve provar os dois percursos, inclusive sucesso e retorno. Não aceitar um helper que só encode `autonomia_agent_panel` enquanto Ligue tiver CTA próprio.

## Conclusão e bloqueio

O achado acima é final e está dentro do residual de rota/origem; não é uma sugestão de implementação. O F0 permanece `DRAFT — não aprovado`. Paro aqui conforme o protocolo: não corrigir o desenho, não iniciar código/telas reais e devolver a decisão ao Rodrigo. Merge, fila, deploy e produção continuam sem autorização.
