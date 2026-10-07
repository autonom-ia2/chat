# Retomada de Agentes de IA — 07/10/2026

## Escopo e autorização

- Épica: https://github.com/autonom-ia2/chat/issues/1114.
- Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`.
- Branch: `docs/agentes-ia-prd`; nó local confirmado por `maccluster node`: M4.
- Rodrigo respondeu “ok. Vamos seguir” às recomendações D1–D35 e ao critério proposto para a rodada 9. Aprovação do plano não é aprovação de merge, deploy, acesso/alteração de produção, banco, auth ou secrets.
- Exige ver todas as telas reais e a jornada em vários cenários antes de subir; protótipo não prova produto implementado.
- Orquestração com subagentes autorizada. Primeira revisão; achados na seguinte exigem parada e causa raiz; após correção da causa, uma revisão final. Persistindo achados, parar e retornar ao Rodrigo.
- Automação do Claude Code coordena fila e deploys. Entregar ao Rodrigo: número do PR, seu OK específico, CI verde no último commit e migration. Somente após “pode enfileirar” cabe `gh pr merge` com `--match-head-commit <SHA>`; depois de pedir vaga, nenhum push. Após deploy autorizado e validação, entregar “ok, SHA”.

## Leituras e conferências

- Lidos integralmente: HANDOFF-CODEX.md, AGENTS.md do checkout e /Users/rodrigosilva/dev/AGENTS.md, audit de causas C1–C15.
- Lidas as seções indicadas do PRD: §0, §4, §5, §6 (incluindo §6.6), §7.0, §10 e §11.7–§11.8.
- `git branch --show-current`: branch indicada. `git status --short`: sem alterações no início.
- `git fetch origin main`: referência atualizada; origin/main = `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Não foi mesclada na branch de documentação.
- Épica criada e Project Autonom.ia Dev preenchido: Hub2You, Investigando, Feature, P1, Alto, Local.
- Connector de Project indisponível (HTTP 404); fallback gh executado com retorno 0 nos sete campos.

## Limite da evidência visual

- Tentativa de abrir mockup local na ferramenta de navegador: `file://` bloqueado pela política de URL, com proibição explícita de contorno por outros caminhos/superfícies.
- Alternativa mais segura: cópia HTTPS já publicada, indicada no handoff. https://claude.ai/artifact/NdjZdAnt8uhTa4P2VziyGM mostra “Faça login para ver esta página”.
- Solicitado ao Rodrigo entrar no Claude nessa aba. Nenhuma credencial solicitada ou lida.
- Não há capturas PNG/JPG/WebP preexistentes em docs/agentes-ia-redesign.
- Após Rodrigo concluir login (“pronto”), a cópia HTTPS ficou acessível. Percorridas as 41 entradas de Todas as telas via controles visíveis e inspecionadas capturas das telas principais em desktop/escuro; não há prova de equivalência byte a byte entre o artefato publicado e o HTML local.
- Jornada demonstrativa completa: Escolha → quatro respostas de Conte → Teste, avanço bloqueado até resposta concluída → canal livre → Ligar → Pronto. Dados e efeitos são simulados pelo protótipo; nenhum agente real foi ligado.
- Usada Ver esta tela como no WhatsApp: número inválido, esperando leitura, código vencido, sessão desligada e conectado. Conferidos perfis no mapa, painéis Clara/Lia, materiais, ferramentas e seções inferiores de Ajustes.
- Conferidas também lista e Conte no protótipo a 400 px/escuro: lista sem overflow horizontal (clientWidth = scrollWidth = 400); viewport restaurada. Tema claro e matriz completa ainda pendentes. Não houve aceite das telas reais nem aprovação visual nova do Rodrigo. Telas de produto ainda não implementadas; checklist permanece desmarcado.
- Na inspeção visual não houve ação em produção. Depois, somente as duas consultas SQL expressamente autorizadas foram executadas; os recibos estão abaixo. Não houve merge, fila, deploy ou implementação.

## Subagentes

- conferencia_backend: conferência factual no código origin/main e pré-requisitos B1, somente leitura.
- jornada_cenarios: inventário estático e autoria restrita de aceite-telas-reais.md, com cenários, afirmações binárias e matriz visual; não executou aceite.
- registrar_decisoes: atualização de documentação de decisões, aprovação visual e protocolo de revisão; ownership restrito aos arquivos de PRD/handoff/gerador.

