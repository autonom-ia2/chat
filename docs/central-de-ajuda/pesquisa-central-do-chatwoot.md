# Pesquisa: o que a Central de Ajuda (Portals) do Chatwoot oferece neste fork

Pesquisa de código, só leitura, no worktree `502-central-fase-0`
(`/Users/rodrigosilva/dev/worktrees/chat2you/502-central-fase-0`). Todo item
tem evidência em `arquivo:linha`. Onde a fonte é a documentação oficial do
Chatwoot (não o código deste fork), está marcado **[doc]**; o resto foi
confirmado lendo o código deste repositório.

## Resumo em 10 linhas

1. O Chatwoot já tem um CMS de Central de Ajuda completo (`Portal` →
   `Category`/`Folder` → `Article`), multi-idioma, com posição/ordem, rascunho,
   arquivamento, SEO e analytics — e este fork o customizou bastante além do
   Chatwoot padrão.
2. As rotas públicas `/hc/:slug/...` servem HTML (layout completo), HTML
   "plain" (sem chrome, pronto para iframe/painel), Markdown (`.md`), JSON,
   sitemap.xml e um pixel de tracking de visualização — tudo sem autenticação.
3. O parâmetro `?show_plain_layout=true` é exatamente o mecanismo para "ler
   dentro do painel": remove o header do site, remove `X-Frame-Options` e
   troca o layout para uma variante enxuta.
4. Busca é full-text por padrão (Postgres `pg_search`/`tsearch`); existe busca
   por embeddings (OpenAI + pgvector) pronta no código, mas desligada por
   padrão e dependente de chave OpenAI própria do Captain.
5. Existe API autenticada completa para criar/atualizar Portal, Category e
   Article, reordenar, bulk actions e upload de imagem — dá para sincronizar
   conteúdo do repositório por script hoje, sem inventar nada.
6. Imagem em artigo não é um "anexo do artigo": é upload genérico
   (`ActiveStorage::Blob`) que devolve uma URL, embutida como
   `![alt](url)` no Markdown do conteúdo.
7. O widget do site e a caixa de resposta do atendente (busca/inserção de
   artigo) já consomem os mesmos endpoints públicos — não é preciso construir
   nada novo para eles.
8. A IA interna do produto **não lê os artigos por padrão**: o assistente
   Captain usa uma base de FAQ própria (`Captain::AssistantResponse`), separada
   do Help Center. Só o **Copilot** (o assistente do agente humano, dentro da
   conversa) tem ferramentas (`search_articles`/`get_article`) que leem
   `Article` diretamente — e mesmo assim atrás da permissão Enterprise
   `knowledge_base_manage`.
9. Gestão de conteúdo (criar/editar/apagar portal, categoria, artigo) é
   admin-only por padrão; o Enterprise acrescenta os papéis customizados
   `knowledge_base_manage`/`knowledge_base_view`.
10. Ponto de atenção real para o nosso plano: o slug de `Article` é único
    **globalmente** no banco (índice único em `articles.slug`, sem escopo de
    portal/conta) — importa saber se as duas contas (Hub2You e Autonomia)
    vivem no mesmo banco antes de gerar slugs pelo script.

---

## (b) Capacidades por tema

### 1. Modelo de dados

**O que é.** Quatro tabelas: `portals`, `categories`, `folders`, `articles`,
mais `related_categories` (N:N de categorias relacionadas) e
`article_embeddings` (Enterprise, busca vetorial).

- **Portal** — `id, name, slug (único, presença), custom_domain (único),
  archived, color, config (jsonb), header_text, homepage_link, page_title,
  ssl_settings (jsonb), channel_web_widget_id, account_id`.
  `config` (jsonb) carrega: `allowed_locales`, `default_locale`,
  `draft_locales` (idiomas do portal ainda não publicados — cada locale pode
  estar em rascunho independente do artigo), `layout` (`classic` |
  `documentation`), `social_profiles`, `locale_translations` (nome/título/
  header por idioma), `popular_content` (categorias/artigos recomendados por
  idioma) e `analytics` (GTM, GA4, Hotjar, Plausible, Amplitude, Clarity, Meta
  Pixel — cada um com formato validado).
  Evidência: `app/models/portal.rb:1-205`, schema de config em
  `app/models/concerns/portal_config_schema.rb:1-65`.
