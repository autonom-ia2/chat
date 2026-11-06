// Anúncios da Meta (#2198 PR 3, #2653), criar post: as regras da tela que não dependem de componente.

export const REDES = ['instagram', 'facebook'];

// Onde o post aparece, para a prévia e a confirmação: as duas redes (AUTO) ou uma só.
export const lugarDoPost = networks =>
  networks.length === 1 ? networks[0].toUpperCase() : 'AUTO';

// Por que cada rede não dá: { instagram: 'NO_PERMISSION' | 'NO_INSTAGRAM' | 'LIMIT', facebook: 'NO_PERMISSION' }. Só
// as que não dão. `publish`: as permissões do token ({ facebook, instagram }). `instagram`: o da Página escolhida, com
// `publish_left` (null quando a Meta não disse: a tela não apaga por isso).
export const motivosDasRedes = (publish, instagram) => {
  const motivos = {};
  if (!publish?.facebook) motivos.facebook = 'NO_PERMISSION';
  if (!publish?.instagram) motivos.instagram = 'NO_PERMISSION';
  else if (!instagram) motivos.instagram = 'NO_INSTAGRAM';
  else if (instagram.publish_left === 0) motivos.instagram = 'LIMIT';
  return motivos;
};

// As redes que já vêm marcadas: todas as que dão.
export const redesQueDao = motivos => REDES.filter(rede => !motivos[rede]);

// O que falta para conferir, na ordem dos campos da tela; '' quando nada falta.
export const faltaNoPost = (post, motivos) => {
  if (!post.page_id) return 'NEED_PAGE';
  if (!post.networks.some(rede => !motivos[rede])) return 'NEED_NETWORK';
  if (post.uploading) return 'UPLOADING';
  if (!post.media?.signed_id) return 'NEED_MEDIA';
  return '';
};

// O post que o "Impulsionar este post" leva: o do Instagram primeiro (é ele que pode levar o botão do WhatsApp),
// senão o da Página. Vídeo da Página não pode (a Meta devolve só o vídeo): `null` quando nenhum pode.
export const alvoDoImpulsionar = published => {
  const rede = REDES.find(item => published?.[item]?.boostable);
  return rede ? { post_source: rede, post_id: published[rede].id } : null;
};

// Junta o que a nova tentativa numa rede publicou ao que já tinha publicado.
export const juntarPublicado = (antes, depois) => ({
  ...antes,
  ...Object.fromEntries(
    REDES.filter(rede => depois[rede]).map(rede => [rede, depois[rede]])
  ),
  failed: depois.failed,
  errors: depois.errors,
});

// Recusas que a tela sabe explicar; outra vira a frase geral. `unconfirmed` (o servidor não sabe se a Meta publicou) e
// `idempotency_conflict` (a mesma tentativa com outro conteúdo, depois de um "não sei") viram a mesma frase: confira
// na rede antes de publicar de novo.
const ERROS_CONHECIDOS = {
  processing: 'PROCESSING',
  cannot_publish: 'CANNOT_PUBLISH',
  in_progress: 'IN_PROGRESS',
  unconfirmed: 'UNCONFIRMED',
  idempotency_conflict: 'UNCONFIRMED',
};
const HTTP_CONFLICT = 409;

// O código da recusa para a frase da tela: um dos de ERROS_CONHECIDOS, 'NETWORK' ou 'UNKNOWN'.
export const erroDoPublicar = error => {
  const response = error?.response;
  if (!response) return 'NETWORK';
  if (response.status === HTTP_CONFLICT) return 'IN_PROGRESS';
  return ERROS_CONHECIDOS[response.data?.error] || 'UNKNOWN';
};

// Sem resposta, ou o servidor não sabe: a Meta pode ter publicado. A tela não troca a chave sozinha.
export const publicacaoIncerta = codigo =>
  ['NETWORK', 'UNCONFIRMED'].includes(codigo);