## Próximas evidências

Protótipo inspecionado. Registro pré-R9 e rodada independente nas quatro lentes em preparação. O backend B1 requer desenho e duas leituras de produção autorizadas antes do código (§11.7 Antes do B1 e Q12a); leituras concluídas conforme recibos abaixo. Cenários das telas reais serão apresentados ao Rodrigo antes de qualquer deploy do redesign.

## Verificação local da documentação e fontes

- Python: `ast.parse` dos dois scripts de tools passou (sem executar nem instalar runtime).
- JavaScript: `node --check` dos sete módulos do mockup passou.
- Shell: `bash -n` de mockup/build.sh e tools/shots.sh passou; não foram executados navegadores headless.
- Montagem gerada comparada por conteúdo: jornada.html corresponde exatamente às fontes e à ordem de build.sh. Essa comparação não prova renderização.
- Project conferido pelo item `PVTI_lAHOC3T16M4BX9UHzg_G_Ig`: sete campos gravados corretamente.
- Conferência factual de backend por subagente: #1063 presente em origin/main, com kept, SoftDelete e preservação de registros; BE-19/BE-25 continuam abertos no código e BE-31 ainda não tem caminho controlado. Não é evidência de runtime ou produção.

## Consistência antes da revisão

- Corrigido o gate circular no handoff: implementar localmente depois da inspeção do protótipo e revisão documental; demonstrar e aprovar todas as telas reais antes do primeiro deploy.
- Normalizado o limite de revisão em PRD/handoff: R9 normal; checagem das correções; achados na checagem exigem causa raiz e revisão final; erro na final exige parada e retorno.
- Aceite admite dados de teste persistidos e falhas de rede/API controladas; não aceita fachada cenográfica. Perfil só ver não acessa rotas de escrita. E5 deriva da conclusão no backend, não da navegação para Pronto.

## Execução das lentes de revisão

- Produto/UX e técnica: revisores independentes da ferramenta de subagentes, sem edição.
- O limite de threads impediu criar os outros dois revisores na mesma ferramenta. Preparado fallback pelo CLI local, somente leitura, modelo configurado `gpt-6.1-sol`/high, sem downgrade nem produção. As duas execuções preliminares foram interrompidas antes de conclusão para respeitar a concorrência máxima; serão executadas em série após liberar os implementadores/revisores atuais. Não contam como rodadas concluídas.
- Esta worktree ainda não tem Procfile.worktree nem .codex/environments/environment.toml; ambiente local do produto precisa ser preparado antes de provar telas reais. Nenhuma configuração de ambiente ou banco foi alterada.

## Pré-requisito de produção preparado

- Desenho inicial B1.md preparado por subagente; ainda exige revisão técnica própria antes do código.
- Consultas Antes B1 e Q12a conferidas no baseline, corrigidas com causa raiz registrada, e revisão final independente passou.
- Solicitado ao Rodrigo somente o OK de executar as duas leituras nas duas stacks. Depois do OK explícito, ambas concluídas conforme recibos abaixo; nenhuma autorização foi inferida pelo tempo. Saída restrita a IDs, nomes de chave e contagens.
- Lente segurança/produção da R9 concluída: zero novos achados. Lente testes concluída posteriormente, com um achado médio. Produto e técnica com correções documentais em consolidação.

- Revisor CLI de testes interrompido sem conclusão após mais de 13 minutos sem nova saída depois das leituras. Nenhum resultado foi tratado como aprovação. Substituído por uma execução independente com o mesmo modelo/tier e escopo da lente delimitado; é continuação da lente da R9, não revisão adicional de resultado corrigido.

## Recibo das duas leituras autorizadas

Rodrigo respondeu “Autorizar somente essas leituras” ao pedido específico de Antes do B1 e Q12a nas duas stacks. A autorização não abrange Q12b, outras consultas, valores de configuração, correção de dados ou alterações de produção.

