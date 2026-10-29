// Seus posts (#2302, F1 #2304): o que GET seus_posts manda (SeusPosts::Leitura, em inglês, como a API) no formato
// que a tela usa. Número que a Meta não mandou continua nulo, nunca 0.

// A Meta leva até 2 dias para mandar os números de um post.
const DIAS_PARA_NUMEROS = 2;
const UM_DIA = 24 * 60 * 60 * 1000;

const ouNulo = valor => (valor === undefined ? null : valor);

// Link de post ou perfil vem da Meta; só o https vira link na tela.
const linkSeguro = endereco => {
  try {
    return new URL(endereco).protocol === 'https:' ? endereco : null;
  } catch {
    return null;
  }
};

// O que pode incluir anúncio, pelo que o servidor sabe separar (Crm::MetaAds::Organico): no Instagram, vezes,
// pessoas e interações saem sem o anúncio; na Página, só as vezes. Seguidores novos podem ter vindo de anúncio nas
// duas.
const LADOS = {
  instagram: { pessoas: false, interacoes: false, seguidores: true },
  facebook: { pessoas: true, interacoes: true, seguidores: true },
};

const resumoDe = (perfil, rede) => {
  const antes = perfil.previous || {};
  const mensagens = perfil.messages || {};
  return {
    apareceu: ouNulo(perfil.views),
    apareceuAntes: ouNulo(antes.views),
    pessoas: ouNulo(perfil.reach),
    pessoasAntes: ouNulo(antes.reach),
    // No Instagram a Meta não junta quem viu um post e um story: o número é o teto ("até N").
    pessoasAte: rede === 'instagram',
    interacoes: ouNulo(perfil.interactions),
    interacoesAntes: ouNulo(antes.interactions),
    seguidores: ouNulo(perfil.followers),
    seguidoresNovos: ouNulo(perfil.new_followers),
    mensagens: ouNulo(mensagens.count),
    mensagensAntes: ouNulo(mensagens.previous),
    comparado: Boolean(perfil.previous),
    primeiroPeriodo: Boolean(perfil.first_period),
    lados: LADOS[rede],
  };
};

export const postParaTela = (post, rede, agora = Date.now()) => {
  const novoNaMeta =
    agora - new Date(post.created_time).getTime() < DIAS_PARA_NUMEROS * UM_DIA;
  const vezes = ouNulo(post.views);
  return {
    id: post.id,
    rede,
    legenda: post.text || '',
    tipo: post.type || null,
    imagem: post.image_url || null,
    link: linkSeguro(post.permalink),
    publicadoEm: post.created_time,
    apareceu: vezes,
    pessoas: ouNulo(post.reach),
    curtidas: ouNulo(post.likes),
    comentarios: ouNulo(post.comments),
    compartilharam: ouNulo(post.shares),
    salvaram: ouNulo(post.saved),
    cliques: ouNulo(post.clicks),
    // F2 (#2305): os comentários que esperam a conta; nulo quando não se sabe (sem permissão, Meta fora, flag
    // desligada), nunca 0. `esperandoMais`: o post tem mais comentários do que os lidos ("50 ou mais").
    esperando: ouNulo(post.waiting),
    esperandoMais: post.waiting_more === true,
    // boosted nil é "não se sabe" (Instagram): só o true vira "Teve anúncio".
    impulsionado: post.boosted === true,
    // Curtidas e comentários incluem o anúncio quando houve: true ou nil (não se sabe) acendem "pode incluir anúncio";
    // só o false (Página com o recorte em 0) garante que não.
    podeTerAnuncio: post.boosted !== false,
    // Novo: a Meta ainda não mandou as vezes. Depois de 2 dias sem elas, o post fica só com curtidas e comentários.
    novo: vezes === null && novoNaMeta,
    // Até 2 dias, um zero ainda não se compara com o normal (os números da Meta podem atrasar).
    recente: novoNaMeta,
    semInsights: vezes === null && !novoNaMeta,
  };
};

// O perfil escolhido. `nome` vem da lista de perfis (guardado no servidor) ou do próprio perfil quando ele foi lido.
export const perfilParaTela = (perfil, nomeGuardado, agora = Date.now()) => {
  const rede = perfil.network;
  const nomeLido = perfil.username ? `@${perfil.username}` : perfil.name;
  const base = {
    id: perfil.id,
    rede,
    nome: nomeGuardado || nomeLido || null,
    status: perfil.status,
    inboxId: perfil.inbox_id ?? null,
    // A Meta não respondeu agora: estes são os números da última leitura boa.
    antigo: perfil.stale === true,
  };
  if (perfil.status !== 'ok') return base;

  const normal = perfil.normal || {};
  return {
    ...base,
    link: linkSeguro(perfil.link),
    resumo: resumoDe(perfil, rede),
    media: { apareceu: ouNulo(normal.views) },
    // 'ok', 'unavailable' (a Meta falhou só nos posts) ou 'needs_permission' (a leitura dos posts foi recusada): nos
    // dois últimos os números do perfil ficam, e só a grade muda.
    postsStatus: perfil.posts_status,
    // A Meta não respondeu nos posts: a grade é a da última leitura boa.
    postsAntigos: perfil.posts_stale === true,
    // A lista parou no teto de posts lidos: em 90 dias, os mais velhos podem faltar.
    postsCortados: perfil.posts_truncated === true,
    posts: (perfil.posts || []).map(post => postParaTela(post, rede, agora)),
    // F2: 'ok', 'needs_permission' ou 'unavailable'; null com a flag desligada (a lista é a do F1).
    esperandoStatus: perfil.waiting_status || null,
  };
};

// Um comentário do post (F2, #2305), da casca comum dos comentários (Crm::MetaAds::InstagramCommentRows e
// FacebookCommentRows). O estado diz o que aconteceu com ele: escondido, recebeu no privado, respondido pela conta,
// da própria conta ou esperando você. A ordem é a do servidor: a mesma régua do "esperando você" da lista.
const autorDe = autor =>
  autor?.username ? `@${autor.username}` : autor?.name || null;

const estadoDe = comentario => {
  if (comentario.author?.is_page) return 'meu';
  if (comentario.hidden) return 'escondido';
  if (comentario.private_reply) return 'privado';
  if ((comentario.replies || []).some(resposta => resposta.author?.is_page))
    return 'respondido';
  return 'esperando';
};

export const comentarioParaTela = comentario => ({
  id: comentario.id,
  autor: autorDe(comentario.author),
  texto: comentario.text || '',
  // Comentário só com foto ou figurinha: a tela diz o tipo, em vez de uma linha vazia.
  anexo: comentario.attachment || null,
  quando: comentario.created_time,
  estado: estadoDe(comentario),
  respostas: (comentario.replies || []).map(resposta => ({
    id: resposta.id,
    autor: autorDe(resposta.author),
    texto: resposta.text || '',
    daConta: resposta.author?.is_page === true,
  })),
  pode: {
    responder: comentario.can_reply === true,
    esconder: comentario.can_hide === true,
    apagar: comentario.can_delete === true,
    privado: comentario.can_reply_private === true,
  },
  privadoExpirado: comentario.private_reply_expired === true,
  privado: comentario.private_reply
    ? {
        enviadoEm: comentario.private_reply.sent_at,
        confirmado: comentario.private_reply.confirmed === true,
        conversa: comentario.private_reply.conversation_path || null,
        podeLiberar: comentario.private_reply.can_release === true,
      }
    : null,
});
