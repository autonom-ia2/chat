# Instagram pelo login único (#2406)

Quem tem uma Página do Facebook com o Instagram ligado passa a ligar o Instagram com o mesmo "Entrar com o Facebook"
dos Anúncios e do Messenger (login único, #2338). Quem só tem o Instagram continua com o login do Instagram, que não
sai. Tudo fica atrás da flag `instagram_login_unico`. Ela depende de `anuncios_login_unico` e nasce desligada.

Decisão do Rodrigo (09/11): aceitar o login único para o Instagram e testar numa conta dele antes do vídeo do App
Review.

## 1. Escopo

### Entra

- No pronto do passo a passo de conectar os Anúncios, o botão "Ligar o Instagram" liga o Instagram da Página
  escolhida ali mesmo, sem abrir o login do Instagram. Isso vale quando a flag está ligada e a Página tem Instagram.
- O resultado é uma caixa do Instagram comum (`Channel::Instagram`), separada da caixa da Página. Ela tem o token da
  Página e fala com `graph.facebook.com`. O canal guarda de que login veio (`login`: `instagram` ou `facebook`) e o id
  da Página (`page_id`). A migration `20261108900000` soma só essas duas colunas.
- Tudo o que a caixa do Instagram faz hoje usa o host e o nó do canal:
  - Direct: receber e responder, digitando, reação, edição, leitura e a resposta citando o story;
  - comentários: ler, responder, ocultar, apagar e responder no privado;
  - Seus posts: perfil, posts, números e comentários embutidos;
  - os números orgânicos dos Anúncios.
  - No login do Facebook, o nó do Instagram é o id dele (o `me` seria a Página). O Direct sai por `/{page_id}/messages`,
    como manda a doc da Messenger Platform para o Instagram.
- O token da Página não expira com o login de empresa. Por isso a caixa do login do Facebook não entra no job que
  renova token do Instagram.
- A inscrição no webhook é a da Página (`subscribed_apps`, com os campos do Messenger), pelo
  `Crm::MetaAds::PageSubscription`. O webhook do Instagram já entrega esses eventos ao mesmo controller (`object:
  instagram`), e a assinatura confere com o `FB_APP_SECRET`.

- Na conta que também tem a caixa da Página com esse Instagram ligado, o Direct e os comentários do Instagram passam a
  ir para a caixa do Instagram, e não mais para a caixa da Página. É a mesma regra de hoje quando a conta tem a caixa do
  login do Instagram (`Instagram::ConnectedChannels`: o canal do Instagram primeiro, a Página depois). O Messenger da
  Página não muda.
- Apagar a caixa da Página não tira a inscrição da Página enquanto uma caixa do Instagram do login único a usa.

### Fica de fora

- O login do Instagram continua igual e não pode ser desligado. Quem só tem Instagram só liga por ele.
- Nenhuma caixa existente troca de login sozinha. Veja "Migração das caixas".
- Publicar no Instagram pelo login do Facebook (`instagram_content_publish`) fica para outra Issue.

## 2. Permissões novas na configuração do login

A configuração `META_ADS_LOGIN_CONFIGURATION_ID` (1533640672115651) precisa pedir também:

| Permissão | Para quê | Sem ela |
|---|---|---|
| `instagram_basic` | ler o perfil e os posts do Instagram da Página | o botão responde `missing_permissions` |
| `instagram_manage_messages` | Direct: receber e responder | o botão responde `missing_permissions` |
| `instagram_manage_comments` | comentários: ler, responder, ocultar e apagar | a caixa liga, mas os comentários do Instagram não leem |
| `instagram_manage_insights` | números de Seus posts e dos Anúncios | a caixa liga, mas os números do Instagram não leem |
| `pages_manage_metadata` | inscrever a Página no webhook | já está na configuração por causa do Messenger |
| `pages_read_engagement`, `pages_show_list` | ler o perfil de quem manda o Direct (nome, foto, @), pela doc do perfil do Instagram na Messenger Platform | o contato chega como "Unknown (IG: …)" |

A doc da Meta pede ainda que o token da Página seja de alguém com a tarefa de moderar (`MODERATE`) e de mandar
mensagem (`MESSAGE`) na Página. O Direct não pede `pages_messaging`: essa é a do Messenger.

A troca da configuração é feita no painel da Meta, pelo Rodrigo. O código não muda essa lista.

## 3. Impacto no App Review

- O envio de 14/11 usa as permissões do login do Instagram (`instagram_business_basic`,
  `instagram_business_manage_messages`, `instagram_business_manage_comments`,
  `instagram_business_manage_insights`). Ele não muda, porque o login do Instagram continua.
- **Precisa de um App Review novo** para `instagram_basic`, `instagram_manage_messages`, `instagram_manage_comments`
  e `instagram_manage_insights` no app do login de empresa (`WHATSAPP_APP_ID`). São outra família de permissões e
  não herdam a aprovação das `instagram_business_*`. Cada uma pede o seu vídeo.
  - `instagram_manage_messages` também pede o recurso "Instagram Messaging" no app e o app publicado, sem o qual o
    webhook não chega.
- Até a aprovação, só funciona com quem tem função no app (Standard Access). É o caso da conta de teste do Rodrigo.

## 4. Migração das caixas

- **Caixa nova:** nasce no login do Facebook quando a pessoa toca em "Ligar o Instagram" com a flag ligada.
- **Caixa que já existe na conta, do login do Instagram, com o mesmo Instagram:** o toque troca essa caixa para o
  login do Facebook. A caixa, as conversas e os contatos continuam os mesmos, e o token passa a ser o da Página. Essa
  troca pede `integration_manage`, como reautorizar.
- **Volta, caixa por caixa:** entrar de novo pelo login do Instagram naquela caixa ("Reautorizar" ou ligar o
  Instagram em Caixas de entrada). O callback do Instagram grava `login: instagram` e limpa o `page_id`.
- **Em massa:** não há. Depois do App Review, a troca em massa é outra Issue, com o OK do Rodrigo.
- **Mesmo Instagram em duas contas:** cada conta tem a sua caixa (#2781), e cada uma escolhe o login.

## 5. Rollback

- Desligar a flag `instagram_login_unico` na conta. O botão volta a levar ao login do Instagram. As caixas já
  trocadas continuam no login do Facebook até a pessoa reautorizar pelo login do Instagram.
- Migration: `bundle exec rails db:migrate:down VERSION=20261108900000` apaga as duas colunas. Antes, as caixas do
  login do Facebook precisam voltar ao login do Instagram, ou ser desligadas. Sem isso, elas ficariam com o token da
  Página falando com `graph.instagram.com`.

## 6. Riscos abertos

- Reação e leitura (`message_reactions`, `messaging_seen`) dependem dos campos do Instagram marcados no painel do app
  do login de empresa (Webhooks > Instagram). A Página se inscreve com os campos do Messenger. Se esses campos não
  estiverem marcados no app, o Direct chega, mas a reação e o "visto" não.
- As chamadas vão sem `appsecret_proof`, como as outras do login de empresa (Anúncios, token da Página). Se o app
  passar a exigir a chave secreta, todas param juntas.
- O formato das respostas da Graph pelo `graph.facebook.com` foi lido na documentação, não numa chamada real. O teste
  do Rodrigo é a primeira chamada real.
- Os nomes das métricas de insights do Instagram pelo login do Facebook seguem a mesma doc. Se a Meta recusar alguma,
  os números do Instagram ficam vazios, como hoje quando falta a permissão.
- O id de quem manda o Direct (IGSID) é o mesmo nos dois logins, pela doc. Se não for, a caixa trocada abriria um
  contato novo para quem já conversava.
