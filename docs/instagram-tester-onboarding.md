# Instagram: preparação opcional do convite de testador (#910)

Este fluxo ajuda a escolher um perfil, preparar seu convite de testador e verificar o aceite
antes de continuar pelo Instagram Login existente. Começa **desligado globalmente** e exige
também uma lista explícita de contas permitidas. OFF é o padrão do código, não uma
constatação da configuração atual. A documentação descreve a implementação local;
não declara a funcionalidade homologada em produção.

**Recuperação #931, 03/10/2026:** PR #913 mergeado/publicado é histórico.
O resultado local das correções está consolidado abaixo; publicação/CI/aprovação devem ser consultados na PR do commit.
Operação autenticada por stack continua pendente. Configuração, sessão e alarmes atuais são desconhecidos.
Ver [matriz de recuperação](audit/instagram-931-recovery.md) para resultados e limites.

Operação por stack: [runbook](runbooks/instagram-tester-onboarding.md).
Entrega de segredos: [production-env-secrets.md](production-env-secrets.md).
Publicação: [production-deploy-gates.md](production-deploy-gates.md).

## Resultado local consolidado #931 — 03/10/2026, 23:01 BRT

Baterias encerradas, separadas e sem soma de cobertura: backend **443/0** sem
`FRONTEND_URL` global; fixture OAuth focal **30/0**; frontend **129/0**; runtime
**72/0**; helpers QA **23/0**, incluindo toast; DEPLOY offline **19/0**;
preparer **25/OK**; regressão Guia **40/0**. Autoload/build aprovados;
i18n **17.222 mensagens/10 catálogos** (não testes); Ruby **25 arquivos/zero infrações**;
JS **zero erros/22 warnings conhecidos**.

Renders finais de 04/10/2026 UTC (03/10 BRT): componente **37/37, 73 capturas**,
fim **01:55:02,520Z**; wizard **72/72, 76 capturas**, fim **01:57:21,093Z**.
Ambos têm **6.658 hashes iguais antes/depois e ao disco**. Review de arte final
aprova seu escopo e fecha copy/toast após inspecionar 12 capturas atuais.
São componentes reais com API simulada; não comprovam Rails/Meta fim a fim.

Os **12 achados estão fechados no código/evidência local**, incluindo P1 BOOT e
userinfo Sentry, sem novo bloqueio nesses reviews. Os 14 especialistas, logs locais
de scratch, manifestos, limites e etapas históricas datadas estão na
[auditoria central](audit/instagram-931-recovery.md); não repetir nem somar rodadas anteriores.

**Publicação, head, CI, Project, revisão final dos docs e aprovação devem ser
consultados na PR do commit correspondente.** Evidência local não autoriza produção.
Configuração/allowlist/sessão/supervisor/alarmes atuais não foram inspecionados;
operação autenticada por stack continua pendente.

**Gate operacional humano ainda não executado:** pausar publishers, drenar código
antigo e rotacionar tombstones legados pelo contrato verificado do store novo ou
aguardar expiração efetiva antes de retomar; descartar capturas em trânsito e
recapturar com nova revisão. Reiniciar states/seleções OAuth antigos e coordenar
cutover de emissores/callbacks. Preservar canais, tokens persistidos, conversas e papéis.
Preparar responsáveis, janela, revisão alvo, evidências e rollback por stack com
aprovação operacional. Não pedir script Redis novo sem contrato verificado.

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
Na correção #931, falha comprovada antes do início do transporte libera somente o
claim da própria tentativa. Após início, timeout/cancelamento/erro HTTP conserva a
proteção; código público sozinho não permite limpá-la. Rejeição booleana explícita
validada preserva o retry deliberado existente. Nenhum erro autoriza retry automático.

Trocar perfil limpa seleção e status, preserva o termo e cancela consultas antigas.
Durante envio, a troca fica bloqueada. Editar a busca descarta resultados anteriores;
trocar conta remonta o componente. Recarregar exige nova seleção e verificação.
Cliques duplicados são bloqueados enquanto há operação em andamento. Voltar aos canais
não remove testador, revoga convite ou desfaz autorização.

Flag global desligada mantém a tela antiga sem chamadas aos novos endpoints.
Com a global ligada, conta fora da lista recebe `enabled=false` e usa a tela antiga.
Conta habilitada com configuração/sessão indisponível recebe orientação própria, suporte
e **Tentar novamente**; a interface não libera um atalho silencioso para OAuth.
A restrição existente `DISABLE_META_INBOX_CREATION` bloqueia busca/status/convite e
autorização; configuração pública continua consultável. Na correção #931 a interface
acompanha esse gate e impede ações que o backend rejeitaria. Indisponibilidade orienta
restabelecer a integração com suporte; preparar convite não resolve sessão/configuração.
Limite de caixas do plano recebe orientação própria por code 402/tipo estático conhecido,
sem exibir descrição bruta. Falha OAuth libera o loading para tentativa deliberada.
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

