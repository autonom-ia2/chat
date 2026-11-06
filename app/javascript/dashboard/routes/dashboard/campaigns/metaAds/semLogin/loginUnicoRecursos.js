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

// page: a Página escolhida (com `instagram` ou null), ou null; declined: permissões desmarcadas.
// falta: null (funciona), 'PAGE', 'INSTAGRAM' ou 'PERMISSION'.
export const recursosDoLogin = ({ page, declined = [] }) =>
  RECURSOS.map(({ chave, precisa, permissao }) => {
    if (precisa && !page) return { chave, falta: 'PAGE' };
    // Instagram por toque à parte (decisão do Rodrigo, 06/11): o login único não o liga.
    if (precisa === 'instagram') {
      return { chave, falta: page.instagram ? 'INSTAGRAM_TAP' : 'INSTAGRAM' };
    }
    return { chave, falta: declined.includes(permissao) ? 'PERMISSION' : null };
  });
