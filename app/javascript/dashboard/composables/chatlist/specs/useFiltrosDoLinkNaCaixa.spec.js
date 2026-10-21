import { defineComponent, h, ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import conversationPage from 'dashboard/store/modules/conversationPage';
import { setPageFilter } from 'dashboard/store/modules/conversations/helpers/actionHelpers';
import {
  abaDoFiltroDoLink,
  statusDoFiltroDoLink,
  funilDoFiltroDoLink,
  abaDaListaComLink,
  chaveDaPaginaDaLista,
  filtroDoLinkDaLista,
  filtrosDoEndereco,
  useFiltrosDoLinkNaCaixa,
  useReleituraPeriodica,
  RELEITURA_PERIODICA_MS,
} from '../useFiltrosDoLinkNaCaixa';

const Vazio = { render: () => null };

// Um componente só para chamar o composable dentro de um setup de verdade.
const componenteQueUsa = usar =>
  defineComponent({
    setup() {
      usar();
      return () => h('div');
    },
  });
const rotas = [
  { path: '/app/accounts/:accountId/dashboard', name: 'home' },
  { path: '/app/accounts/:accountId/inbox/:inbox_id', name: 'inbox_dashboard' },
  {
    path: '/app/accounts/:accountId/conversations/:conversation_id',
    name: 'inbox_conversation',
  },
  { path: '/app/accounts/:accountId/crm', name: 'crm_kanban_index' },
  { path: '/app/accounts/:accountId/contacts', name: 'contacts_dashboard' },
].map(rota => ({ ...rota, component: Vazio }));

const montar = async inicio => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: rotas,
  });
  let filtros;
  const Teste = componenteQueUsa(() => {
    filtros = useFiltrosDoLinkNaCaixa();
  });
  await router.push(inicio);
  await router.isReady();
  mount(Teste, { global: { plugins: [router] } });
  return { router, filtros };
};

describe('filtrosDoEndereco', () => {
  it('lê da_ia=1 e esperando_min dentro de 1..1440', () => {
    expect(
      filtrosDoEndereco({ query: { da_ia: '1', esperando_min: '30' } })
    ).toEqual({ daIa: true, esperandoMin: 30, noFunil: false });
  });

  it('ignora valor que a caixa não oferece', () => {
    ['0', '1441', '-1', 'abc', '30.5', '0x1e', ''].forEach(valor => {
      expect(
        filtrosDoEndereco({ query: { da_ia: 'sim', esperando_min: valor } })
      ).toEqual({ daIa: false, esperandoMin: null, noFunil: false });
    });
  });
});

describe('filtroDoLinkDaLista (o filtro que a lista pede)', () => {
  const nulo = { daIa: undefined, esperandoMin: undefined };

  it('com o link, pede os dois valores', () => {
    expect(filtroDoLinkDaLista({ daIa: true, esperandoMin: 30 })).toEqual({
      daIa: true,
      esperandoMin: 30,
    });
  });

  it('no Spam ou na Lixeira, a pasta manda: filtro nulo', () => {
    expect(
      filtroDoLinkDaLista({ daIa: true, esperandoMin: 30, pasta: 'spam' })
    ).toEqual(nulo);
  });

  it('com filtro avançado ou pasta salva, filtro nulo', () => {
    expect(
      filtroDoLinkDaLista({
        daIa: true,
        esperandoMin: 30,
        filtroAvancado: true,
      })
    ).toEqual(nulo);
  });

  it('sem o link, as duas chaves vêm vazias (o merge da store não guarda valor antigo)', () => {
    expect(filtroDoLinkDaLista({ daIa: false, esperandoMin: null })).toEqual(
      nulo
    );
  });
});

