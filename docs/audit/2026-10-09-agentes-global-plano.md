# Auditoria global do redesign Agentes de IA — plano de execução

Rodrigo aprovou visualmente F5–F7 em 09/10 e, antes de qualquer PR, pediu explicitamente dez especialistas independentes para auditar tudo que foi alterado. Esta é uma nova auditoria global autorizada, não uma quarta rodada automática de F5–F7. A preparação do PR fica suspensa até a consolidação.

Worktree única: `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`; branch `docs/agentes-ia-prd`; HEAD inicial `532a5b7beb56902d2a0168013a3e8b657ba31488`. Épica #1114; blocos relacionados #1160 e #1164. Nenhuma alteração de implementação, fixture, runtime, banco ou Git nesta auditoria. Cada especialista escreve somente o relatório que lhe foi atribuído. O coordenador integra evidências e registro; preserva mudanças alheias e snapshots.

## Distribuição

| Especialista | Escopo | Evidência exigida | Superfície de escrita |
|---|---|---|---|
| 01 | Direção de arte e QA visual | Capturas originais vistas, comparação com mockup em quatro variantes | Relatório 01 |
| 02 | UX/UI e simplicidade | Textos/ações reais, próxima ação compreensível, estados e carga de decisão | Relatório 02 |
| 03 | Linha de base e escopo | SHA main atual e evidência de release, inventário tracked/untracked e alterações compartilhadas | Relatório 03 |
| 04 | Jornada de criação e retomada | Escolha → Conte → Teste → Ligue → Pronto, sair/voltar/erros, múltiplas caixas | Relatório 04 |
| 05 | Jornada de gestão | Lista → painel → ensinar/testar/ajustar/pausar/religar/excluir, interno/both/cotação | Relatório 05 |
| 06 | Contratos frontend/backend na criação | Rotas, parâmetros, DTOs, estados assíncronos, validação e persistência | Relatório 06 |
| 07 | Contratos frontend/backend na gestão | Materiais/FAQ, canais, ferramentas, cotação, versões, resultados e conversas | Relatório 07 |
| 08 | Runtime e agentes já ativos | Caminho de resposta, contexto, ferramentas, encaminhamento, espelhos, jobs e legado | Relatório 08 |
| 09 | Segurança e compatibilidade | Conta/caixa/perfil, flag desligada, API/Guia, Enterprise e componentes compartilhados | Relatório 09 |
| 10 | QA de cobertura e consistência | O que os testes realmente provam, correspondência entre fonte/capturas/recibos e lacunas de regressão | Relatório 10 |

Executar em grupos respeitando os quatro slots disponíveis, sem diminuir a classe de modelo. Leitura pode ocorrer em paralelo; serviços e testes pesados, quando necessários, ficam sob coordenação do root e regras MacCluster. Não abrir navegador pessoal. Preferir capturas originais e navegação isolada. Não duplicar testes nem jobs sem objetivo concreto.

## Critério de conclusão

Cada relatório deve conter fonte e arquivos conferidos, veredito por escopo, cenários efetivamente cobertos, achados P0–P3 com gatilho/efeito/causa/evidência/proposta, confiança e limitações. Falta de acesso é BLOQUEADO, não aprovação. Testes antigos são evidência histórica até conferir suas entradas contra a fonte atual. Main, CI e metadados de release não substituem prova do runtime de produção.

Consolidar achados duplicados por causa, cruzar frontend/backend e distinguir defeito introduzido, comportamento anterior, alteração intencional aprovada e lacuna de evidência. Não afirmar ausência universal de regressão. Achado relevante impede declaração de pronto e é devolvido com plano concreto; não corrigir produto enquanto auditores revisam a fonte.

Sem commit, push, novo PR, fila, merge, deploy, produção, consulta de banco de cliente, secrets ou limpeza. As duas leituras SQL antigas não autorizam novas consultas. Automação continua coordenando fila/deploy.

## Ocorrências de execução

- O terminal padrão do Codex falhou com `Too many open files (os error 24)`; acesso de leitura pela ferramenta Local Terminal funciona. Nenhum serviço foi encerrado.
- O agente 01 falhou duas vezes antes de produzir parecer: `Fatal error: application network permission was revoked`. Isso é falha da execução, não achado do produto nem aprovação visual. As demais frentes continuam em andamento; status será consolidado sem ocultar o bloqueio.

## Linha de base obtida pelo coordenador

A ferramenta Local Terminal permitiu as leituras Git/GitHub mesmo com a falha do terminal padrão. Inventário de 518 caminhos; comparação SHA-256 dos 367 arquivos fora de docs com fonte80, sem diferenças. Main atual e último deploy registrado: `28e1e0ac8b3835577f7469368f03a86d1a8dab0d`. GitHub deployments 6943966962 (Hub2You) e 6943966912 (Autonom.ia), ambos success, workflows 37826925422/37826925413. Sem inspeção direta de runtime. HEAD está 136 commits atrás; 16 caminhos do candidato se sobrepõem a mudanças da main. Recibos: inventory.json, working-vs-source80.json, comparison-main.json, main-drift.json, github-baseline.json e deployment-*.json em .codex/preview/global-audit-20261009.

O primeiro relatório do especialista03 foi incompleto por erro de processo e contém referências de caminho/bloco que exigem retificação; não será tratado como aprovação independente. O coordenador providenciou a evidência faltante e fará rechecagem independente disponível. Falhas de execução não serão classificadas como P1 de produto.

## Encerramento

As dez frentes entregaram pareceres, incluindo recuperação01 e retificações03/06/07/09. Auditoria concluída com pendências; produto congelado, pacote não aprovado para PR. Consolidação final:2026-10-09-agentes-global-consolidado.md. Não repetir auditoria geral: próximo bloco é correção localizada dos achados comprovados/provas dirigidas, seguido do protocolo de revisão do Rodrigo e telas afetadas antes de subir. Freeze final367inputs sem diferença/diffcheck0. Nova bateria2344/1falha/3pending, sem prova de atendimento quebrado. Aceite visualF5–F7 preservado, produção não tocada.
