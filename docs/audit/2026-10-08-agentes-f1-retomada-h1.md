# F1 — retomada autorizada do H1 e matriz visual

Rodrigo autorizou “pode retomar” depois da parada final32. Escopo: corrigir a causa conhecida do título do estado vazio e validar a primeira tela nos cenários locais. Não libera F2, merge, fila, deploy ou produção.

Aplicado somente `text-white` diretamente ao H1 de `AgentsEmptyHero.vue`, para vencer a regra direta de headings de `_base.scss`; nenhuma alteração no stylesheet global. O erro e sua causa permanecem documentados no audit final32.

Harness preserva Axe, overflow, alvo mínimo e contratos de API. Capturas antes do Axe permitem observar estados mesmo quando a validação falha; lower-list agora rola até Clara, no fim real da lista. A matriz completa usa quatro projetos (1440/400, claro/escuro), sete grupos cada. Três repetições do caso de escrita são dispensadas explicitamente: pausa/religação/exclusão local executam uma vez em desktop/claro. Runner usa max-failures=0 nessa execução única para reunir a evidência restante, retries continuam zero.

Snapshot, execução e capturas ainda pendentes. Não considerar a suíte histórica224 como prova dessa matriz. Nenhum novo commit/push/PR de implementação, merge, fila, deploy ou produção.
