# F0/F1 — candidatos para confirmação limitada da R1

**Data:** 2026-10-07  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Escopo:** registrar o estado da única R1 normal e os próximos comprovantes mínimos, sem reabrir a revisão.

## Estado comprovado

- A R1 normal única está dividida em três pareceres: 10 achados comportamentais/visuais da lista, 2 achados de rotas/foco e 2 lacunas de cobertura dos controles D9. A correção foi tratada em um bloco; a confirmação limitada ainda não foi executada.
- A execução oficial de formatos no lote 28 passou. Isso cobre a verificação do gerado oficial naquele lote, não o aceite das telas.
- No snapshot30, a integração JavaScript registrou 33 arquivos e 199 testes verdes, exit 0, com as réplicas verificadas antes/depois. Essa prova é distinta da R1 e não a aprova.
- A captura real da primeira tela teve falhas de Axe; o Axe permanece no bloco normal de correção única. Nenhuma captura real foi aceita.

## Candidatos e prova mínima

| Candidato | Prova limitada necessária | Camada que decide |
|---|---|---|
| `F1-R1-01..10` | Casos focados da lista para cópia, estados, menu, switch, métricas, modelos e responsividade; depois cenários reais em 1440/400 px, claro/escuro. | Testes/componentes para contrato; navegador real para a tela. |
| `F0-F1-R1-ROTAS-01` | Montagem lista → rota com `resume` account/agente corretos, uma chamada, zero `start`; 401/404 voltam à lista com aviso localizado. | Spec de integração e, depois, percurso real no navegador. |
| `F0-F1-R1-ROTAS-02` | Resolução dos nomes de rota e estado ativo da Sidebar em cada destino, incluindo a decisão para a rota legada. | Teste de router/guards e navegador real para o destaque visual. |
| `F0-F1-R1-01..02` do parecer de produto | Adaptadores reais de etapas em en/pt_BR e `AgentSwitch` real com E5/E6, ARIA e bloqueio da mutação. | Specs dos componentes; navegador se o aceite visual alterar. |
| Axe da primeira captura | Reexecutar Axe no app real após a correção única, sem desativar regras e sem tratar o mockup como produto. | Navegador Playwright isolado; resultado ainda pendente. |

## Limite

Nenhum candidato é GREEN ou aprovado neste registro. Teste unitário, snapshot JavaScript, formatos do Guia ou screenshot isolado não substituem a captura real exigida pelo aceite. Se a confirmação limitada encontrar erro, aplica-se a parada, causa raiz e limite de uma rodada definidos no handoff. Não houve CI novo, merge, fila, deploy ou produção.