- **Category** — `id, name, description, icon, icon_color, locale (default
  "en"), position, slug, portal_id, account_id, parent_category_id`
  (subcategoria), `associated_category_id` (liga a mesma categoria entre
  idiomas — é usado para tradução, não para "categorias relacionadas" no
  sentido de conteúdo parecido). Slug é único por `(slug, locale, portal_id)`,
  não globalmente. "Categorias relacionadas" de fato é a tabela
  `related_categories` (N:N, `RelatedCategory`).
  Evidência: `app/models/category.rb:1-102`,
  `app/models/related_category.rb:1-19`.
- **Folder** — agrupamento dentro de uma categoria (`belongs_to :category`,
  `has_many :articles`); é um nível extra de organização que o Chatwoot padrão
  não documenta publicamente como conceito de primeira classe — aqui existe
  como tabela própria.
  Evidência: `app/models/folder.rb:1-20`.
- **Article** — `id, title, slug (único no banco, sem uniqueness no model),
  content (markdown), description, draft_title, draft_content, locale
  (default "en", not null), meta (jsonb: title/description/tags — SEO),
  position, status (enum draft=0/published=1/archived=2), views (contador),
  author_id (obrigatório, User da conta), category_id, folder_id, portal_id,
  associated_article_id` (liga a mesma peça entre idiomas, análogo à
  categoria). `content` só é obrigatório quando `published`.
  Evidência: `app/models/article.rb:1-228`.
- Slugs reservados que não podem virar slug de artigo:
  `search, articles, categories` (colidiriam com rotas do HC).
  Evidência: `app/models/article.rb:61,67`.
- Rascunho de edição: `draft_title`/`draft_content` são campos de autosave
  paralelos ao título/conteúdo publicados — dá para editar um artigo já
  publicado sem afetar o que o público vê, e sem "sujar" o `updated_at`
  público (grava via `update_columns`, sem tocar timestamp).
  Evidência: `app/controllers/api/v1/accounts/articles_controller.rb:94-106`.

**Como usar no nosso caso.** Modelo já cobre tudo que planejamos: 1 portal por
conta, categorias/pastas para organizar por produto/fluxo, artigo com
posição/ordem fixa, status para controlar o que é visível, e locale único
`pt_BR` (não precisamos de multi-idioma, então `allowed_locales: ["pt_BR"]`
resolve).

---

### 2. Rotas públicas e formatos

**O que é.** Rotas registradas em `config/routes.rb:962-973`:

| Rota | Controller#ação | Formato |
|---|---|---|
| `GET /hc/:slug` | `portals#show` | redireciona para `/hc/:slug/:locale` |
| `GET /hc/:slug/:locale` | `portals#show` | HTML (home do portal) |
| `GET /hc/:slug/sitemap.xml` | `portals#sitemap` | XML |
| `GET /hc/:slug/:locale/search` | `portals/search#index` | HTML (busca) |
| `GET /hc/:slug/:locale/articles` | `portals/articles#index` | HTML/JSON (lista) |
| `GET /hc/:slug/:locale/categories` | `portals/categories#index` | HTML/JSON |
| `GET /hc/:slug/:locale/categories/:category_slug` | `portals/categories#show` | HTML |
| `GET /hc/:slug/:locale/categories/:category_slug/articles` | `portals/articles#index` | HTML/JSON |
| `GET /hc/:slug/articles/:article_slug` | `portals/articles#show` | HTML |
| `GET /hc/:slug/articles/:article_slug.md` | `portals/articles#show_markdown` | `text/markdown` cru |
| `GET /hc/:slug/articles/:article_slug.png` | `portals/articles#tracking_pixel` | imagem 1×1 (conta view) |

Todas passam por `PublicController` (`app/controllers/public_controller.rb:3`),
sem autenticação, com CSRF desligado — são realmente públicas.

**Variantes de layout (Rails `request.variant`):**
- **Padrão (`classic`)** — layout completo do site de ajuda.
- **`documentation`** — layout alternativo (sidebar de categorias, TOC), ativado
  quando `portal.config['layout'] == 'documentation'`.
