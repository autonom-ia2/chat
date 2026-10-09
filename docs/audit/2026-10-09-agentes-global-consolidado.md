# Atualização após as correções — 09/10/2026

G01–G06 implementados; mesmo revisor aprovouR2 para código/JavaScript,227/227testes40arquivos. Relatórioatual `2026-10-09-agentes-global-correcoes.md` prevalece para estado dascorreções. Auditoriaoriginalabaixo é histórica e preservada. RSpecfinal/novascapturas aindaimpedidos por snapshotsv1/CLIv2 semmigração/reusooficial; não hárelease/CI/PRaprovado. Aceitevisualanteriorpreservado;QAplanejada nãoéexecutada. Semprodução/merge/deploy.

---

# Auditoria global do redesign — resultado consolidado

**09/10/2026 — dez frentes concluídas, com limites explícitos. Pacote não aprovado para PR/release.**

Rodrigo aprovou visualmente F5–F7 e pediu dez especialistas antes do PR. Esse aceite está preservado. A auditoria global é uma nova solicitação expressa, não R4 automática. Cada parecer examinou um escopo delimitado; nenhum é certificado universal de zero regressão. O coordenador conferiu os achados críticos, eliminou falsos positivos e reuniu provas novas. Sem alterações de produto durante a leitura dos auditores.

Worktree única `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`, branch `docs/agentes-ia-prd`, HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`. Épica1114 e issues1160/1164. Os relatórios individuais são a foto de cada entrega; esta consolidação prevalece sobre contagens, hipóteses e metadados antigos ainda presentes neles.

## Dez frentes e resultado

| Frente | Parecer | Resultado delimitado |
|---|---|---|
| 01 Direção de arte | [01-arte](2026-10-09-agentes-global-01-arte.md) | Capturas originais nomeadas e quatro referências de mockup vistas. Compositor alinhado e múltiplas caixas preservados. Barra de conhecimento e abas móveis têm problemas objetivos de clareza. |
| 02 UX/UI simples | [02-simplicidade](2026-10-09-agentes-global-02-simplicidade.md) | Jornada principal compreensível; cortes e sobreposições móveis observados. Não houve teste com pessoas leigas. |
| 03 Base e escopo | [baseline03](2026-10-09-agentes-global-baseline-03.md) | Leitura independente dos recibos corrigiu SHA completo, drift, blocos, caminhos e localização dos snapshots. Produção conhecida somente por metadados. |
| 04 Criação/retomada | [04-criacao](2026-10-09-agentes-global-04-criacao.md) | Falhas estáticas de renovação do teste, entrada/retomada e pré-seleção de canal único. Capturas de criação históricas, sem nova navegação. |
| 05 Gestão | [05-gestao](2026-10-09-agentes-global-05-gestao.md) | Caminhos de gestão examinados; duas alegações de remoção refutadas. O portal citado é recibo anterior, não execução nova desta auditoria. |
| 06 Contratos da criação | [06-contratos-criacao](2026-10-09-agentes-global-06-contratos-criacao.md) | Retomada/erro localizado e fechamento/409 examinados. P1 de envelope retirado pelo autor após probe Rails. |
| 07 Contratos da gestão | [07-contratos-gestao](2026-10-09-agentes-global-07-contratos-gestao.md) | Parecer retificado: nenhum defeito confirmado; concorrência no limite de materiais permanece candidata. Envelope/500 retirados; codes antigos não geram expansão automática. |
| 08 Runtime/agentes ativos | [08-runtime](2026-10-09-agentes-global-08-runtime.md) | Um gate de cobertura falhou. Handoff/retrieval têm riscos condicionais, sem regressão funcional reproduzida. |
| 09 Segurança/compatibilidade | [09-seguranca](2026-10-09-agentes-global-09-seguranca.md) | Parecer retificado: nenhum P1/P2 confirmado. Totais agregados são contrato aprovado; drift/Enterprise/runtime são lacunas. Flag no deep link legado é candidata. |
| 10 QA das evidências | [10-evidencias](2026-10-09-agentes-global-10-evidencias.md) | Proveniência, duplicações, falsos positivos e limites conferidos. Entrega ocorreu antes das retificações finais03/07; os dois já estão concluídos e esta tabela contém o estado final. |

O primeiro agente01 falhou duas vezes sem parecer; foi substituído por outro da mesma classe de modelo. 07/08 recuperaram a execução após erro de permissão. EMFILE foi contornado por filesystem/Local Terminal. Falhas de ferramenta não foram tratadas como defeito do produto ou aprovação. Não houve downgrade.

## Correções sustentadas por evidência

| ID | Gatilho e efeito | Prova / mínimo necessário |
|---|---|---|
| G01 — renovar teste | Salvar Nome/Primeira mensagem invalida o teste, mas mantém o histórico antigo; a próxima pergunta reenvia a conversa anterior. | `useAgentCreation.js:328–336`, `AgentCreationPage.vue:267–277`, `AgentTestPhone.vue:175–184,245–260`; PRD§6.2.3/CA-TES-09 exige conversa nova e aviso. Centralizar reset da conversa quando houver alteração aceita que invalide o teste. |
| G02 — entrada e retomada | A entrada retoma todo guiado em Teste/Ligue. Agente API/Guia E3/E4 sem thread recebe404 e volta à lista. Falha de canais também impede Conte/Teste porque o GET é obrigatório na mesma Promise.all. | `AgentCreationPage.vue:347–384`; `BuildThreadsController#resume:7–17` exige thread e corretamente não cria outra. Separar hidratação necessária por etapa e erro recuperável, conservar agente/contexto; não inventar fallback de criação ao falhar resume. Linha1247–1252 do relatório04 é incorreta, substituída por11. |
| G03 — canal único | Uma caixa livre continua desmarcada. Seleção de várias caixas funciona e deve permanecer. | `AgentBuildGoLivePage.vue:21,65–76`; CA-LIG-03 exige uma caixa pré-marcada quando só há uma. Não forçar seleção com várias nem desfazer escolha explícita da pessoa. |
| G04 — conhecimento legível | Contador0/30 ou7/30 acompanha barra de cerca de70% sem identificar confiança. | PNGs01/02/03b vistos, `PanelKnows.vue:43–46,227–251`. É `knowledge_confidence`, não percentual de materiais prontos. Separar/rotular a confiança como no mockup; não recalcular avaliação da IA no front. |
| G05 — aba móvel ativa | Abrir Onde atende/Ajustes em400px pode deixar o nome da aba ativa cortado ou fora da área visível. | PNGs atuais08a/09c e `AgentPanelShell.vue:71–78,228–248`. Levar a aba ativa à área visível também na montagem/troca de rota, preservando teclado e foco. |
| G06 — registro de recusa | A bateria ampliada encontra `answerer.rb#skip_test_tool#1` sem um gatilho registrado. | `recusa_registro_spec.rb[1:2]` falhou. Registrar um cenário determinístico significativo, sem relaxar o scanner. É falha do candidato já existente na fonte80, não comportamento preexistente comprovado em produção. |

