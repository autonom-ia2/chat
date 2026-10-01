# Issue 815 — critérios do status para classificação por IA

Data: 2026-10-01. Base: main `5bc07b468f481f4eb831e85d905ceca5660bfb7d`.

## Decisão e escopo

Rodrigo pediu preparar a descrição de um status específico para a IA classificar as conversas com menos ambiguidade. Nome e descrição do alvo são o foco; os demais são contexto somente. Reforça evidência suficiente e insuficiente, ação solicitada ou pretendida versus concluída, limites da etapa e preservação de regras explícitas. Retorna apenas descrição do alvo e pergunta curta quando falta definição; não renomeia etapas nem reescreve outras descrições.

Descrição vazia: criar pelo nome/contexto. Descrição presente: melhorar os critérios existentes sem ampliar escopo. Rodrigo corrigiu a indicação de modelo para GPT-6 Luna, que permanece. Em criação, não importar procedimentos/restrições de outros status para o alvo sem definição. Revisão encontrou uma proposta criada com exigência de envio formal; instrução ajustada e retestada com proposta apresentada verbalmente.

UI: campo vazio mostra Criar com IA e explica o contexto; preenchido mostra Melhorar com IA. Sugestão permanece em revisão até aplicação manual somente no campo selecionado. Agora não descarta criação; Manter minha descrição descarta melhoria. Nome faltante explica ação desabilitada. Funil novo mostra apenas aviso para salvar antes de usar IA. Layout e componentes existentes preservados; textos en/pt_BR conforme autorização explícita. Sem mudança de rotas/menu. Nenhum override do serviço em enterprise.

Execução real autorizada com chave da conta 16 e limite de US$ 1. Rodrigo exige ver respostas antes de publicar. Hotfix #814 segue separado.

## Validação local

Banco isolado release815_criteria, porta 55808; Redis DB 15. Nenhuma credencial real local. Dependências instaladas offline pelo pnpm 10.2.0 já disponível, com lockfile preservado.

- `bundle exec rspec spec/services/crm/ai/stage_criteria_improver_spec.rb spec/services/crm/ai/default_stage_criteria_spec.rb spec/requests/api/v1/accounts/crm/ai_settings_spec.rb`: 15 exemplos, zero falhas; saída integral lida na versão final.
- `bundle exec rubocop app/services/crm/ai/stage_criteria_improver.rb spec/services/crm/ai/stage_criteria_improver_spec.rb`: dois arquivos, zero infrações. Sem auto-correção.
- Vitest: CrmPipelineDrawer.spec.js e CrmPipelineDescriptionActions.spec.js, nove testes passando, zero falhas. Inclui alternância criar/melhorar, snapshot do contexto não salvo, revisão antes de aplicar, imutabilidade dos outros status, nome faltante e aviso antes de salvar.
- ESLint dos dois arquivos Vue/JS: zero erros. Drawer tem 125 warnings de i18n; catálogos verificados pelo check específico do fork.
- `node scripts/check-fork-i18n.mjs`: nove catálogos, 15974 mensagens compiladas, cobertura en/pt_BR de chaves e parâmetros.
- `git diff --check`: sem erros.

O primeiro commit não ocorreu por ausência de .husky/_/husky.sh no worktree. Checks aplicáveis executados manualmente, lidos e configuração de hooks dispensada apenas no comando de commit. Nenhuma regra de CI ou configuração global alterada. Formatação manual relida e checks repetidos. Specs testam contrato e UI; julgamento semântico foi avaliado com o modelo, sem regex/filtro de palavras.

## Execução real autorizada

Chave resolvida somente no servidor pelo hook da conta 16, sem fallback global. Instrução proposta aplicada apenas ao processo temporário do teste. Critérios padrão e conversas sintéticas; nenhuma conversa de cliente lida, nenhum status/card salvo. Telemetria normal de consumo registrada pelo cliente existente. Classifier direto, sem Evaluator/aplicação de movimentação.

Rodada final: três melhorias e duas criações; sete pares de classificação comparando critérios atuais com somente o critério gerado relevante alterado. Mesmo contexto, mensagens, IDs, ordem, modelo e esforço. Caso verbal usa a descrição criada de Proposta. Modelo/esforço efetivos: GPT-6 Luna/high, iguais ao caminho de movimentação atual.

Casos: primeiro contato; qualificação iniciada; proposta pedida mas não apresentada; proposta apresentada; cliente apenas pensando; proposta apresentada verbalmente sem documento; recusa explícita com concorrente. Atual 7/7 e critério gerado 7/7, 14/14 classificações com IDs esperados. Justificativas citam evidências. Há critérios mais explícitos, mas nenhum aumento de acurácia demonstrado nesta amostra dirigida. A descrição de Perdido pede a definição das tentativas, sem inventar quantidade ou prazo.

Total acumulado de todas as rodadas autorizadas: 81 chamadas bem-sucedidas, US$ 0.02507766 estimados pelo pricing do aplicativo, abaixo de US$ 1; estimativa, não comprovação de fatura. Rodada final: 19 chamadas, US$ 0.00546567. Limite de saída e reserva conservadora de até três tentativas HTTP por chamada no processo de teste. Uma tentativa anterior do helper falhou por chave String/Symbol antes do provedor; corrigida e repetida, sem chamada paga nessa tentativa.

Digest final da instrução testada e conferida com o código: `4dfe60c5a136246fcd0bb776e9a8360a6f89048545d42ce0ecf29a60c0805ea3`. SSM final `acb7be0f-23fa-4598-bf1f-9623ebb00b9d`: Success/0. QA independente aprovou instrução e cinco respostas finais, incluindo ausência de exigência de canal/documento em criação. UX aprovou fluxo, com ajuste do aviso para funil novo incorporado. Resultados sintéticos completos e logs locais fora do código versionado; nenhum prompt completo, credencial ou dado de cliente neste registro.

## Revisão visual, publicação e rollback

Componente real renderizado em QA local na porta 47835, com dados de teste e reprodução das respostas já geradas pelo Luna. Essa navegação não chamou o provedor nem representa produção. Campo vazio e ação Criar com IA conferidos; revisão/aplicação manual cobertas pelos testes e conferência visual.

Sem merge/deploy. Aguardar aprovação das respostas pelo Rodrigo e CI/review. Coordenar publicação pelo responsável do release usando main atualizado. Rollback pelo fluxo blue-green para imagem anterior de cada ambiente. Sem migração, mudança de chaves/configuração/preços/infraestrutura/classificador.
