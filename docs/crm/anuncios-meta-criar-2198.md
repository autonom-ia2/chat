# Anúncios da Meta: o Gerenciador simples (#2198)

Estado em 27/10/2026: o Rodrigo aprovou a implementação real, atrás da flag
`meta_ads_criar`, com a tela aprovada no protótipo (rodada r10b). Ela entra em
quatro PRs, nesta ordem:

1. Orçamento e datas, mais anúncio novo (servidor, tela, migration
   `20261108580000` e a flag).
2. Impulsionar post do Instagram e do Facebook.
3. Criar post (e "Publicar e impulsionar").
4. Cuidar: duplicar e trocar a foto como cópia (`can_swap_creative`).

Este documento guarda o que a implementação precisa cumprir e que a tela já
promete ao cliente. O que o servidor faz está em "Servidor do PR 1" e
"Servidor do PR 2" (impulsionar post, #2339).

O escopo cresceu em 26/10 por decisão do Rodrigo: "inclua as permissões para
14/11 e complete. Quero a experiência do gerenciador aqui, só que de forma
simples como sempre fazemos." Épico do pedido à Meta: #2194.

## Os cinco fluxos

| Fluxo | Telas | Toques até criar |
|---|---|---|
| 1. Anúncio novo | O que fazer → foto/vídeo/carrossel e texto (com "Quem tocar vai para: WhatsApp · Trocar") → quem vê → quanto investir → conferir | 9 |
| 2. Impulsionar post | O que fazer → o post (abas Instagram e Facebook) → quem vê → quanto investir → conferir | 8 |
| 3. Criar post | O que fazer → onde publicar, mídia e legenda → conferir → confirmar | 7 (11 com "Publicar e impulsionar") |
| 4. Onde aparece | Na conferência: "Automático · Trocar" | 0 (2 para trocar) |
| 5. Cuidar | No detalhe do anúncio: pausar, orçamento, duplicar, trocar foto ou texto | Duplicar 2; trocar 5 (texto: 3) |

Ativar custa mais 2 toques em todos: "Ativar anúncio" e a confirmação com o
valor por extenso.

## O que a tela promete

- Orçamento e datas: o cliente vê o valor antigo e o novo, por extenso, antes de
  confirmar. Teto de R$ 6 a R$ 500 por dia. A troca vai para a Auditoria com o
  nome de quem fez.
- Anúncio novo, impulsionar e duplicar: **nasce pausado** e não gasta nada até a
  pessoa tocar em "Ativar anúncio". O botão mostra quanto vai gastar antes de
  começar.
- Criar post: **publica na hora**, depois de uma confirmação que diz onde. É de
  graça. "Publicar e impulsionar" publica e segue para o impulsionamento, que
  nasce pausado e reaproveita a mídia e a legenda.
- Trocar foto ou texto: a confirmação diz que a Meta analisa de novo e que o
  anúncio pode ficar fora do ar enquanto isso.
- Anúncio criado por aqui e ainda pausado aparece no topo do Resultado
  ("Pausados, esperando você ativar"), para quem volta ao painel sem ativar.
- Público do CRM fica fora desta entrega.

## Tudo nasce pausado; o "Ativar anúncio" liga os três

Decisão do Rodrigo (opção a, 27/10): a campanha, o grupo de anúncios e o
anúncio são criados com `status: PAUSED`. O "Ativar anúncio" (a rota de
ativação que já existia, #2161) liga os três, nesta ordem: campanha, grupo,
anúncio, relendo cada um. Se um falhar, os já ligados voltam para `PAUSED` e a
tela recebe o erro; se nem voltar der, `meta_partial` e a Auditoria registra o
que ficou ligado (`meta_ads_activate_partial`). A pessoa continua tocando em
uma chave só. Pausar um anúncio criado aqui é simétrico (decisão da revisão,
27/10): pausa os três, na ordem anúncio, grupo, campanha, relendo cada um. Se
a pausa falhar no meio, a tela recebe o erro e a Auditoria registra o que
ficou ligado (`meta_ads_pause_partial`); nada é religado. Enquanto um "Ativar"
ou "Pausar" liga ou pausa os três, um segundo clique recebe `in_progress`
(trava `switching_at`, por UPDATE condicional). A Auditoria do
`meta_ads_ad_status` guarda os ids da campanha, do grupo e do anúncio. Se a
Meta ligou tudo e só a gravação local falhar, a resposta continua sendo
sucesso. Anúncio que não foi criado aqui segue a ativação de sempre (só o
anúncio). O gasto é zero até o toque em "Ativar anúncio", mas só se o servidor
cumprir os sete pontos abaixo. Cada um é obrigatório na implementação.

1. **`status: PAUSED` explícito nos três** (`/campaigns`, `/adsets`, `/ads`).
   Nunca depender do padrão da Meta.
2. **Reler depois de criar.** Ler o `status` dos três. O que não vier
   pausado é pausado na hora e fica na Auditoria (`meta_ads_create_repaused`).
3. **Falha no meio desfaz o começo.** Se a campanha ou o grupo foram criados e
   um passo seguinte falhou, apagar (ou arquivar, se a Meta não deixar apagar)
   o que foi criado. A tela diz "Nada foi criado" e isso precisa ser verdade.
4. **Chave de idempotência** por tentativa de criar. Dois toques no botão, ou
   uma nova tentativa depois de timeout, não criam duas campanhas.
5. **Revalidar no servidor** o valor (R$ 6 a R$ 500 por dia) e as datas
   (início não antes de hoje, fim depois do início). O grupo recebe
   `start_time` e `end_time` iguais aos que a tela mostrou.
6. **Ao ativar, ligar e conferir os três.** Anúncio criado aqui: liga e relê
   campanha, grupo e anúncio. Outro anúncio: se a campanha ou o grupo não
   estiver ativo (pausado no Gerenciador, por exemplo), avisar a pessoa em vez
   de dizer que o anúncio começou a rodar.
7. **Teste que cria, relê e confirma** `PAUSED` e gasto zero, nas contas de
   teste, antes de ligar a flag para qualquer cliente.

## O que o servidor devolve para a tela

Mais quatro pontos, que a tela já supõe:

8. **O GET das opções de criar devolve `facebook_login`** (`app_id`,
   `api_version`, `configuration_id`), igual ao GET da conexão. Sem ele, o
   "Entrar com o Facebook" do criar vira "Ir para a Conexão e entrar".
9. **A lista de pausados vem marcada na criação.** O servidor grava quais
   anúncios a plataforma criou e lê na Meta só esses, quando ainda pausados.
   Não lista todos os pausados da conta. No protótipo a lista vem da memória do
   navegador.
   Com o próprio anúncio `PAUSED`, a lista decide por classe de
   `effective_status` (#2354): `PAUSED` está pronto para ativar;
   `PENDING_REVIEW` e `IN_PROCESS` estão em análise da Meta e entram com
   `in_review: true`; o resto fica fora. Leitura real de 29/10 (conta 18,
   anúncio 120255124400230416, os três níveis pausados): logo depois de criar,
   `IN_PROCESS`; depois da análise, `PAUSED`. `CAMPAIGN_PAUSED` e
   `ADSET_PAUSED` também contam como prontos, por regra: o Ativar de um anúncio
   criado aqui liga os três níveis. Que a Meta devolva um deles para um anúncio
   pausado: **não confirmado** (não apareceu na leitura real).
   O `in_review` vale em todo lugar que oferece o Ativar: a lista, o topo do
   anúncio (o detalhe traz `in_review` da gestão) e o cartão de criado (a
   resposta do criar traz `in_review` da releitura que ele já faz). No lugar do
   botão, a mesma frase: "A Meta está conferindo este anúncio. Em geral leva
   até 1 dia. Você poderá ativar quando ela terminar." O servidor relê o
   anúncio depois da trava e recusa ligar com `in_review` (ou
   `meta_unavailable`, se não conseguir ler), no anúncio criado aqui e em
   qualquer outro da conta. Nível pausado na hora pelo criar é relido depois de
   pausar. A mesma chave pedida de novo (depois de uma falha de rede) não chama
   a Meta (ponto 4) e volta `in_review: false`: o cartão de criado oferece o
   Ativar, e o servidor recusa com a frase da análise se for o caso.
   A doc do Ad não diz se dá para ligar um anúncio durante a análise: **não
   confirmado**, por isso não oferecemos. Ela diz que, ao fim da análise, o
   anúncio volta ao status escolhido (aqui, PAUSED).
   [Enum do Ad](https://developers.facebook.com/docs/marketing-api/reference/adgroup/),
   [análise em até 24 horas, seção 3](https://transparency.meta.com/policies/ad-standards/)
10. **O orçamento traz `active_ads_count`**: quantos anúncios do grupo (ou da
    campanha, quando o dinheiro é dela) estão no ar agora. O "Ativar" só diz
    "passa a dividir o dinheiro com os outros" quando esse número é maior que
    zero. Com os outros pausados, o anúncio gasta sozinho e o texto mostra o
    valor por dia e o total.
11. **A falha ao ler o orçamento devolve erro, nunca `null` mudo.** A tela trata
    vazio como falha: diz "Não deu para ler o orçamento agora" e oferece
    "Tentar de novo". Sem orçamento lido, o "Ativar" não fica disponível.
12. **As opções de criar trazem só o que a chamada real já confirmou** para a
    conta (ver "Confirmar na chamada real"):

    ```json
    {
      "destinations": ["WHATSAPP", "WEBSITE"],
      "placements_by_destination": {
        "WHATSAPP": ["AUTO"],
        "WEBSITE": ["AUTO", "INSTAGRAM", "FACEBOOK"]
      }
    }
    ```

    A tela mostra só os destinos que vieram, na ordem dela (WhatsApp primeiro),
    e, na conferência, só os lugares do destino escolhido. "Automático" vale
    sempre; com um lugar só, não há "Trocar". Lugar que deixa de valer ao
    trocar o destino volta para "Automático". Post do Instagram com botão de
    WhatsApp usa os lugares de `WHATSAPP`; post sem botão, os três. O
    rascunho nasce com o primeiro destino que veio. Sem nenhum, o cartão
    "Anúncio novo" fica apagado, com o motivo (cena `?demo=sem-destino`).
13. **A gestão do anúncio traz `can_swap_creative`.** Com `true`, o "Trocar foto
    ou texto" troca o criativo no próprio anúncio. Com `false`, o mesmo diálogo
    vira "Trocar a foto (cria uma cópia)", com "Duplicar" como link: cria a
    cópia pausada (Fluxo 5) já com a mídia e o texto novos, e o anúncio
    original continua como está. A confirmação diz o valor e pede para pausar
    este quando ativar a cópia, para não gastar em dobro. O
    campo fica na gestão, e não nas opções de criar, porque é o detalhe do
    anúncio que mostra o botão, e ele não carrega as opções de criar.
14. **Publicar devolve o resultado por rede**: `{ instagram, facebook,
    failed: ["instagram"] }`. Nenhuma rede publicada é erro ("Nada foi
    publicado"). Uma só: a tela diz qual não deu e tenta de novo só nela. Se
    a nova tentativa falhar, a frase diz que o post continua na outra rede.

**Regra:** a gravação da Meta (vídeo do App Review) só mostra o que a chamada
real confirmou. No protótipo, `?demo=so-confirmado` mostra o caso mínimo, só com
o que a doc já garante: WhatsApp e site (o Messenger espera o item 9),
WhatsApp só em "Automático" e "Trocar a foto (cria uma cópia)" no lugar de
"Trocar foto ou texto". As outras cenas mostram tudo, como se a chamada real
tivesse confirmado.

## Fluxo 1: anúncio novo

Verificado na documentação oficial em 26/10/2026.

- **Destino, WhatsApp primeiro e marcado.** É decisão de produto: não há dado
  oficial da Meta sobre qual destino é o mais usado. A troca fica numa linha no
  topo da tela da foto ("Quem tocar vai para: WhatsApp · Trocar"), sem passo a
  mais.
  - **WhatsApp:** campanha `OUTCOME_ENGAGEMENT`; grupo com
    `destination_type: WHATSAPP`, `optimization_goal: CONVERSATIONS` e
    `promoted_object` com `page_id` (obrigatório) e `whatsapp_phone_number`;
    criativo com `call_to_action` `WHATSAPP_MESSAGE` e `app_destination:
    WHATSAPP`, e a mensagem pronta em `page_welcome_message`. Aceita foto,
    vídeo e carrossel.
    [Fonte](https://developers.facebook.com/documentation/ads-commerce/marketing-api/ad-creative/messaging-ads/click-to-whatsapp)
  - **Messenger:** `OUTCOME_ENGAGEMENT`, destino `MESSENGER`, otimização
    `CONVERSATIONS`, `promoted_object` com `page_id`; botão `MESSAGE_PAGE`.
    [Fonte](https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group/)
  - **Direct do Instagram:** destino `INSTAGRAM_DIRECT`, botão `MESSAGE_PAGE`
    com `app_destination: INSTAGRAM_DIRECT`.
    [Fonte](https://developers.facebook.com/documentation/ads-commerce/instagram/ads-api/guides/use-posts-as-ads)
    O objetivo e a otimização para ele sozinho **não estão confirmados** na doc.
    Entrou no protótipo por decisão de 26/10; **confirmar na chamada real antes
    da flag**. Sem conta do Instagram ligada à Página, a opção aparece apagada,
    com o motivo.
  - **Site:** `OUTCOME_TRAFFIC`, `LINK_CLICKS`, `link` e botão `LEARN_MORE`
    (padrão) ou `SHOP_NOW`.
    [Fonte do link e do botão](https://developers.facebook.com/documentation/ads-commerce/marketing-api/get-started/basic-ad-creation/create-an-ad-creative)
    A lista completa de botões do Tráfego **não está confirmada**: a tela oferece
    só os dois do exemplo oficial. A pessoa digita o endereço como conhece
    ("lojaexemplo.com.br"); a tela completa com `https://` na conferência e no
    envio. O servidor confere o endereço (https e domínio) de novo.
  - Sem número de WhatsApp, a tela para com "Conectar número" e oferece
    "Anunciar com outro destino" (o primeiro destino confirmado depois do
    WhatsApp; sem nenhum, só "Conectar número").
- **O que a pessoa vende:** campo obrigatório no topo ("bolo de pote a R$ 12").
  Ele monta o texto ("{oferta}. Chame no WhatsApp e faça seu pedido.", com o fim
  do destino escolhido) e o título ("{oferta}") até a pessoa mexer neles.
- **Carrossel:** de 2 a 10 cartões em `object_story_spec.link_data.child_attachments`;
  vídeo no cartão leva também `image_hash` ou `picture`.
  [Fonte](https://developers.facebook.com/documentation/ads-commerce/marketing-api/guides/videoads)
  Só com destino WhatsApp ou site. Com Messenger e Direct a doc **não
  confirma**; a tela apaga essas opções enquanto houver cartão extra, com o
  motivo. Todos os cartões levam o mesmo título e o mesmo botão. A mesma página
  diz que carrossel não roda nos Stories do Facebook: a prévia não promete
  lugar ("A Meta escolhe onde mostrar").
- **Foto e vídeo do celular:** a tela lê largura, altura e duração no navegador
  e tira a capa do vídeo. O servidor recebe o arquivo, sobe a foto em
  `POST /act_{id}/adimages` (devolve o `hash`) e o vídeo em
  `/act_{id}/advideos` com `file_url`: o vídeo fica no armazenamento da
  plataforma (S3) e a Meta o busca por um endereço assinado e com prazo. Assim
  o arquivo de até 1 GB não passa em partes pelo servidor. A capa do vídeo sobe
  como foto e vai em `image_hash`. Antes de criar, o servidor confere se a Meta
  terminou de processar o vídeo; se não, a tela pede para tentar de novo em um
  minuto, sem nada criado.
  [Fonte de imagem](https://developers.facebook.com/docs/marketing-api/reference/ad-image/),
  [fonte de vídeo](https://developers.facebook.com/docs/marketing-api/reference/ad-account/advideos/)
  Os limites da tela (foto JPG ou PNG de até 30 MB; vídeo MP4 ou MOV de até 1 GB
  e 1 minuto) são **nossos**. O servidor valida de novo.
- **Uma mídia para todos os lugares.** Mídia diferente por posição
  (`asset_customization_rules`) só está documentada para os objetivos antigos:
  fica fora.
  [Fonte](https://developers.facebook.com/documentation/ads-commerce/marketing-api/ad-creative/asset-feed-spec/asset-customization-rules)
  O `adapt_to_placement` só aparece em anúncio de catálogo: **não confirmado**.
  A prévia mostra a foto inteira no centro dos Stories e não promete ajuste.
  [Fonte](https://developers.facebook.com/docs/marketing-api/reference/ad-creative-features-spec/)

## Fluxo 2: impulsionar post

- **Post do Instagram:** criativo com `source_instagram_media_id` (e
  `instagram_user_id`) e botão `WHATSAPP_MESSAGE`, quando a conta tem número.
  A página do clique para WhatsApp aceita "existing Instagram content".
  [Fonte](https://developers.facebook.com/documentation/ads-commerce/instagram/ads-api/guides/use-posts-as-ads),
  [clique para WhatsApp](https://developers.facebook.com/documentation/ads-commerce/marketing-api/ad-creative/messaging-ads/click-to-whatsapp)
  Atenção: `effective_instagram_media_id` não é o nome antigo de
  `source_instagram_media_id`; o que saiu na v22 foi `instagram_story_id`.
  [Fonte](https://developers.facebook.com/documentation/ads-commerce/marketing-api/marketing-api-changelog/version22.0)
- **Pode impulsionar?** No Instagram, `boost_eligibility_info` do post
  ([fonte](https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/));
  a doc **não lista os subcampos**. O servidor devolve `{ eligible, reason }` e
  repassa o motivo como a Meta escrever. Post com música protegida ou filtro
  não pode ser impulsionado (guia de posts como anúncio, acima). Na Página,
  `is_eligible_for_promotion`, sem motivo; a tela diz "A Meta não deixa
  impulsionar este post".
  [Fonte](https://developers.facebook.com/docs/graph-api/reference/post/)
  O post que não pode aparece apagado, com o motivo, e não é escolhido.
- **Post da Página do Facebook:** criativo com `object_story_id`, leva ao post,
  sem WhatsApp. Botão de WhatsApp em post da Página **não está confirmado**. Roda
  no Facebook (`publisher_platforms: ["facebook"]`); a conferência não oferece
  "Trocar" no onde aparece.
  [Fonte](https://developers.facebook.com/docs/marketing-api/reference/ad-creative/)
- A aba Instagram abre primeiro quando há post de lá que pode ser impulsionado,
  porque leva o WhatsApp.

## Rastreio do clique (`url_tags`, #2345)

O anúncio novo com destino site sai com `url_tags` igual ao texto da tela
Conexão › Destino, de uma fonte só (`Crm::MetaAds::UrlTags::TEXT`). O
`url_tags` vale para os links clicados em anúncio de post da Página; o anúncio
novo é um post da Página não publicado, criado pelo `object_story_spec`. A doc
não lista `url_tags` entre os campos que se atualizam no criativo (`name`,
`status`, `adlabels`, `account_id`); por isso vai na criação. Que a Meta aceita
o campo no anúncio de site: **não confirmado** em chamada real. Anúncio com
botão de WhatsApp e post impulsionado não levam ao site: o campo não vai
(decisão de 29/10, para não arriscar recusa onde ele não serve).
[Fonte](https://developers.facebook.com/docs/marketing-api/reference/ad-creative/)

## Fluxo 3: criar post

- **Página do Facebook:** `POST /{page-id}/photos`, `/videos` ou `/feed`, com
  token de Página. A pessoa precisa das tarefas `CREATE_CONTENT`, `MANAGE` e
  `MODERATE` na Página.
  [Fonte](https://developers.facebook.com/docs/pages-api/posts/)
- **Instagram:** `POST /{ig-user-id}/media` (cria o contêiner) e
  `/media_publish`. Só JPEG: o servidor converte PNG. A imagem é buscada por
  URL pública: o servidor sobe a mídia num endereço temporário. O contêiner
  expira em 24 horas; conferir `status_code` (`FINISHED`) antes de publicar.
  Vídeo vai como Reels (de 3 s a 15 min, até 300 MB; a tela continua limitada a
  1 minuto).
  [Fonte](https://developers.facebook.com/docs/instagram-platform/content-publishing/),
  [contêiner](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/)
- **Limite por dia:** a doc diz 100 posts em 24 horas numa parte e 50 em outra
  (**conflito**). O servidor lê `GET /{ig-user-id}/content_publishing_limit` e a
  tela apaga o Instagram, com o motivo, quando não sobra post.
- **Publicar e impulsionar:** publica, guarda o id que a Meta devolver e segue
  para quem vê, com a mesma mídia e a mesma legenda. Com Instagram publicado, o
  impulsionamento usa o post de lá (com WhatsApp); só com Facebook, o da Página.
- **Falha parcial:** se uma rede publicar e a outra não, a tela diz qual foi
  ("Publicado no Facebook. No Instagram não deu: tente de novo.") e o botão
  tenta de novo só nela (ponto 14). Cena `?demo=publicar-parcial`.
- Fica fora: carrossel orgânico, Stories orgânicos, agendar e editar post.

## Fluxo 4: onde aparece

- **Automático (recomendado):** `publisher_platforms: ["facebook", "instagram"]`
  sem posição; a Meta escolhe feed, Stories ou Reels. Omitir o campo inteiro
  seria o Advantage+ de verdade, mas incluiria Messenger, Audience Network e
  Threads, e a tela diria "Instagram e Facebook" sem ser verdade.
  [Posições](https://developers.facebook.com/docs/marketing-api/audiences/reference/placement-targeting/),
  [Advantage+ é o padrão](https://developers.facebook.com/documentation/ads-commerce/marketing-api/advantage-campaigns)
- **Só Instagram / Só Facebook:** uma plataforma em `publisher_platforms`. Com
  destino WhatsApp, a doc do clique para WhatsApp **não diz se dá**. Entrou por
  decisão de 26/10; **confirmar na chamada real antes da flag**. Até lá o
  servidor não devolve essas opções para WhatsApp (ponto 12).
- A tela não promete posição: as notas da prévia dizem "se a Meta mostrar lá".

## Fluxo 5: cuidar do que existe

- **Pausar, ativar, orçamento e datas:** já existiam (#2161 e acima).
- **Duplicar:** `POST /{campaign_id}/copies` com `deep_copy: true` e
  `status_option: PAUSED`. A cópia tem orçamento próprio, igual ao do original;
  copiar só o anúncio dividiria o dinheiro do grupo. A confirmação diz o valor
  por extenso, e o "Ativar" da cópia fica ali mesmo.
  [Fonte](https://developers.facebook.com/docs/marketing-api/reference/ad-campaign-group/copies/),
  [cópia de anúncio (PAUSED é o padrão)](https://developers.facebook.com/docs/marketing-api/reference/adgroup/copies/)
  O servidor relê o `effective_status` da cópia, como no criar (ponto 2).
- **Trocar foto ou texto:** o criativo só aceita mudar `name` e `status`, então
  o servidor cria outro criativo e troca no anúncio (`POST /{ad_id}` com
  `creative`). O exemplo oficial desse `POST` **não está confirmado**: confirmar
  na chamada real. Se não der, a saída é "Trocar a foto (cria uma cópia)"
  (`can_swap_creative: false`, ponto 13). Mudar o criativo leva a nova análise
  da Meta, e a tela avisa antes. Depois da troca, o detalhe já mostra a foto
  nova e a situação "Em análise da Meta", com "Volta ao ar sozinho quando a
  Meta aprovar." (`effective_status` `PENDING_REVIEW` ou `IN_PROCESS`).
  [Criativo](https://developers.facebook.com/docs/marketing-api/reference/ad-creative/),
  [anúncio](https://developers.facebook.com/docs/marketing-api/reference/adgroup/),
  [nova análise](https://www.facebook.com/business/ads/review-policy-guidelines)

## Permissões por fluxo

Referência: [permissões da Meta](https://developers.facebook.com/documentation/development/permissions).

| Fluxo | Permissões |
|---|---|
| Anúncio novo, todos os destinos, e onde aparece | `ads_management`, `pages_manage_ads`, `pages_read_engagement`, `pages_show_list`; `ads_read` para ler. Token de Página com a tarefa ADVERTISE. |
| Impulsionar post do Facebook | As do anúncio novo. `pages_read_engagement` lista os posts. |
| Impulsionar post do Instagram | As do anúncio novo e `instagram_basic` (listar posts e ler `boost_eligibility_info`). |
| Criar post no Facebook | `pages_manage_posts`, `pages_read_engagement` e `pages_manage_engagement` (já no pedido pelo #2197). Vídeo: ver item 10 de "Confirmar na chamada real". |
| Criar post no Instagram | `instagram_basic`, `instagram_content_publish`, `pages_read_engagement`; `ads_management` e `ads_read` quando a pessoa tem papel no Business Manager da Página. |
| Publicar e impulsionar | As do post e as do impulsionar. |
| Cuidar (pausar, orçamento, duplicar, trocar) | `ads_management`, `ads_read`. |
| Respostas do Direct na caixa de entrada | `instagram_manage_messages` (o #2079 já usa). |

Decisão de 26/10 (D3), revista em 27/10: entram no pedido de 14/11
`instagram_basic`, `pages_manage_posts` e `instagram_content_publish`.
`pages_read_user_engagement` saiu: não existe no painel do app, e ler os
comentários da Página já é coberto por `pages_read_user_content` (#2197).
`publish_video` fica a confirmar (item 10 abaixo): o painel a descreve como
vídeo ao vivo, e ela só entra no pedido se a chamada real provar que precisa.

## Confirmar na chamada real antes de ligar a flag

Na conta de teste, com os testadores do app:

1. Objetivo e otimização do anúncio com destino Direct do Instagram sozinho.
2. "Só Instagram" e "Só Facebook" com destino WhatsApp.
3. `POST /{ad_id}` com `creative` novo, sem recriar o anúncio.
4. Subcampos de `boost_eligibility_info`.
5. Limite de posts do Instagram por dia (100 ou 50).
6. Carrossel com destino Messenger ou Direct (hoje a tela não oferece).
7. Botão de WhatsApp em post da Página (hoje a tela não oferece).
8. Posições aceitas pelo clique para WhatsApp e `adapt_to_placement`.
9. Destino Messenger com objetivo de mensagens.
10. Publicar vídeo comum no post da Página: provar se precisa de `publish_video`
    ou se `pages_manage_posts` basta.
11. Tirar a data de fim de um grupo com orçamento por dia: o servidor manda
    `end_time: 0`.
12. Formato da mensagem pronta do WhatsApp em `page_welcome_message`.
13. Formato do número em `promoted_object.whatsapp_phone_number` (o servidor
    manda em E.164, como está na caixa).
14. Categoria especial: `special_ad_categories: ["FINANCIAL_PRODUCTS_SERVICES"]`
    com `special_ad_category_country: ["BR"]`.
15. Campanha com orçamento no grupo: `is_adset_budget_sharing_enabled: false`.
16. A Meta busca o vídeo pelo endereço assinado do S3 (`file_url`).

Os itens 1, 2, 3 e 9 já viram dado: o que não passar fica fora de `destinations`,
`placements_by_destination` ou `can_swap_creative` (pontos 12 e 13), e a tela
não oferece. Nos outros, se algum não passar, a frase ou a opção da tela muda
antes da flag.

## Servidor do PR 1

Flag `meta_ads_criar`. Sem ela, 404 e nenhuma chamada à Meta. Rotas em
`/api/v1/accounts/:id/crm/meta_ads_connection`:

| Rota | O que faz | Quem |
|---|---|---|
| `GET create_options` | Opções de criar (pontos 8 e 12), com moeda e hoje no fuso da conta de anúncios | `meta_ads_manage` |
| `POST media` | Foto ou vídeo do celular → `hash` ou `video_id` | `meta_ads_manage` |
| `POST ads` | Anúncio novo, sempre pausado | `meta_ads_manage` |
| `GET ads/:ad_id/budget` | Orçamento e datas (pontos 10 e 11) | `meta_ads_view` |
| `PATCH ads/:ad_id/budget` | Muda valor e fim | `meta_ads_manage` |
| `GET paused_ads` | Criados aqui que seguem pausados (ponto 9) | `meta_ads_view` |
| `POST ads/:ad_id/status` | Já existia (#2161); com a flag, ao ativar devolve `held_by` (ponto 6) | `meta_ads_manage` |

- Criar e mudar orçamento ficam na Auditoria da conta (`meta_ads_ad_created`,
  `meta_ads_budget_change`, `meta_ads_create_repaused`), com quem fez e sem o
  token.
- A tabela `crm_meta_ads_created_objects` guarda cada tentativa de criar pela
  chave de idempotência, os ids criados na Meta (para desfazer e para a lista
  de pausados) e o orçamento de quando criou. A linha nasce `creating` antes da
  primeira chamada, e o nome da campanha leva a marca da tentativa
  (`Nome [1a2b3c4d]`, os 8 primeiros caracteres da chave). Se a resposta da
  campanha se perde, o desfazer procura a campanha na Meta por essa marca antes
  de dizer "Nada foi criado"; sem conseguir procurar, a resposta é
  `nothing_created: false`.
- Moeda: o criar lê a moeda da conta de anúncios na Meta e só cria em real
  (`currency_not_supported`). Sem moeda confirmada, as opções dão erro e a tela
  não mostra valor. Dinheiro sem float: mais de 2 casas é recusa, e a Meta
  recebe centavos inteiros.
- "Hoje" das datas é o do fuso da conta de anúncios: o servidor manda `today`
  nas opções e no orçamento. Valores saem como texto decimal (`"20.57"`), nunca
  float.
- Campanha sem resposta (tempo esgotado): a busca pela marca vazia não é "nada
  criado". A tentativa fica `unconfirmed`, e a tela pede para conferir no
  Gerenciador de Anúncios. A mesma chave procura de novo antes de criar: se
  achar, desfaz e refaz; vazia de novo, continua `unconfirmed`, por mais tempo
  que passe. Tentativa `creating` parada há mais de 10 minutos (o processo
  caiu) segue a mesma regra: nunca cria sem saber. Com a campanha achada,
  desfaz e refaz; com a busca vazia, fica `unconfirmed` até a pessoa recriar.
  Só a pessoa libera, no botão "Não está no Gerenciador, criar de
  novo" (quem tem `meta_ads_manage`), só para uma tentativa `unconfirmed` desta
  chave, e isso fica na Auditoria (`meta_ads_create_recreated`, com o nome e a
  marca da tentativa antiga). Depois que ela libera, se a campanha antiga
  aparecer mais tarde, as duas existem: a marca na Auditoria é o jeito de achar
  a antiga no Gerenciador. A tela recria com o pedido guardado da tentativa e
  não deixa editar enquanto ela está `unconfirmed`.
- O mesmo pedido com outra chave (outra aba, outro aparelho, a tela reaberta)
  não cria a segunda campanha. Quem deduplica é o servidor: cada tentativa
  guarda o SHA-256 do pedido validado (`request_digest`, sem a chave; os
  estados em ordem, os cartões do carrossel na ordem deles), e um índice único
  parcial em (conta, conta de anúncios, digest) para `creating`, `unconfirmed`
  e `rollback_failed` deixa só uma tentativa que ainda pode ter campanha viva
  por pedido, mesmo com dois pedidos no mesmo instante. Quem bate nela recebe
  a chave dela (`idempotency_key` na resposta) e a tela segue com essa
  tentativa: `in_progress` se ela está criando, `unconfirmed` se não foi
  confirmada (ou parou de criar), `meta_unavailable` sem "nada criado" se nem
  desfazer deu. Sem a pessoa liberar, atraso da Meta não vira campanha
  duplicada. Tentativa já `created` fica fora do índice de propósito: pedir o
  mesmo anúncio de novo depois de criado é uma intenção legítima, e o segundo
  também nasce pausado.
- Campanha da tentativa que já não existe na Meta (apagada pelo Gerenciador)
  conta como desfeita: a chave não fica presa. "Não existe" é só o erro 100
  com subcódigo 33, ou a releitura dizer `DELETED`/`ARCHIVED`; o 100 puro é
  parâmetro inválido e não conta.
- Nenhuma trava de banco fica presa durante uma chamada à Meta. Retomar uma
  tentativa começa por um UPDATE condicional que a leva para `creating`; só
  quem ganha desfaz o que ficou e cria, e, se desfazer falhar, a linha volta
  para a situação de antes. A chave de idempotência da tela fica só na
  memória da página (nada do pedido vai para o armazenamento do navegador): um
  UUID, com recurso para navegador sem `crypto.randomUUID`.
- O que a chamada real confirmou fica em `Crm::MetaAds::Creation::Confirmed`.
  Hoje é o caso mínimo do `?demo=so-confirmado`: WhatsApp só em Automático e
  site nos três lugares. Cada item confirmado entra ali num PR.
- Os itens de "Confirmar na chamada real" passam por um diagnóstico escrito
  como código revisado (PR à parte). Ele cria tudo **pausado** na conta de
  teste, relê, apaga e grava o resultado na Auditoria. Rodar em produção é
  escrita na conta de anúncios do cliente: só com OK explícito do Rodrigo,
  pedido pela sessão Meta aprovar e reconfirmado pela Orquestração. Nada é
  ativado e nenhum centavo é gasto.

## Servidor do PR 2

Impulsionar post (#2339), na mesma flag `meta_ads_criar`. Pedido do Rodrigo em
28/10: "ja coloca no ar agora".

- `GET meta_ads_connection/boost_posts?page_id=` (`meta_ads_manage`): os posts
  da Página escolhida, só uma que o token alcança, e os do Instagram ligado a
  ela. A tela lê quando a pessoa chega no passo do post, então cada Página tem
  os seus. Ficam 25 de cada lado, os mais recentes. Falha ao ler devolve
  `posts_error` e a tela diz que não conseguiu ler, nunca "sem posts".
- Página: `published_posts` com o token da Página. Pode impulsionar quando
  `is_eligible_for_promotion` é true. Foto de perfil ou de capa (anexo
  `profile_media` ou `cover_photo`) sai apagada com o motivo
  `profile_or_cover`, mesmo que a Meta diga que pode. Ela recusa no criar:
  erro #1487472 no post 122099468234344741, em 28/10.
- Instagram: `/{ig-user}/media` com o token do Facebook. Pode impulsionar só
  com `boost_eligibility_info.eligible_to_boost` true. A doc da Meta não lista
  os subcampos, e o nome vem da biblioteca restfb. Sem o campo, conta como
  "não pode".
- Criar (`POST ads` com `kind: post`): o mesmo caminho do anúncio novo, com a
  chave, o gêmeo, os três níveis `PAUSED`, a releitura e o desfazer. O
  rascunho é `Crm::MetaAds::Creation::PostDraft`. O post é relido na Meta antes
  de criar qualquer coisa. Um post que não é da Página ou do Instagram dela dá
  `invalid_post`; um que não pode ser impulsionado dá `post_not_eligible`.
- Post do Instagram leva `object_id` (a Página), `instagram_user_id` e
  `source_instagram_media_id`. Com número do WhatsApp na conta, o número é
  obrigatório e o anúncio leva o botão `WHATSAPP_MESSAGE`, com o grupo de
  conversas no WhatsApp, em Automático. Sem número, é engajamento no post
  (`ON_POST`, `POST_ENGAGEMENT`).
- Post da Página leva `object_story_id`, só no Facebook, com engajamento no post
  e sem botão de WhatsApp (item 7 continua a confirmar).
- Na chamada real (conta 18, flag só nela), confirmar:
  - os subcampos de `boost_eligibility_info` e o `children{...}` do carrossel,
    que vão na mesma leitura de `/media`: se a Meta recusar um dos dois, a
    lista do Instagram inteira falha;
  - se `ON_POST` com `OUTCOME_ENGAGEMENT` passa sem `promoted_object`;
  - o filtro de perfil e capa num post real.

## Permissões que a Meta precisa ver no vídeo

Cada permissão do pedido aparece em uso no vídeo do App Review, só com o que a
chamada real confirmou (regra do ponto 12): criar anúncio (com cada destino
confirmado), impulsionar post do Instagram e do Facebook, criar post nas
duas redes (foto e vídeo), duplicar e trocar. A cena no Gerenciador de Anúncios
(anúncio pausado aparecendo lá) só existe com chamada real, na implementação.

## Fora desta entrega

- Público do CRM (listas personalizadas).
- Formulário de leads (é o #2195), slideshow e catálogo.
- Messenger, Audience Network e Threads como lugar de exibição.
