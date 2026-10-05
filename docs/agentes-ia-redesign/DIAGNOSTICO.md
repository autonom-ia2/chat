# Agentes de IA — diagnóstico para o redesign (05/10/2026)

Etapa 1 de 3 (diagnóstico → proposta + protótipo navegável → implementação).
Fontes: leitura do código em `main` (467efd68a9), três auditorias independentes
(frontend, padrão visual, backend) e as sessões que remodelaram Campanhas,
Automações e Primeiros passos/Central. Nada foi executado em produção.

## 1. Resumo em uma tela

| Frente | Situação |
|---|---|
| Visual | Destoa em tudo: título 16px em barra fina, roxo (`n-iris`) no lugar do azul da marca, cards `p-4`, botões < 44px, vazio genérico do Chatwoot. Nunca passou por redesign (último commit #803). |
| Jornada | 3 decisões técnicas antes de começar, etapa "base" escondida, barra mostra 2 passos de 4, "Testar" sai do assistente, rascunho não ativa pelo painel. |
| Backend | 2 problemas HIGH que perdem trabalho ou deixam cliente sem resposta; o modelo escolhido é descartado no meio da conversa. Base sólida em isolamento por conta e autorização. |

## 2. Bugs e riscos (corrigir independente do redesign)

| # | Gravidade | Problema | Evidência |
|---|---|---|---|
| B1 | HIGH | Limpeza automática apaga agente **já construído** e não publicado após 48h parado (com materiais e conhecimento). Não checa `instruction`; o Construtor nunca muda o status ao terminar. Spec não cobre. | `app/jobs/autonomia/agents/reap_stale_drafts_job.rb:45-51`; `builder.rb:1008-1023` |
| B2 | HIGH (confirmar em ambiente) | Pausar o agente não desliga o bot-espelho da caixa: conversa nova recebe o espelho como responsável, mas o agente não responde → cliente sem resposta. Só `disconnect!` devolve para humano. | `conversation.rb:354-364`; `operate.rb:44`; nenhum callback de status em `agent.rb` |
| B3 | HIGH (produto) | Modelo escolhido (Suporte, Qualificador…) é descartado quando o rascunho nasce: rascunho criado com `agent_type: 'custom'` e o tipo é lido do rascunho antes da escolha. Com "Com base" (padrão) acontece já na abertura. | `builder.rb:1401` e `builder.rb:904-906` |
| B4 | MEDIUM | Excluir agente também não devolve conversas para humano. | `agent_inbox.rb:68-73` |
| B5 | MEDIUM | Ativar + conectar canal são 2 requests com rollback feito no front; agente fica "ativo sem canal" e atende antes de ser testado. | `PanelPublish.vue:62-90`, `AgentBuilderPage.vue:361-394` |
| B6 | MEDIUM | Janela de "geração presa" (5 min) menor que o pior caso da chamada (≈9 min) → geração dobrada, custo dobrado. | `build_thread.rb:127`; `responses_client.rb:9-10` |
| B7 | MEDIUM | Sem rate limit em `build_threads`, `test`, `suggest` (chamadas caras). | `config/initializers/rack_attack.rb` |
| B8 | MEDIUM | Agente pode ser ativado sem instrução. | `BuilderReview`; `external_agent_lifecycle_spec.rb:33` |
| B9 | LOW | `create` aceita chaves de config reservadas ao sistema (`PROTECTED_CONFIG_KEYS` só no update). | `agents_controller.rb:38-41,162,183` |
| B10 | LOW | Build threads visíveis a qualquer pessoa da conta com `autonomia_view`. | `base_controller.rb:55-62` |
| B11 | LOW | Exclusão lenta (`dependent: :destroy` em trechos de conhecimento); `ToolRun` sem FK fica órfão. | `agent.rb:50`; `schema.rb:3375` |
| B12 | LOW | `enabled` e `status` redundantes, sem validação cruzada. | `agent.rb` |

## 3. Jornada atual e atritos

```
Lista ──► Escolha (Externo/Interno + Com/Sem base + 7 cards) ──► [Base: soltar arquivos]
      ──► Conversa + materiais ──► Revisão (caixa de entrada + "Conectar e ativar") ──► Painel (7 abas)
```

| Atrito | Onde |
|---|---|
| Duas perguntas técnicas antes de saber o que o agente faz ("Interno", "base de conhecimento"). | `AgentTypePicker.vue:14-15` |
| Clicar no card já começa — sem confirmar, sem voltar. | `AgentTypePicker.vue:83-105` |
| Etapa "base" não aparece na barra; barra tem 2 passos para 4 telas. | `BuilderStepBar.vue:26`; `AgentBuilderPage.vue:164-166` |
| Arquivo que falha trava a base; saída só pelo "Pular". | `AgentBuilderPage.vue:86-88,169-171` |
| Nome do agente nunca é perguntado; nasce "Novo agente" fixo em português. | `builder.rb:1401` |
| "Testar" na revisão sai do assistente; para publicar é preciso voltar pela lista. | `AgentBuilderPage.vue:353-359` |
| Ativar acontece **antes** do teste. | `PanelPublish.vue` |
| Rascunho sem botão "Ativar" no painel; Publicar é aba escondida. | `AgentPanelPage.vue:226-247` |
| Excluir só existe no card da lista e é a única ação visível dele (vermelha). | `AgentCard.vue:137-144` |
| Sem renomear, duplicar, arquivar. | — |
| Métricas do card são "—" fixo no código; endpoint existe só por agente (pesado). | `AgentCard.vue:28-29`; `analytics.rb:35` |
| Card não distingue "rascunho inacabado" de "pronto para ligar". | `AgentCard.vue` |
| Mídias só gerenciáveis dentro do construtor; regras de material diferentes entre construtor e painel (limite 30, confirmação de remoção). | `BuilderKnowledgePanel.vue:79-86,102,163-175`; `PanelKnowledge.vue:36,80-95` |
| Menu repete o caminho: "Construtor de agentes" no menu + botão "Criar agente com IA". | `Sidebar.vue:791-818` |
| Vazio promete "3 minutos"; base avisa "até 5 minutos" só de processamento. | i18n `agents.json` |

## 4. Diferença visual contra o padrão (Automações #982 = referência mais madura)

| Elemento | Agentes hoje | Padrão Chat2You |
|---|---|---|
| Página | `bg-n-background`, largura total, `p-6 gap-4` | `bg-n-surface-1`, `max-w-6xl mx-auto px-5 py-8 md:px-8 md:py-10 gap-8` |
| Título | barra `px-6 py-4 border-b`, `text-base font-medium` | `h1 text-3xl md:text-4xl font-bold tracking-tight`, subtítulo `text-base md:text-lg` |
| Destaque | `n-iris` (roxo) | `n-brand` `#2781F6` + azul-marinho `#0D2344` (herói) |
| Card | `rounded-xl p-4`, título `text-sm` | `rounded-2xl p-6 ring-1 ring-inset ring-n-weak shadow-sm hover:-translate-y-0.5 hover:shadow-lg`, título `text-lg font-semibold` |
| Ícones dos modelos | tile colorido em 4 de 6 (Pós-venda/Reativação sem tile) | tile `size-14 rounded-2xl` com par `bg-n-<cor>-3 text-n-<cor>-11` em todos |
| Botões | `sm`/`xs` | `Button size="lg" !min-h-12 !rounded-xl`, 1 primário por tela |
| Vazio | `EmptyStateLayout` do Chatwoot | herói escuro + modelos prontos |
| Etapas | barra de 2 passos | `AutomacaoEtapas.vue` (bolinhas, nome por objetivo, `aria-current`) / `JourneyStepper.vue` (Campanhas, ramo `feat/993`) |
| Estados | spinner | esqueleto, erro com "Tentar de novo", sucesso `bg-n-teal-3` |
| Ícones (código) | 3 jeitos (`span`, `i`, `<Icon>`) | `i-lucide-* size-N aria-hidden` ou `<Icon>` |

Componentes reaproveitáveis: `Button`, `ChoiceSelect`, `Switch`, `Dialog` (components-next);
`AutomacaoEtapas`, `AutomacaoHeroi`, `AutomacaoEnsaio`; `FirstStepsFocus`; de Campanhas
(ainda fora da main) `JourneyStepper`, `AudienceSidePanel` + `useModalFocus`.

Achados de código na área: controles nativos e modal próprio em `PanelTools.vue` (só SuperAdmin),
textos fora do i18n em `PanelTools.vue:49,78,81,192`, `text-white` fixo em 3 arquivos, polling
duplicado em `BuilderKnowledgePanel.vue:224-246`, botões só-ícone sem `aria-label` em
`PanelTools.vue:294-314`. Sem `<select>` nativo; sem CSS custom.

Lacunas do sistema de design (fora deste escopo, anotar): não há componente de cabeçalho de página
compartilhado; `#0D2344` está fixo em 4 arquivos sem token; `docs/guia-operante/GUIA-VISUAL.md`
desatualizado em relação ao #982.

## 5. Regras de UX que valem para a proposta (vindas das telas aprovadas)

- Linguagem para leigo ("QI 70"): frases curtas, nomes por objetivo, sem jargão, sem CAIXA ALTA, sem texto repetido.
- Uma tela, uma tarefa, um botão primário. Botão "Alterar" explícito.
- Mostrar antes de fazer: testar/ensaiar **antes** de ligar. Começar pronto (modelos).
- Só canais realmente conectados. Textos genéricos (Hub2You **e** Autonomia — nada de nicho seguro).
- Estados completos: carregando, erro, vazio que ensina, sucesso. Alvo ≥ 44px, teclado, leitor de tela, tema escuro.
- Construção aditiva no fork, com flag para voltar à tela antiga. Sem `<select>` nativo. i18n en + pt_BR.
- Aprovação por protótipo HTML navegável por jornada, com dados reais; conferir captura antes de enviar.

## 6. O que dá só no front × o que exige API

| Só front | Exige backend |
|---|---|
| Unificar escolha inicial (padrão `external` + `with_knowledge`, decisões viram perguntas da conversa) | Corrigir B1, B2, B3, B4 |
| Testar o rascunho antes de ativar (`POST agents/:id/test` já aceita rascunho) | Ativar + conectar atômico (B5) |
| Deduzir canal quando só há 1 caixa elegível (`GET channels`) | Métricas em lote no `index` |
| Barra de etapas fiel, nome do agente editável na revisão, ações no painel (ativar rascunho, excluir, renomear via PATCH) | Validar no servidor as condições para publicar (B8) |
| Card com estado "inacabado / pronto para ligar / no ar / pausado" | Retomar conversa do construtor de um agente (TODO `build_thread.rb:103-106`) |
| | Duplicar agente; rate limit (B7); janela de geração presa (B6) |
