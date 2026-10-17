import { mount } from '@vue/test-utils';
import { defineComponent, h, nextTick, ref } from 'vue';
import ForkSidebarSeta from '../fork/ForkSidebarSeta.vue';
import { temaDoMenu } from '../fork/tema';
import { useSetasDeRolagem } from '../fork/useSetasDeRolagem';

// Pílulas "N itens abaixo/acima" do menu novo (#1781): contagem dos itens de topo fora da vista, pluralização,
// rótulo completo para o leitor de tela e o respiro só na primeira vez em cada tela.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params, n) => (n === undefined ? chave : `${chave}:${n}`),
  }),
}));

const caixaEm = (el, { top, bottom }) => {
  el.getBoundingClientRect = () => ({ top, bottom, height: bottom - top });
};

const montar = async () => {
  const tela = ref('/a');
  let api;
  const wrapper = mount(
    defineComponent({
      setup() {
        const caixa = ref(null);
        const conteudo = ref(null);
        api = useSetasDeRolagem(caixa, conteudo, () => tela.value);
        return () =>
          h('nav', { ref: caixa }, [
            h('div', { ref: conteudo }, [
              h(
                'ul',
                [0, 1, 2, 3, 4].map(i => h('li', { 'data-i': i }))
              ),
            ]),
          ]);
      },
    }),
    { attachTo: document.body }
  );
  await nextTick();
  const nav = wrapper.find('nav').element;
  Object.defineProperty(nav, 'clientHeight', {
    value: 100,
    configurable: true,
  });
  Object.defineProperty(nav, 'scrollHeight', {
    value: 250,
    configurable: true,
  });
  caixaEm(nav, { top: 0, bottom: 100 });
  const itens = [...nav.querySelectorAll('li')];
  const rolarPara = async topo => {
    nav.scrollTop = topo;
    itens.forEach((li, i) =>
      caixaEm(li, { top: i * 50 - topo, bottom: i * 50 + 50 - topo })
    );
    nav.dispatchEvent(new Event('scroll'));
    await nextTick();
  };
  return { wrapper, api, tela, rolarPara };
};

describe('useSetasDeRolagem', () => {
  afterEach(() => vi.useRealTimers());

  it('conta os itens de topo fora da vista acima e abaixo', async () => {
    const { api, rolarPara, wrapper } = await montar();
    await rolarPara(0);
    expect([api.itensAcima.value, api.itensAbaixo.value]).toEqual([0, 3]);
    await rolarPara(100);
    expect([api.itensAcima.value, api.itensAbaixo.value]).toEqual([2, 1]);
    wrapper.unmount();
  });

  it('respira dois ciclos só na primeira vez em cada tela', async () => {
    vi.useFakeTimers();
    const { api, tela, rolarPara, wrapper } = await montar();
    await rolarPara(0);
    const vistos = [];
    for (let i = 0; i < 6; i += 1) {
      vi.advanceTimersByTime(350);
      vistos.push(api.respirando.value.abaixo);
    }
    expect(vistos).toEqual([true, false, true, false, false, false]);

    await rolarPara(150);
    await rolarPara(0);
    vi.advanceTimersByTime(350);
    expect(api.respirando.value.abaixo).toBe(false);

    tela.value = '/b';
    await nextTick();
    vi.advanceTimersByTime(350);
    expect(api.respirando.value.abaixo).toBe(true);
    wrapper.unmount();
  });
});

describe('ForkSidebarSeta', () => {
  const pilula = props =>
    mount(ForkSidebarSeta, {
      props: {
        lado: 'abaixo',
        visivel: true,
        controla: 'lista',
        tema: temaDoMenu(true),
        ...props,
      },
    });

  it('mostra a contagem com plural e o rótulo completo', () => {
    const botao = pilula({ contagem: 3 }).find('button');
    expect(botao.text()).toBe('FORK_SIDEBAR.ITENS_ABAIXO:3');
    expect(botao.attributes('aria-label')).toBe(
      'FORK_SIDEBAR.ROLAR_ABAIXO_ITENS:3'
    );
    expect(botao.html()).toContain('i-lucide-chevron-down');
    expect(botao.html()).toContain('backdrop-blur-md');
  });

  it('recolhido mostra só o chevron; acima usa o chevron para cima', () => {
    const botao = pilula({ lado: 'acima', contagem: 2, recolhido: true }).find(
      'button'
    );
    expect(botao.text()).toBe('');
    expect(botao.attributes('aria-label')).toBe(
      'FORK_SIDEBAR.ROLAR_ACIMA_ITENS:2'
    );
    expect(botao.html()).toContain('i-lucide-chevron-up');
  });

  it('invisível não renderiza o botão', () => {
    expect(pilula({ visivel: false }).find('button').exists()).toBe(false);
  });
});
