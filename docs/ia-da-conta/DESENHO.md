# IA da conta: chave da OpenAI e login ChatGPT. Desenho F0

Épico autonom-ia2/chat#2472. Versão 1, de 02/11/2026. Base lida: origin/main `2877c841d1`.

**Escopo decidido pelo Rodrigo em 02/11:**
- Só OpenAI por enquanto: login ChatGPT e/ou chave de API.
- Anthropic fica de fora. O login da assinatura Claude é proibido pelos termos, e a chave Claude não entra agora.
- Tudo dentro das regras: o login usa o programa oficial **Sign in with ChatGPT (SIWC)**.

## 1. O problema, em uma frase por ponto

- A conta só pode usar chave de API. Quem já paga o ChatGPT não consegue aproveitar o plano.
- Quando o crédito acaba, a IA para em silêncio. O 429 `insufficient_quota` é tratado como passageiro e a plataforma tenta de novo. Não há aviso.
- O teste da chave no cadastro só reprova o 401. Chave sem crédito passa.
- A chave fica em texto puro no `integrations_hooks.settings` (app `crm_kanban_ai`).

## 2. As fontes de IA de uma conta

| Fonte | Para o dono | Como entra | Paga quem |
|---|---|---|---|
| Login ChatGPT | "Seu ChatGPT" | Botão "Continuar com ChatGPT" (SIWC) | O plano ChatGPT do dono |
| Chave da OpenAI | "Sua chave da OpenAI" | Colar a chave | O saldo do dono na OpenAI |
| IA da plataforma | Não aparece na tela | Já existe: conta sem chave usa `CAPTAIN_OPEN_AI_API_KEY` | Nós |

### Modos

| Modo | Conectado | Ordem de uso | Quando acaba |
|---|---|---|---|
| A | Só a chave | Chave | Aviso "o crédito acabou" com botão para pôr crédito |
| B | Só o login | Login | Aviso "seu ChatGPT chegou no limite" com botão "Ver meu uso" |
| C | Login + chave | Login → chave | Troca sozinha para a chave e mostra uma nota discreta. Se a chave também acabar, aviso |
| D | Nada | IA da plataforma (como hoje) | Ver decisão D1 |

O modo C é o "4" do pedido original. Os modos "1" (as 4 fontes) e "5" (outras formas) caíram junto com a Anthropic. O desenho deixa a porta aberta: a fonte é uma linha de tabela com `provider`, então outro provedor entra sem refazer nada.

**Regra de ouro da troca:** trocar de fonte nunca muda o modelo. A conta continua no `gpt-6.1-sol`. Se o modelo exigido não está disponível na fonte (por exemplo, o plano do dono não tem o modelo), a plataforma pula para a próxima fonte. Se nenhuma tem, a tarefa para com `BLOCKED_MODEL_TIER` e registra o motivo. Nunca rebaixa a classe em silêncio.

## 3. O que o login ChatGPT consegue fazer (doc oficial)

Fonte: developers.openai.com/siwc/token-sharing-open-source/preview-limitations e models-and-inference.

| Recurso | Pelo login | Impacto aqui |
|---|---|---|
| Responses API em `api.openai.com/v1/responses` | Sim, com `store:false` e `stream:true` obrigatórios | O `ResponsesClient` já manda `store:false`. Falta ler a resposta em stream |
| Ferramentas (function tools) | Sim | O laço de ferramentas dos agentes funciona |
| Entrada de imagem e arquivo | Sim, se o modelo aceitar | Visão do CRM funciona |
| Web search | "Sujeito à política da conta" | Funciona, mas pode falhar por conta: tratar como erro de recurso e pular de fonte |
| `instructions` | Sim. Mensagem `system` explícita é recusada | Já usamos `instructions` |
| `background` | **Não** | O e-mail em segundo plano (`create_background`) só roda com a chave |
| `temperature`, `max_output_tokens`, `metadata`, `user`, `truncation` e outros | **Não** (omitir) | O adaptador remove esses campos |
| Transcrição, áudio, Files API | **Não** | Whisper e voz só com a chave |
| Embeddings | Não citado: tratar como **não** | RAG só com a chave |
| `json_schema`, `reasoning.effort`, `prompt_cache_key` | **Não citados** | Pergunta 5 no formulário. É crítico, porque o Answerer depende de `json_schema` |

Os recursos se dividem por "o que precisam":

