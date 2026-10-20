# Funções personalizadas — Lote 0 (#1157)

Data: 08/10/2026. Base: `origin/main` `0ad23bca99`. Branch `fix/1157-funcoes-lote0`.

## Origem

Rodrigo relatou que uma função com Campanhas liberado não via Anúncios Meta e pediu avaliação
completa. A auditoria (3 varreduras: 190 rotas e menu, 252 controllers e 90 policies, PRs desde
20/09) achou brechas no servidor, travamentos e telas sem chave. Decisões do Rodrigo em 08/10:
chave própria `meta_ads_view` (Lote 1, #1158); fechar só a listagem do módulo Contatos; manter o
#1136 como documento da etapa de escopos. Este lote cobre as brechas e os travamentos.

## O que mudou

| Item | Antes | Depois | Evidência |
|---|---|---|---|
| CRM em massa | só `index?`: quem via cards movia, reatribuía, fechava e arquivava 100 por chamada | por card, a mesma policy da ação individual (`move?`, `update?`, `close?`, `destroy?`); a barra só mostra o permitido e avisa quando algum card não mudou | `cards_bulk_permissions_spec.rb` (falha sem a correção) |
| Contatos | `contact_view` nunca conferido no servidor | lista, ativos, resumo, filtro e lista de empresas exigem `contact_view`/`contact_manage` numa função; contato aberto pela conversa/card e busca seguem abertos | `contacts_module_read_spec.rb` (falha sem a correção) |
| Custo de IA do CRM | todo agente via o gasto da conta | `crm_manage_ai` (`crm_admin` implica) na policy, rota, menu e escopo de token | `ai_usage_spec.rb` (OSS e EE) |
| Facebook | cadastrar página e trocar token sem conferência | `inbox_manage` | `callbacks_controller_spec.rb` |
| Linear | issue em conversa que a pessoa não vê | `show?` da conversa | `linear_controller_spec.rb` |
| PATCH do agente | sem `custom_role_id`, apagava a função; aceitava id de outra conta | só mexe quando o campo vem; função de outra conta → 404 antes de gravar | `agents_controller_spec.rb` (EE) |
| Lista de conversas | "não atribuídas" + "participando": aplicava só a primeira | soma as duas, como a abertura (`ConversationPolicy#show?`) | `permission_filter_service_spec.rb` (falha sem a correção) |
| `crm_admin` antigo | editor mostrava "Ver"; rotas do CRM negavam | editor mostra "Editar"; payload de permissões leva `_manage`→`_view` e `crm_admin`→todas `crm_*` | `account_user_spec.rb`, `permissionMatrix.spec.js` |
| Login de função sem área inicial | mandado ao `/dashboard`, negado, reenviado | vai para o perfil; o menu mostra as áreas da função | `routeHelpers.spec.js` |
| Tela nova sem decisão | nada obrigava | `scripts/guide-map/funcoes.mjs` na trava do Guia: rota aceita chave de função ou entra em `adminOnlyRoutes.json` com motivo | `scripts/guide-map/specs/funcoes.spec.js` |

## Fora deste lote, com motivo

- **Modelos de CSAT** (`inbox_policy.rb#manage_csat_templates?`): membro da caixa cria modelo por
  decisão registrada no #452 (comportamento do Chatwoot preservado). Não mexido.
- **Sugestões de FAQ do Captain**: revisadas pelos atendentes por desenho do Chatwoot (rota aceita
  chaves de conversa). Não é brecha.
- **SAML/SSO** atribuem `custom_role_id` direto, sem o controller de agentes. Fora do PATCH; não
  mexido.
- Telas sem chave (Anúncios Meta, Modelos do WhatsApp, Mídia da empresa e outras): Lote 1, #1158.
  Já listadas em `adminOnlyRoutes.json` como pendentes; a checagem obriga tirá-las ao abrir.

## Riscos

- **Token de integração (n8n) que lia o custo de IA com `crm_view_reports`** passa a precisar
  de `crm_manage_ai`. Conferir tokens em produção antes do merge (consulta só de leitura, com OK).
- **Agente comum deixa de ver o custo de IA.** Decisão aprovada em 08/10 (gasto da conta).
- **Função sem `contact_view`** deixa de listar contatos pela API e pela tela Contatos. Dentro da
  conversa e do card nada muda.
- Payload de permissões maior para funções com `_manage`/`crm_admin`: só amplia o que
  `permission_granted?` e `crm_permission?` já concediam no servidor.

## Validação local

Serviços de teste isolados (Postgres 55432, Redis 56379), Ruby 3.4.4 e Node 24 do MacCluster.
Cada spec novo foi rodado contra o código original (arquivo de produção revertido para `HEAD`)
e falhou; com a correção, passou. Resultados da bateria ampla e da revisão independente no PR.
