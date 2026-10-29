# Anúncios da Meta — primeira configuração de uma conta (#2338)

Como levar uma conta do zero até os Anúncios da Meta funcionando: o que a instalação precisa ter, o que ligar na
conta e o passo a passo que o cliente faz no painel. O desenho de cada fase está em `anuncios-meta-f1.md` (conexão)
a `anuncios-meta-f5.md`, `anuncios-meta-criar-2198.md` (criar e impulsionar), `../meta/comentarios-instagram.md` e
`../meta/webhook-de-pagina.md`.

O documento descreve o que está no código. O que depende do painel da Meta (escopos da configuração de login,
endereço do webhook) aparece como "fica no painel da Meta". Trechos marcados "(#2372)", "(#2373)" ou "(#2374)" valem
depois que esses PRs entram no ar.

---

## 1. Antes de começar: a instalação

Uma vez por instalação, não por conta. Aqui só os nomes; os valores nunca vão para o repositório.

**Só no ambiente** (variável do servidor, não aparecem no Super Admin):

| Para quê | Variáveis | Sem elas |
|---|---|---|
| CRM ligado | `CRM_KANBAN_ENABLED` | A API de Anúncios responde 404 e a página cai no Início. |
| Guardar token cifrado | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Colar a chave responde `encryption_not_configured`; o token da parceira não é lido. |

**No Super Admin** (InstallationConfig):

| Para quê | Configurações | Sem elas |
|---|---|---|
| "Entrar com o Facebook" nos Anúncios | `META_ADS_LOGIN_CONFIGURATION_ID`, `WHATSAPP_APP_ID`, `WHATSAPP_APP_SECRET` (versão: `WHATSAPP_API_VERSION`) | O botão não aparece; sobram os outros dois jeitos de conectar. |
| "Compartilhar com a parceira" | `META_ADS_PARTNER_BUSINESS_ID`, `META_ADS_PARTNER_BUSINESS_NAME` (padrão Hub2You), `META_ADS_SYSTEM_USER_ID` e o token da plataforma (abaixo) | Sem o Facebook configurado, a opção diz "Compartilhar ainda não está disponível". Com o Facebook configurado, ela só não aparece. |
| Página do Facebook (Messenger, Seus posts, webhook `/bot`) | `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN`, `FACEBOOK_API_VERSION`; repasse entre stacks: `FB_PAGE_WEBHOOK_RELAY_URLS` | Sem caixa da Página não há comentários do Facebook nem Seus posts da Página. |
| Instagram | `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN`; repasse: `INSTAGRAM_WEBHOOK_RELAY_URLS` | Sem caixa do Instagram não há comentários do Instagram nem Seus posts do Instagram. |

O token da plataforma (`META_ADS_PLATFORM_TOKEN` no formulário do Super Admin) não fica na InstallationConfig nem é
lido do ambiente: o Super Admin grava cifrado como credencial `meta_ads` (`SuperAdmin::MetaAdsAppConfig`), e é só
dali que `Crm::MetaAds::Platform` lê.

Fica no painel da Meta: os escopos da configuração de login (`META_ADS_LOGIN_CONFIGURATION_ID`) e o endereço do
webhook da Página. Enquanto o App Review de `ads_read` não sai, só entra pelo Facebook quem tem função no app
(`anuncios-meta-f1.md`).

## 2. Na conta: flags e acesso

### Flags

O padrão de fábrica está em `config/features.yml`. O que uma conta nova recebe de fato vem de
`ACCOUNT_LEVEL_FEATURE_DEFAULTS` (InstallationConfig), que pode mudar isso: confira na conta antes de começar.