G01/G02 são problemas da jornada, G03/G04/G05 são correções localizadas de produto, G06 é falha de validação. Ainda não foram corrigidos nesta auditoria. Deduplicar G02 entre04/06, sem abrir três P1s para o mesmo tratamento universal de entrada.

## Candidatos que precisam de prova dirigida

- Limpar conversa mantém o teste registrado: alinhar o significado da conversa atual antes de revogar validade persistida arbitrariamente. A UI limpa mensagens/erro, não testValid/testResult.
- Material novo pode invalidar a projeção no backend antes de a UI reler o agente. Não há prova de publicação sem teste: Publisher revalida e pode recusar.
- Sinais no_materials/force_close existem, mas a página nova não os chama. O fechamento textual do modelo ainda pode ocorrer; conferir BE-26 com quatro respostas e Testar antes de mudar o controle.
- 409/build_in_progress mantém polling, mas pode conservar mensagem genérica. Reproduzir dupla submissão/settle sem duplicar turno/job.
- Promise.all de uploads e count/save sem lock podem ultrapassar30; copy já usa agentlock, create não. Corrida e baseline não executados. Não afirmar defeito reproduzido.
- Guia sobre controles inferiores é visível nas capturas; medir toque e adaptar área segura local sem remover ajuda. `Salvar e sair` truncado tem evidência histórica54 e padrão atual de código; recapturar variante atual400px.
- Quatro toasts Salvo cobrem o cabeçalho no PNG, mas o componente é compartilhado/preexistente e dura2.500ms. Medir cadência/baseline antes de atribuir P1 ou alterar componente global.
- Handoff antes de bot_handoff e rescue amplo de retrieval são riscos condicionais. Falta gatilho legítimo específico; não adicionar fallback especulativo para erro genérico de infraestrutura.
- PanelTune legado lê uma flag divergente, mas a rota normalON usa o painel novo. Só o deep link explícito `/legacy/tune` permanece candidato de compatibilidade.

## Seis alegações retiradas, em quatro grupos

1. **Dois PATCH sem envelope:** initializer habilita wrapping JSON; não há override relevante. Probe standalone Rails7.1.5.2 com mesmo namespace retorna200, rootagent e valores{name,greeting}. Não bootou aplicação nem usou banco/redeHTTP. Não há defeito HTTP demonstrado de salvar ou pausar/ativar.
2. **Duas remoções Connect/MetaAds:** comparar árvore antiga inteira com main produziu falso positivo. `git merge-file -p main baseHEAD candidate` em scratch retornou0 e preservou ambos. Não foi feito merge de branch. Integração textual não substitui testes.
3. **Upload500 sem JSON:** ApplicationController inclui RequestExceptionHandler; RecordInvalid retorna422JSON{message,attributes}. Codes/DTO antigos são observação separada, não ausência de handler.
4. **Totais analytics como vazamento:** BE-25 explicita que o agregado não muda. Filtro aplica-se ao drilldown de conversas/FAQ, não aos números gerais. O drilldown revisado usa PermissionFilterService. Não alterar autorização por uniformidade presumida.

