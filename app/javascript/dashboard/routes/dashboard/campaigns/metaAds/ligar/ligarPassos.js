// Passo a passo único para ligar Anúncios da Meta numa conta nova (#2338). Um passo por tela, nesta ordem:
// entrar com o Facebook (conta de anúncios, Página e Instagram num login só), escolher a conta de anúncios,
// conferir a Página e o Instagram, trazer o Instagram para a caixa de entrada e dizer para onde o anúncio leva.
export const PASSOS = ['FACEBOOK', 'CONTA', 'PAGINA', 'INSTAGRAM', 'DESTINO'];

const FEITO = {
  FACEBOOK: estado => estado.facebook,
  CONTA: estado => Boolean(estado.adAccount),
  PAGINA: estado => Boolean(estado.page),
  // Página sem Instagram ligado: o passo não tem o que fazer e conta como feito.
  INSTAGRAM: estado =>
    Boolean(estado.page) && (!estado.page.instagram || estado.instagramInbox),
  DESTINO: estado =>
    Boolean(estado.destinations.whatsapp || estado.destinations.site),
};

export const passoFeito = (passo, estado) => FEITO[passo](estado);

// O primeiro passo que falta; 'PRONTO' quando nada falta.
export const passoDaVez = estado =>
  PASSOS.find(passo => !passoFeito(passo, estado)) || 'PRONTO';

// O que cada recurso precisa e, faltando, o passo que resolve. `null` em `falta` = já funciona.
const RECURSOS = [
  { chave: 'RESULTADO', precisa: ['FACEBOOK', 'CONTA'] },
  { chave: 'CRIAR', precisa: ['FACEBOOK', 'CONTA', 'PAGINA'] },
  { chave: 'COMENTARIOS_FACEBOOK', precisa: ['FACEBOOK', 'CONTA', 'PAGINA'] },
  { chave: 'FORMULARIOS', precisa: ['FACEBOOK', 'CONTA', 'PAGINA'] },
  {
    chave: 'COMENTARIOS_INSTAGRAM',
    precisa: ['FACEBOOK', 'CONTA', 'PAGINA', 'INSTAGRAM'],
  },
];

// Permissão que a pessoa desmarcou na janela da Meta: o recurso diz qual e leva a entrar de novo.
const PERMISSAO = {
  CRIAR: 'ads_management',
  COMENTARIOS_FACEBOOK: 'pages_manage_engagement',
  FORMULARIOS: 'leads_retrieval',
};

export const recursos = estado => [
  ...RECURSOS.map(({ chave, precisa }) => {
    const passo = precisa.find(item => !passoFeito(item, estado));
    const semPermissao = (estado.semPermissao || []).includes(PERMISSAO[chave]);
    return { chave, falta: passo || (semPermissao ? 'PERMISSAO' : null) };
  }),
  // Anúncio que leva ao site precisa da página ligada (#2338): sem ela, ninguém sabe quem chegou pelo anúncio.
  ...(estado.destinations.site
    ? [
        {
          chave: 'SITE',
          falta: (estado.sitePages || []).length ? null : 'PAGINA_SITE',
        },
      ]
    : []),
  // Seus posts lê os números da Página pela caixa de entrada do Facebook: liberar é um clique à parte.
  { chave: 'SEUS_POSTS', falta: estado.pageInsights ? null : 'NUMEROS' },
  { chave: 'VENDAS', falta: estado.salesSignal ? null : 'VENDAS' },
];
