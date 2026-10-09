# Relatório das correções da auditoria global — 09/10/2026

**Estado final deste bloco: código revisado; release não liberado.** G01–G06 foram implementados. O mesmo revisor aprovou a R2 para código e evidência JavaScript, sem novo P0–P2. RSpec final e novas telas reais continuam pendentes por incompatibilidade do ambiente de validação. Não há garantia universal de zero regressão em produção.

Issue #1164, épica #1114. Branch `docs/agentes-ia-prd`, worktree `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`, HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`. Rodrigo autorizou este bloco com orquestração dinâmica e relatório final. HEAD identifica a base: a implementação ainda é working tree, sem commit próprio. O núcleo G01–G06 tem vinte arquivos de produto/specs/locales diferentes da fonte80; a nova especificação preparatória de QA está separada; manifesto `input-final.json`, SHA do conjunto `8973a6594b53c8d76586bd71042873d775175d5c2d4872e7862e9c73664315a2`.

## O que foi corrigido

| Item | Resultado | Evidência e limite |
|---|---|---|
| G01 — apresentação no Teste | PATCH aceito reinicia conversa, apaga retry antigo e pede nova tentativa; PATCH falho conserva a conversa e o teste válido. | Composable, componente e página cobertos na bateria JS. Saudação/histórico em navegador ainda exigem execução local. |
| G02 — entrada e retomada | Teste/Ligue não dependem de BuildThread; só Conte retoma conversa. Canais não bloqueiam Conte/Teste. Falhas recuperáveis mantêm etapa/agente e retry, sem criar thread artificial. | Specs de página e integração usando a rota nova; leitura do próprio agente com acesso negado/inexistente continua respeitando autorização. |
| G03 — Ligue | Uma caixa elegível começa marcada, pode ser desmarcada; várias caixas continuam com seleção múltipla. | Variantes de uma/várias/ocupadas e atualização da lista nos specs. Conexão e QR continuam em Canais. |
| G04 — O que sabe | Confiança do backend aparece como percentual/qualidade, separada do contador de materiais. | Traduções en/pt-BR, aria-label e teste do estado71%. Não há cálculo de confiança pela quantidade de fontes. |
| G05 — celular | Aba ativa fica visível ao abrir diretamente e ao mudar rota, preservando foco e teclado. | Mount/routechange/teclado nos specs; geometria real e PNG móvel ainda pendentes. |
| G06 — gate Ruby | Registrado cenário determinístico de skip_test_tool via Playground e ferramenta assíncrona de teste. | Scanner e Answerer preservados; sintaxe aprovada. RSpec final ainda não executado. |

O alinhamento do compositor de Teste e a seleção de múltiplas caixas já aceitos pelo Rodrigo foram preservados. Aceite anterior F5–F7 permanece válido; somente estados alterados precisam de novas capturas/aceite. As seis alegações retiradas na auditoria não geraram correções. Candidatos adicionais (limpar conversa, material assíncrono, fechamento,409,limite30,Guia/toasts/legado) não foram transformados em mudanças especulativas.

## Orquestração e revisão

Três frentes de implementação com ownership separado: criação/retomada/Ligue; clareza visual/abas; gate Ruby. Depois: especialista de ambiente MacCluster, QA de jornada/capturas e revisor independente. As dez lentes da auditoria global anterior não foram repetidas.

- R1 encontrou um P1 de cobertura: `AgentsContinue.integration.spec.js` ainda montava a página antiga e aceitava o retorno à lista. Foi migrado para `AgentCreationPage`, mantendo compatibilidade explícita E2m, viewer e novos casos E3/E4. Não era prova de defeito remanescente do produto novo.
- Mesmo revisor: **R2 aprovada para código e JavaScript**, sem novo achado P0–P2. Relatórios `2026-10-09-agentes-global-correcoes-r1.md` e `...-r2.md`. Não houve R3/R4.
- Regressões foram escritas antes das correções pelos implementadores. Não houve uma execução RED integral congelada deste bloco: não alegar TDD plenamente comprovado. A falha Ruby global histórica é evidência anterior separada.
- Conferidos invariantes: isolamentos/permissões, sem publicar sem teste no caminho novo, nenhuma conexão WhatsApp no builder, multicaixas, sem alterações de runtime do atendimento.

## Verificações realmente executadas