| Recurso | Flag | Padrão no `features.yml` | Observação |
|---|---|---|---|
| Anúncios (o hub) | `meta_ads_hub` | ligada | Sem ela, o menu some e a página do site no Destino responde 404 (#2374). |
| Resultado do WhatsApp sem login | `anuncios_sem_login` | ligada | Mostra quem veio de anúncio antes de conectar. |
| Pausar/ativar e Página na Conexão | `meta_ads_gestao` | ligada | Pré-requisito dos comentários do Instagram. |
| Comentários do Instagram | `meta_ads_comentarios_instagram` | desligada | Exige também `meta_ads_gestao`. |
| Comentários do Facebook | `meta_ads_comentarios_facebook` | desligada | |
| Formulários de leads | `meta_ads_formularios` | desligada | |
| Criar e impulsionar anúncio | `meta_ads_criar` | desligada | A mesma flag cobre os dois. |
| Seus posts (página própria) | `seus_posts` | desligada | Com ela e `posts_view` ou `posts_manage`, a aba antiga de Anúncios leva à página nova. |
| Seus posts (aba antiga em Anúncios) | `meta_ads_organico` | desligada | |

Flag nova liga primeiro nas contas piloto; ligar para todas é decisão do Rodrigo.

### Quem vê e quem mexe

| Chave | O que libera |
|---|---|
| `meta_ads_view` | Painel de Resultado, estado da conexão, lista de páginas do site no Destino (#2374). Não vê a aba Conexão. |
| `meta_ads_manage` | Conectar, escolher conta e Pixel, Destino (inclusive ligar a página do site, #2374), Avisar a Meta, pausar, criar, orçamento. Implica `meta_ads_view`. Chave protegida: só o administrador entrega. |
| `sales_value_view` | Valores de venda em R$ no painel e no anúncio. Sem ela, aparecem só contagens. |
| `contact_view` | Em Formulários, a lista de quem chegou (nome, telefone, e-mail). Trazer quem já preencheu pede também poder criar card no CRM. |
| `campaign_view` / `campaign_manage` | Não liberam Anúncios. Com `campaign_view`, o Destino mostra também o resultado por campanha da página do site; editar e apagar a página continua em Links e QR codes (`campaign_manage`). |
| `posts_view` / `posts_manage` | Seus posts. |

Comentários: ver pede `meta_ads_view`; agir pede `meta_ads_manage`. Os do Instagram pedem também ver a caixa do
Instagram, para ler e para agir (#2358); "Entrar de novo" no Instagram pede `integration_manage`. Os do Facebook
pedem também ver a caixa do Messenger da Página.

## 3. O passo a passo no painel

Caminho: **Crescer › Campanhas › Anúncios**, aba **Conexão** (`/accounts/:id/campaigns/meta-ads?aba=conexao`).
Sem conta de anúncios escolhida, a página só mostra a Conexão. A lista "Passos da conexão" acompanha a pessoa:

| # | Passo | O que a pessoa faz | Fica pendente quando |
|---|---|---|---|
| 1 | Conectar | Escolhe um dos três jeitos (abaixo). | — |
| 2 | Conta de anúncios | Escolhe a conta que paga os anúncios e o código do site (Pixel), ou "Não tenho site". | Falta o Pixel e não marcou "Não tenho site": "Falta o código do site (Pixel)". |
| 3 | Destino do anúncio | Marca WhatsApp, site ou os dois. Com site, liga a página do site ali mesmo (#2374): cola o endereço, o nome sai do endereço e o WhatsApp é o da conta (com mais de um, escolhe). Precisa de um WhatsApp conectado na conta; sem ele, a janela diz isso. | Marcou site e não há página ligada: "Falta ligar a página do site", com o botão "Ligar" (#2374). |
| 4 | Avisar a Meta | Escolhe, por funil, o que cada etapa significa para a Meta e liga o envio de avanços e vendas. | Não fica pendente: se a pessoa tocar "Agora não", o passo aparece "Desligado", com o botão "Ligar". |

A página ligada no Destino é o mesmo link de site de Links e QR codes: aparece lá também, e é lá que se edita ou
apaga. Depois de ligar, use "Copiar texto" no bloco "Cole este texto nos anúncios que levam para o site" e cole em
cada anúncio que leva ao site (Gerenciador de Anúncios › anúncio › Rastreamento › Parâmetros de URL). Sem esse texto,
a página avisa que o clique de anúncio "chegou sem o nome da campanha" (#2373).

### Os três jeitos de conectar

| Jeito | Quando usar | Limites |
|---|---|---|
| Entrar com o Facebook (`facebook_login`) | Padrão quando disponível; ocupa o passo inteiro. A pessoa usa o mesmo Facebook em que cria os anúncios e deixa tudo marcado, inclusive a Página. | Ele e a chave de acesso são os jeitos que dão token próprio, que é o que comentários do Facebook, formulários e criar anúncio precisam. |
| Compartilhar com a parceira (`partner`) | O cliente prefere só dar acesso de leitura. Na Meta: Configurações do negócio › Usuários › Parceiros › Adicionar › Conceder a um parceiro acesso aos seus ativos › colar o código › marcar a conta com "Ver desempenho" e o Pixel › voltar e tocar "Já compartilhei". | Só aparece com a parceira configurada e um WhatsApp ligado pela Meta (não pelo QR Code). Só leitura: não serve para comentários do Facebook, formulários nem criar. |
| Chave de acesso (`token`) | Quem já tem um token com `ads_read`. | O servidor testa a chave antes de gravar. |

Trocar de jeito numa conexão já gravada:
- **para Facebook ou chave**: ao gravar o token novo, a conta de anúncios e o Pixel escolhidos são apagados
  (`SELECTION_RESET`), porque o token novo pode não ler a conta antiga. A pessoa volta ao passo 2.
- **para a parceira**: nada é apagado ao escolher; a conta só muda quando a nova seleção é salva, e aí o token
  próprio é apagado.

Se a pessoa abrir Criar anúncio sem conta escolhida, a tela diz "Para criar anúncio por aqui, falta ligar a sua conta
de anúncios." e o botão "Ligar a conta de anúncios" leva ao passo 2 (#2372).

## 4. Cada recurso: o que precisa além da conexão

| Recurso | Precisa de | A tela avisa |
|---|---|---|
| Comentários do Instagram | Caixa do Instagram (login do Instagram, não o dos anúncios) e reautorização com `instagram_business_manage_comments`. | "Conectar o Instagram" sem caixa; "Entrar com o Instagram" quando falta a permissão. |
| Comentários do Facebook | Conexão por Facebook ou chave, com a Página marcada no login e os escopos `pages_read_user_content` e `pages_manage_engagement`; e a caixa do Messenger da Página. O `feed` é assinado na primeira vez que alguém com `meta_ads_manage` abre a aba. | "Ir para a Conexão" (`needs_login`, inclusive no modo parceira) e "Conectar no Messenger" (sem caixa). |
| Formulários de leads | Conexão por Facebook ou chave, com a Página marcada no login e os escopos `pages_manage_metadata` e `leads_retrieval`. Não depende da caixa do Messenger. Escolher o funil assina o `leadgen`. | "Não achamos sua Página do Facebook. Conecte de novo e marque a Página…" |
| Criar e impulsionar | Token próprio com `ads_management` e `pages_manage_ads`. | "Para criar anúncios por aqui, entre de novo com o Facebook." |
| Seus posts | Caixa do Instagram (reautorização com `instagram_business_manage_insights`) ou da Página (login da Página pelo `FB_APP_ID`, com `read_insights`). Não usa a conexão de anúncios. | "Conecte seu Instagram…" sem caixa; "Libere os números…" sem permissão. |

Os escopos de comentários do Facebook e de formulários vêm do login dos Anúncios, configurado no painel da Meta; o
login da caixa da Página (`helper/facebookScopes.js`) não os pede. As mensagens e eventos da Página chegam pelo mesmo
webhook `/bot` (Messenger, `leadgen` e `feed`).

## 5. Conferência de uma conta nova

1. Flags da seção 2 conferidas na conta.
2. Passos 1 a 3 sem pendência na lista "Passos da conexão"; passo 4 ligado se o cliente usa funil.
3. Com destino site: a página aparece no Destino e em Links e QR codes; "Testar agora" confirma o aviso do site.
4. Para cada recurso ligado, a aba abre sem aviso de falta (seção 4).
5. Criar anúncio abre o formulário (e não o aviso de conta).
