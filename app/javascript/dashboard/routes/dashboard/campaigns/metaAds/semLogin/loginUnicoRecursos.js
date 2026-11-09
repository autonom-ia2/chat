// Login único (#2338): o que já funciona depois de entrar uma vez com o Facebook. Cada recurso precisa da conta de
// anúncios (sempre ligada aqui), da Página ou do Instagram dela, e de uma permissão que a pessoa pode ter desmarcado
// na janela da Meta. Ordem: o que mais se usa primeiro.
const RECURSOS = [
  { chave: 'SPEND', precisa: null, permissao: 'ads_read' },
  { chave: 'CREATE', precisa: 'page', permissao: 'ads_management' },
  {
    chave: 'COMMENTS_FACEBOOK',
    precisa: 'page',
    permissao: 'pages_manage_engagement',
  },
  {
    chave: 'MESSAGES_FACEBOOK',
    precisa: 'page',
    permissao: 'pages_messaging',
  },
  { chave: 'FORMS', precisa: 'page', permissao: 'leads_retrieval' },
  { chave: 'POSTS', precisa: 'page', permissao: 'read_insights' },
  {
    chave: 'COMMENTS_INSTAGRAM',
    precisa: 'instagram',
    permissao: 'instagram_manage_comments',
  },
  {
    chave: 'MESSAGES_INSTAGRAM',
    precisa: 'instagram',
    permissao: 'instagram_manage_messages',
  },
];

// page: a Página escolhida (com `instagram` ou null), ou null. granted/declined: o que a Meta concedeu e o que a
// pessoa desmarcou. Recurso da Página cuja permissão não está em nenhuma das duas a configuração do login não pede:
// sai da lista, para não prometer o que este login não liga. Sem a lista de concedidas (a Meta não respondeu), mostra
// tudo. O Instagram fica sempre: ele se liga por um toque à parte, com o login do próprio Instagram.
// falta: null (funciona), 'PAGE', 'INSTAGRAM', 'INSTAGRAM_TAP' ou 'PERMISSION'.
// pelaPagina (#2406, flag instagram_login_unico): o Instagram da Página liga por este mesmo login. Depois de ligado
// (agora, ou antes: `page.instagram.linked`), conta como os recursos da Página.
const pedidoNoLogin = ({ precisa, permissao }, granted, declined) =>
  precisa === 'instagram' ||
  !granted.length ||
  granted.includes(permissao) ||
  declined.includes(permissao);

const faltaDoInstagram = (page, pelaPagina, instagramLigado) => {
  if (!page.instagram) return 'INSTAGRAM';
  const ligado = instagramLigado || page.instagram.linked;
  return pelaPagina && ligado ? null : 'INSTAGRAM_TAP';
};

export const recursosDoLogin = ({
  page,
  granted = [],
  declined = [],
  pelaPagina = false,
  instagramLigado = false,
}) =>
  RECURSOS.filter(recurso => pedidoNoLogin(recurso, granted, declined)).map(
    ({ chave, precisa, permissao }) => {
      if (precisa && !page) return { chave, falta: 'PAGE' };
      const falta =
        precisa === 'instagram'
          ? faltaDoInstagram(page, pelaPagina, instagramLigado)
          : null;
      if (falta) return { chave, falta };
      return {
        chave,
        falta: declined.includes(permissao) ? 'PERMISSION' : null,
      };
    }
  );