- **`plain`** — ativado por `?show_plain_layout=true`; remove o chrome (header,
  footer, busca) e remove `X-Frame-Options`, então a página pode ser carregada
  em `<iframe>`. Views existem para home, categoria e artigo:
  `show.html+plain.erb`, `articles/show.html+plain.erb`.
  Evidência: `app/controllers/public/api/v1/portals/base_controller.rb:14-32,66-68`,
  `app/views/public/api/v1/portals/show.html+plain.erb:1-3`,
  `app/views/public/api/v1/portals/articles/show.html+plain.erb:1-11`.

**JSON.** `index`/`show` respondem a `format: :json` (usado pelo widget e pela
área logada) — `app/views/public/api/v1/portals/articles/index.json.jbuilder:1-16`,
`show.json.jbuilder:1`.

**Markdown cru.** `show_markdown` devolve `article.content` como está, sem
render, `content_type: text/markdown` — útil para consumo por outra
ferramenta/IA sem parsear HTML.
Evidência: `app/controllers/public/api/v1/portals/articles_controller.rb:29-33`.

**Sitemap.** Lista só artigos `published`, usa `ChatwootApp.help_center_root`
(env `HELPCENTER_URL` ou `FRONTEND_URL`) como base da URL.
Evidência: `app/controllers/public/api/v1/portals_controller.rb:17-21`,
`app/views/public/api/v1/portals/sitemap.xml.erb:1-9`,
`lib/chatwoot_app.rb:43-45`.

**Tracking pixel.** `/hc/:slug/articles/:slug.png` incrementa `views` só se o
artigo estiver `published`, serve uma imagem estática de `public/assets`,
cache privado de 24h (não é CDN-cacheável, então não conta visita duplicada do
mesmo navegador).
Evidência: `app/controllers/public/api/v1/portals/articles_controller.rb:35-48`.

**Como usar no nosso caso.** Para "ler dentro do painel", a rota certa é
`/hc/:slug/:locale?show_plain_layout=true` (home/lista) e
`/hc/:slug/articles/:slug?show_plain_layout=true` (artigo) — carregadas em
iframe ou via fetch+render, sem precisar de domínio próprio nem de login.
Confirma a decisão já tomada.

---

### 3. Busca

**O que é.** Duas implementações, trocadas por feature flag de conta:

- **Padrão — full text Postgres.** `Article` usa `pg_search_scope :text_search`
  com `tsearch`, pesos diferentes por campo (`title: A, description: B,
  content: C`), prefixo habilitado, normalizado por tamanho do artigo para não
  favorecer artigo longo.
  Evidência: `app/models/article.rb:84-114`.
  Não é sensível a idioma além do que o Postgres já resolve por
  configuração default de dicionário (não há dicionário por locale
  configurado no código) — **não confirmado** se isso afeta relevância em
  pt_BR (acentos/stemming); não achei configuração de dicionário `portuguese`
  no `pg_search_scope`.
- **Opcional — busca vetorial (Enterprise).** Se a conta tem a feature
  `help_center_embedding_search` ligada, `search`/`index` chamam
  `Article.vector_search`: gera embedding da query via
  `Captain::Llm::EmbeddingService` (OpenAI), busca por `nearest_neighbors`
  (pgvector, distância cosseno) na tabela `article_embeddings`. Cada artigo
  tem seus embeddings recalculados (via job) sempre que título, descrição ou
  conteúdo mudam, gerando antes "termos de busca" com uma chamada a
  `gpt-4o`.
  Evidência: `enterprise/app/models/enterprise/concerns/article.rb:1-89`,
  `enterprise/app/controllers/enterprise/public/api/v1/portals/articles_controller.rb:1-11`,
  `enterprise/app/controllers/enterprise/public/api/v1/portals/search_controller.rb:1-9`,
  `enterprise/app/models/article_embedding.rb:1-31`,
  `enterprise/app/jobs/portal/article_indexing_job.rb:1-7`.
  A feature está **desligada por padrão** e marcada `premium` +
  `chatwoot_internal: true` em `config/features.yml:135-138`.

