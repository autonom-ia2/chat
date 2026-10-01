# Auditoria do Guia da Plataforma para consultas CRM

**Data:** 2026-10-01  
**Escopo:** leitura estática, sem produção, contas autenticadas, banco externo, IA paga ou edição do produto.  
**Checkout local:** `12b6433b639ae1a31e38f50eabb227c7719a518d`, com alterações locais não relacionadas.  
**Referência da implementação atual auditada:** `origin/main` em `902f0059d76da8b1c74c47f57c8e66edc6d55bca`.

## Parecer curto

O Guia atual não é apenas RAG. Ele tem uma ferramenta de leitura runtime, `ler_da_conta`, que escolhe uma rota GET real da conta, chama a própria pilha Rails com o usuário atual e resume a resposta para o modelo. Isso já cobre conversas, funis e cards; também pode consultar empresas no Enterprise quando o recurso está habilitado.

A pergunta “quero as oportunidades da Norte” ainda não tem um caminho determinístico completo. Hoje `crm/cards?search=Norte` procura somente em `crm_cards.title`. “Norte” como nome de empresa não é resolvido pelo filtro de cards, e o card não carrega a empresa canônica no payload compacto. O Guia poderia encontrar a empresa e seus contatos, mas não há um filtro de oportunidades por `company_id` ou por uma lista de `contact_id` que feche a consulta sem ler uma lista parcial e tentar casar texto.

## Evidência da leitura runtime