describe('useFiltrosDoLinkNaCaixa', () => {
  it('a lista que abre pelo link liga o filtro', async () => {
    const { filtros } = await montar('/app/accounts/1/dashboard?da_ia=1');

    expect(filtros.daIa.value).toBe(true);
    expect(filtros.esperandoMin.value).toBe(null);
  });

  it('abrir uma conversa da lista filtrada leva o link junto; voltar pelo menu, sem o link, desliga', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?esperando_min=30'
    );

    await router.push('/app/accounts/1/conversations/7');
    expect(router.currentRoute.value.query).toEqual({ esperando_min: '30' });
    expect(filtros.esperandoMin.value).toBe(30);

    await router.push('/app/accounts/1/conversations/8');
    expect(filtros.esperandoMin.value).toBe(30);

    await router.push('/app/accounts/1/inbox/3');
    expect(filtros.esperandoMin.value).toBe(null);
  });

  it('caixa filtrada → CRM → conversa pelo card: a lista NÃO vem filtrada', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );

    await router.push('/app/accounts/1/crm');
    expect(filtros.daIa.value).toBe(false);

    await router.push('/app/accounts/1/conversations/7');
    expect(router.currentRoute.value.query).toEqual({});
    expect(filtros.daIa.value).toBe(false);
  });

  it('Contatos → conversa também chega sem filtro', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );
    await router.push('/app/accounts/1/contacts');
    await router.push('/app/accounts/1/conversations/9');

    expect(filtros.daIa.value).toBe(false);
  });

  it('limpar tira só os parâmetros do link e mantém o resto do endereço', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/inbox/3?da_ia=1&esperando_min=30&pasta=spam'
    );

    await filtros.limpar();

    expect(router.currentRoute.value.query).toEqual({ pasta: 'spam' });
    expect([filtros.daIa.value, filtros.esperandoMin.value]).toEqual([
      false,
      null,
    ]);
  });

  it('limpar dentro da conversa aberta tira o link dela também', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );
    await router.push('/app/accounts/1/conversations/7');

    await filtros.limpar();

    expect(router.currentRoute.value.name).toBe('inbox_conversation');
    expect(router.currentRoute.value.query).toEqual({});
    expect(filtros.daIa.value).toBe(false);
  });

  it('outra conversa aberta enquanto o Limpar navega não perde o link', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );
    await router.push('/app/accounts/1/conversations/7');

    const limpando = filtros.limpar();
    await router.push('/app/accounts/1/conversations/8');
    await limpando;

    expect(router.currentRoute.value.path).toBe(
      '/app/accounts/1/conversations/8'
    );
    expect(router.currentRoute.value.query).toEqual({ da_ia: '1' });
  });

  it('clicar de novo na conversa aberta, na lista filtrada, mantém o filtro', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );
    await router.push('/app/accounts/1/conversations/7');

    await router.push('/app/accounts/1/conversations/7');

    expect(router.currentRoute.value.query).toEqual({ da_ia: '1' });
    expect(filtros.daIa.value).toBe(true);
  });

  describe('irParaALista (marcar como não lida, excluir)', () => {
    it('com o filtro ligado, a conversa volta para a lista com o link', async () => {
      const { router, filtros } = await montar(
        '/app/accounts/1/dashboard?da_ia=1&esperando_min=30'
      );
      await router.push('/app/accounts/1/conversations/7');

      await filtros.irParaALista('/app/accounts/1/dashboard', true);

      expect(router.currentRoute.value.name).toBe('home');
      expect(router.currentRoute.value.query).toEqual({
        da_ia: '1',
        esperando_min: '30',
      });
    });

    it('com o filtro desligado (pasta ou filtro avançado), volta sem o link', async () => {
      const { router, filtros } = await montar(
        '/app/accounts/1/dashboard?da_ia=1'
      );
      await router.push('/app/accounts/1/conversations/7');

      await filtros.irParaALista('/app/accounts/1/dashboard', false);

      expect(router.currentRoute.value.query).toEqual({});
    });
  });

  describe('enderecoComLink (Ctrl/Cmd+clique)', () => {
    it('na lista filtrada, o endereço da conversa leva o link', async () => {
      const { filtros } = await montar(
        '/app/accounts/1/dashboard?esperando_min=30&da_ia=0'
      );

      expect(filtros.enderecoComLink('/app/accounts/1/conversations/7')).toBe(
        '/app/accounts/1/conversations/7?esperando_min=30'
      );
    });

    it('fora da lista filtrada, o endereço fica como está', async () => {
      const { filtros } = await montar('/app/accounts/1/crm');

      expect(filtros.enderecoComLink('/app/accounts/1/conversations/7')).toBe(
        '/app/accounts/1/conversations/7'
      );
    });
  });

  describe('limparTudo (a seta "Limpar filtros")', () => {
    it('com o link no endereço, um clique tira o link e não relê à parte', async () => {
      const { router, filtros } = await montar(
        '/app/accounts/1/dashboard?da_ia=1'
      );
      const reler = vi.fn();

      await filtros.limparTudo(reler);

      expect(router.currentRoute.value.query).toEqual({});
      expect(reler).not.toHaveBeenCalled();
    });

    it('com link que a caixa não oferece (?da_ia=0), tira o link e relê', async () => {
      const { router, filtros } = await montar(
        '/app/accounts/1/dashboard?da_ia=0'
      );
      const reler = vi.fn();

      await filtros.limparTudo(reler);

      expect(router.currentRoute.value.query).toEqual({});
      expect(reler).toHaveBeenCalledTimes(1);
    });

    it('sem o link, só relê (o filtro avançado sai na releitura)', async () => {
      const { filtros } = await montar('/app/accounts/1/dashboard');
      const reler = vi.fn();

      await filtros.limparTudo(reler);

      expect(reler).toHaveBeenCalledTimes(1);
    });
  });
});

