# Contrato de carregamento Instagram — 2026-10-07

Este documento registra a origem do contrato de carregamento usado pela PR #1112. Ele não contém cookies, respostas completas, nomes de clientes, IDs pessoais ou dados de usuários. Os cinco `doc_id` da fixture são identificadores públicos de documentos compilados e ficam separados no arquivo de teste versionado.

## Evidência

O diagnóstico somente leitura `observe-loading-responses.mjs` foi executado uma vez no mesmo perfil e proxy do serviço, sem publicação. O recibo sanitizado é `.codex/loading-responses-110725-receipt.txt` (SHA-256 `b34a2e3ec28082b31ec1569120dca7e1c95ca676df06239e19c80117ccdb4cf7`). A fonte executada tem SHA-256 `7a5ed066f0ebf1bc0bc084592e22e54ad48aa61de1ed5ab0d842c6111c58b033`.

Depois, o coletor somente leitura `collect-loading-public-documents.mjs` confirmou os cinco identificadores públicos contra os SHA aprovados, sem ler respostas, cookies ou configuração de autenticação. Seu recibo sanitizado é `.codex/loading-public-documents-111618.json` (SHA-256 `0cc73cb3c2241332f315f0fe530d171282ffdd610ed75cb6b6bb0c5c960fbde0`) e a fonte tem SHA-256 `dcb66065ab8b0a6714b4d335f40ac193e244778c074f8629587c6959611e670c`. A fixture local foi validada antes de ser reduzida à metadata pública versionada em `tests/instagram_testers/fixtures/loading-documents.json`.

O recibo observou a inicial e quatro queries de carregamento permitidas, todas com identidade correspondente, e a resposta `RolesTable_Query` original com HTTP 200, `data.get_app_roles` e validação completa. A resposta do Header veio HTTP 200, mas não foi JSON; ela não é usada para captura nem para aceite. As demais respostas de carregamento observadas eram JSON sem erro e com vínculo de aplicativo. A Overlay permaneceu bloqueada em três ocorrências e não participa do contrato.

## Pins públicos

Os valores abaixo são SHA-256 dos identificadores públicos `doc_id` observados. O código compara o hash do identificador recebido; não fabrica nem repete requisições.

| Query | SHA-256 do documento |
|---|---|
| `GeoNextAppControllerContainerQuery` | `e3050f6f5039fae023bca06560b9aba52597bccd045d0e84bf1388e8abeca508` |
| `DeveloperHeaderComponentContainerQuery` | `34abd55916c1d35a7c4f9aa7db399dd263dbc0b2bb5b85ac93df704b4050e7e2` |
| `DeveloperAppVisibilityToggleLazyLoadedQuery` | `eb759a93022e512816320a08284e22585c2eafb0476dbea91baf2c1431838f6e` |
| `DeveloperAppBannerQuery` | `108dc0b68c940503ae888f48ab296b1e6e1ac323398ef236f4968db71b2c7abd` |
| `DeveloperAppDashboardSidebarNavigationV2Query` | `998762536e2ad143534eb74762e333c33d763c5bc97b52df2fb8d828f5f5582b` |

Para as cinco queries, o endpoint precisa ser exatamente `https://developers.facebook.com/api/graphql/`, o método precisa ser `POST`, e `__bid`, `__user` e `av` precisam corresponder à configuração canônica. As variáveis são exatas: a inicial, Visibility, Banner e Sidebar usam somente `appID` igual ao aplicativo; Header usa somente `businessID` igual ao negócio e `businessID_is_null: false`.

O nome `MetaDeveloperAssistantPageOverlayQuery` continua fora da lista de permissão e é abortado. `RolesTable_Query` continua passando pelo filtro original. A observação/publicação da sessão considera exclusivamente a resposta completa e válida de `RolesTable_Query`; respostas de carregamento não reservam publicação.

## Fontes relacionadas

- Diagnóstico de metadata compilada: `.codex/loading-documents-110208-receipt.txt` (SHA-256 `9157a51252c9d8a8532538db253e8a85b2eaca2e23c12ba251c0cbc9740557f5`).
- Coleta dos identificadores públicos: `.codex/loading-public-documents-111618.json` (SHA-256 `0cc73cb3c2241332f315f0fe530d171282ffdd610ed75cb6b6bb0c5c960fbde0`).
- Diagnóstico da resposta inicial: `.codex/browser-105544-receipt.txt` (SHA-256 `c0c7f0ec5fdc80bd8b32c0042bbb32a2bf3a79720ce9d251926d819a8c842cbc`).
- Fixture pública versionada: `tests/instagram_testers/fixtures/loading-documents.json`.
- Código canônico de identidade, resposta e captura: `scripts/instagram_testers/session-observer.mjs` e `scripts/instagram_testers/session-manager.mjs`.