- A ferramenta nativa é `Autonomia::Agents::Tools::Native::GuiaLeitura`, com slug `ler_da_conta`; sua descrição diz que lê dados reais da conta e aceita novas leituras, páginas e campos ([`app/services/autonomia/agents/tools/native/guia_leitura.rb:23-70`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/agents/tools/native/guia_leitura.rb#L23)).
- O Guia nasce com `ler_da_conta`, `propor_acao`, `mostrar_tela` e `ler_da_central` no config canônico ([`app/services/autonomia/guide/seed.rb:18-22,155-179`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/seed.rb#L18)).
- O loop passa `operador: contexto` e permite até dez rodadas para ler, observar e consultar outra página/recurso ([`app/services/autonomia/guide/chat.rb:62-77`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/chat.rb#L62), [`app/services/autonomia/agents/answerer.rb:281-290,341-360`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/agents/answerer.rb#L281)).
- O catálogo de recursos é derivado das rotas GET do Rails, não de uma lista fixa ([`app/services/autonomia/guide/consulta.rb:34-41`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/consulta.rb#L34)).
- A ferramenta recebe o recurso, parâmetros de rota em JSON, status, página e campos; parâmetros simples adicionais são encaminhados como query string ([`guia_leitura.rb:35-55,78-93`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/agents/tools/native/guia_leitura.rb#L35), [`consulta.rb:60-66,128-141`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/consulta.rb#L60)).
- A chamada interna fixa o `account_id` da conta do turno, usa o token do usuário e restaura o estado `Current` ao terminar ([`app/services/autonomia/guide/rotas.rb:10-33`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/rotas.rb#L10), [`app/services/autonomia/guide/chamada_interna.rb:25-46,64-70`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/chamada_interna.rb#L25)).
- A resposta é resumida com teto, mantém totais quando a API fornece e remove nomes conhecidos de segredos ([`app/services/autonomia/guide/resumo.rb:17-23,47-59,76-90,167-181`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/resumo.rb#L17)).
- A spec de integração contra a aplicação real confirma leitura de recursos da conta, item por id, recusa de recurso fora do catálogo, isolamento de outra conta e tratamento de 401/403 ([`spec/services/autonomia/guide/consulta_spec.rb:19-88,91-124`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/spec/services/autonomia/guide/consulta_spec.rb#L19)).

O checkout local `12b6433b63` é anterior a essa ferramenta: nele o Guia usa `Leituras` com cinco assuntos pré-definidos e o `Seed` não liga ferramentas nativas ([`app/services/autonomia/guide/chat.rb:34-44,151-177`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/chat.rb#L34), [`app/services/autonomia/guide/seed.rb:149-171`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/guide/seed.rb#L149)). Por isso não usei o checkout local antigo para negar a capacidade de `origin/main`.

## O que já pode ser consultado

| Assunto | Evidência | Limite atual |
|---|---|---|
| Conversas | O roteador expõe GET `conversations`, `conversations/search`, `conversations/meta`; o catálogo do Guia inclui `conversations` e a spec confirma isso ([`config/routes.rb:474-510`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/config/routes.rb#L474), [`spec/services/autonomia/guide/consulta_spec.rb:19-25`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/spec/services/autonomia/guide/consulta_spec.rb#L19)). | O leitor da ferramenta só chama GET. O filtro POST de conversas não entra no catálogo; o GET usa os filtros do `ConversationFinder`, como status, inbox, assignee, team, labels, `q` e paginação ([`app/finders/conversation_finder.rb:60-71,73-107,135-168,193-207`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/finders/conversation_finder.rb#L60)). |
| Funis | GET `crm/pipelines` está nas rotas CRM e no catálogo; o endpoint aplica `policy_scope` e ordena pipelines da conta ([`config/routes.rb:205-212`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/config/routes.rb#L205), [`app/controllers/api/v1/accounts/crm/pipelines_controller.rb:1-10,36-43`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/controllers/api/v1/accounts/crm/pipelines_controller.rb#L1)). | É possível listar e abrir funis/estágios, mas isso não cria por si só uma busca semântica por oportunidade. |
| Cards/oportunidades | GET `crm/cards` existe; o controller usa `policy_scope(Crm::Card)` e `Crm::Cards::FilterQuery` ([`config/routes.rb:220-236`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/config/routes.rb#L220), [`app/controllers/api/v1/accounts/crm/cards_controller.rb:15-21,339-345`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/controllers/api/v1/accounts/crm/cards_controller.rb#L15)). | Filtros atuais incluem pipeline, inbox, owner, prioridade, external id, estágios, equipe, valor, stale, responsável, labels, campanhas, follow-up, status e ordenação ([`app/services/crm/cards/filter_query.rb:4-10,31-37,63-76,92-115`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/filter_query.rb#L4), [`app/services/crm/cards/shared_filters.rb:16-21,38-107`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/shared_filters.rb#L16)). |
| Empresas | Enterprise expõe GET `companies`, `companies/search` e `companies/:company_id/contacts`; a busca da empresa usa nome ou domínio ([`config/routes.rb:521-542`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/config/routes.rb#L521), [`enterprise/app/controllers/api/v1/accounts/companies_controller.rb:25-34,68-89`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/controllers/api/v1/accounts/companies_controller.rb#L25), [`enterprise/app/models/company.rb:38-47`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/models/company.rb#L38)). | A rota é protegida pelo feature gate `companies` e por autorização. Não há ligação posterior automática entre empresa encontrada e filtro de cards. |

## Autorização e isolamento

- O controller do Guia só aceita conta elegível; a pergunta vira job com `account_id` e `user_id`, e a resposta de outro usuário/conta não é devolvida ([`app/controllers/api/v1/accounts/autonomia/guide_controller.rb:7-27,34-40,89-101`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/controllers/api/v1/accounts/autonomia/guide_controller.rb#L7)).
- A leitura passa pela API real, logo herda controller, Pundit, papéis e funções personalizadas. Para cards, o escopo inclui a conta e limita agentes a cards dos inboxes, atribuídos, participados ou próprios ([`app/policies/crm/card_policy.rb:1-12,71-87`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/policies/crm/card_policy.rb#L1), [`app/services/crm/cards/visible_scope_query.rb:9-23,25-67`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/visible_scope_query.rb#L9)).
- Empresas são Enterprise e dependem de `Current.account.feature_enabled?('companies')`; a busca usa `Current.account.companies`, portanto não deve cruzar contas ([`enterprise/app/controllers/api/v1/accounts/companies_controller.rb:11-18,25-34,68-89`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/controllers/api/v1/accounts/companies_controller.rb#L11), [`enterprise/app/controllers/api/v1/accounts/companies/base_controller.rb:1-19`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/controllers/api/v1/accounts/companies/base_controller.rb#L1)).
- O modo sem `operador` recusa leitura; não existe uma permissão implícita do agente ([`guia_leitura.rb:60-70,96-101`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/autonomia/agents/tools/native/guia_leitura.rb#L60)).
- Isso é leitura runtime autorizada, não RAG. O RAG explica telas e conceitos; os dados da conta vêm da ferramenta e das rotas.

## Gap específico: “oportunidades da Norte”

1. O filtro `search` do board e da lista faz apenas `LOWER(crm_cards.title) LIKE ...` ([`app/services/crm/kanban/board_payload_builder.rb:85-90`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/kanban/board_payload_builder.rb#L85), [`app/services/crm/cards/filter_query.rb:98-103`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/filter_query.rb#L98)).
2. O relacionamento de uma oportunidade é `crm_cards.contact_id`; contato pode ter `company_id` opcional no Enterprise ([`app/models/crm/card.rb:24-32,183-199`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/models/crm/card.rb#L24), [`enterprise/app/models/enterprise/concerns/contact.rb:1-12`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/models/enterprise/concerns/contact.rb#L1)).
3. O payload compacto do Kanban serializa do contato somente `id`, `name` e `phone_number`; não inclui `company_id` ou `company.name` ([`app/services/crm/kanban/card_payload_builder.rb:75-85,122-129`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/kanban/card_payload_builder.rb#L75)).
4. O payload completo de cards inclui `additional_attributes` e `custom_attributes`, mas isso não é uma relação canônica de empresa nem um filtro. O Enterprise apenas sincroniza um texto legado `additional_attributes['company_name']` quando o contato muda ([`app/services/crm/cards/payload_builder.rb:185-200`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/app/services/crm/cards/payload_builder.rb#L185), [`enterprise/app/models/enterprise/concerns/contact.rb:43-50`](https://github.com/autonom-ia2/chat/blob/902f0059d76da8b1c74c47f57c8e66edc6d55bca/enterprise/app/models/enterprise/concerns/contact.rb#L43)).
5. Ler toda a lista de cards, extrair texto e tentar casar “Norte” seria incorreto para listas paginadas/truncadas e poderia confundir empresa, pessoa, pipeline ou título. O modelo deve perguntar quando a intenção estiver ambígua.

**Conclusão:** “Norte” como título de oportunidade pode funcionar com o `search` atual. “Norte” como empresa exige resolver a empresa/contatos e aplicar uma consulta de cards por essa relação. Hoje isso não está pronto como um único filtro.

## Recomendação mínima

Não mexer no RAG e não colocar interpretação de linguagem em regex ou no controller.

1. Manter o Guia e `Consulta` como orquestradores: eles já fornecem catálogo, operador, account scope, Pundit, paginação e resumo.
2. Criar um resolvedor de leitura CRM pequeno e tipado, usado apenas para essa intenção. O modelo produz um contrato restrito, por exemplo `entity: company|contact|card|pipeline`, termo, status, pipeline, estágio e paginação; o backend valida ids e valores antes da consulta.
3. Para `entity=company`, resolver nome/domínio por `companies/search` somente quando o recurso Enterprise estiver habilitado. Se houver mais de uma correspondência, pedir escolha; nunca escolher silenciosamente.
4. Consultar cards por relação account-scoped. O menor contrato OSS/Enterprise é adicionar um filtro de `contact_ids`/relação de contatos ao serviço de cards, com a implementação Enterprise para `company_id -> contact_ids`; a query deve partir de `policy_scope(Crm::Card)`. Não fazer N+1 nem buscar cards fora do escopo.
5. Expor a consulta como uma ferramenta nativa de leitura do Guia, ou como uma extensão estreita da leitura CRM existente. Não criar um “subagente” separado: o loop de ferramentas do Guia já suporta leituras em sequência.
6. Responder “não encontrei”, “há duas empresas” ou “não tenho acesso” com base no resultado real; preservar total/paginação e indicar quando há corte.

## Matriz curta de aceitação

| Cenário | Resultado obrigatório |
|---|---|
| Conta Enterprise com uma empresa “Norte” e três contatos ligados a ela | Retornar somente cards visíveis desses contatos, com total/página e pipeline/estágio corretos. |
| “Norte” existe como empresa e como título de oportunidade | Pedir esclarecimento ou mostrar as duas interpretações; não escolher uma por texto. |
| Duas empresas “Norte” ou nome parcial ambíguo | Pedir escolha, sem consultar ou expor cards até resolver o id. |
| Usuário sem acesso a um inbox/card | Aplicar `VisibleScopeQuery`; não revelar existência, nome ou total do card oculto. |
| Conta sem feature Companies ou sem relação empresa-contato | Informar que não há empresa disponível e oferecer busca por título/pessoa, sem inventar vínculo. |
| B2C, card sem contato/empresa | Tratar como oportunidade sem empresa; não fabricar “Norte” a partir de `additional_attributes`. |
| Muitos cards | Preservar total e paginação; nunca tratar a primeira página resumida como a conta inteira. |

**Limitação desta auditoria:** não executei requests autenticados, banco, navegador ou modelo pago. As conclusões são do código em `origin/main` e não equivalem a smoke test de produção.

