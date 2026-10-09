# B1 — revisão normal independente de frontend/produto

Lente root, que não escreveu a correção de frontend B1-COD-06. Alvo: os seis arquivos JS/Vue e os catálogos de Registro de atividades, dentro do inventário de 47 arquivos com fingerprint `7aaa8c39a9a8a0980fed0c838f9492964664e1192b8ce546efd8d1962c71e119`. Método: leitura do código, contrato BE-31, store, guardas de conta e specs existentes; não é aceite no navegador.

## B1-UI-01 — P2 — filtro ativo aparece como “Todos” quando o catálogo não contém o agente

**Prova:** `AuditLogFilters.vue` resolve `selectedAgent` apenas em `props.agents`. O item “todos” recebe `isSelected: !selectedAgent.value`; o rótulo do botão vem desse item selecionado. Em `Index.vue`, a consulta usa `filters.agent_id` independentemente do catálogo. Uma URL salva com `agent_id=42` continua filtrada por 42, mas se o agente foi arquivado, o catálogo falhou ou o gate do produto está desligado, o botão passa a dizer que todos estão selecionados. O catálogo vem de `AgentsController#index`/`agents_scope`, limitado aos agentes mantidos; a auditoria permanece como histórico.

**Causa:** o estado do filtro está sendo inferido pela disponibilidade do nome no catálogo, em vez do parâmetro ativo que determina a consulta.

**Efeito:** a pessoa lê “Todos” e recebe somente parte do histórico, sem perceber a restrição. Limpar o filtro ou recarregar uma URL salva não tem uma indicação fiel da condição aplicada.

**Correção mínima:** o item “todos” só está selecionado quando não existe `agentId` ativo. Se há ID ativo sem nome no catálogo, apresentar uma opção/rótulo localizado com o ID, mantendo a consulta e a opção de limpar. Não criar endpoint de agentes arquivados nem ampliar permissões. Cobrir o filtro com catálogo vazio/ID ativo e a transição para catálogo carregado; a página já prova catálogos humano/IA distintos.

## Pontos conferidos

- A página usa o catálogo de IA no filtro e preserva o catálogo humano para as atividades existentes.
- O handler distingue uma ou várias chaves e usa `actor.name`/`username`; a linha exibe resumos old/new e não despeja JSON bruto.
- Telefones já chegam mascarados pelo contrato do backend; texto e listas sensíveis recebem somente os resumos tipados previstos.
- O wrapper de Settings usa chave de caminho e o Dashboard usa versão da conta; não foi encontrado caminho que prove a hipótese de reaproveitamento da página sem remount entre contas. Não adicionada guarda especulativa.
- A tela não foi aberta no navegador nesta revisão. Os resultados anteriores de Vitest/build não comprovam aceite visual.

Esta é a única revisão normal desta lente para B1. Corrigir o bloco consolidado de todas as lentes e então realizar a checagem limitada; nenhuma implementação, fila, merge, deploy ou produção é autorizada por este relatório.
