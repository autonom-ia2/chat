# Correção focada da retomada 38 — navegação e Central de Ajuda

Data: 2026-10-08  
Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
Branch: `docs/agentes-ia-prd`

Este registro cobre somente os dois pontos atribuídos a r9_produto após a
parada da conferência 38. Não reabre a revisão do bloco F2+F3 e não declara a
entrega aprovada.

## 1. Saída de Conte → lista

### Causa raiz

O produto já chama `router.push({ name: 'autonomia_agents_index', ... })` em
`app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.vue:120-124`.
O teste em `AgentCreationPage.spec.js` usava `router.isReady()` logo depois do
clique. Esse método aguarda apenas a navegação inicial do router; não aguarda
a navegação disparada pelo clique. A falha era uma sincronização incompleta do
teste, não uma ausência de rota ou de ação no produto.

### Correção

`app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.spec.js:239-242`
agora registra `router.afterEach`, dispara o clique e aguarda a conclusão da
navegação antes de verificar `autonomia_agents_index`. A asserção continua
comportamental e mantém a verificação da rota final.

Validação direcionada:

```text
node_modules/.bin/vitest run \
  app/javascript/dashboard/routes/dashboard/autonomia/agentes/pages/AgentCreationPage.spec.js \
  --no-watch --no-cache --no-coverage
```

Resultado: 1 arquivo, 5 testes, 5 aprovados, exit 0. Permaneceram somente os
avisos já emitidos pelo ambiente (Browserslist e registro duplicado de
componente do Vue I18n).

## 2. Cobertura da Central de Ajuda

### Causa raiz

As três rotas existiam no roteador, mas não estavam associadas ao catálogo de
rotas da Central. Por isso o verificador não conseguia encontrar uma explicação
para elas, embora já houvesse artigos adequados e blocos correspondentes no
Guia:

- `autonomia_agent_build` está em
  `autonomia.routes.js:131-141` e representa a retomada de uma construção;
- `autonomia_agent_ready` está em `autonomia.routes.js:143-152` e representa o
  resultado após a configuração;
- `autonomia_agent_panel_legacy` está em `autonomia.routes.js:154-165` e
  representa o painel legado com suas abas.

### Correção mínima

Em `docs/central-de-ajuda/mapa-de-artigos.json`, as rotas foram associadas aos
artigos existentes, sem criar artigo artificial e sem editar arquivos gerados:

- artigo `11.05` — **Fechar a construção e revisar o agente** →
  `autonomia_agent_build`;
- artigo `11.06` — **Publicar um agente externo ou interno** →
  `autonomia_agent_ready`;
- artigo `11.07` — **O painel do agente: abas e estados** →
  `autonomia_agent_panel_legacy`.

Essas associações complementam as rotas canônicas já cobertas pelos mesmos
artigos. O texto dos artigos já explica a jornada em linguagem operacional
simples e aponta que a conexão de WhatsApp acontece em Configurações → Caixas
de entrada.

Validação oficial:

```text
node scripts/central-de-ajuda/conferir.mjs
```

Resultado: exit 0 — `Central em dia: 184 artigos, 189 telas cobertas.` O
verificador emitiu avisos de evidências antigas já existentes, sem falha de
cobertura. `git diff --check` e o parse do JSON também passaram.

## Limites

Estas correções não resolvem as duas falhas Ruby, as 39 ocorrências do
RuboCop, a defasagem do catálogo de formatos, nem substituem build, navegador,
aceite visual, CI, PR, merge, deploy ou produção. Nenhuma migration foi criada.
