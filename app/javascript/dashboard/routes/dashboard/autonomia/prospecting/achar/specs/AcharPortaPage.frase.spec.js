import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import AcharPortaPage from '../pages/AcharPortaPage.vue';

// Pedido em uma frase (#2696) na porta de verdade, com a demonstração: a IA
// preenche "O quê?", "Onde?" e os ajustes; erro e "não entendi" deixam os
// campos como estavam e dizem o que fazer; sem a IA da conta, o campo some.
const { rota } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return {
    rota: reactive({
      name: 'autonomia_prospecting_achar',
      params: { accountId: '1' },
      query: {},
    }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = { getCurrentAccountId: 1, getCurrentUser: { id: 1 } };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
// Trocar o dono (#2694) é crm_manage_pipelines: aqui ninguém gere funis.
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => false) }),
    };
  }
);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: () => computed(() => false),
  };
});

// O pedido que a porta manda à fonte, para conferir o que foi junto.
const pedidos = vi.hoisted(() => []);
vi.mock('../utils/acharFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    criarFonte: opcoes => {
      const fonte = original.criarFonte(opcoes);
      return {
        ...fonte,
        async criarBusca(pedido) {
          pedidos.push(pedido);
          return fonte.criarBusca(pedido);
        },
      };
    },
  };
});

const botao = wrapper => wrapper.find('[data-principal]');
const oQue = wrapper => wrapper.find('[data-campo-o-que]').element.value;

const pedir = async (wrapper, frase = 'padarias no centro com nota boa') => {
  await vi.waitFor(
    () => {
      expect(wrapper.find('[data-campo-frase]').exists()).toBe(true);
    },
    { timeout: 3000 }
  );
  await wrapper.find('[data-campo-frase]').setValue(frase);
  await wrapper.find('[data-preencher]').trigger('click');
};

describe('AcharPortaPage: o pedido em uma frase', () => {
  it('preenche o quê, o onde (com as sugestões para conferir) e os ajustes', async () => {
    rota.query = { demo: 'porta' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.CONFIRA'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Padarias');
    expect(wrapper.find('[data-ficou-de-fora]').text()).toContain(
      'horário que abre'
    );
    expect(wrapper.text()).toContain('PORTA.COMO.AJUSTES');
    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]')).toHaveLength(3);
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('erro da IA: os campos ficam como estavam e o aviso pede para preencher', async () => {
    rota.query = { demo: 'porta-frase-erro' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.ERRO'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Escritórios');
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('PORTA.COMO.AJUSTES');
    wrapper.unmount();
  });

  it('"não entendi": nada muda e o aviso pede outro jeito', async () => {
    rota.query = { demo: 'porta-frase-nao-entendeu' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper, 'bom dia');

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.NAO_ENTENDEU'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Escritórios');
    wrapper.unmount();
  });

  it('ajuste e ordem escolhidos à mão ficam quando a frase não fala deles', async () => {
    rota.query = { demo: 'porta-frase-ajuste-manual' };
    const wrapper = mount(AcharPortaPage);
    await vi.waitFor(
      () => {
        expect(wrapper.text()).toContain('PORTA.COMO.AJUSTES');
      },
      { timeout: 3000 }
    );

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Padarias');
      },
      { timeout: 3000 }
    );
    expect(wrapper.text()).toContain('PORTA.COMO.AJUSTES');
    // O pedido que sai ao tocar no lugar e em "Achar empresas" leva o que foi
    // escolhido à mão (a ordem não aparece no texto das chaves de tradução).
    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]').length).toBeGreaterThan(0);
      },
      { timeout: 3000 }
    );
    await wrapper.find('[data-sugestao]').trigger('mousedown');
    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
      },
      { timeout: 3000 }
    );
    await botao(wrapper).trigger('click');
    await vi.waitFor(() => {
      expect(pedidos).toHaveLength(1);
    });
    expect(pedidos[0].oQue).toBe('Padarias');
    expect(pedidos[0].como).toMatchObject({
      primeiro: 'pouco',
      ajustes: { nota: 'n45' },
    });
    wrapper.unmount();
  });

  it('o lugar da frase não é escolhido sozinho, nem com uma sugestão só', async () => {
    rota.query = { demo: 'porta-frase-uma-sugestao' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]')).toHaveLength(1);
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    expect(wrapper.find('[data-dica]').text()).toContain('PORTA.FALTA.TOCAR');
    expect(botao(wrapper).attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('enquanto a IA lê, "O quê?", as ideias e "Onde?" ficam travados', async () => {
    rota.query = { demo: 'porta' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);
    await nextTick();

    expect(
      wrapper.find('[data-campo-o-que]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-ideia]').attributes('disabled')).toBeDefined();
    expect(
      wrapper.find('[data-alterar-lugar]').attributes('disabled')
    ).toBeDefined();
    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Padarias');
      },
      { timeout: 3000 }
    );
    expect(
      wrapper.find('[data-campo-o-que]').attributes('disabled')
    ).toBeUndefined();
    expect(
      wrapper.find('[data-campo-onde]').attributes('disabled')
    ).toBeUndefined();
    wrapper.unmount();
  });

  it('com a frase em voo, a lista de sugestões fecha e tocar numa sugestão não escolhe', async () => {
    rota.query = { demo: 'porta-sugestoes' };
    const wrapper = mount(AcharPortaPage);
    await vi.waitFor(
      () => {
        expect(wrapper.findAll('[data-sugestao]')).toHaveLength(3);
      },
      { timeout: 3000 }
    );
    const sugestao = wrapper.find('[data-sugestao]');

    await pedir(wrapper);
    await nextTick();

    expect(wrapper.find('[data-sugestoes]').exists()).toBe(false);
    if (sugestao.exists()) await sugestao.trigger('mousedown');
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    expect(
      wrapper.find('[data-campo-onde]').attributes('disabled')
    ).toBeDefined();
    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Padarias');
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('com a frase em voo, "Achar empresas" e o Enter do formulário não criam busca', async () => {
    pedidos.length = 0;
    rota.query = { demo: 'porta' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);
    await nextTick();

    expect(botao(wrapper).attributes('disabled')).toBeDefined();
    await botao(wrapper).trigger('click');
    await wrapper.find('[data-cartao-porta]').trigger('submit');
    expect(wrapper.find('[data-alterar]').attributes('disabled')).toBeDefined();
    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Padarias');
      },
      { timeout: 3000 }
    );
    expect(pedidos).toHaveLength(0);
    wrapper.unmount();
  });

  it('a IA da conta desligada no meio do caminho: o aviso diz isso', async () => {
    rota.query = { demo: 'porta-frase-sem-ia' };
    const wrapper = mount(AcharPortaPage);

    await pedir(wrapper);

    await vi.waitFor(
      () => {
        expect(wrapper.find('[data-aviso-frase]').text()).toContain(
          'PORTA.FRASE.SEM_IA'
        );
      },
      { timeout: 3000 }
    );
    expect(oQue(wrapper)).toBe('Escritórios');
    wrapper.unmount();
  });

  it('conta sem a IA: o campo da frase não aparece e os dois campos seguem', async () => {
    rota.query = { demo: 'porta-sem-ia' };
    const wrapper = mount(AcharPortaPage);

    await vi.waitFor(
      () => {
        expect(oQue(wrapper)).toBe('Escritórios');
      },
      { timeout: 3000 }
    );
    expect(wrapper.find('[data-frase]').exists()).toBe(false);
    expect(wrapper.find('[data-lugar-escolhido]').exists()).toBe(true);
    wrapper.unmount();
  });
});
