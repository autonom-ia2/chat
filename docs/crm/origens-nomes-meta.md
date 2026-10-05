# Origens do contato e nomes das campanhas da Meta (#1034)

Contrato técnico. Base: `docs/crm/ponte-lp-atribuicao.md` (#1011). Construção aditiva: arquivos e tabelas do fork.

## 1. Problemas

1. O card guarda até 20 toques (`conversation.additional_attributes['campaign_touches']`, agregados por
   `Crm::Cards::PayloadBuilder.aggregated_campaigns_for`). A tela mostra só o primeiro, e o "+N" é um número sem ação.
2. Os parâmetros automáticos da Meta trazem IDs (`utm_campaign=120254710067060416`, `utm_term=<adset id>`,
   `utm_content=<ad id>`). O cliente quer ver os nomes.

## 2. Credencial de leitura de anúncios (por conta)

Tabela nova `crm_meta_ads_connections`:

| coluna | tipo | uso |
|---|---|---|
| `account_id` | bigint, not null, índice único | uma por conta |
| `access_token` | text, not null | `encrypts :access_token`; exige `Chatwoot.encryption_configured?` (igual a `AiProviderCredential`) |
| `status` | string, not null, default `'active'` | `active` \| `invalid` (a Meta recusou) |
| `last_checked_at` | datetime | último teste ou uso com sucesso |
| `last_error` | string(255) | mensagem curta e sanitizada (`Meta::ConversionsApiClient::SENSITIVE_PATTERN`) |
| timestamps | | |

**API (somente administrador da conta):** `GET/PUT/DELETE /api/v1/accounts/:account_id/crm/meta_ads_connection`.

- `GET` → `{ configured: bool, status, last_checked_at, last_error }`. **Nunca** devolve o token nem parte dele.
- `PUT { access_token }` → testa antes de salvar com `GET /me/permissions`, que precisa ter `ads_read` com status
  `granted`.
  - Sem `ads_read`: 422 com `error: 'missing_ads_read'`.
  - Token recusado: 422 com `error: 'invalid_token'`.
  - Em caso de sucesso: grava, devolve o mesmo formato do `GET` e enfileira a resolução retroativa (seção 4).
- `DELETE` → apaga a credencial. Os nomes já resolvidos ficam.

O token vai só no header `Authorization: Bearer`. Nunca entra em log, erro, payload, webhook ou Sentry. Acrescentar
`access_token` a `filter_parameters`, se ainda não estiver. Strong params só aceitam `access_token`.

## 3. Resolução de nomes

Tabela nova `crm_meta_ad_objects` (cache):

| coluna | uso |
|---|---|
| `account_id`, `object_id` (string) | índice único por conta |
| `object_type` | `ad` \| `adset` \| `campaign` |
| `name` | string(255) |
| `campaign_id`, `adset_id` | para anúncios |
| `fetched_at` | datetime |

`Crm::MetaAds::NameResolver.new(account).resolve(ids)`:

- **ID** = string só de dígitos, entre 6 e 30 caracteres, conferida sem regex (`str.each_char.all? { _1 >= '0' && _1 <= '9' }`).
- Primeiro o cache, válido por 7 dias. Os IDs que faltam vão num lote:
  `GET /v22.0/?ids=a,b,c&fields=name,adset{id,name},campaign{id,name}` para anúncios, ou `fields=name` quando o tipo
  for desconhecido. No máximo 50 por chamada, timeout de 8 s.
- **Token inválido** (código 190) → `status: invalid`, `last_error` sanitizado, e nada é resolvido.
- **Falta de permissão** (código 10 ou 200–299) → confere `GET /me/permissions` uma vez por execução. Sem `ads_read`
  `granted` (ou com o próprio `/me/permissions` recusado) → `invalid`, como acima. Com `ads_read` concedida, é um
  objeto fora do alcance do token (por exemplo, de outra conta de anúncios) e vale como erro de objeto. Assim, um ID
  de uma conta sem acesso não derruba a credencial inteira.
- **Erro por objeto** (código 100 ou 803) → o lote é refeito ID a ID; o ID que falha sozinho entra no cache sem nome
  (**cache negativo**, `name: nil`, `fetched_at: agora`) e fica 7 dias sem nova busca. Um nome já conhecido do mesmo
  ID é mantido (só `fetched_at` muda).
- **Indisponibilidade** (limite de taxa 4, 17, 32, 613, 80000+; HTTP 5xx; rede) → para a busca naquela execução,
  devolve só o que está no cache, não refaz ID a ID e não mexe na credencial.
- Devolve `{ id => { name:, type:, campaign_name:, adset_name: } }`.

`Crm::MetaAds::EnrichTouchesJob(conversation_id)`:

- Para cada toque, monta os IDs: `utm_content` (anúncio), `utm_term` (conjunto) e `utm_campaign`/`utm_id`
  (campanha), quando forem IDs. Nos toques `meta_ctwa`, o `source_id` é o ID do anúncio.
- Grava no toque, com lock e merge, sem apagar chaves: `ad_name`, `adset_name`, `campaign_name`. O `headline` só
  é refeito em toque de site cujo headline atual seja `"<nome da origem> · <ID>"`; passa a
  `"<nome da origem> · <campaign_name>"`. Faz o mesmo no `campaign` (origem) quando ele for o mesmo toque.
- Re-transmite os cards (`Crm::Cards::RebroadcastConversationCardsJob`).
- Sem credencial ativa: não faz nada.

**Quando roda:**

- logo depois de cada atribuição (`Ctwa::CampaignBuilder.attribute!` com toque persistido) que tenha algum ID — no
  máximo uma vez por conversa a cada 5 min;
- na resolução retroativa (`Crm::MetaAds::BackfillJob(account_id)`), ao salvar a credencial: conversas da conta
  com toques dos últimos 90 dias que tenham ID e não tenham nome. Os IDs de todas as conversas são resolvidos uma
  vez, por tipo, e o mesmo resultado é gravado em cada conversa (sem nova consulta por conversa).

## 4. Payload do card

`campaign_touches_for` passa a expor `campaign_name`, `adset_name`, `ad_name` e `touched_at` (já expõe os `utm_*`).

## 5. Interface

- **`useCrmOrigin`.** Rótulos da hierarquia: o `*_name`, se houver; senão o `utm_*`. Valor só de dígitos
  aparece como "ID 1202…0416" (completo no título). As linhas são Campanha, Conjunto e Anúncio. Para toque CTWA sem
  nome resolvido, o anúncio é o `headline`.
- **Componente novo `CrmOriginList.vue`.** Lista todos os toques, do primeiro ao último: data curta, ícone e rótulo
  da origem, hierarquia (só as linhas que existem) e link do post quando houver `source_url`. Máximo de 20.
- **Drawer.** Seção "Origens do contato" com o `CrmOriginList` quando houver mais de um toque; com um toque só, a
  hierarquia como hoje.
- **Kanban.** O "+N" do selo vira um botão acessível (`aria-expanded`, `aria-controls`, Esc fecha, foco volta ao
  botão) que abre um popover com o `CrmOriginList`. O clique não abre o card (`stop`). Usar o padrão de popover já
  existente em `components-next`; nada de CSS próprio.
- **Credencial:** em **Links e QR codes**, um bloco "Nomes das campanhas da Meta":
  - status: não conectado / conectado (verificado há X) / precisa atenção (com `last_error`);
  - botão "Conectar" abre um diálogo para colar o token, com passo a passo curto e o botão "Testar e salvar";
  - "Remover" com confirmação;
  - só administrador vê e edita.
- Textos en + pt_BR no `crm.json` do fork; Guia (`porques.md`) atualizado.

## 6. Fora do escopo

Filtro por nome de campanha (o filtro atual por `source_id` segue valendo); renomeação de campanha (o cache de
7 dias atualiza); outras plataformas.
