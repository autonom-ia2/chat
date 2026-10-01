# Identidade do cliente e Prospecção → CRM

## Auditoria adicional: Prospecção, vínculo canônico e identidade do card

**Referência:** `origin/main` em `902f0059d76da8b1c74c47f57c8e66edc6d55bca`. Esta seção também é leitura estática, sem dados reais, requests autenticados ou alteração de produto.

### O que a seleção realmente carrega e envia

- O payload de cada lead inclui `name`, `phone`, `website` e os dados básicos da empresa/prospecção; pesquisa confirmada acrescenta `research.company`, sócios e decisor. O payload também traz `contact_id` e `crm_card_id` quando o lead já foi convertido ([`app/services/autonomia/prospecting/lead_payload.rb:4-17,23-38,55-59`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/lead_payload.rb#L4), [`app/services/autonomia/prospecting/research/payload.rb:17-25,35-39`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/research/payload.rb#L17)).
- A janela de envio não envia nome, telefone, site ou empresa de volta ao servidor: envia `lead_ids`, `pipeline_id` e `stage_id`. O servidor relê os leads dentro do escopo visível da conta ([`app/javascript/dashboard/api/autonomiaProspecting.js:65-73`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/javascript/dashboard/api/autonomiaProspecting.js#L65), [`app/javascript/dashboard/routes/dashboard/autonomia/prospecting/components/crm/CrmSendModal.vue:102-113`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/javascript/dashboard/routes/dashboard/autonomia/prospecting/components/crm/CrmSendModal.vue#L102), [`app/controllers/api/v1/accounts/autonomia/prospecting/leads_controller.rb:64-78,194-197`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/controllers/api/v1/accounts/autonomia/prospecting/leads_controller.rb#L64)). Isso evita confiar no objeto editável da tela.
- No envio criado, o resumo devolve `lead_id`, `card_id`, `contact_id` e `company_id`. No reenvio já existente, devolve apenas `lead_id` e `card_id` ([`app/services/autonomia/prospecting/crm_card_batch.rb:61-69`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/crm_card_batch.rb#L61)). A tela preserva o `contact_id` antigo quando o item existente não o traz ([`app/javascript/dashboard/routes/dashboard/autonomia/prospecting/composables/useSearchLeads.js:87-103`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/javascript/dashboard/routes/dashboard/autonomia/prospecting/composables/useSearchLeads.js#L87)).

### Como empresa, contato e card são gravados

1. `CrmCardConverter` trava o lead e, na mesma transação, chama `CompanyUpserter`, `ContactConverter`, cria o card e grava `lead.crm_card_id` ([`app/services/autonomia/prospecting/crm_card_converter.rb:56-71`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/crm_card_converter.rb#L56)).
2. `CompanyUpserter` procura a `Company` da mesma conta por CNPJ, domínio, empresa lembrada no metadata ou empresa já ligada ao contato; índices e retry cobrem corrida de criação ([`app/services/autonomia/prospecting/company_upserter.rb:35-65,88-119`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/company_upserter.rb#L35)).
3. `ContactConverter` reutiliza contato por telefone, identificador ou e-mail na conta. Quando o contato ainda não tem empresa, liga-o à empresa calculada; quando ele pertence a outro lead da prospecção, preserva nome, dados e empresa já existentes ([`app/services/autonomia/prospecting/contact_converter.rb:38-53,64-83,98-114`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/contact_converter.rb#L38)).
4. O card recebe `contact_id`, `title: @lead.name`, prioridade, descrição e `metadata.autonomia_prospecting.company` com apenas `id`, CNPJ e razão social ([`app/services/autonomia/prospecting/crm_card_converter.rb:94-105,119-130,153-168,187-192`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/crm_card_converter.rb#L94)). Portanto, o título da oportunidade é específico e estável, mas hoje não deve ser tratado como a identidade principal da empresa.

### Reuso e duplicação: o que está garantido

- Reenviar o mesmo lead retorna o card vinculado, sem criar novo card, contato ou empresa; o vínculo do lead e o `external_id` são as duas proteções do fluxo ([`app/services/autonomia/prospecting/crm_card_converter.rb:23-40,74-76,108-110`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/crm_card_converter.rb#L23), [`spec/services/autonomia/prospecting/crm_card_converter_spec.rb:44-51`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/spec/services/autonomia/prospecting/crm_card_converter_spec.rb#L44)).
- Leads diferentes podem gerar cards diferentes para a mesma empresa. Isso é compatível com o domínio: o card é por lead/oportunidade, não por empresa. O dedupe de empresa ocorre antes, pela chave empresarial; não existe `company_id` no modelo do card ([`app/services/autonomia/prospecting/company_upserter.rb:61-66,88-103`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/company_upserter.rb#L61), [`app/models/crm/card.rb:24-32`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/models/crm/card.rb#L24)).
- Contatos compartilhados por telefone/e-mail também são uma regra explícita. O segundo lead aponta para o mesmo contato, mas a empresa calculada para ele pode ser outra; a própria spec confirma `second.contact == first.contact`, `contact.company == first.company` e `second.company != first.company` ([`spec/services/autonomia/prospecting/contact_converter_spec.rb:172-216`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/spec/services/autonomia/prospecting/contact_converter_spec.rb#L172)). Isso evita renomear ou mover silenciosamente um contato existente, mas cria uma divergência que a UI precisa conhecer.

### Bloqueador para a hierarquia “empresa → pessoa → oportunidade”

**P1 de contrato visual/dados:** hoje não existe uma fonte única que entregue a empresa correta de um card de prospecção.

- O payload compacto usado pelo Kanban serializa do contato somente `id`, `name` e telefone; não serializa `contact.company` nem `metadata.autonomia_prospecting.company` ([`app/services/crm/kanban/card_payload_builder.rb:75-85,122-129`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/kanban/card_payload_builder.rb#L75)). O preload do board também não carrega a empresa ([`app/services/crm/kanban/board_payload_builder.rb:143-151`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/kanban/board_payload_builder.rb#L143)). A lista/API completa entrega os atributos JSON do contato, mas continua sem a relação canônica da empresa ([`app/services/crm/cards/payload_builder.rb:185-200`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/payload_builder.rb#L185)).
- O payload completo do card expõe `additional_attributes`, onde há o texto legado `company_name`, mas isso não é uma relação canônica. O Enterprise mantém esse texto sincronizado a partir de `contact.company` ([`app/services/crm/cards/payload_builder.rb:185-200`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/payload_builder.rb#L185), [`enterprise/app/models/enterprise/concerns/contact.rb:43-50`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/models/enterprise/concerns/contact.rb#L43)).
- Para o caso de dois leads com telefone/e-mail compartilhado, usar ingenuamente `card.contact.company` pode mostrar a empresa do primeiro lead no card do segundo. Usar somente a descrição, `company_name` ou `research.company` também pode mostrar texto antigo ou não persistido. O código preserva a empresa do lead atual no metadata do card, mas o Kanban não o entrega com nome ([`app/services/autonomia/prospecting/crm_card_converter.rb:153-168,187-192`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/prospecting/crm_card_converter.rb#L153)).

Isso é risco concreto para a proposta visual, não uma falha de dedupe: a regra de compartilhar contato é intencional; falta representar a empresa da oportunidade sem confundi-la com a empresa atual do contato compartilhado.

### Contrato mínimo recomendado antes da UI

- Para card `source = autonomia_prospecting`, o backend deve resolver de forma account-scoped o `metadata.autonomia_prospecting.company.id` e expor `company: { id, name }` no payload compacto e completo, com carregamento em lote para não fazer N+1. Se o metadata não tiver empresa, usar `contact.company` como fallback explícito.
- Para card genérico de conversa, usar `contact.company` quando existir; não usar `additional_attributes.company_name` como identidade primária. A implementação Enterprise precisa manter o campo como opcional para contas sem Companies.
- No Kanban, a ordem pode então ser: empresa principal; pessoa (`contact.name`) abaixo; título da oportunidade em menor hierarquia para distinguir dois cards da mesma empresa. Sem empresa, pessoa é a principal; sem contato, mostrar título/“sem pessoa” e nunca o nome da inbox como se fosse cliente.
- `responsible`/owner continua sendo o atendente ou bot, e `inbox` continua sendo a origem da conversa. Nenhum dos dois pode ocupar o lugar de empresa ou pessoa ([`app/models/crm/card.rb:140-159`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/models/crm/card.rb#L140), [`app/javascript/dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue:63-81`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/javascript/dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue#L63)).

### Matriz de aceitação da trilha

| Cenário | Resultado esperado |
|---|---|
| Lead com empresa e decisor, primeiro envio | Uma empresa canônica do card, pessoa abaixo, título menor; resposta traz os IDs criados. |
| Lead sem decisor | Empresa principal, sem inventar pessoa; nome do contato pode ser o nome da empresa, então a UI deve evitar duplicação visual. |
| Lead B2C sem empresa | Pessoa principal; nenhum rótulo de empresa vazio ou fabricado. |
| Dois leads da mesma empresa | Dois cards/opportunidades distintos, mesma empresa quando o vínculo for o mesmo; não fundir cards. |
| Dois leads com telefone/e-mail compartilhado e empresas diferentes | O contato pode ser compartilhado, mas cada card deve mostrar a empresa da oportunidade; `contact.company` sozinho não basta. |
| Reenvio do mesmo lead | Um único card; retorno `existing` não deve apagar o vínculo local nem criar novo contato/empresa. |
| “Usar como contato” depois do card | Pessoa pode mudar conforme a regra de adoção; empresa da oportunidade e título permanecem estáveis. |
| Card automático sem contato | Título ou identificador da conversa; nunca inbox apresentada como pessoa. |

**Parecer:** a cadeia de criação/reuso está account-scoped e tem cobertura estática para reuso, concorrência e compartilhamento de contato. A tela pode adotar a hierarquia solicitada depois que o payload trouxer uma empresa explicitamente resolvida por card; sem isso, há risco real de exibir a empresa errada em contatos compartilhados. Não executei requests autenticados, banco, navegador ou modelo pago nesta seção.

## Conferência visual ao vivo pelo integrador

Rodrigo autorizou as abas existentes do Chrome. Foram lidos o Kanban da conta 16
no Chat2You e da conta 20 no destino autenticado agents.autonomia.site, além dos
resultados já existentes de Prospecção e da janela de envio ao CRM da conta 16.
Não houve nova busca, enriquecimento, conversão ou gravação. Nenhum dado de cliente
foi copiado para fixtures, documentos ou capturas versionadas.

As telas confirmam nomes de pessoa/empresa misturados no título, pessoa secundária
quando diferente e cards avulsos sem contato. A Prospecção destaca o nome da empresa,
com decisor em outro nível, e pede funil/estágio antes do envio. Isso comprova a UI
observada, sem atribuir origem de Prospecção a um card apenas pelo seu nome.

## Decisão visual revisada

Empresa do card em destaque, contato abaixo, negócio menor quando distinto.
Sem empresa, contato principal; sem ambos, título e indicação de vínculo ausente.
Os nomes persistidos são preservados. Responsável e inbox não viram identidade
do cliente. A consulta e o filtro devem usar a mesma empresa resolvida por card.
O cenário fictício Prospecção · exemplo mostra dois cards com o mesmo contato e
empresas diferentes, além de título/contato/empresa iguais sem repetição visual.