**Como usar no nosso caso.** Busca full-text padrão já resolve. Busca por
embeddings é tentadora (semântica), mas custa chamada OpenAI a cada
criação/edição de artigo e depende de `CAPTAIN_OPEN_AI_API_KEY` configurada —
avaliar custo/valor antes de ligar a flag.

---

### 4. Layout, tema, branding, home

**O que é.**
- Logo do portal via `has_one_attached :logo` (ActiveStorage); exibida no
  header público. `app/models/portal.rb:37`, `app/views/public/api/v1/portals/_header.html.erb:5-7`.
- Cor de marca (`portal.color`, hex validado, default `#1f93ff`) usada para
  gerar variações de fundo/hover via `color-mix()` CSS.
  Evidência: `app/models/portal.rb:31,124-126`,
  `app/helpers/portal_helper.rb:20-33`.
- Tema claro/escuro/sistema, alternável pelo visitante (`?theme=dark|light`),
  aplicado tanto no header quanto no corpo.
  Evidência: `app/controllers/public/api/v1/portals/base_controller.rb:18-20`,
  `app/views/public/api/v1/portals/_header.html.erb:24-40`.
- Botão "ir para o site" (`homepage_link`) no header, com UTM automático
  quando usado para voltar à marca.
  Evidência: `app/models/portal.rb` (coluna `homepage_link`),
  `app/helpers/portal_helper.rb:85-94`.
- Conteúdo recomendado na home (`popular_content` no config): até 3 categorias
  e 6 artigos escolhidos manualmente por locale, com fallback automático por
  posição/visualizações quando não configurado.
  Evidência: `app/controllers/concerns/portal_home_data.rb:1-65`,
  `app/models/portal.rb:82-84,146-152`.
- OG image dinâmica (para compartilhamento em redes) via CDN externo opcional
  (`OG_IMAGE_CDN_URL`) — se não configurado, simplesmente não gera.
  Evidência: `app/helpers/portal_helper.rb:3-18`.

**Como usar no nosso caso.** Dá para ter identidade visual (logo, cor) igual
nas duas centrais (Hub2You/Autonomia) ou diferente por conta — é
configuração por `Portal`, não por deploy.

---

### 5. Integração com o widget do site

**O que é.** O widget do site (chat embutido) já tem uma tela "Home" que lista
os artigos populares do portal conectado ao inbox, e um leitor de artigo
embutido (`ArticleViewer.vue`). Ele consome exatamente o mesmo endpoint
público JSON: `GET /hc/:slug/:locale/articles.json`.
Evidência: `app/javascript/widget/api/endPoints.js:119`,
`app/javascript/widget/components/pageComponents/Home/Article/ArticleBlock.vue:1-48`,
`app/javascript/widget/views/ArticleViewer.vue`.

O vínculo widget↔portal vem da serialização do inbox: se o inbox (canal
Web Widget) tem `portal_id` setado, a API do inbox expõe
`help_center: { name, slug }`, que tanto o widget quanto o dashboard usam.
Evidência: `app/views/api/v1/models/_inbox.json.jbuilder:23-27`.

**Como usar no nosso caso.** Não é o nosso caso de uso principal (nosso público
é "clientes dentro do painel", não visitantes do site), mas confirma que os
mesmos endpoints públicos já são "produção" — não têm status de rascunho
interno.

---

### 6. Integração com a caixa de resposta do atendente (reply box)