describe('useReleituraPeriodica', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const montarReleitura = ligado => {
    const reler = vi.fn();
    const wrapper = mount(
      componenteQueUsa(() => useReleituraPeriodica(ligado, reler))
    );
    return { reler, wrapper };
  };

  it('relê uma vez por minuto só com o filtro ligado', async () => {
    const ligado = ref(true);
    const { reler, wrapper } = montarReleitura(ligado);

    vi.advanceTimersByTime(RELEITURA_PERIODICA_MS * 2);
    expect(reler).toHaveBeenCalledTimes(2);

    ligado.value = false;
    await nextTick();
    vi.advanceTimersByTime(RELEITURA_PERIODICA_MS * 3);
    expect(reler).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });

  it('não relê com a aba do navegador escondida, e para ao desmontar', () => {
    const visibilidade = vi
      .spyOn(document, 'visibilityState', 'get')
      .mockReturnValue('hidden');
    const { reler, wrapper } = montarReleitura(ref(true));

    vi.advanceTimersByTime(RELEITURA_PERIODICA_MS);
    expect(reler).not.toHaveBeenCalled();

    visibilidade.mockReturnValue('visible');
    wrapper.unmount();
    vi.advanceTimersByTime(RELEITURA_PERIODICA_MS);
    document.dispatchEvent(new Event('visibilitychange'));
    expect(reler).not.toHaveBeenCalled();
    visibilidade.mockRestore();
  });

  it('relê logo que a aba volta a ficar visível, só com o filtro ligado', async () => {
    const visibilidade = vi
      .spyOn(document, 'visibilityState', 'get')
      .mockReturnValue('visible');
    const ligado = ref(true);
    const { reler, wrapper } = montarReleitura(ligado);

    document.dispatchEvent(new Event('visibilitychange'));
    expect(reler).toHaveBeenCalledTimes(1);

    ligado.value = false;
    await nextTick();
    document.dispatchEvent(new Event('visibilitychange'));
    expect(reler).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    visibilidade.mockRestore();
  });
});

// #1999: o número do Números conta todas as conversas que a pessoa enxerga; a caixa abre em "Todas" para bater.
describe('abaDoFiltroDoLink', () => {
  const ABAS = ['me', 'unassigned', 'all'];

  it('com o filtro do link, abre em Todas', () => {
    expect(
      abaDoFiltroDoLink({ daIa: true, esperandoMin: 30 }, ABAS, 'all')
    ).toBe('all');
    expect(
      abaDoFiltroDoLink({ daIa: false, esperandoMin: 30 }, ABAS, 'all')
    ).toBe('all');
  });

  it('sem o filtro do link, ou sem a aba Todas, vale a aba de sempre', () => {
    expect(
      abaDoFiltroDoLink({ daIa: false, esperandoMin: null }, ABAS, 'all')
    ).toBeNull();
    expect(
      abaDoFiltroDoLink({ daIa: true, esperandoMin: 30 }, ['me'], 'all')
    ).toBeNull();
  });
});

// #1999: o Números conta as conversas abertas; com o filtro do link, a caixa abre em "Abertas" mesmo com outro salvo.
describe('statusDoFiltroDoLink', () => {
  it('com o filtro do link, abre em Abertas mesmo com Pendentes salvo', () => {
    expect(
      statusDoFiltroDoLink({ daIa: true, esperandoMin: 30 }, 'pending', 'open')
    ).toBe('open');
  });

  it('sem o filtro do link, fica o status salvo', () => {
    expect(
      statusDoFiltroDoLink(
        { daIa: undefined, esperandoMin: undefined },
        'pending',
        'open'
      )
    ).toBe('pending');
  });
});

// #1999: com o filtro do link, o escopo do funil vem do link (no_funil), e o funil escolhido na caixa fica de lado.
describe('funil da lista com o filtro do link', () => {
  it('com o filtro do link, a lista ignora o funil escolhido; sem ele, vale o escolhido', () => {
    expect(funilDoFiltroDoLink({ daIa: true }, '42', '')).toBe('');
    expect(funilDoFiltroDoLink({ daIa: undefined }, '42', '')).toBe('42');
  });

  it('no_funil vai ao servidor só junto de um dos filtros do link', () => {
    expect(
      filtroDoLinkDaLista({ daIa: true, esperandoMin: 30, noFunil: true })
    ).toEqual({ daIa: true, esperandoMin: 30, noFunil: true });
    expect(filtroDoLinkDaLista({ noFunil: true })).toEqual({
      daIa: undefined,
      esperandoMin: undefined,
      noFunil: undefined,
    });
  });

  it('lê no_funil=1 do endereço', () => {
    expect(
      filtrosDoEndereco({ query: { da_ia: '1', no_funil: '1' } }).noFunil
    ).toBe(true);
  });
});

