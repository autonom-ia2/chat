# MCP nativo com OAuth (#3089)

O Chat2You publica o próprio servidor MCP. Quem **administra** uma conta cola o endereço no app (Em d.ia,
Claude, ChatGPT), clica em conectar, entra com o login de sempre e permite. O app passa a usar a plataforma com
as permissões dessa pessoa, em todas as contas ativas que ela administra (#3106).

| Instalação | Endereço MCP |
|---|---|
| Hub2You | `https://chat.hub2you.ai/mcp` |
| Autonom.ia | `https://agents.autonomia.site/mcp` (também responde em `chat.autonomia.site`) |

## Base

Porte da branch `feat/mcp-server` do Chatwoot (06–07/10/2026, ainda fora do `develop` deles), commits
`ad55a2ca47..02a3873d7f` com `cherry-pick -x`. A migration mantém o nome do upstream
(`20261006173150_create_doorkeeper_tables`) para o merge futuro não duplicar as tabelas.

- **Doorkeeper**: authorization code com PKCE S256 obrigatório, refresh token rotativo, segredos guardados só
  como hash. O `account_id` do token é só a conta padrão: a conta em que a pessoa estava na tela de
  consentimento, ou a primeira que ela administra.
- **DCR** (`POST /oauth/register`, RFC 7591): cliente público, sem segredo. É como Claude e ChatGPT se registram.
- **CIMD** (`Oauth::ClientMetadataDocument`): o `client_id` é a URL https de um documento JSON com
  `client_name` e `redirect_uris`. É como o Em d.ia se identifica. A busca só aceita https, sem redirecionamento,
  só na porta 443, com o host resolvendo só para endereço público e a conexão indo ao endereço conferido; 5 s no
  total e 16 KB no máximo; o cliente conhecido é relido no máximo a cada hora, e o documento recusado só é buscado
  de novo depois de 10 min. Os escopos do documento são ignorados: cada pedido de
  autorização pede os seus, e o Doorkeeper confere.
- **Consentimento**: `/oauth/authorize` leva à tela `/app/accounts/:id/oauth/authorize`. Sem sessão, o login (SSO
  da Autonom.ia ou e-mail e senha) devolve à mesma tela. A tela diz que a conexão vale para todas as contas que a
  pessoa administra, com os nomes, sem pedir para escolher uma, e mostra, em destaque, o endereço que vai receber o acesso: o nome do app é escolhido por quem o
  registrou, o endereço não.
- **`/mcp`**: Streamable HTTP sem estado (gem `mcp`). Recusa token revogado, vencido, ou de quem não administra
  mais nenhuma conta ativa. Cada ferramenta roda como a pessoa, com as policies do painel.
- **Várias contas** (#3106): `list_accounts` lista as contas ativas que a pessoa administra e marca a padrão. Toda
  outra ferramenta aceita `account_id`, e sem ele usa a padrão. A lista é lida em cada chamada
  (`Mcp::AccountAccess`): uma conta que a pessoa passa a administrar entra na hora, e uma que ela deixa de
  administrar, ou que é suspensa, sai na hora. O super admin é cadastrado em todas as contas, então não tem regra
  própria.
- **Apps conectados**: Perfil → Apps conectados, com o botão para desconectar.

## Escopos e ferramentas

| Escopo | Ferramentas |
|---|---|
| `conversations:read` | `list_accounts`, `list_inboxes`, `list_conversations`, `get_conversation`, `list_labels`, `list_teams`, `list_agents`, `list_canned_responses` |
| `conversations:write` | `update_conversation`, `assign_conversation` |
| `messages:write` | `send_message` (resposta ao cliente ou nota interna) |
| `contacts:read` | `search_contacts`, `get_contact`, `list_companies`, `get_company` |
| `contacts:write` | `create_contact`, `update_contact`, `add_contact_note` |
| `reports:read` | `get_report_summary` |

Toda ferramenta de escrita sai com `readOnlyHint: false`: o Claude e o ChatGPT pedem confirmação à pessoa antes.
No Em d.ia quem pede é o prompt. As próximas ondas (CRM e Relacionamentos, Marketing, Automação e IA) entram
no mesmo `Mcp::Tools::ALL`.

## Ligar numa instalação

1. Migration do Doorkeeper (deploy normal).
2. Super Admin → App Config: `OAUTH_PROVIDER_ENABLED = true`. Antes disso nenhuma rota OAuth/MCP existe (404).
3. Instalação com mais de um endereço: `OAUTH_PROVIDER_EXTRA_HOSTS=chat.autonomia.site` (lista separada por
   vírgula). É variável de ambiente do container (web), não App Config do Super Admin. Os metadados e o desafio do `/mcp` passam a nomear o host que o cliente usou.

Limites de frequência (Rack::Attack, sem teto diário): `RATE_LIMIT_MCP` (300/min por token),
`RATE_LIMIT_OAUTH_TOKEN` (60/min por IP e cliente juntos; Claude e ChatGPT renovam de servidores compartilhados, e o ID público de um cliente sozinho não esgota a cota de ninguém),
`RATE_LIMIT_OAUTH_AUTHORIZATION` (60/min por IP na API da tela de consentimento, que pode buscar o CIMD) e
`RATE_LIMIT_OAUTH_REGISTRATION` (100/h por IP).

## Desligar

`OAUTH_PROVIDER_ENABLED = false` some com todas as rotas na hora, sem apagar nada. Para cortar um app de uma
pessoa: Perfil → Apps conectados → Desconectar (revoga tokens e grants).

## Dependências

`doorkeeper ~> 5.9` e `mcp ~> 1.7`. A gem `mcp` exige `json_schemer >= 2.4`: o lock sobe de 0.2.24 para 2.5.0
(usada também pelos validadores de JSON do fork). O 2.x lê esquema sem `$schema` como draft 2020-12 e
expressões como Ruby; os esquemas do fork foram escritos para draft 7 e ECMA, então todos passam por
`JsonSchemaDraft7.schema`, que fixa os dois. Só o MCP usa a gem direto. `tidewave` (só desenvolvimento) sobe para
0.9.0, que não depende mais do `fast-mcp`.