A seleção assinada dura **2 horas** e, na implementação #931, mantém conta, operador,
App pai, instalação, ID e username retornados pela busca até o callback.
O `POST /instagram/authorization` aceita opcionalmente `tester_selection_token`;
com ele, valida a seleção e reconsulta o aceite antes do OAuth. Sem o campo, mantém
API/reautorização sem seleção obrigatória ou configuração testers obrigatória.

Todos os states recém-emitidos, inclusive sem seleção e na reautorização, usam versão 2,
ator, conta, `iat`/`exp` de até **15 minutos** e nonce de uso único. A identidade da
instalação é digest da base de callback normalizada de `FRONTEND_URL` configurada,
sem Host do request ou fallback; difere do namespace Redis da sessão administrativa.
O callback revalida associação e permissão de criar caixa antes da troca e novamente
antes de gravar, incluindo papéis Enterprise. No assistido, também confere escopo/App
pai e username OAuth igual ao selecionado. IDs de papéis e OAuth não são intercambiáveis.

**States e seleções anteriores em trânsito são recusados após rollout.** Reiniciar OAuth
no legado/reautorização e busca/seleção no assistido; não manter bypass para formato
antigo. Mudança da base de callback também invalida artefatos anteriores. Caixas/tokens
persistidos não são migrados por essa mudança. Rollout/rollback e tombstones legados
exigem preparo próprio no [runbook](runbooks/instagram-tester-onboarding.md).
O limite é **30 operações por minuto por conta/operador**; o lock de convite por App/alvo dura **90 segundos**.

### Erros retornados pelos endpoints de testador

| `error_code` | HTTP | Interpretação/recuperação |
|---|---|---|
| `invalid_username` | 422 | Corrigir o usuário |
| `invalid_selection` | 422 | Buscar e selecionar novamente; inclui escopo/expiração inválidos |
| `meta_unavailable` | 503 | Configuração, transporte ou serviço indisponível; suporte/verificação |
| `proxy_unavailable` | 503 | Transporte administrativo indisponível; suporte restabelece integração |
| `meta_session_expired` | 503 | HTTP 401/403; operador verifica sessão/permissão, sem pedir segredo ao cliente; 403 não prova expiração |
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
Produção exige fonte `managed`: payload administrativo cifrado no Redis local e revisão
opaca `string | null`, publicada pelo gestor separado. `INSTAGRAM_TESTER_SESSION_JSON`
permanece para preparação/teste sintético; não é fallback de produção. O overlay backend
não aceita sessão JSON nem credenciais do gestor/proxy. OAuthApp/secret existentes
continuam na entrega de segredos; não publicar seus valores.

Na correção #931, invalidar avança a revisão e impede publicação com revisão anterior,
independentemente do relógio. Recuperação exige recaptura com a revisão nova; sessões
ativas continuam legíveis, mas tombstones antigos exigem preparo no rollout. Schema,
cifra, namespace e TTL permanecem, sem migration de banco. Isso descreve contrato de
código, não sessão válida ou publisher instalado atualmente.

| Evidência | O que sustenta | O que não sustenta |
|---|---|---|
| Screenshots/POC do usuário | Três formatos de endpoint e respostas observados | Aceite atual do produto ou integração por stack |
| Specs/fixtures sintéticas | Contrato, controles e regressões exercitados localmente | Autenticação/funcionamento da Meta real |
| Navegador com componentes/wizard reais e API simulada | Estados, texto e interação em cenários separados | Rails E2E ou OAuth/DM real |
| Integração real por stack | **NÃO EXECUTADA** | Nenhuma aprovação de produção inferida |

Os relatórios #910/#913 registram testes backend/frontend e revisão visual histórica.
A aprovação visual daqueles ajustes permanece histórica. As fontes finais #931 têm
renders e review de arte encerrados no fechamento de 03/10/2026, 23:01 BRT, conforme
[matriz #931](audit/instagram-931-recovery.md), separados da homologação autenticada.
O coordenador mantém logs completos, fontes/CSS consumidos e critérios de aceite.
Pedido mínimo autenticado, novo adaptador ao vivo, aceite/OAuth/webhook/DM real em cada
stack seguem **NÃO EXECUTADOS**. O probe anterior foi bloqueado pela ferramenta;
não repetir nem delegar a chamada bloqueada. cURL do POC local é evidência, não implementação de produção.

## Capturas da implementação

Capturas históricas #910: dados sintéticos; componente real com API simulada, sem
representar produção nem aceite visual das alterações #931.

[Desktop pendente](assets/instagram-testers-910/desktop-pendente.png) · [Tema escuro](assets/instagram-testers-910/desktop-escuro-pendente.png) · [Mobile](assets/instagram-testers-910/mobile-pendente.png) · [Convite aceito](assets/instagram-testers-910/desktop-aceito.png).

Matriz completa e limites da validação: [termos de aceite](audit/instagram-tester-onboarding-910.md).
