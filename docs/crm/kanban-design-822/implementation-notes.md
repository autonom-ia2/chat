# Da proposta ao produto

Este é um mapa de decisões para uma futura PR de código, após aprovação visual.
Nenhum item desta lista foi implementado no produto pela Issue #822.

## Funções atuais e lugar proposto

| Função existente | Lugar proposto | Regra preservada |
|---|---|---|
| Escolher funil | Controle de Funil próximo à busca | Carregar o dataset inteiro do funil escolhido; preservar escopo de conta. |
| Kanban / Lista / Calendário | Alternância de visualização visível | Estado selecionado acessível; não esconder o caminho manual de edição/lote da Lista. |
| Criar oportunidade | Único botão primário do quadro | Abrir criação de oportunidade com os modos de vínculo existentes da PR #793. |
| Editar funil / status | Configurar → Editar Funil | Drawer aprovado, ordem única, exclusão com regras existentes e campos de critérios IA. |
| Criar funil | Ação visível junto ao seletor de funil | Fluxo próprio; não confundir com Nova oportunidade. |
| Atribuição e handoff | Configurar → Responsáveis e repasse | Preservar elegibilidade/permissões e distinção entre owner, responsável e bot. |
| Gestão de caixas da conta | Configurar → Caixas de entrada | Preservar gestão/autorização atual por conta; não criar permissões novas. |
| Vínculos das caixas com o funil | Última etapa do Editar Funil | Mais de uma caixa por funil; vínculo não equivale a cadastrar novo canal na conta. |
| Página de agendamento | Configurar → Agendamento | Respeitar feature flag, papel e fluxo já disponível. |
| Atualizar quadro | Ação pequena com rótulo acessível | Não deslocar foco nem apagar filtros; erro/retry claros. |
| Buscar e filtrar | Linha de trabalho visível | Nenhum filtro atual desaparece; novos campos de busca precisam de backend autorizado. |
| Abrir card / conversa | Card e ação contextual | Alvos distintos; conservar conversa primária e permissões. |
| Mover entre status | Arrastar + Mover para… | Mesmo endpoint e regras; rollback visual se a API rejeitar a gravação. |

O protótipo não reproduz toda a complexidade dessas telas. Menus/contextos
demonstrativos precisam deixar isso explícito, sem fingir gravação ou navegação
em produção.

## Identidade e empresa

Fontes verificadas em `56b56f3a79`:

- `app/services/crm/kanban/card_payload_builder.rb`: payload compacto próprio,
  sem empresa canônica no contato.
- `app/services/crm/kanban/board_payload_builder.rb`: preload/paginação por coluna.
- `app/javascript/dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue`:
  título da oportunidade, subtítulo do contato, avatar do responsável.
- `enterprise/app/models/enterprise/concerns/contact.rb`: associação de empresa.
- `app/javascript/dashboard/routes/dashboard/crm/components/CrmCardRelationshipPanel.vue`:
  fetch de contato/empresa no detalhe.

Contrato mínimo proposto: acrescentar `contact.company` com `id/name` ou `null`.
Usar extensão compatível com Enterprise; não presumir associação em OSS. A consulta
deve carregar a associação em lote e manter autorização/escopo de conta.

Não inferir empresa pelo nome da oportunidade ou por `additional_attributes`.
Não consultar CompanyAPI por card. Atualização do vínculo deve refletir em quadro,
lista e detalhe sem cache antigo de empresa.

## Atenção e proveniência

Um responsável bot não prova que o score foi calculado por IA. O número do board
não vem acompanhado da origem/motivo usados pelo componente para diferenciá-lo.
Portanto, a implementação deve adicionar uma representação mínima de proveniência
ou usar rótulo neutro até esse contrato existir.

Não alterar o algoritmo, as faixas ou a prioridade humana nesta proposta. Não
transformar o score em probabilidade de venda. Score ausente não significa que
um processamento IA está pendente. Texto de próximo passo criado no mockup não
deve virar novo campo obrigatório sem fonte/contrato aprovado.

## Busca, contagens e ordem

A busca atual é apenas pelo título, tanto no quadro quanto na lista. Buscar por
contato/empresa exige consulta autorizada no servidor; filtrar só o conjunto
carregado produz resultados incompletos. A interface deve mostrar o escopo da
contagem filtrada, o total aberto e quantos cards estão carregados.

A paginação atual seleciona por ID e a ordenação por score/atividade é client-side
sobre esse recorte. Se o produto prometer prioridade do funil inteiro, cursor e
ordenação devem seguir a mesma chave no servidor, com desempate estável. Um teste
com um card antigo de alta atenção fora dos 30 mais recentes deve comprovar isso.

## Aceitação de implementação

- B2B, B2C, vínculo nulo, título diferente/igual ao contato e mudança de empresa.
- Contato/empresa de outra conta não vazam nem podem ser vinculados.
- OSS e Enterprise; papéis de gestor, agente, custom role e usuário sem gestão.
- Score IA/manual/sem origem/sem score; responsável humano/IA/não atribuído.
- Busca por título, pessoa e empresa; filtros combinados e limpar sem perder funil.
- Coluna vazia, 31+ cards, carregar mais, prioridade e contagem coerente após mover.
- Drag e Mover para por clique/teclado, falha de API e concorrência/realtime.
- Desktop, celular, zoom/texto maior, teclado, foco de menus/gavetas e rodapé.
- Nenhum select nativo; design system e inglês/pt_BR juntos no código de produto.

Os testes de interface do protótipo demonstram interação em memória. Não
substituem esses testes integrados ou a revisão de release.
