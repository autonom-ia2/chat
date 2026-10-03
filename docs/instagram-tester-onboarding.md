# Instagram: preparação opcional do convite de testador (#910)

Este fluxo ajuda a escolher um perfil, preparar seu convite de testador e verificar o aceite
antes de continuar pelo Instagram Login existente. Começa **desligado globalmente** e exige
também uma lista explícita de contas permitidas. A documentação descreve o código atual;
não declara a funcionalidade homologada em produção.

Operação por stack: [runbook](runbooks/instagram-tester-onboarding.md).
Entrega de segredos: [production-env-secrets.md](production-env-secrets.md).
Publicação: [production-deploy-gates.md](production-deploy-gates.md).

## O que muda para quem conecta

Em **Configurações → Caixas de entrada → Nova caixa → Instagram**, quando disponível:

1. Informe o `@` do perfil e clique em **Buscar perfil** ou pressione Enter.
2. Confira foto, `@` e nome. Selecione explicitamente o perfil, mesmo com um único resultado.
3. A seleção consulta o convite; não envia nada automaticamente.
4. Se o perfil estiver ausente da lista de testadores, clique em **Enviar convite**.
5. Se estiver pendente, siga as instruções abaixo e retorne para verificar.
6. Com **Convite aceito**, clique em **Continuar com Instagram** e autorize o mesmo perfil.
7. O callback existente cria ou atualiza a caixa; atribua os agentes e finalize o assistente.

O Instagram Login deste fluxo não exige uma Página do Facebook. O perfil precisa ser
profissional e conceder as permissões de acesso e mensagens exigidas pelo OAuth existente.
Ser testador não substitui OAuth, não comprova propriedade do perfil e não contorna App Review
ou outras exigências da Meta. Não há promessa de disponibilidade comercial desses endpoints.

### Como aceitar

1. **No navegador de um computador**, entre no Instagram com o `@` exato selecionado.
2. Abra **Apps e sites → Convites do testador**.
3. Localize o **nome do aplicativo configurado**, exibido na tela, e clique em **Aceitar**.
4. Volte ao Chat2You e clique em **Já aceitei — verificar**.

