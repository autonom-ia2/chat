# Issue 815 — critérios do status para classificação por IA

Data: 2026-10-01. Base: main `5bc07b468f481f4eb831e85d905ceca5660bfb7d`.

## Decisão e escopo

Rodrigo pediu melhorar a descrição de um status específico, usando seu nome e descrição como foco e os demais apenas como contexto. Depois explicitou a finalidade: preparar critérios para a IA classificar as conversas com menos ambiguidade. A instrução reforça evidência suficiente e insuficiente, ação solicitada ou pretendida versus concluída, limites da etapa e preservação de regras explícitas. Retorna apenas a descrição do alvo e uma pergunta curta quando faltar uma definição; não renomeia etapas nem reescreve as demais.

Alteração exclusiva da instrução de StageCriteriaImprover e cobertura do contrato existente. Modelo, formato, idioma e aplicação manual preservados. Busca em app e enterprise: nenhum override do serviço. Descrição vazia continua podendo ser criada pelo nome/contexto; Rodrigo sugeriu explicitar Criar com IA na tela, ainda em alinhamento e sem mudança de interface nesta PR.

Execução real foi pedida pelo Rodrigo com chave da conta 16 e limite de US$ 1. Ele exige ver os resultados para aprovar antes de publicar. O hotfix do editor #814 segue separado.

## Validação local

Banco local isolado release815_criteria, porta 55808; Redis DB 15. Nenhuma credencial real local.

- `bundle exec rspec spec/services/crm/ai/stage_criteria_improver_spec.rb spec/services/crm/ai/default_stage_criteria_spec.rb spec/requests/api/v1/accounts/crm/ai_settings_spec.rb`: 15 exemplos, zero falhas, zero pendências, na versão final; saída integral lida.
- `bundle exec rubocop app/services/crm/ai/stage_criteria_improver.rb spec/services/crm/ai/stage_criteria_improver_spec.rb`: dois arquivos, zero infrações. Sem auto-correção.
- `git diff --check`: sem erros.

A spec verifica o alvo pelo índice, contexto não salvo, imutabilidade, modelo/idioma/contrato e índices inválidos. Julgamento semântico avaliado com o modelo real, sem regex/filtro de palavras.

O primeiro commit não ocorreu: faltava o arquivo gerado local .husky/_/husky.sh. As verificações Ruby aplicáveis foram executadas manualmente e lidas; para este commit sem alteração JS/Vue, o hook local ausente foi dispensado via configuração temporária de hooks. Nenhuma regra de CI foi alterada.

## Execução real autorizada

Chave resolvida exclusivamente no servidor pelo hook da conta 16; sem fallback para chave global. A instrução proposta foi aplicada apenas ao processo temporário do teste. Critérios padrão e conversas sintéticas; nenhuma conversa de cliente lida, nenhum status/card salvo. Telemetria normal de consumo registrada pelo cliente existente. Classifier usado diretamente, sem chamar Evaluator ou aplicar movimentação.

Rodada preliminar: cinco respostas, incluindo descrição vazia/ambígua e instrução indevida em outro status. Após esclarecimento do objetivo, versão final: três novas descrições e comparação com o StageClassifier real em seis cenários, versões atual e nova. Complemento: seis classificações trocando somente o critério do alvo relevante por cenário, mantendo outros critérios, mensagens, IDs, ordem, modelo e esforço.

Casos: primeiro contato; qualificação iniciada; proposta pedida mas não enviada; proposta apresentada; cliente apenas pensando; recusa explícita com concorrente. Goldens revisados independentemente pelo QA. Modelo e esforço efetivos: GPT-6 Luna/high, iguais ao caminho de movimentação atual.

Resultado: atual 6/6, novo conjunto 6/6, novo critério isolado 6/6. Justificativas citaram evidências das conversas. Há critérios mais explícitos, mas não há ganho de acurácia demonstrado nesta amostra. A descrição final de Perdido pede definição das tentativas do funil, sem inventar quantidade ou prazo. Seis casos dirigidos não comprovam consistência estatística nem ausência universal de regressões.

Total: 26 chamadas bem-sucedidas; custo estimado pelo aplicativo US$ 0.00831915, abaixo do teto de US$ 1. Limite de saída e reserva conservadora de tentativas HTTP no processo de teste. Estimativa, não comprovação de fatura.

Uma tentativa do helper de comparação isolada falhou antes da primeira chamada ao provedor por chave String/Symbol ao ler a fixture JSON; corrigida e repetida com sucesso. Não houve chamada paga nessa tentativa.

Digest final da instrução testada: `fc68db7c9f671eaf9bbafbb7775af33663e770b6735945104d00bc4e8ed93582`. SSM final: `5781db4a-6eba-4cb6-8f4a-a357b916a68d` e `711c9273-ea24-47da-ae30-d744981fa5ad`, ambos Success/0. Resultados completos sintéticos preservados localmente, fora do código versionado; nenhum prompt completo ou credencial neste registro.

## Publicação e rollback

Sem merge/deploy. Aguardar aprovação das respostas pelo Rodrigo e CI/review. Coordenar publicação pelo responsável do release usando o main atualizado. Rollback pelo fluxo blue-green para a imagem anterior de cada ambiente. Sem migração ou alteração em chaves, configuração, preços, infraestrutura ou classificador.
