# Issue #480 — UI/UX do gráfico temporal de campanhas

Data: 2026-09-19.

## Escopo

Ajuste de frontend/QA da Gestão de Campanhas. Sem alteração de backend, banco, migrations, reputação, regras de envio ou flags.

## Implementação

- card específico `CampaignTimelineChart.vue`;
- KPIs de Entregas/Aberturas/Cliques acima do gráfico;
- seletor segmentado Por dia / Por hora com componentes/tokens Chatwoot;
- números sobrepostos em cada ponto removidos;
- tooltip nativo do `@chatwoot/viz` preservado e agrupando as três séries;
- todos os buckets reais preservados;
- eixo X reduzido visualmente por stride, sem remover dados;
- visão horária validada com 24 pontos;
- tooltip ampliado localmente para evitar truncamento de rótulos;
- `LineChart.vue` ganhou opções opt-in, mantendo os defaults antigos para os demais consumidores.

## Gates executados antes da integração com main

- focused frontend: 16/16;
- fixtures QA: 10/10;
- helpers browser: 11/11;
- Vite build real: aprovado;
- Chromium isolado: 215 checks, 0 falhas, 150 screenshots;
- console errors: 0;
- page errors: 0;
- external requests: 0;
- missing translations: 0.

## Visual review

Revisão independente: PASS_WITH_POLISH, sem P1/P2. Daily desktop, hourly desktop, dark e RTL aprovados. O único P3 identificado foi truncamento do primeiro rótulo do tooltip; corrigido depois do review. A captura mobile correta do gráfico horário tem 342x648 e inclui o card completo.

## Regras de produto verificadas

- nenhum nome AWS/SES/provedor de infraestrutura exposto ao cliente;
- Direct Inbox mantém a semântica de aceitação pelo serviço, sem alegar confirmação do servidor destinatário;
- alternar Por dia/Por hora não agrega nem descarta buckets do payload;
- a redução do eixo X afeta apenas rótulos visíveis;
- outros consumidores do LineChart mantêm os defaults existentes.

## Pendente antes de aprovação final

Após rebase na main atual: repetir gates de frontend/build/browser e CI da PR.