A tela oferece [Abrir Apps e sites](https://www.instagram.com/accounts/manage_access/) em
outra aba. Confira o perfil logado nessa aba: o Chat2You não detecta a sessão do Instagram
em outra origem. A orientação continua sendo usar computador, mesmo ao abrir o painel no celular.
Se o convite não aparecer, confira o `@` e o aplicativo, verifique novamente e procure suporte.
Nunca forneça senha, cookie ou token ao painel ou ao suporte para executar esse passo.

## Estados e recuperação

| Estado interno | Significado | Próxima ação |
|---|---|---|
| `absent` | Não localizado em uma resposta válida e completa de papéis | Enviar convite explicitamente |
| `pending` | Papel `PENDING`, ou envio confirmado aguardando propagação/aceite | Aceitar e verificar |
| `accepted` | Papel `CONFIRMED` observado | Continuar pelo OAuth, por clique |
| Erro/desconhecido | Não há evidência suficiente | Corrigir ou consultar novamente |

**Convite aceito não significa caixa conectada**, autorização concluída ou titularidade.
HTTP 200 sozinho não comprova envio. O adaptador exige `payload.success === true`;
`false` é rejeição, e resposta incompleta ou timeout deixa o resultado indeterminado.
Nenhuma resposta bruta da Meta é tratada como sucesso ou apresentada ao usuário.

Após erro de envio, a interface exige **Verificar convite** antes de permitir nova tentativa.
O backend também reconcilia o estado antes de enviar; `PENDING` e `CONFIRMED` evitam outro POST.
Um resultado incerto permanece protegido em Redis por até 24 horas. Consultar `absent`
durante esse período não autoriza reenvio cego. O TTL limita a proteção; não prova falha de envio.
Leitura real de `pending`/`accepted` limpa o marcador da mesma tentativa com controle de concorrência.

Trocar perfil limpa seleção e status, preserva o termo e cancela consultas antigas.
Durante envio, a troca fica bloqueada. Editar a busca descarta resultados anteriores;
trocar conta remonta o componente. Recarregar exige nova seleção e verificação.
Cliques duplicados são bloqueados enquanto há operação em andamento. Voltar aos canais
não remove testador, revoga convite ou desfaz autorização.

Flag global desligada mantém a tela antiga sem chamadas aos novos endpoints.
Com a global ligada, conta fora da lista recebe `enabled=false` e usa a tela antiga.
Conta habilitada com configuração/sessão indisponível recebe orientação própria, suporte
e **Tentar novamente**; a interface não libera um atalho silencioso para OAuth.
A restrição existente `DISABLE_META_INBOX_CREATION` continua bloqueando envio e autorização.
O caminho existente de reautorização permanece sem seleção de testador obrigatória.

## Identificadores: não são intercambiáveis

| Identificador | Origem e uso no código |
|---|---|
| `uniqueID` → candidato `id` | Typeahead de papéis; alvo do convite e correspondência com `users[].id` |
| `user_id` do OAuth | Detalhes retornados pelo Instagram; gravado em `Channel::Instagram.instagram_id` |
| `id` do OAuth | Detalhes retornados pelo Instagram; gravado em `app_scoped_user_id` |
| `user_id` da sessão administrativa | JSON privado; usado em `__user` e `av`, não identifica o cliente |

Não comparar o ID de papel com os IDs OAuth para inferir identidade.
`INSTAGRAM_META_DEVELOPER_APP_ID` identifica o **App pai da Meta** para papéis.
`INSTAGRAM_APP_ID` identifica o **OAuthApp do Instagram** usado no login existente.
Um não substitui o outro; a relação operacional precisa ser conferida em cada stack.

## API interna e vínculo com o perfil escolhido

As rotas ficam sob `/api/v1/accounts/:account_id/instagram/testers`, com autenticação
e permissão `inbox_manage`; não são um relay administrativo público.

| Método/rota | Entrada | Resposta própria |
|---|---|---|
| `GET /configuration` | Conta da rota | `enabled`, `available`, `app_name`, `acceptance_url` |
| `GET /search` | `username` | `results` com `id`, `username`, `name`, `avatar_url`, `selection_token` |
| `POST /status` | `selection_token` | `status`: `absent`, `pending` ou `accepted` |
| `POST /invite` | `selection_token` | `status`: `pending`/`accepted`; `invited`: booleano |

Busca aceita 1–30 caracteres ASCII: letras, números, ponto e sublinhado. A fronteira
remove espaços externos, um `@` inicial e normaliza para minúsculas. IDs são strings
numéricas ASCII de 1–40 caracteres. O cliente não pode enviar um ID arbitrário para convidar.

A seleção assinada dura **2 horas** e vincula conta, operador, App pai, ID e username
retornados pela busca. O `POST /instagram/authorization` aceita opcionalmente
`tester_selection_token`; com ele, valida a seleção e reconsulta o aceite antes do OAuth.
Sem esse campo, preserva o contrato legado, inclusive reautorização.
O state do novo fluxo dura **15 minutos**, tem proteção contra reutilização e carrega a seleção.
No callback, o username retornado pelo OAuth deve ser igual ao selecionado, antes de gravar
canal ou token. Perfil diferente/seleção inválida exige recomeçar; não se conectam perfis por aproximação.
O limite é **30 operações por minuto por conta/operador**; o lock de convite por App/alvo dura **90 segundos**.

### Erros retornados pelos endpoints de testador

| `error_code` | HTTP | Interpretação/recuperação |
|---|---|---|
| `invalid_username` | 422 | Corrigir o usuário |
| `invalid_selection` | 422 | Buscar e selecionar novamente; inclui escopo/expiração inválidos |
| `meta_unavailable` | 503 | Configuração, transporte ou serviço indisponível; suporte/verificação |
| `meta_session_expired` | 503 | HTTP 401 observado; operador verifica sessão, sem pedir segredo ao cliente |
| `unknown_status` | 502 | Resposta de papéis incompleta, contraditória ou inválida; consultar novamente |
| `invite_rejected` | 422 | Meta retornou `payload.success=false`; verificar antes de tentar |
| `invite_unknown` | 503 | Envio incerto ou proteção de resultado; reconciliar, sem retry automático |
| `rate_limited` | 429 | Aguardar; não há promessa de prazo no corpo da resposta |
| `forbidden` | 403 | Permissão ausente ou criação Meta restrita |
| `not_enabled` | 404 | Conta/feature não habilitada |
| `busy` | 409 | Convite concorrente; aguardar e verificar |

O corpo é `{error_code}`. Nem todo erro é sessão expirada: HTML, redirect, JSON inválido
ou falha GraphQL não autorizam essa conclusão. O frontend agrupa vários erros em mensagens próprias.

## Adaptador Meta: contrato observado, sem garantia de estabilidade

O backend faz POST somente para rotas fixas em `https://developers.facebook.com`:

- `/roles/instagram/typeahead/user/?value=...`, com `@` codificado na query.
- `/apps/{App_pai}/async/instagram/roles/add/`, com `role=instagram testers`,
  `user_id_or_vanitys[0]` numérico e `reload_on_success=false`.
- `/api/graphql/`, com `RolesTable_Query`, `variables.app_id` e `doc_id` configurado.

O transporte usa a sessão permitida, `__bid`, Origin/Referer e os campos/headers previstos
no client; GraphQL inclui `av`, `RelayModern` e friendly name. Timeout: **10 segundos**;
redirects não são seguidos. Não há endpoint configurável nem execução de cURL capturado.
O `doc_id` é uma referência observada, obrigatória e configurável; pode mudar sem aviso.
Configuração e captura de origem precisam continuar correspondendo a este adaptador.

A consulta inspeciona **todos** os grupos `role=instagram testers`, inclusive grupos vazios.
Valida `data.get_app_roles.app_roles`, grupos e usuários; erros GraphQL em qualquer nível
invalidam a resposta. `PENDING`/`CONFIRMED` são os únicos estados de usuário aceitos;
duplicatas com estados contraditórios falham. Quando `page_info` existe, exige
`has_next_page=false` no contêiner/grupos. O adaptador não percorre páginas adicionais.
Esquema incompleto, paginação aberta, estado desconhecido ou timeout **não são ausência**.

## Configuração e limites da evidência

Os nomes exatos, schema privado e preparo offline estão no [runbook](runbooks/instagram-tester-onboarding.md).
`available=true` significa configuração estruturalmente válida, não sessão autenticada hoje.
O JSON completo da sessão chega por ENV via entrega existente de segredos; não ganha
criptografia automática em runtime por ser ENV. O SSM existente fornece proteção em repouso.
Não há migration de banco, infraestrutura ou dependência nova para este recurso.

| Evidência | O que sustenta | O que não sustenta |
|---|---|---|
| Screenshots/POC do usuário | Três formatos de endpoint e respostas observados | Aceite atual do produto ou integração por stack |
| Specs/fixtures sintéticas | Contrato, controles e regressões exercitados localmente | Autenticação/funcionamento da Meta real |
| Navegador com componente real e API simulada | Estados, texto e interação do componente | Wizard completo, Rails E2E ou OAuth/DM real |
| Integração real por stack | **NÃO EXECUTADA** | Nenhuma aprovação de produção inferida |

Os relatórios concluídos registram testes backend/frontend e correções após revisão.
A revisão visual encontrou ajustes; código alterado exige capturas/revisão atualizadas.
O coordenador mantém a auditoria de aceite, comandos, resultados e pendências.
Pedido mínimo autenticado, novo adaptador ao vivo, aceite/OAuth/webhook/DM real em cada
stack seguem **NÃO EXECUTADOS**. O probe anterior foi bloqueado pela ferramenta;
não repetir nem delegar a chamada bloqueada. cURL do POC local é evidência, não implementação de produção.
