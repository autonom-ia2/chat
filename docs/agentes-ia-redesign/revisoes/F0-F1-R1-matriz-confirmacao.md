# Matriz de confirmação limitada — F1/R1

**Data:** 2026-10-07  
**Escopo:** confirmação dos dez achados `F1-R1-01..10` do parecer técnico da lista e dos dois achados `F0-F1-R1-ROTAS-01..02`.  
**Método:** definir a menor prova necessária para cada achado. Nada abaixo foi executado ou aprovado; esta matriz não reabre a revisão geral.

Os dois gaps de cobertura dos controles D9 do parecer de produto (`F0-F1-R1-01..02`) continuam identificados no relatório próprio e não são renumerados nesta matriz.

| Achado | Confirmação mínima | Prova de API/teste | Navegador real |
|---|---|---|---|
| `F1-R1-01` aviso de pausa ausente | Sucesso com agente pausado mostra o callout; vazio, carregando e erro não mostram. | Spec da lista para os quatro estados e catálogo en/pt_BR. | **Sim**, para presença, posição e quebra em 400 px. |
| `F1-R1-02` switch sem “Atendendo/Pausado” | E5 e E6 exibem estado humano no controle, com `role=switch`, `aria-checked` e nome do agente. | Spec real de `AgentSwitch` e `AgentRow`, incluindo payload/status e bloqueio durante mutação. | **Sim**, para texto, alvo e leitura visual; sem endpoint novo. |
| `F1-R1-03` cópia errada para ajudante interno | Pausa de agente interno mostra o efeito no painel; externo/ambos mantêm a transferência de conversas. | Spec de seleção por `actuation` e chaves en/pt_BR; PATCH existente continua enviando somente status/enabled. | **Sim**, para confirmação real e cópia localizada. |
| `F1-R1-04` exclusão de rascunho promete apagar materiais | Confirmação diz apenas que o rascunho sai da lista, sem prometer apagar materiais. | Spec do diálogo e trace PATCH/DELETE + GET/reload que demonstre a projeção arquivada e materiais preservados, conforme contrato. | **Sim**, para texto e resultado percebido após confirmar. |
| `F1-R1-05` menu não fecha com Escape/antes do diálogo | Escape fecha o menu; “Excluir” fecha o menu antes do diálogo e o foco volta ao gatilho ao cancelar/fechar. | Teste de teclado e ciclo menu → diálogo → retorno, com `aria-expanded`; não depende de API nova. | **Sim**, para foco e ordem de camadas. |
| `F1-R1-06` “Sem canal” sem alerta âmbar | E1/E2 sem canal mostram ícone e token âmbar; outros avisos permanecem neutros. | Spec do ramo sem canal + asserções de nome acessível/semântica do alerta. | **Sim**, para contraste, ícone e hierarquia visual. |
| `F1-R1-07` cabeçalho fora da coluna de 72 rem | H1, subtítulo, ação, resumo e cartões compartilham a coluna aprovada; escala permanece legível em 1440/400. | Checagem de classes/estrutura e screenshot automatizado; API não participa. | **Sim**, em 1440 e 400 px, claro e escuro. |
| `F1-R1-08` duas linhas de métricas | Cada cartão exibe uma única linha pela prioridade semana → mês → sem conversas, sem perder os quatro valores do payload. | Spec da projeção com semana/mês e estados vazios; fixture conserva `week/month.replies/handoffs`. | **Sim**, para densidade e quebra em 400 px. |
| `F1-R1-09` cartão quebra avatar e corpo em blocos | Em 400 px avatar e identidade permanecem juntos; ações descem como bloco próprio sem overflow. | Teste/asserção de layout pode detectar estrutura, mas não substitui captura; API não participa. | **Sim**, obrigatório em 400 px e conferência em 1440. |
| `F1-R1-10` cartões de modelo iguais | Os três modelos preservam ícone, cor, tamanho e exemplos distintos da fonte aprovada. | Spec de props/modelo e catálogo; API não participa. | **Sim**, nos quatro estados de viewport/tema usados no aceite. |
| `F0-F1-R1-ROTAS-01` retomada lê BE-05 duas vezes | Cartão E1/E2 → rota e deep link têm um único dono da hidratação; `start` nunca é disparado nessa retomada. | Teste de integração contando GET account-scoped, verificando thread/IDs e ausência de POST/start; 401/404 preservam aviso localizado. | **Sim**, para o percurso real cartão → painel; a duplicidade é provada pelo teste/trace. |
| `F0-F1-R1-ROTAS-02` Sidebar perde estado ativo | O item “Meus agentes” permanece ativo em index, builder, build, ready, panel e na decisão documentada para a rota legada. | Teste de resolução/guards e matriz de nomes de rota na mesma conta/flag; não editar registry gerado manualmente. | **Sim**, para confirmar o destaque na navegação em cada rota. |

## Regra de leitura

Cada linha permanece **pendente** até sua prova correspondente existir. Screenshot do mockup, inspeção estática ou teste unitário isolado não substitui o navegador real quando a coluna assim exige; navegador real também não substitui o teste de escopo, contagem de chamadas ou persistência. Qualquer falha na checagem limitada encerra a rodada conforme o critério do handoff.
