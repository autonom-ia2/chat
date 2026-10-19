import { defineComponent, h, ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import {
  filtrosDoEndereco,
  useFiltrosDoLinkNaCaixa,
  useReleituraPeriodica,
  RELEITURA_PERIODICA_MS,
} from '../useFiltrosDoLinkNaCaixa';

const Vazio = { render: () => null };
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
  const Teste = defineComponent({
    setup() {
      filtros = useFiltrosDoLinkNaCaixa();
      return () => h('div');
    },
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
    ).toEqual({ daIa: true, esperandoMin: 30 });
  });

  it('ignora valor que a caixa não oferece', () => {
    ['0', '1441', '-1', 'abc', '30.5', '0x1e', ''].forEach(valor => {
      expect(
        filtrosDoEndereco({ query: { da_ia: 'sim', esperando_min: valor } })
      ).toEqual({ daIa: false, esperandoMin: null });
    });
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
      defineComponent({
        setup() {
          useReleituraPeriodica(ligado, reler);
          return () => h('div');
        },
      })
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
