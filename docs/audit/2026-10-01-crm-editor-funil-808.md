# Editor de funil — issue 808

Data: 2026-10-01. Branch: `codex/808-pipeline-editor`. Base: `476db3af5e`.

## Escopo autorizado

Rodrigo autorizou implementação do desenho aprovado, botão Melhorar com IA usando GPT-6 Luna, múltiplas caixas de entrada no fim de Mais ajustes, cores com amostra e nome, nenhuma lista com select nativo e textos em português também. Merge e deploy não autorizados.

## Decisões

- Editor de 40rem, nome e status na primeira visão, descrição em edição focada e ajustes secundários separados. Meta passa a ter escolhas visuais explicadas, seleção explícita e requisitos de envio sem afirmar conexão externa.
- Novos funis recebem IA, movimentação, extração de campos, score e callback habilitados. A reavaliação padrão é 168 horas. Funis existentes conservam flags persistidas até serem editados e salvos; nenhuma migração ou atualização em massa.
- Salvar um funil existente também salva seus critérios e os padrões incluídos de IA. Calendário/notificação permanecem; envio opcional usa callback_mode=both. Follow-up conserva ativação, modo, intervalos e agenda existentes.
- Melhorar com IA usa o fluxo assíncrono existente, account/pipeline scoping e permissão manage_ai. Compara nomes e descrições de todos os status, inclusive rascunhos, e altera apenas o texto escolhido após Usar esta descrição. Modelo fixo gpt-6-luna, sem fallback. Nenhuma conversa real é buscada para esta melhoria.
- Dados inválidos rejeitados antes de enfileirar. Critérios novos seguem metadata.ai_criteria. Gates globais e Enterprise preservados.
- Guia alterado em porques.md e regenerado; arquivo gerado não foi editado manualmente.

## Validação

- Vitest existente: Drawer, AiSettingsPanel, actions do store e ChoiceSelect: 4 arquivos, 68 testes passando.
- RSpec existente: ai_settings, pipelines_and_stages, pipeline_inboxes: 18 exemplos, zero falhas, 2 pendentes de quarentena já existentes.
- RSpec existente: evaluator e ResponsesClient retries: 32 exemplos, zero falhas. WebMock/mocks; sem chamada paga.
- Depois do ajuste de compatibilidade metadata.ai=null no inicializador: pipelines_and_stages novamente, 5 exemplos, zero falhas, 1 pendência já incluída nas duas anteriores.
- RuboCop nos cinco arquivos Ruby alterados: zero offenses. ESLint e diff --check verificados após reler alterações dos formatadores.
- Validação de entrada isolada: formato válido aceito e oito formatos inválidos rejeitados; nenhuma chamada ao provedor.
- i18n fork: 9 catálogos, cobertura de chaves e parâmetros en/pt_BR. Guia: 169 fluxos, 170 telas, zero sem explicação; quatro explicações órfãs preexistentes.
- Browser local: componentes Vue reais + SCSS/Tailwind do produto, montados com dados fictícios e API simulada. Conferidos descrição legível, aplicar sugestão sem alterar outros status, cores, teclado no seletor, várias caixas sem reset de rascunho e save com callback_mode=both + defaults true + stale_hours=168. Viewport pequeno 375x812 e viewport desktop conferidos.

## Revisão visual

Rodrigo solicitou diretor de arte, QA e especialista UX/UI. Diretor de arte apontou caixas aninhadas, Meta escondida junto das cores, rótulos vagos e descrição cortada na lista. Correções: Meta como seção independente, redução de recuos, opções com explicações e descrição legível na lista. O especialista UX/UI recomendou contexto da etapa, recuos menores, requisitos técnicos recolhidos e resumos em duas linhas com texto completo no detalhe. Implementados número/cor/nome, Meta independente, min-h-0 e espaço inferior. Diretor de arte e UX concordaram em manter números como posições dinâmicas. Rodrigo autorizou arraste e ordenação convencional: vuedraggable já existente, alça separada, UUID local estável, setas 44px, teclado e anúncio aria-live; drag Proposta→2, teclado Up/Down com foco mantido e botão Subir etapa conferidos sem troca de critérios. Nenhuma identidade de status é baseada no número.

QA independente encontrou ordem incorreta ao criar um status no meio: o reorder anterior só usava IDs antigos. Corrigido para capturar as respostas de todos os create/update em Promise.all e enviar a sequência completa. Removido limite arbitrário de 30 status no helper IA. QA conferiu as duas correções sem bloqueador identificado. Validação adicional da ação real do store via Vite SSR/API simulada: novo status no meio, todos os IDs, posições únicas, critério próprio preservado, editorKey excluído; segundo reorder manteve a ordem. No navegador local, criado Qualificação, movido para segunda posição por teclado, salvo/fechado e reaberto; posição e critério mantidos com a ação real e backend simulado. Não é prova integrada no banco.

## Limites e publicação

Não foi validada qualidade de uma resposta real paga do GPT-6 Luna, nem entrega/recebimento Google Ads ou Meta. A prévia local demonstra o componente real, mas não a integração completa autenticada com o backend. Não houve mutação de produção ou dados de clientes. Não há garantia absoluta de ausência de regressões.

Após revisão e autorização explícita: publicar backend/frontend pelo procedimento existente, confirmar gates e credencial do modelo, testar em conta autorizada criação/edição, descrição, caixas e um pedido de sugestão com orçamento. Separar validação de eventos externos de aparência/CI. Rollback: restaurar release anterior; sem migração de schema. Configurações salvas por operadores continuam persistidas, portanto rollback não desfaz essas escolhas automaticamente.