**O que é.** Existe um botão "inserir artigo" na caixa de resposta
(`ReplyBox.vue`) que abre um popover de busca de artigos
(`ArticleSearchPopover`/`SearchPopover.vue`/`SearchResults.vue`) e insere um
link Markdown `[título](url)` no editor ao selecionar um artigo.
Evidência: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:15,666-676,1310-1311,1357-1360`,
`app/javascript/dashboard/routes/dashboard/helpcenter/components/ArticleSearch/SearchPopover.vue`.

Esse botão só aparece se o inbox da conversa tiver portal conectado
(`connectedPortalSlug`, derivado de `inbox.help_center.slug`).
Evidência: `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:482-486`.

**Como usar no nosso caso.** Para o atendente poder inserir um artigo da
Central "Plataforma" numa resposta, o inbox dele precisa estar associado ao
`Portal` (campo `inboxes.portal_id`). Vale considerar conectar os inboxes
relevantes de cada conta ao respectivo portal só por esse ganho, mesmo que o
uso principal da central seja "cliente lê dentro do painel".

---

### 7. Uso por IA (Captain, Copilot) — este é o ponto que mais difere do que se
assumiria por padrão

**O que é, com evidência de que são três coisas diferentes:**

1. **Captain (assistente que conversa com o cliente final).** A ferramenta
   `search_documentation` que ele usa busca em
   `Captain::AssistantResponse` (uma base de **FAQ própria**, gerada/curada
   dentro do produto Captain), **não** em `Article`/Portal.
   Evidência: `enterprise/app/services/captain/tools/search_documentation_service.rb:1-38`,
   `enterprise/app/services/captain/tools/search_reply_documentation_service.rb:1-46`.
   Captain também tem um pipeline de ingestão de documentação própria
   (`Captain::Document`, crawler de URL externa) — outra fonte, também
   separada do Help Center.
   Evidência: `enterprise/app/models/captain/document.rb`,
   `enterprise/app/services/captain/documents/sync_service.rb`.
2. **Copilot (assistente do agente humano, dentro da tela de conversa).** Este
   sim lê `Article` diretamente: ferramentas `search_articles` (busca por
   título/conteúdo com `ILIKE`, filtra por categoria/status) e `get_article`
   (traz o artigo inteiro formatado para o LLM via `article.to_llm_text`).
   Ambas exigem a permissão Enterprise `knowledge_base_manage` para ficarem
   ativas (`active?`).
   Evidência: `enterprise/app/services/captain/tools/copilot/search_articles_service.rb:1-35`,
   `enterprise/app/services/captain/tools/copilot/get_article_service.rb:1-18`,
   `app/services/llm_formatter/article_llm_formatter.rb:1-22`,
   `app/models/concerns/llm_formattable.rb:1-7`.
3. **Busca vetorial do próprio Help Center** (seção 3) é uma terceira coisa:
   embeddings gerados a partir do artigo, usados só para a busca pública do
   portal — não alimentam Captain nem Copilot.

**Como usar no nosso caso.** Se a intenção é "IA responde cliente usando a
Central Plataforma como fonte", isso **não acontece automaticamente** hoje —
seria preciso ou (a) ativar/():ligar o Copilot para o agente e contar com ele
puxar artigos manualmente durante o atendimento, ou (b) fazer o Captain
ingerir o conteúdo via `Captain::Document` (crawleando as próprias páginas
públicas `/hc/...`, já que são públicas), ou (c) construir uma integração nova
— qualquer uma dessas é decisão de produto, não algo "de graça" do Portal.

---

### 8. Portal ↔ Inbox

**O que é.** `Inbox belongs_to :portal, optional: true`
(`app/models/inbox.rb:60`); `Portal has_many :inboxes, dependent: :nullify`
(`app/models/portal.rb:38`). Existe também `portal.channel_web_widget_id`,
setado só quando o inbox conectado via `inbox_id` no formulário do portal é
efetivamente um Web Widget (`live_chat_widget_params`,
`app/controllers/api/v1/accounts/portals_controller.rb:121-130`).
Isso alimenta: (1) o botão de artigo na reply box (seção 6), e (2) a tela Home
do widget daquele inbox (seção 5). Não vi nenhum outro efeito colateral de
"conectar" um inbox ao portal.

**Como usar no nosso caso.** Não precisamos necessariamente conectar inbox
algum ao portal — nosso consumo é direto via rota pública dentro do painel,
não depende de `inbox.portal_id`. Conectar só se quisermos o botão de inserir
artigo na reply box (seção 6).

---

### 9. API autenticada de gestão — como publicar conteúdo por script

**O que é.** Sob `api/v1/accounts/:account_id/portals`
(`config/routes.rb:744-761`), tudo autenticado por token de usuário/API do
Chatwoot:

| Ação | Endpoint | Controller |
|---|---|---|
| Listar/criar/editar/destruir portal | `.../portals` | `Api::V1::Accounts::PortalsController` |
| Arquivar portal, apagar logo, enviar instruções de domínio, status SSL | member actions em `.../portals/:id` | idem |
| CRUD + reorder de categoria | `.../portals/:portal_id/categories` | `Api::V1::Accounts::CategoriesController` |
| CRUD + reorder de artigo | `.../portals/:portal_id/articles` | `Api::V1::Accounts::ArticlesController` |
| Bulk: mudar status, mudar categoria, apagar em lote, traduzir | `.../articles/bulk_actions/...` | `Api::V1::Accounts::Articles::BulkActionsController` |
| Upload de imagem (genérico, usado pelo editor) | `POST /api/v1/accounts/:id/upload` | `Api::V1::Accounts::UploadController` |

Evidência: `app/controllers/api/v1/accounts/portals_controller.rb:1-146`,
`app/controllers/api/v1/accounts/categories_controller.rb:1-63`,
`app/controllers/api/v1/accounts/articles_controller.rb:1-124`,
`app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:1-59`,
`app/controllers/api/v1/accounts/upload_controller.rb:1-54`.

**Detalhe importante para script:** `bulk_actions#translate` existe na rota
mas está **não implementado** (`head :not_implemented`) —
`app/controllers/api/v1/accounts/articles/bulk_actions_controller.rb:6-8`.
Não conte com tradução automática via API.