// #1999, revisão 2: quem não tem "Todas" (função com conversation_unassigned_manage) vê a lista do link inteira, as
// Minhas mais as Não atribuídas, o mesmo que o número conta; o servidor corta pelas permissões.
describe('abaDaListaComLink', () => {
  const SEM_TODAS = ['me', 'unassigned'];

  it('sem a aba Todas, a lista do link pede todas', () => {
    expect(
      abaDaListaComLink(
        { daIa: true, esperandoMin: 30 },
        SEM_TODAS,
        'me',
        'all'
      )
    ).toBe('all');
  });

  it('com a aba Todas, ou sem o filtro do link, vale a aba escolhida', () => {
    expect(
      abaDaListaComLink(
        { daIa: true, esperandoMin: 30 },
        [...SEM_TODAS, 'all'],
        'me',
        'all'
      )
    ).toBe('me');
    expect(
      abaDaListaComLink(
        { daIa: false, esperandoMin: null },
        SEM_TODAS,
        'me',
        'all'
      )
    ).toBe('me');
  });
});

// #1999, revisão 2: trocar só o no_funil também relê a lista (a assinatura do link muda).
describe('assinatura do link', () => {
  it('muda quando só o no_funil muda', async () => {
    const { router, filtros } = await montar(
      '/app/accounts/1/dashboard?da_ia=1&esperando_min=30'
    );
    const antes = filtros.assinatura.value;

    await router.push(
      '/app/accounts/1/dashboard?da_ia=1&esperando_min=30&no_funil=1'
    );
    await nextTick();

    expect(filtros.assinatura.value).not.toBe(antes);
  });
});

// #1999, revisão 3: a lista junta do link pede "todas" e a resposta grava o avanço em "todas"; a próxima página e o fim
// da lista têm que ser lidos ali. Simula a rolagem da caixa com o módulo de páginas de verdade.
describe('paginação da lista junta do link', () => {
  const POR_PAGINA = 25;
  const novaLoja = () =>
    createStore({
      modules: {
        conversationPage: {
          ...conversationPage,
          state: structuredClone(conversationPage.state),
        },
      },
    });

  // Pede páginas como o rodapé da lista: lê a página e o fim na chave dada; a resposta grava na aba que a lista pediu.
  const rolar = (loja, { abaPedida, chave, total }) => {
    const pedidas = [];
    for (let vez = 0; vez < 6; vez += 1) {
      if (loja.getters['conversationPage/getHasEndReached'](chave)) break;
      const pagina =
        loja.getters['conversationPage/getCurrentPageFilter'](chave) + 1;
      pedidas.push(pagina);
      const vieram = Math.max(
        0,
        Math.min(POR_PAGINA, total - (pagina - 1) * POR_PAGINA)
      );
      setPageFilter({
        dispatch: loja.dispatch,
        filter: abaPedida,
        page: pagina,
        markEndReached: vieram === 0,
      });
    }
    return pedidas;
  };

  it('quem não tem Todas avança 1→2→3 e para quando a lista acaba', () => {
    const loja = novaLoja();
    const abaDaLista = abaDaListaComLink(
      { daIa: true, esperandoMin: 30 },
      ['me', 'unassigned'],
      'me',
      'all'
    );

    const pedidas = rolar(loja, {
      abaPedida: abaDaLista,
      chave: chaveDaPaginaDaLista(false, abaDaLista),
      total: 60,
    });

    expect(pedidas).toEqual([1, 2, 3, 4]);
    expect(loja.getters['conversationPage/getHasEndReached']('all')).toBe(true);
  });

  it('lendo a página na aba escolhida (Minhas), a lista ficaria na página 1', () => {
    const loja = novaLoja();

    const pedidas = rolar(loja, { abaPedida: 'all', chave: 'me', total: 60 });

    expect(pedidas).toEqual([1, 1, 1, 1, 1, 1]);
  });

  it('com o filtro avançado, a página fica na gaveta dele', () => {
    expect(chaveDaPaginaDaLista(true, 'all')).toBe('appliedFilters');
    expect(chaveDaPaginaDaLista(false, 'unassigned')).toBe('unassigned');
  });
});
