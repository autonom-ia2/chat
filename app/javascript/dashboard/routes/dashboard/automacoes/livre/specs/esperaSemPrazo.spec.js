import { defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import LivreAlterar from '../components/LivreAlterar.vue';
import { galhosDe, SEM_PRAZO } from '../receita';
import { fraseDoPasso } from '../frases';

// #2750 — o "Esperar até" sem prazo: uma escolha explícita no painel, que só
// termina pela condição e não tem "Se o prazo acabar".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));

const PainelFalso = defineComponent({
  name: 'SidePanel',
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /><slot name="footer" /></div>',
});

const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

const CONDICAO = {
  campo: { $valor: 'conversa.status' },
  op: 'igual',
  valor: 'resolved',
};

const CATALOGO = {
  gatilhos: [],
  operadores: [{ op: 'igual', pede_valor: true, frase: 'IGUAL' }],
  unidades: [{ valor: 'dias', frase: 'DIAS' }],
  valores: [{ caminho: 'conversa.status', frase: 'STATUS' }],
  passos: [
    {
      tipo: 'esperar_ate',
      grupo: 'CONTROLE',
      frase: 'ESPERAR_ATE',
      campos: [
        { nome: 'condicao', peca: 'condicao', rotulo: 'CONDICAO' },
        { nome: 'prazo', peca: 'prazo', rotulo: 'PRAZO' },
        { nome: 'se_vencer', peca: 'passos', rotulo: 'SE_VENCER' },
      ],
    },
  ],
};

const espera = extra => ({
  id: 'p1',
  tipo: 'esperar_ate',
  condicao: CONDICAO,
  prazo: { valor: 2, unidade: 'dias' },
  ...extra,
});

const montar = async passo => {
  const wrapper = mount(LivreAlterar, {
    props: {
      catalogo: CATALOGO,
      opcoes: {},
      atributosDaPeca: () => [],
      atributosDo: () => [],
    },
    global: {
      stubs: { SidePanel: PainelFalso },
      mocks: { $t: chave => chave },
    },
  });
  wrapper.vm.abrir({ tipo: 'passo', valor: passo });
  await flushPromises();
  return wrapper;
};

const escolhaDoPrazo = wrapper =>
  wrapper
    .find('[data-peca="prazo"]')
    .findAllComponents({ name: 'ChoiceSelect' })[0];

const salvarDesligado = wrapper =>
  wrapper.find('[data-salvar]').attributes('disabled') !== undefined;

describe('esperar até sem prazo', () => {
  it('o painel oferece "Sem prazo" como opção explícita, ao lado do prazo', async () => {
    const wrapper = await montar(espera());

    expect(escolhaDoPrazo(wrapper).props('options')).toEqual([
      { value: 'com_prazo', label: 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.COM_PRAZO' },
      { value: SEM_PRAZO, label: 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO' },
    ]);
    expect(wrapper.find('[data-peca="duracao"]').exists()).toBe(true);
  });

  it('escolher "Sem prazo" grava "sem_prazo", esconde o tempo e salva', async () => {
    const wrapper = await montar(espera());

    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', SEM_PRAZO);
    await flushPromises();

    expect(wrapper.find('[data-peca="duracao"]').exists()).toBe(false);
    expect(wrapper.find('[data-sem-prazo-dica]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(false);
    await wrapper.find('[data-salvar]').trigger('click');
    expect(wrapper.emitted('salvar')[0][0].valor.prazo).toBe(SEM_PRAZO);
  });

  it('voltar para "Até um prazo" devolve o último tempo escrito', async () => {
    const wrapper = await montar(espera());

    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', SEM_PRAZO);
    await flushPromises();
    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', 'com_prazo');
    await flushPromises();
    await wrapper.find('[data-salvar]').trigger('click');

    expect(wrapper.emitted('salvar')[0][0].valor.prazo).toEqual({
      valor: 2,
      unidade: 'dias',
    });
  });

  it('com passos em "Se o prazo acabar", sem prazo não salva e diz o porquê', async () => {
    const wrapper = await montar(
      espera({ se_vencer: [{ id: 'p2', tipo: 'parar' }] })
    );

    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', SEM_PRAZO);
    await flushPromises();

    expect(wrapper.find('[data-sem-prazo-se-vencer]').exists()).toBe(true);
    expect(salvarDesligado(wrapper)).toBe(true);
  });

  it('sem prazo, o passo não abre o galho "Se o prazo acabar"; o "a cada mensagem" fica (G63)', () => {
    expect(galhosDe(espera()).map(galho => galho.ramo)).toEqual([
      'se_vencer',
      'a_cada_mensagem',
    ]);
    expect(
      galhosDe(espera({ prazo: SEM_PRAZO })).map(galho => galho.ramo)
    ).toEqual(['a_cada_mensagem']);
  });

  it('galho que ainda tem passo continua à vista, para a pessoa tirar', () => {
    const passo = espera({
      prazo: SEM_PRAZO,
      se_vencer: [{ id: 'p2', tipo: 'parar' }],
    });

    expect(galhosDe(passo).map(galho => galho.ramo)).toEqual([
      'se_vencer',
      'a_cada_mensagem',
    ]);
  });

  it('a frase diz "sem prazo"', () => {
    expect(fraseDoPasso(espera({ prazo: SEM_PRAZO }), CATALOGO, t)).toMatch(
      /^AUTOMACAO_LIVRE\.FRASES\.ESPERAR_ATE_SEM_PRAZO /
    );
  });
});

// G64 (#2839) — sem prazo, a conferência diária numa hora marcada, que nasce
// às 8h (decisão 12) e a pessoa muda; "Assim que algo mudar" tira a hora.
describe('esperar até sem prazo: a hora da conferência', () => {
  const escolhaDaHora = wrapper =>
    wrapper.find('[data-conferir-as]').findComponent({ name: 'ChoiceSelect' });
  const salvo = async wrapper => {
    await wrapper.find('[data-salvar]').trigger('click');
    return wrapper.emitted('salvar').at(-1)[0].valor;
  };

  it('escolher "Sem prazo" já marca 8h e mostra a escolha da hora', async () => {
    const wrapper = await montar(espera());

    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', SEM_PRAZO);
    await flushPromises();

    expect(escolhaDaHora(wrapper).props('modelValue')).toBe(8);
    expect(escolhaDaHora(wrapper).props('options')).toHaveLength(25);
    expect(await salvo(wrapper)).toMatchObject({
      prazo: SEM_PRAZO,
      conferir_as: 8,
    });
  });

  it('a pessoa troca a hora, ou volta a conferir a cada mudança', async () => {
    const wrapper = await montar(espera({ prazo: SEM_PRAZO, conferir_as: 8 }));

    escolhaDaHora(wrapper).vm.$emit('update:modelValue', 7);
    await flushPromises();
    expect((await salvo(wrapper)).conferir_as).toBe(7);

    escolhaDaHora(wrapper).vm.$emit('update:modelValue', 'ao_mudar');
    await flushPromises();
    expect(await salvo(wrapper)).not.toHaveProperty('conferir_as');
  });

  it('a espera sem prazo antiga, sem hora, segue "a cada mudança" até a pessoa escolher', async () => {
    const wrapper = await montar(espera({ prazo: SEM_PRAZO }));

    expect(escolhaDaHora(wrapper).props('modelValue')).toBe('ao_mudar');
    expect(await salvo(wrapper)).not.toHaveProperty('conferir_as');
  });

  it('voltar para "Até um prazo" tira a hora: ela só vale sem prazo', async () => {
    const wrapper = await montar(espera({ prazo: SEM_PRAZO, conferir_as: 8 }));

    escolhaDoPrazo(wrapper).vm.$emit('update:modelValue', 'com_prazo');
    await flushPromises();

    expect(wrapper.find('[data-conferir-as]').exists()).toBe(false);
    expect(await salvo(wrapper)).not.toHaveProperty('conferir_as');
  });

  it('a frase diz a hora da conferência', () => {
    const frase = fraseDoPasso(
      espera({ prazo: SEM_PRAZO, conferir_as: 8 }),
      CATALOGO,
      t
    );

    expect(
      frase.startsWith('AUTOMACAO_LIVRE.FRASES.ESPERAR_ATE_SEM_PRAZO_AS ')
    ).toBe(true);
    expect(frase).toContain('"hora":8');
  });
});