Executadas em 2026-10-07T11:00:38.994735+00:00 pelo SSM `AWS-RunShellScript`, no `chatwoot-web`, via `psql -X -v ON_ERROR_STOP=1`, sem Rails runner. Cada consulta usou `BEGIN`, `SET TRANSACTION READ ONLY`, `statement_timeout=5s`, `lock_timeout=1s` e `ROLLBACK`. O payload é exatamente os dois blocos SQL do desenho B1 §5.1/§5.2, após revisão final.

| Stack | CURRENT consultado | Comando SSM | Antes B1 | Q12a |
|---|---|---|---|---|
| Hub2You | i-0d77e7fe7cb5e774a, v437 | 157a3c9a-1631-4b5a-b9b5-18ca2f544688 | 0 linhas | 0 linhas |
| Autonom.ia | i-090287c8cacb21493, v426 | 5d7fc35a-60a3-4c32-a207-3b3abf02a4e1 | 0 linhas | conta 20, chave `recovery`, 1 ocorrência em 1 agente |

Ambos comandos retornaram `Success`, código 0, com os dois `ROLLBACK` confirmados. Não foram consultados valores de chaves, telefones, mensagens ou IDs de conversa. A chave `recovery` exige classificação pelo código antes de decidir o tratamento; não será ocultada da consulta nem removida automaticamente. O resultado Antes B1 é uma foto do instante, não prova que os riscos de código foram corrigidos.

Lente testes/aceite concluída: um achado médio de cobertura da Lia (R9-TST-1), corrigido no checklist; nenhum aceite de tela real executado.

### Classificação da chave encontrada

Revisor técnico conferiu o baseline fixo: `recovery` não tem leitor nem escritor semântico no módulo, não está nos acessores do model, não é chave calculada pelo Builder nem chave pública do serializer. A porta genérica de `config: {}` em `agents_controller.rb:157-164,183-193` poderia tê-la persistido, mas isso não prova a origem. Classificação: chave desconhecida/órfã. Preservar sem consultar valor nem remover; eventual saneamento depende de decisão humana e autorização própria. Isso não bloqueia fechar a entrada pública em B1, que preserva chaves legadas e não faz limpeza.

O `origin/main` observado ao final da conferência avançou para `149550330cd276a8367f93e20d53b2456565b843` por outra sessão. A revisão conserva o baseline `6242e31695fd1c6b8b088f2fcb819c027fc5083c`; nenhuma mesclagem ou rebase foi feito.

### Checagem das correções do aceite

Produto/UX conferiu as correções UX02/03/05/06 e TST1 no checklist: fechadas, sem nova falha concreta no recorte. UX04 é resolvido pela prova do caminho existente no navegador, registrada no checklist. UX01 ainda depende da checagem do texto final de exclusão no PRD. Nenhuma marca de aceite local foi preenchida.

### Fechamento local das correções documentais

O worker de PRD foi interrompido após salvar as correções de PRD/handoff; root assumiu explicitamente o gerador e o fechamento, sem edições concorrentes. Um comando de edição documental foi bloqueado por falha fechada da cadeia do hook antes de executar; a mesma edição reversível foi concluída por patch explícito. Não houve rejeição de uma consulta de produção nem ampliação de autorização.

Regenerado `PRD-agentes.html` pelo comando `uv run --offline --with markdown python3 tools/build_prd_html.py`: 35 decisões e 9 rodadas. AST dos dois scripts e conferência do HTML (D1–D35 únicos, 35 estados de decisão, nove rodadas) passaram, assim como `git diff --check`. O primeiro comando de conferência contou também o cabeçalho da tabela; o filtro foi corrigido para IDs numéricos e o resultado passou. São verificações documentais, não provas de produto.

Checagem técnica das correções TEC01–05 e checagem do texto final de exclusão UX01 solicitadas aos revisores independentes. Desenho B1 completo continua rascunho para revisão separada antes do código; a revisão final limpa anterior cobre apenas os SQL.

Produto/UX confirmou também UX01 corrigido, com preservação histórica, roteamento vivo removido, devolução de conversas e destinos dos rascunhos coerentes. Sem nova falha nessa checagem. Lente técnica permanece pendente.

Checagem técnica concluída: TEC01–05 passaram sem novo achado. R9 encerrada no escopo documental, com zero achados residuais. Não foi acionada a revisão final documental, pois a checagem normal terminou limpa. Os SQL tiveram protocolo próprio de parada/causa/revisão final registrado no audit específico.