Esqueleto sem texto visível coincide com mockup e CA-RES-08; rótulo de loading é sugestão de clareza, não bloqueador contratual. Diferenças de gosto não geram redesign adicional.

**Causa dos falsos positivos:** omissão de initializers/ancestrais/framework; comparação de branch antiga inteira em vez de integração de patch; inferência de regra de privacidade diferente do PRD aprovado. Mudança de método: subir cadeia de herança, conferir contrato e framework, fazer probe mínimo sem banco e comparar patch em scratch antes de propor correção. Nenhum produto foi alterado para corrigir essas alegações.

## Evidências, linha de base e limites

- Inventário518 caminhos(195tracked/323untracked), incluindo mudanças alheias; não são518 arquivos do redesign. **Freeze final09/10 08:39:22UTC:367 inputs fora de docs, zero diferenças, diffcheck0; branch e HEAD preservados.**
- Main/último deploy registrado: `28e1e0ac8b3835577f7469368f03a86d1a8dab0d`. Hub2You deployment6943966962→workflow37826925422; Autonom.ia6943966912→37826925413, ambos success. Nenhum SHA efetivamente servido ou agente de produção testado diretamente.
- HEAD136commits atrás,666 caminhos novos/alterados na main,16overlaps. Patch final precisa integrar somente arquivos próprios, preservar alterações alheias e validar os overlaps; sem rebase/reset/merge automático. PRs backend/front/runtime separados pelo PRD§10.1.
- **RSpec ampliado novo:2.344 examples,1failure,3pending**, 199,2s RSpec/213,4s coordenação. Pending são evals pagos desativados. Executou no snapshot79M2; equivalência backend/specAST para80 demonstrada por comparação integral14.987entradas. Não somar com276 focais para inventar total independente.
- Fonte79 localM4 ausente, M2presente. Fonte80 existe nos dois nós. Bateria adicional sharedroles/SuperAdmin/OnlineStatus/autoassignment **não executada**: planner recusou contexto localdirty/réplica ausente. Sem force, cópia/restauração, limpeza ou mudança de infraestrutura. Job global80 workspacebusy foi cancelado oficialmente antes de começar; prévias preservadas.
- Recibos anteriores F5–F7:200JS/33arquivos,276Rubyfocais,124jornadas/4perfis,196capturas/49estados,18destinos autenticados/236imagens. Inputs correspondentes conferidos; ESLint0erros/523warnings, não zero avisos. Build/Guia/i18n/formatos anteriores não são CI do candidato nem novas execuções desta auditoria.
- Gestão tem capturas fonte80; criação54 é histórica e59720 estava indisponível. Não houve navegação fresca da criação nem leitura integral de196PNGs por cada revisor. Arte01 nomeou seu subconjunto e refs efetivamente vistos. Aceite visual do Rodrigo permanece; mudanças futuras exigem capturas/aceite dos estados afetados antes de subir.
- Sem produção, dados de cliente, nova SQL, fila, PR, commit, push, merge, deploy ou provedor pago. Runtime em produção será camada própria após aprovação pela Automação; sua ausência não impede encerrar esta auditoria local, mas impede atestar zero regressão ativa universal.

Recibos: `.codex/preview/global-audit-20261009/` contém inventory/comparison-main/main-drift/working-vs-source80/freeze-check-final, github-baseline/deployment-*, merge-readonly-result, rails-params-wrapper-probe-ascii/scope, ruby-global79-result/log, ruby-cross79-plan-valid e snapshot-locality-progress. Project/HANDOFF atualizados; nenhuma migration nova da auditoria.

## Próximo bloco seguro

Corrigir os pontos comprovados de teste/entrada/Ligue e conhecimento/abas móveis, fechar o gate de recusas e executar as provas dirigidas dos candidatos antes de qualquer mudança adicional. Congelar fonte após esse bloco; executar checks pertinentes e recapturar somente estados afetados, com APIs reais/banco sintético e sem IA paga. Revisão pelo protocolo do Rodrigo: R1→correção→R2; se R2 reprovar, causa raiz→correção→R3; se R3 ainda reprovar, parar e retornar. Não iniciar R4.

A auditoria não autoriza release. Automação continua coordenando fila/deploy. Somente “pode enfileirar” autoriza `gh pr merge --match-head-commit <SHA>`; sem push após pedir vaga. Antes de subir, Rodrigo vê as telas alteradas. Não solicitar aprovação para riscos hipotéticos nem repetir aceite já dado.