**Imagem em artigo.** Não existe endpoint "anexar imagem ao artigo X". O fluxo
real é: `POST /upload` com o arquivo (`params[:attachment]`) **ou** uma URL
externa (`params[:external_url]`, que o servidor busca via `SafeFetch`) →
devolve `{ file_url, blob_id }` (blob do ActiveStorage) → você embute
`file_url` como `![alt](file_url)` no Markdown de `content` ao criar/atualizar
o artigo. A imagem "pertence" ao blob do ActiveStorage da conta, não ao
artigo.
Evidência: `app/controllers/api/v1/accounts/upload_controller.rb:1-54`.

**Autor obrigatório.** `Article` exige `author_id` de um `User` que já existe
na conta (`validates :author_id, presence: true`,
`app/models/article.rb:64`; validação extra:
`author_belongs_to_account?` em
`app/controllers/api/v1/accounts/articles_controller.rb:86-88`). Um script de
sincronização precisa de um usuário "autor" real na conta (ex.: um usuário de
serviço "Autonomia Bot") — não dá para inventar um `author_id`.

**Como usar no nosso caso.** Dá para escrever hoje um script (Ruby/HTTP) que:
1. garante o `Portal` da conta (create/update idempotente por `slug`);
2. garante `Category`/`Folder` por `slug`+`locale`+`portal_id`;
3. para cada imagem do artigo-fonte no repositório, `POST /upload`, guarda o
   `file_url`, reescreve o Markdown;
4. `POST`/`PATCH` em `.../articles` com `status: published`, `author_id` fixo,
   `slug` estável (gerado a partir do caminho do arquivo-fonte, não do
   título — título pode mudar);
5. usa `reorder` para fixar a posição pretendida.

---

### 10. Feature flags, permissões, o que é Enterprise-only

**Feature flags (`config/features.yml`):**
- `help_center` (linha 42-45): habilitada por padrão (`enabled: true`). Só
  bloqueia acesso público quando `ChatwootApp.chatwoot_cloud?` é verdadeiro
  (`app/controllers/public_controller.rb:22-27`) — **em self-hosted (nosso
  caso) essa checagem não bloqueia nada**, então não é um interruptor útil
  para nós a menos que estejamos em modo cloud.
- `help_center_embedding_search` (linha 135-138): `enabled: false`, marcada
  `premium` + `chatwoot_internal: true` — busca vetorial (seção 3).
- `captain_integration` (linha 141-144): `enabled: false`, `premium` —
  controla o assistente Captain, não a Central em si.

**Permissões.** Fora do Enterprise, só `administrator?` pode
criar/editar/apagar Portal, Category, Article
(`app/policies/portal_policy.rb:1-37`, `article_policy.rb:1-31`,
`category_policy.rb:1-31`). Qualquer usuário da conta pode listar/ver
(`index?`/`show?` liberado a `@account.users.include?(@user)` em alguns
casos). O Enterprise (`enterprise/app/policies/enterprise/*_policy.rb`)
acrescenta papéis customizados: `knowledge_base_manage` (gerencia
tudo) e `knowledge_base_view` (só leitura) — documentado em
`enterprise/app/models/custom_role.rb:25,35,59,68`.

