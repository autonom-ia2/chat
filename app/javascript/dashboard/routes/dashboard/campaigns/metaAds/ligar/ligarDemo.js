import { ref } from 'vue';
import { instalarMetaDemo } from './demoMeta';

// PROTÓTIPO (#2338), só para a demo local: com `?demo=<cena>` no endereço, a Meta é simulada (demoMeta.js) e a cena
// fica guardada na aba (sessionStorage) para seguir valendo ao navegar. Nada daqui vai ao PR final; lá, o estado
// vem do servidor (GET da conexão + `setup_status`).
//
// ?demo=novo           conta sem nada ligado (começa do zero)
// ?demo=pronto         tudo ligado: painel, comentários, formulários, criar e conexão
// ?demo=duas-paginas   o login trouxe duas Páginas: a pessoa escolhe qual anuncia
// ?demo=sem-pagina     o login não trouxe Página nenhuma
// ?demo=sem-permissao  na janela da Meta a pessoa desmarcou "gerenciar comentários" e "formulários"
// ?demo=sem-conta      tudo ligado, mas criar anúncio acha a conta de anúncios limpa (o 404 not_connected)
// ?demo=sair           volta ao painel de verdade
const CHAVE = 'demo-2338';

const PAGE = {
  id: 'pg_1',
  name: 'Loja Exemplo',
  instagram: { id: 'ig_1', username: 'lojaexemplo' },
};
const OTHER_PAGE = { id: 'pg_2', name: 'Loja Exemplo Outlet', instagram: null };

const zerado = cena => ({
  facebook: false,
  adAccount: null,
  pages: (() => {
    if (cena === 'sem-pagina') return [];
    if (cena === 'duas-paginas') return [PAGE, OTHER_PAGE];
    return [PAGE];
  })(),
  page: null,
  instagramInbox: false,
  pageInsights: false,
  destinations: { whatsapp: false, site: false },
  salesSignal: false,
  semPermissao:
    cena === 'sem-permissao'
      ? ['pages_manage_engagement', 'leads_retrieval']
      : [],
  perdeContaNaCriacao: false,
});

const ligado = cena => ({
  ...zerado(cena),
  facebook: true,
  adAccount: { id: 'act_1001', name: 'Loja Exemplo' },
  page: PAGE,
  instagramInbox: true,
  destinations: { whatsapp: true, site: false },
  salesSignal: true,
  perdeContaNaCriacao: cena === 'sem-conta',
});

const CENAS_LIGADAS = ['pronto', 'sem-conta', 'sem-permissao'];

export const estadoDemo = ref(null);
let cenaAtiva = null;

const lerCena = () => {
  try {
    return window.sessionStorage.getItem(CHAVE);
  } catch {
    return null;
  }
};
const guardarCena = cena => {
  try {
    if (cena) window.sessionStorage.setItem(CHAVE, cena);
    else window.sessionStorage.removeItem(CHAVE);
  } catch {
    // Sem armazenamento: a cena vale só enquanto o ?demo= estiver no endereço.
  }
};

// Um Facebook de mentira na janela: "Entrar com o Facebook" volta na hora com um código.
const fingirFacebook = () => {
  const script = document.createElement('script');
  script.type = 'text/plain';
  script.src = 'https://connect.facebook.net/en_US/sdk.js';
  script.setAttribute('data-loaded', 'true');
  document.head.appendChild(script);
  window.FB = {
    init: () => {},
    login: callback =>
      setTimeout(() => callback({ authResponse: { code: 'demo' } }), 400),
  };
};

// Liga a demo quando o endereço (ou a aba) pede. Devolve a cena ativa, ou null.
export const ativarDemo = query => {
  const pedida = query.demo;
  if (pedida === 'sair') {
    guardarCena(null);
    return null;
  }
  const cena = pedida || lerCena();
  if (!cena) return null;
  // Navegar com o mesmo ?demo= no endereço não zera a cena: só uma cena nova (ou a primeira) começa do início.
  if (!estadoDemo.value || cena !== cenaAtiva) {
    cenaAtiva = cena;
    guardarCena(cena);
    estadoDemo.value = CENAS_LIGADAS.includes(cena)
      ? ligado(cena)
      : zerado(cena);
    fingirFacebook();
    instalarMetaDemo(estadoDemo);
  }
  return cena;
};
