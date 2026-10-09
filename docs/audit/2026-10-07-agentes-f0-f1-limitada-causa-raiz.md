# F0/F1 — parada da confirmação limitada e causa raiz

## Estado antes de corrigir

Snapshot31 `d974cedd1b5a1df30148ac5712f7ce1ff8d376b366fa23966f27b72a53577e5c`, duas réplicas verificadas antes da execução. A única confirmação limitada identificou resíduos de cobertura dos dois achados D9; não aprova a entrega. Produto não será ampliado para F2. Uma correção da causa e uma passagem final são permitidas pela regra do Rodrigo; erro nessa final exige parar e retornar.

## Resíduos e causas

1. **R1-01: matriz en/pt_BR e evento go incompleta.** O implementador transformou a recomendação em casos pt_BR, sem uma tabela de cada combinação obrigatória. O coordenador conferiu nomes dos arquivos, não cada assertiva pedida no parecer. Correção da causa: dois adaptadores × dois idiomas × rótulos/ARIA/índice go, explícitos nos próprios specs; o revisor final confere essa tabela, sem nova revisão geral.
2. **R1-02: wrapper real, consumidor ainda com stub.** O spec novo de AgentSwitch foi considerado suficiente, mas o parecer também exigia AgentRow real em E5/E6 e busy. Correção da causa: montar o cartão com interruptor real, confirmar pausa antes do payload, religação com payload exato e bloqueio durante busy. Preservar o teste genérico e as assertivas existentes.
3. **Spec de foco falhou na execução31.** Job `m2-35ee8c50a7304a20961de02b7039ca69`: 38 arquivos/219 testes, 218 passaram e um falhou, sem outro erro externo reportado. AgentRow estava montado fora do documento, então focus() não podia alterar document.activeElement. Correção da causa: attachTo document.body nos casos de foco e desmontagem automática; nenhuma asserção de foco removida. O navegador real permanece obrigatório para confirmar o efeito no produto.
4. **Import D9 do loader foi anexado ao fim.** Patch com contexto vazio inseriu o import após a função. A formatação não move imports, e o coordenador não releu a posição antes de congelar. Lint31 `m2-90c84883e1d2489198aee79c39900f02`: 106 arquivos, uma infração `no-use-before-define` nesse import e 847 avisos, predominantemente resolução de catálogo legado/dinâmico; não alegar lint sem avisos. JSON SHA-256 `9a901bcd9e2cba4ee17ca74c2a355b8ea145e85677a5ec80bc220974fba951c9`. Correção da causa: mover a importação para o topo; lint final precisa conferir o arquivo tocado. A mudança de idioma mantém a proteção contra resposta atrasada e as assertivas de document.lang em pt-BR/es/en.

## Limite e provas restantes

5. **Navegador31: título do documento vazio.** Job `m2-e3cd4eda06b5434cba4c02c9531e9cd8` encerrou no primeiro cenário: somente `document-title` serious, os cinco grupos Axe anteriores não reapareceram nessa página. O HTML e routes/index.js leem INSTALLATION_NAME; o banco sintético veio de schema:load e não recebeu a configuração de instalação. A rodada normal parou antes de enxergar essa configuração faltante. Correção da causa: preparar no seed local somente o nome de instalação pelo contrato oficial; não inventar fallback no produto nem excluir regra Axe. Os demais 27 casos não executaram; não afirmar matriz completa.
6. **R1-02 visual: nome do agente também aparecia no rótulo visível do switch.** Captura31 mostra “Pausado: Pausado”, porque o mesmo texto foi passado a label e ariaLabel. A correção pediu status visível e nome acessível, mas os testes verificavam apenas existência. Correção da causa: label recebe só Atendendo/Pausado; ariaLabel mantém status+nome. Spec verifica os dois separadamente; confirmação final lê a captura.

Captura real da falha31: `.codex/preview/agents/screenshots/limited31-1440-light.png`, SHA-256 `f4bf7a71eee6fad9f7f07c6159387cc98e4f866a9c342704413cec628a62b7c3`; bytes conferidos e imagem lida pelo coordenador, ainda não aceita.

Linter e navegador do snapshot31 ainda em conferência para fechar a mesma confirmação limitada. Qualquer resíduo encontrado será registrado aqui antes da respectiva correção, dentro de um único bloco final; nenhum teste é relaxado nem regra Axe excluída. Depois desse bloco, um novo snapshot e uma única passagem final. Sem commit, push, PR de implementação, merge, fila, deploy ou produção.