**O que é Enterprise-only, confirmado no código:**
- Busca vetorial (`enterprise/app/models/enterprise/concerns/article.rb`).
- Permissões customizadas de Central de Ajuda
  (`enterprise/app/policies/enterprise/{portal,category,article}_policy.rb`).
- Verificação de domínio customizado via Cloudflare
  (`enterprise/app/models/enterprise/concerns/portal.rb:8-13`) — só roda em
  Chatwoot Cloud (`return unless ChatwootApp.chatwoot_cloud?`), irrelevante
  para nós.
- Ferramentas do Copilot que leem artigos
  (`enterprise/app/services/captain/tools/copilot/{search,get}_article*`).

Este fork parece ter o Enterprise habilitado (`custom_roles`,
`captain_integration` etc. existem como flags reais, e há código Enterprise
completo em `enterprise/`) — **não confirmado por este agente** se
`ChatwootApp.enterprise?` está de fato `true` no ambiente de produção; isso é
configuração de deploy, não algo que dá para ler no código-fonte.

---

### 11. Limitações e pegadinhas relevantes

1. **Slug de artigo é único globalmente no banco, não por portal.**
   `index_articles_on_slug (slug) UNIQUE` (`app/models/article.rb:32`), e o
   *model* não tem `validates :slug, uniqueness: true` — só existe a
   constraint do banco. Duas consequências: (a) se as contas Hub2You e
   Autonomia estiverem no mesmo banco/app, os slugs dos artigos das duas
   centrais competem pelo mesmo espaço de nomes; (b) uma colisão de slug
   estoura como `ActiveRecord::RecordNotUnique` (erro feio de banco), não como
   uma mensagem de validação amigável — o script de sync precisa checar
   unicidade antes de gravar, ou capturar essa exceção especificamente.
2. **`locale` do portal não é validado contra uma lista fechada de idiomas.**
   `allowed_locale_codes` aceita qualquer string não vazia
   (`app/models/portal.rb:102-107`); só a tradução de *interface* (textos do
   Chatwoot) cai para o idioma padrão se o valor não bater com
   `I18n.available_locales` (`app/controllers/concerns/switch_locale.rb:59-72`).
   O *conteúdo* (qual artigo aparece) usa o locale literal da URL. Ou seja,
   dá para ter conteúdo em `pt_BR` mesmo que a UI do Chatwoot não tenha
   tradução completa para esse locale — bom para nós, mas exige cuidado para
   não digitar o locale errado ao publicar (não há validação que pegue erro
   de digitação).
3. **`content` sem limite de tamanho** (coluna `text` do Postgres) — não é
   pegadinha, é folga.
4. **Markdown do artigo é renderizado por um renderer próprio**
   (`CustomMarkdownRenderer`, `lib/custom_markdown_renderer.rb:1-220`) com
   suporte a tabelas com largura fixa, embeds (vídeo/link, configurados em
   `config/markdown_embeds.yml`), superscript (`^texto^`) e redimensionamento
   de imagem via querystring (`?cw_image_width=NNNpx`). HTML bruto dentro do
   Markdown **não foi confirmado como seguro/permitido** — o parser roda com
   `CommonMarker.render_doc(@content, :DEFAULT, [:table])`, sem a extensão
   `:UNSAFE`, então o comportamento padrão do CommonMarker é filtrar HTML cru;
   não recomendo depender de HTML embutido para o "botão que leva à tela do
   painel" — melhor usar um link Markdown normal e deixar nosso CSS do
   container estilizá-lo como botão.
5. **Não existe campo nativo de "call-to-action" no artigo.** `meta` (jsonb)
   só aceita `title`, `description`, `tags` (`app/controllers/api/v1/accounts/articles_controller.rb:111-113`).
   Um botão "abrir tela X do painel" por artigo teria que ser um link Markdown
   normal (`[Abrir orçamento](chatwoot://...)` ou uma URL absoluta), não um
   campo estruturado.
6. **`bulk_actions#translate` não está implementado** (ver seção 9).
7. **Busca full-text não tem dicionário de português configurado** no
   `pg_search_scope` — relevância de acento/plural em pt_BR não confirmada.