| Verificação | Resultado atual | Recibo |
|---|---|---|
| JavaScript após correção R1 | **227 testes,40 arquivos,0 falhas**,11,78s | `.codex/preview/global-correcoes-20261009/frontend-r2.log` |
| ESLint dos16 arquivos JS/Vue do primeiro conjunto | **0 erros,159 avisos** | `eslint-final.log`; avisos não são zero e não foram apagados |
| ESLint do spec de integração atualizado | **0 erros,0 avisos**, depois de nó resfriar e formatação corrigida | `eslint-r2-integration-verified.log` |
| Traduções do fork |13 catálogos,21.238 mensagens compiladas; chaves/parâmetros en/pt-BR cobertos | `frontend-checks.log` |
| Guia |196 fluxos,189 telas,0 sem explicação; gerado em dia | `frontend-checks.log` |
| Build | Compilação Vite passou em40,90s; saída local `public/vite-test` | `frontend-checks.log`; comando combinado saiu1 por um erro de formatação corrigido depois, não por build |
| Sintaxe Ruby do gate | `Syntax OK` | `ruby-syntax.log`; não é RSpec |
| Whitespace Git | `git diff --check` aprovado | Execução local final |
| CI GitHub | Não executado; não há PR novo | Não declarar CI verde |
| RSpec e navegador finais | **Não executados**, ambiente recusado pelo planner | Bloqueio abaixo |

A primeira execução JS teve duas falhas nos novos asserts (identidade de objeto reativo e texto localizado); corrigidas e reexecutadas. Um erro Prettier foi corrigido de forma pontual; lint reexecutado. O spec de integração atualizado teve29 erros de formatação: Prettier aplicado só nesse arquivo, diff inteiro lido, lint0/0 e seus8 testes reexecutados com0falhas em2,53s. Esses8 já pertencem aos227, não somar. São resultados de validação, não rodadas adicionais de revisão. Logs/resultados/hashes sob `.codex/preview/global-correcoes-20261009/`.

## Bloqueio confirmado e próxima ação

M4 é o nó da worktree. M2 está disponível por Thunderbolt; energia/keep-awake estavam saudáveis. Os snapshots79/80 desta entrega têm manifesto `version:1`, sem `content_algorithm`. O CLI atual exige `version:2` e `sha256-workspace-v2`; `work plan`/`workspace verify` recusam79 com `legacy-workspace-checksum-requires-review`. A réplica79 M4 está ausente;80 permanece preservada. O snapshot antigo intacto funciona apenas no CLI antigo; copiar as correções mudaria seu checksum e ele deixaria de ser válido também.

Inspeção do CLI: não há migrate/repin/allow-legacy. `workspace prepare` não converte; `snapshot --name` cria sempre um ID novo, não atualiza79. Nenhum snapshot v2 equivalente com o mesmo HEAD estava disponível no M2. Não foram alterados markers à mão, contornados gates ou criadas novas cópias por rodada. A regra `/Users/rodrigosilva/dev/AGENTS.md` de09/10 manda reaproveitar a cópia da entrega; mudanças de infraestrutura exigem autorização explícita. Limpeza continua no outro chat.

**Para encerrar a validação:** disponibilizar migração/reuso oficial v1→v2 (ou resolver uma exceção concreta de snapshot compatível), aplicar os20 inputs com hashes, executar o gate Ruby e a bateria pertinente, depois rodar QA em APIs reais/banco sintético, desktop1440/celular400, claro/escuro. O plano e o spec de QA estão separados e ainda não são prova de execução: sintaxe TypeScript passou, typecheck ficou sem dependências e Playwright/PNGs não executaram. F1/GESTAO usam processos e manifestos separados. O preparo não exige apagar seeds, bancos ou screenshots anteriores. Depois mostrar ao Rodrigo somente estados afetados e registrar o novo aceite visual. Não reiniciar dez auditorias nem revogar aceite anterior.

Nenhuma migration de aplicação, commit, push, PR, fila, merge, deploy, SQL/produção, dado de cliente ou provedor pago neste bloco. Automação coordena fila e deploy; só “pode enfileirar” autoriza `gh pr merge --match-head-commit <SHA>`, sem push após pedir vaga. Ao preparar PRs, separar backend/frontend/runtime pelo PRD§10.1 e validar integração dos overlaps com main; a branch antiga inteira não é um pacote de release.

Project3 atualizado com R2/227 testes e a próxima ação de reuso compatível. Item continua em Ajustes, pois runtime/aceite visual do que mudou permanecem pendentes. Recibo `project-update-result.json`.