- **Texto** (responder, Construtor, CRM, follow-up, resumo, comentários, redação): login → chave → plataforma.
- **Só chave** (embeddings/RAG, transcrição, voz, e-mail em segundo plano): chave → plataforma. O login nunca serve para esses.
- **Fixos** (juízes, placares e evals: `JuizDaProva`, `JuizDoPlacar`, `JuizDoAutoteste`, rake de eval): ficam como estão. Fora da troca, nunca usam o login, pedido da sessão Agentes IA.
- **Comentários IA (#2454):** só fontes **da conta** (login ou chave), nunca a plataforma. A regra de hoje continua.

## 4. Pontos que dependem da OpenAI

O pacote do formulário está em `docs/ia-da-conta/formulario-openai-siwc.md`. Antes da resposta, o login fica **pronto e desligado**. Duas respostas mudam o desenho:

1. **Se não pode uso sem o dono presente:** o login atende só o que o dono faz na hora (rascunho, resumo, Construtor, redação). Agentes 24 horas, follow-up e CRM automático ficam na chave. A tela diz isso em uma frase.
2. **Se `json_schema` não funciona pelo login:** o Answerer e quem depende de saída estruturada pulam o login. Isso fica marcado por tipo de chamada (`exige: [:schema]`).

## 5. Arquitetura

### 5.1 Onde a credencial mora (migration, versão pedida à Orquestração)

Tabela nova `ai_credentials`, uma linha por fonte da conta:

| Coluna | Tipo | Nota |
|---|---|---|
| `account_id` | FK | `validate: false`, se a Orquestração pedir |
| `provider` | string | `openai` (abre espaço para outro provedor) |
| `kind` | string | `api_key` ou `chatgpt_login` |
| `api_key` | text, `encrypts` | Só `api_key` |
| `api_base` | string | Só `api_key` (hoje vem do hook) |
| `access_token`, `refresh_token` | text, `encrypts` | Só `chatgpt_login` |
| `expires_at` | datetime | Validade do access token (1 h) |
| `status` | string | `funcionando`, `limite_atingido`, `sem_credito`, `recusada`, `sem_acesso_ao_modelo`, `desconectada` |
| `status_desde`, `tentar_de_novo_em` | datetime | Para a fonte voltar sozinha |
| `ultimo_erro` | string | Só o **código** do provedor (ex.: `insufficient_quota`), nunca o corpo |
| `conta_chatgpt_email` | string | Mostrado na tela ("conectado como …") |
| `connected_by_id` | FK users | Quem conectou |

- Índice único em `(account_id, provider, kind)`.
- Cifra por `encrypts` do Rails em coluna própria. No jsonb não funciona (comentário em `crm/meta_ads_connection.rb:71`). Segue o padrão de `channel/tiktok.rb`.
- **Passagem da chave atual:** um job copia `crm_kanban_ai.settings.api_key` para `ai_credentials`. O resolver lê a tabela nova e, enquanto ela está vazia, cai no hook. Assim nada quebra no meio.
- O cartão antigo de integração passa a gravar na tabela nova. Apagar o `api_key` do jsonb fica para uma fase seguinte, depois de conferir a cópia (escrita em prod: avisar a Orquestração, fazer backup e travar por `account_id`).

### 5.2 Escolha da fonte: `Crm::Ai::CredentialResolver` por dentro

- `resolve` continua devolvendo o hash de hoje (`api_key`, `api_base`, `source`) para os 84 arquivos que já o usam. Por dentro, ele passa a ler `ai_credentials`.
- Método novo `cadeia(precisa:)` devolve as fontes utilizáveis em ordem, já sem as que estão em `limite_atingido` ou `sem_credito` antes de `tentar_de_novo_em`. `precisa:` pode ser `:texto`, `:so_chave` ou `:da_conta`.
- Os 8 pontos que leem `api_key` direto (embeddings, transcrição, voz) pedem `:so_chave` e nunca recebem um login.

### 5.3 Troca durante a chamada: `Crm::Ai::ResponsesClient`

**Quem chama não muda.** Os 56 `ResponsesClient.new(credential: …)` seguem iguais. A mudança fica dentro do cliente:

- **Transporte por tipo de fonte.**
  - Chave: igual a hoje.
  - Login: põe `stream:true`, tira os campos proibidos e lê o stream (SSE) até `response.completed`.
  - Em seguida remonta o mesmo objeto de resposta que o modo normal devolve. O `parse_response`, o laço de ferramentas e o `record_usage` continuam iguais.
- **Erros que fazem pular para a próxima fonte, com o mesmo modelo:**

| Fonte | Erro | Status gravado | Volta quando |
|---|---|---|---|
| Login | 429 `subscription_sharing_usage_limit_exceeded` (também chega no meio do stream, como `response.failed`) | `limite_atingido` | Nova tentativa a cada 30 min. A doc pede para não deduzir o horário de volta |
| Login | 403 `subscription_sharing_user_not_eligible` | `sem_acesso_ao_modelo` | Só quando o dono reconectar |
| Login | 401 `subscription_sharing_invalid_user` ou `invalid_grant` no refresh | `desconectada` | Só quando o dono entrar de novo |
| Login | 400 `subscription_sharing_unsupported_capability` | nenhum: o login fica `funcionando` | Pula só nesta chamada e registra o `error.param` no log |
| Chave | 429 `insufficient_quota`, `credit_balance_exhausted` ou `*_spend_limit_exceeded` | `sem_credito` | Verificação leve a cada 1 h, ou na hora quando o dono clicar em "Já coloquei crédito" |
| Chave | 401 | `recusada` | — |

- **Sem retry nesses casos.** Hoje o 429 de quota cai no retry de "passageiro", que gasta tempo e não resolve. O retry continua só para o 429 de limite de taxa (`rate_limit_exceeded`), o 5xx e erro de rede.
- **Sem fonte sobrando:** levanta `ResponsesClient::SemFonte`, com o motivo da última fonte. Cada funcionalidade já trata o erro do cliente hoje. O que muda é que o aviso ao dono (seção 6) sai de um lugar só.

**Regras pedidas pela revisão da Agentes IA (02/11), obrigatórias na F2:**

1. **Troca no meio do laço de ferramentas continua o turno, nunca recomeça.**
   - Se a fonte cai na rodada N, a próxima fonte recebe a `conversa` acumulada, com as saídas das ferramentas já executadas.
   - Nenhuma ferramenta roda duas vezes: HTTP com efeito, especialista, entrega e o assíncrono do #1430.
   - Spec: a fonte cai na rodada 2 com uma ferramenta já executada. A ferramenta roda 1 vez e a resposta sai pela fonte seguinte.
2. **Saída estruturada: o login não é tentado enquanto a OpenAI não confirmar.**
   - Chamada com `schema:` (marca `exige: [:schema]`) pula o login direto.
   - Depois da confirmação, se o login devolver texto que não passa no parse do schema, isso também é motivo de pular para a próxima fonte, **dentro do cliente**. Nunca sobe como `JSON::ParserError` para o Answerer: lá vira erro, e o erro vira passagem para pessoa sem motivo.
   - Spec dos dois casos.
3. **Erros novos ficam na mesma família.**
   - `SemFonte` e os erros de fonte são subclasses de `Crm::Ai::ResponsesClient::Error`. Existem 11 `rescue` por essa classe: answerer, classificador, foto e rascunho dos comentários, reviewer, avaliação conjunta, e-mail e outros. Uma classe fora da família vira 500 ou job morto.
   - `SemFonte#passageira?` é `false`. Quem hoje faz retry de erro passageiro (Comentários IA tratam `Indisponivel` com retry pelo job; `retry_on` do opt-out) **para** em `SemFonte`, senão vira laço eterno. Nos Comentários, `SemFonte` vira "não cuidei", com o motivo.
   - O PR lista, por grep, todo código que lê status ou mensagem do erro (429, "quota", "insufficient").
4. **Custo por fonte.**
   - `crm_ai_usage_events` ganha a coluna `fonte` (`login`, `chave`, `plataforma`), na mesma migration da F1.
   - Pelo login, o `cost_estimate` é zero para nós e para a chave do dono. Os tokens continuam gravados.
   - Sem isso, o painel de desempenho (#2226) e o custo por conta ficam errados.
5. **Embedding não muda de modelo com a fonte.** A consulta usa o mesmo modelo do índice (3-small ou 3-large, pela coluna ativa), venha a credencial da chave ou da plataforma. Spec.
6. **Juízes fixos fora da cadeia.**
   - `JuizDaProva`, `JuizDoPlacar`, `JuizDoAutoteste` e os evals usam a credencial de hoje: `CredentialResolver#resolve` (chave da conta ou plataforma), ou `ENV OPENAI_API_KEY` no rake.
   - Nunca chamam `cadeia()` e nunca usam o login.

### 5.4 Renovação do login

- O access token vale 1 h e o refresh token **troca a cada uso** (uso único): developers.openai.com/siwc/token-sharing-open-source/token-reference.
- Dois workers renovando juntos fazem um dos dois receber `refresh_token_reused`, e a conta perde a conexão. Para evitar isso:
  1. Renovar com a linha travada (`credential.with_lock`).
  2. Ler de novo depois do lock: se outro worker já renovou, usar o token novo.
  3. Renovar 5 min antes de vencer.
  4. Gravar access, refresh, validade e escopos **juntos**.
- Se o refresh falhar, `desconectada` e aviso ao dono.

### 5.5 Login (controller e callback)

- Rotas `GET /api/v1/accounts/:account_id/openai/authorization` (inicia) e `GET /openai/callback`, no padrão de `google/callbacks_controller.rb`.
- PKCE S256, `state` e `nonce` guardados no Redis por 10 min, presos ao `account_id` e ao `user_id`.
- Client **confidencial**: `client_secret_basic` só no backend.
- `OPENAI_SIWC_CLIENT_ID` e `OPENAI_SIWC_CLIENT_SECRET` ficam em `InstallationConfig`, tipo `secret`. A ENV no SSM é com o Rodrigo.
- Confere o ID token (assinatura via JWKS, `iss`, `aud`, `exp`, `nonce`) e se o grant trouxe `chatgpt.tokens.use.direct`.
- Busca `GET /v1/models` com o token para guardar quais modelos o plano tem.
- **O botão só aparece se o `client_id` estiver configurado.** Sem flag nova: é configuração da plataforma.

### 5.6 Permissão

- Só administrador. Gestão de credencial é integração e nunca se delega por função personalizada (regra do projeto).
- Parecer da sessão "Funções personalizadas" antes da fila.

## 6. Avisos: quem fica sabendo e onde

O mesmo evento (`IaDaConta::Aviso`) alimenta três lugares. Ele sai **uma vez por incidente**, não a cada mensagem.

| Situação | Onde aparece | Texto |
|---|---|---|
| Login no limite, com chave para assumir | Só na tela IA da conta, nota discreta | "Seu ChatGPT chegou no limite. Por enquanto, usamos sua chave." |
| Nenhuma fonte da conta sobrou | Faixa no topo do painel, só para admin (padrão "aviso na conversa: faixa no topo") + e-mail aos admins + notificação | "A IA da sua conta parou. [Resolver]" |
| Login desconectado | Igual ao de cima | "Seu ChatGPT foi desconectado. [Entrar de novo]" |
| A fonte voltou | A faixa some sozinha | — |

- O aviso nunca trava nada nosso: só avisa (regra "sem freio no uso do cliente").
- O tipo de notificação novo entra em `Notification::NOTIFICATION_TYPES`.

## 7. A jornada (regra de ouro: premium, QI 70)

**Uma tela: Configurações › IA da conta.**
- Substitui o cartão "Chave da OpenAI" das integrações. O cartão leva para cá.
- O passo 1 do onboarding e o botão "Resolver" da faixa também abrem esta tela.

1. **Herói com uma frase de estado:** "Sua IA está funcionando." (verde) / "Sua IA parou: o crédito acabou." (vermelho) / "Escolha como sua IA vai funcionar." (vazio).
2. **Dois cartões lado a lado** (empilhados no celular):
   - **Seu ChatGPT:** "Use o plano do ChatGPT que você já paga." Botão oficial **Continuar com ChatGPT**, com logo branco, conforme developers.openai.com/siwc/ui-ux-guidelines. A tradução do rótulo para pt-BR será confirmada com a OpenAI.
   - **Sua chave da OpenAI:** "Pague só o que usar, direto na OpenAI." Botão **Colar minha chave** abre a gaveta: 1 campo, o link "Onde pego minha chave?" com 3 passos curtos e o botão **Conferir e salvar**.
3. **Conectado, o cartão mostra:**
   - um selo: Funcionando / Chegou no limite, volta sozinho / Sem crédito / Precisa entrar de novo;
   - os botões: **Ver meu uso** (chatgpt.com/settings/usage, o "Manage usage" da OpenAI), **Pôr crédito** (OpenAI Billing), **Desconectar**.
4. **Com os dois conectados:** uma linha simples, "Primeiro usamos seu ChatGPT. Se acabar, sua chave." Sem configuração de ordem (YAGNI).
5. **Primeiro login:** janela "Você está usando seu plano do ChatGPT" e o botão **Entendi**. É obrigatória pelas diretrizes da OpenAI.
6. **Limite:** "Limite de uso atingido. Veja seu plano ou o limite deste app nas configurações do ChatGPT." Ação principal: **Ver meu uso**.

**Texto proibido na tela:** "API", "token", "OAuth", "modelo", "SIWC", "provedor". Usar "chave" e "entrar com ChatGPT".

## 8. Fases

| Fase | Entrega | Depende da OpenAI? |
|---|---|---|
| **F1: base segura** | Tabela cifrada + cópia da chave atual, resolver lendo a tabela, `insufficient_quota` vira `sem_credito` sem retry, teste de chave que pega conta sem crédito, aviso (faixa, e-mail, notificação), tela IA da conta com o cartão da chave | Não |
| **F2: login ChatGPT** | Controller e callback, renovação travada, transporte em stream no `ResponsesClient`, troca de fonte, cartão "Seu ChatGPT" | Precisa do `client_id` para ligar. Dá para codar e testar antes contra stub |
| **F3: ajuste pelas respostas da OpenAI** | O que as perguntas 1, 2, 3 e 5 mudarem (uso sem o dono presente, `json_schema`) | Sim |

Cada fase pede:
- mockup de tela real aprovado antes de implementar;
- revisão crítica do diff;
- parecer de acesso;
- Guia (`porques.md`, `pnpm guia:build`) para a tela nova;
- formatos regerados para o controller novo.

## 9. Decisões para o Rodrigo

**Respostas do Rodrigo em 02/11:**
- **D1:** conta sem chave fica **sem IA**. Não existe IA da plataforma no produto. O fallback `system_credential` do `CredentialResolver` (`CAPTAIN_OPEN_AI_API_KEY`) sai do caminho das funcionalidades da conta. Antes, conferir se essa chave está preenchida em produção e quais contas dependem dela hoje.
- **D2:** o login vale para tudo. O que a OpenAI não faz pelo login (embeddings, transcrição, voz, segundo plano) precisa da chave da conta. Sem chave, esses recursos ficam parados e a tela diz isso.
- **D3:** sem flag nova.
- **D4:** é o formulário de liberação da OpenAI. O Rodrigo envia.
- **D5:** o login vale para tudo, inclusive agentes 24 horas, follow-up e CRM automático. Na hora de conectar, o dono vê um aviso simples de que as conversas passam pela conta ChatGPT dele. A pergunta 9 continua no formulário, só como registro.

Consequência da D5: a seção 4, item 1, vale só se a OpenAI **proibir** uso sem o dono presente. Não é mais escolha nossa.

Texto original das perguntas, mantido como registro:

- **D1. Conta sem nenhuma fonte continua usando a IA da plataforma, como hoje?** Recomendo **sim**: não muda nada para quem já está assim. A alternativa é parar e mostrar a tela de escolha.
- **D2. Conta só com login: quem paga RAG, áudio, voz e e-mail em segundo plano?** O login não faz esses recursos.
  - (a) A IA da plataforma, paga por nós. Embeddings e transcrição são baratos. O dono não vê nada. **Recomendo.**
  - (b) Pedir a chave também: "Para ouvir áudios e ler documentos, falta a sua chave." A jornada fica mais pesada.
  - (c) Desligar esses recursos.
- **D3. Sem flag nova?** O login aparece quando o `client_id` existir. A tela nova lê e grava a mesma credencial que o cartão antigo, então não precisa de flag de volta. Recomendo **sem flag nova**.
- **D4. Formulário SIWC:** você envia, com o texto pronto no outro arquivo.
- **D5. Conversa do cliente final pela conta ChatGPT do dono.** Pelo login, mensagens com CPF, saúde ou seguro passam pela conta ChatGPT do dono, que pode ser pessoal. A doc oficial do SIWC não diz se esse uso fica retido, aparece no histórico ou entra em treino. Conferi em 02/11: /siwc, /profiles-and-sessions, /models-and-inference e /preview-limitations, e nenhuma fala de dados. Virou a pergunta 9 do formulário.
  - (a) Até a OpenAI responder com garantia de que não treina nem retém: os **agentes 24 horas, follow-up e CRM automático ficam na chave**. O login atende só o que o dono faz na hora (rascunho, resumo, Construtor, redação). **Recomendo.**
  - (b) O login vale para tudo desde o começo, e o dono aceita um aviso na hora de conectar.

## 10. Riscos

- **OpenAI não aprovar, ou proibir uso sem o dono presente.** A entrega continua de pé com a chave (F1 inteira). O login vira um extra para o que o dono faz na hora.
- **Refresh concorrente** derrubando a conexão: lock por linha (5.4) e spec de concorrência.
- **Stream no meio do laço de ferramentas:** a remontagem do objeto precisa de spec com os eventos reais. Erro no meio do stream (`response.failed`) pode chegar depois de começar a gerar texto. Descartar e pular para a próxima fonte.
- **Repo público:** nenhum token, chave ou corpo de erro do provedor em log, Issue ou PR. O log guarda só o código do erro.
- **Cruzamentos:**
  - Agentes IA revê a parte do Answerer e do Retriever.
  - O PR 3b do #2436 mexe no `answerer.rb`: a F1 não toca nele.
  - O #1430 assíncrono não toca o cliente.