8. **`help_center` feature flag não bloqueia nada em self-hosted** — não é um
   kill-switch útil aqui.
9. **Rate limit genérico do Rack::Attack** (`req/ip`, 3000/min por padrão,
   `config/initializers/rack_attack.rb:71`) cobre `/hc/...` porque não há
   regra específica de exceção nem de limite mais apertado para essas rotas —
   folga suficiente para uso interno, mas vale saber que existe um teto.
10. **Autor obrigatório e válido** (seção 9) — publicar por script exige um
    `User` real por conta.

---

## (c) Recomendações

**Aproveitar como está, sem construir nada nosso:**
- O modelo de dados inteiro (`Portal`/`Category`/`Folder`/`Article`), a API
  autenticada de CRUD/bulk/reorder, e o upload genérico de imagem — dá para
  escrever hoje o script de sincronização repositório → Central sem tocar em
  uma linha de Ruby/Vue.
- As rotas públicas `/hc/...` com `?show_plain_layout=true` para renderizar
  dentro do painel — é literalmente o mecanismo desenhado para isso.
- Busca full-text padrão — não precisa da busca vetorial para o volume que
  provavelmente teremos.
- SEO básico via `meta` (title/description/tags) e sitemap automático, mesmo
  que não pretendamos indexar publicamente agora (custa nada deixar
  preenchido).

**Ignorar por enquanto (não é grátis, é decisão de produto):**
- Busca por embeddings (`help_center_embedding_search`) — custo OpenAI por
  edição de artigo, flag `premium`/`chatwoot_internal`, ganho incerto para o
  nosso volume de conteúdo.
- Domínio customizado / verificação Cloudflare do portal — já descartado
  pelo contexto ("sem domínio próprio").
- Conectar inbox ao portal, a menos que a gente também queira o botão
  "inserir artigo" na reply box do atendente — é opcional, não é pré-requisito
  do nosso uso.
- Integração com Captain/Copilot como fonte de conhecimento — não existe
  hoje "de graça"; se quisermos IA respondendo com base na Central, é um
  projeto à parte (crawlear as páginas públicas como `Captain::Document`, ou
  estender o Copilot).

**Riscos a resolver antes de programar o script:**
- Confirmar se Hub2You (conta 16) e Autonomia (conta 1) estão no mesmo banco
  — se sim, o gerador de slug do script precisa evitar colisão global
  (prefixar por conta, por exemplo), por causa do índice único descrito na
  seção 11.1.
- Definir o usuário "autor" de serviço em cada conta antes de publicar.
- Decidir se usamos link Markdown estilizado (recomendado) ou se vale a pena
  estender `meta` para um campo de CTA estruturado — isso *seria* mexer no
  fork, fora do escopo desta pesquisa (só leitura).

---

## (d) Perguntas em aberto

1. As contas 16 (Hub2You) e 1 (Autonomia) rodam na mesma instalação/banco de
   dados do Chatwoot, ou são deploys separados? Determina se o slug de artigo
   precisa de prefixo por conta (seção 11.1). Não dá para responder lendo só
   o código deste worktree.
2. `ChatwootApp.enterprise?` está ligado em produção? Isso decide se as
   permissões `knowledge_base_manage`/`knowledge_base_view` e as ferramentas
   de Copilot sobre artigos (seção 7.2) estão realmente disponíveis, ou se só
   existem no código mas desligadas por licença/flag de deploy.
3. Vale a pena, no fluxo de publicação por script, gerar automaticamente
   `Captain::Document`s a partir das páginas públicas `/hc/...` para o Captain
   (bot do cliente) também "saber" o conteúdo da Central? Isso é uma decisão
   de produto que este documento não deveria tomar sozinho.
4. Existe algum usuário de serviço (`User`) já convencionado para "autoria"
   de conteúdo publicado por automação em cada conta, ou precisamos criar um?
5. Queremos usar `layout: documentation` (sidebar + TOC, mais parecido com
   docs técnicos) ou `classic` (mais parecido com central de ajuda tradicional)
   para a Central "Plataforma"? Ambos existem prontos; é escolha de produto,
   não limitação técnica.
