# Revisão de prontidão — PR #840

Data: 02/10/2026. Revisão somente leitura do produto; sem merge, deploy, escrita em banco ou acesso a dados de clientes.

## Veredito

Complemento posterior desta revisão: [testes executados em Firefox, Safari real e WebKit](2026-10-02-840-cross-browser-review.md). As matrizes finais do zoom passaram; esse relatório complementa a limitação de navegador registrada abaixo e mantém separado o achado de login.

Sem defeito bloqueante encontrado na revisão do código. Tecnicamente apto a integrar um lote de release, com evidência de interação específica em Chromium. Não equivale a homologação em Safari/Firefox ou confirmação do estado atual de produção.

Commit revisado: `9b60773a7cdba194f4bcd8323bb4fa1117753b25`. Base atual remota e ancestral: `43901a40c2eb6ef43cf3e5052c297879e0abdbd4`. PR aberto, não draft, MERGEABLE/CLEAN. Oito check runs SUCCESS, incluindo duas execuções do fluxo Guia; nenhum review formal registrado na API consultada.

## Evidência verificada nesta revisão

- `gh pr view 840 --json ...`, `gh api repos/autonom-ia2/chat/pulls/840/reviews` e `/comments`: SHA, arquivos, checks, ausência de review formal e conflitos.
- `git fetch origin main feat/839-kanban-zoom`, `git merge-base origin/main HEAD`, `git diff --check origin/main...HEAD`: base atual incluída e diff sem erros de whitespace.
- `gh run view 37023327394 --json headSha,event,conclusion,jobs`: execução vinculada ao SHA final; testes, lint, traduções, build Vite e harness aprovados.
- Leitura do log remoto do job `110891777929`: 652 arquivos e 7.423 testes passaram, sem falhas. Testes específicos: página 27, componente 16, preferência 82 e auto-scroll 32. Não são somados à suíte completa.
- Inspeção de componente, composables, helpers, integração da página, helper LocalStorage, Popover compartilhado, specs, scripts locais e árvore enterprise. Não há override relacionado encontrado em enterprise. Permissões, API e recuperação de movimento permanecem no fluxo existente.
- Leitura das matrizes JSON versionadas e dos scripts que as produzem; captura versionada de 87% inspecionada. Os resultados de navegador são evidência fornecida pelo PR, não reexecução nesta revisão. O harness remoto é de e-mail e não comprova por si só o drag-and-drop do Kanban.
- Nenhuma dependência, API, migration ou configuração de infraestrutura alterada pelo diff de produto. Scripts de QA restritos a host/banco local sintético.

Não foram reexecutados testes locais nem navegador nesta revisão: a nova worktree não contém dependências instaladas. Foi usada a saída real dos testes remotos no commit exato, além da inspeção do código e da evidência versionada de QA.

## Condições operacionais e limitações

1. `deploy-autonomia-blue-green.yml` e `deploy-hub2you-blue-green.yml` disparam em push na main para estes arquivos. Portanto, merge direto deste PR inicia publicação nas duas stacks; não é uma etapa operacional isolada.
2. `docs/processo-de-release.md` exige código em lote de release. O PR está com base main; a preparação do lote e sua validação integrada devem preceder a publicação, salvo instrução explícita do Rodrigo que altere esse procedimento.
3. Chromium tem matrizes específicas de mouse/toque e persistência. Firefox não iniciou e WebKit teve erros de módulos na execução reportada: não há homologação aceita desses motores. Isso é uma lacuna, não prova de defeito.
4. Antes da publicação, identificar a versão/instância anterior e confirmar que o rollback blue-green está disponível nas duas stacks. Após publicação, smoke com registros de teste autorizados: 70/87/130%, recarga, arraste entre etapas, última coluna, Lista/Calendário e painéis sem escala. Rollback pelo workflow existente com action=rollback; sem rollback de banco específico desta feature.

`gh run list` mostrou os últimos deploys de ambas as stacks concluídos com success no SHA `eda6f1f22fd5e90573f3cd6b10b06b10c9d0fe6b`. Isso confirma o resultado dos workflows consultados, não substitui inspeção atual das instâncias/imagens. Não havia release PR aberto na listagem consultada.

Revisão concluída. Autorização explícita para merge/publicação permanece pendente. Este relatório local não foi commitado nem publicado no GitHub.
