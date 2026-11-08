import { mount } from '@vue/test-utils';
import LivreGatilho from '../components/LivreGatilho.vue';
import LivreSelecao from '../components/LivreSelecao.vue';
import { fraseDoGatilho } from '../frases';

// #2635 (G7) — o recorrente no editor: a frequência, o dia que ela pede (da
// semana no semanal, do mês no mensal), a hora e a seleção dos cards ou dos
// contatos. A condição em branco não vai na receita.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave,
  }),
}));

const parametro = nome => ({
  nome,
  peca: nome,
  obrigatorio: true,
  frase: `AUTOMACAO_LIVRE.PARAMETROS_DO_GATILHO.${nome.toUpperCase()}`,
});
const DO_RECORRENTE = [
  'frequencia',
  'dia_da_semana',
  'dia_do_mes',
  'hora',
  'selecao',
].map(parametro);
const recorrente = (tipo, alvo, chave) => ({
  tipo,
  alvo,
  frase: `AUTOMACAO_LIVRE.GATILHOS.${chave}`,
  grupo: 'tempo',
  parametros: DO_RECORRENTE,
});
const GATILHOS = [
  recorrente('card.recorrente', 'Crm::Card', 'CARD_RECORRENTE'),
  recorrente('contato.recorrente', 'Contact', 'CONTATO_RECORRENTE'),
  {
    ...recorrente('conta.recorrente', 'Account', 'CONTA_RECORRENTE'),
    parametros: DO_RECORRENTE.filter(item => item.nome !== 'selecao'),
  },
];
const CATALOGO = { gatilhos: GATILHOS };

const montar = modelValue =>
  mount(LivreGatilho, {
    props: { modelValue, gatilhos: GATILHOS, escolhas: {}, opcoes: {} },
    global: { mocks: { $t: chave => chave } },
  });
const ultimo = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];
const seletorDe = (wrapper, nome) =>
  wrapper
    .find(`[data-parametro="${nome}"]`)
    .findComponent({ name: 'ChoiceSelect' });

describe('gatilho recorrente', () => {
  it('ao escolher, vem todo dia às 8h, com a seleção vazia', () => {
    const wrapper = montar(null);
    wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'contato.recorrente');

    expect(ultimo(wrapper)).toEqual({
      tipo: 'contato.recorrente',
      frequencia: 'diaria',
      hora: 8,
      selecao: {},
    });
  });

  it('o da conta vem sem seleção e avisa que roda uma vez só', () => {
    const wrapper = montar(null);
    wrapper
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'conta.recorrente');

    expect(ultimo(wrapper)).toEqual({
      tipo: 'conta.recorrente',
      frequencia: 'diaria',
      hora: 8,
    });
    const conta = montar({
      tipo: 'conta.recorrente',
      frequencia: 'diaria',
      hora: 8,
    });
    expect(conta.find('[data-parametro="selecao"]').exists()).toBe(false);
    // #2680: a conta não tem com quem abrir conversa; o card e o contato têm.
    expect(conta.find('[data-parametro="conversa_nova"]').exists()).toBe(false);
    expect(conta.text()).toContain(
      'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.AVISO_CONTA'
    );
  });

  it('o dia da semana só no semanal, o do mês só no mensal', () => {
    const base = { tipo: 'card.recorrente', hora: 8, selecao: {} };
    const nomes = wrapper =>
      wrapper
        .findAll('[data-parametro]')
        .map(item => item.attributes('data-parametro'));

    expect(nomes(montar({ ...base, frequencia: 'diaria' }))).toEqual([
      'frequencia',
      'hora',
      'selecao',
      'conversa_nova',
    ]);
    expect(
      nomes(montar({ ...base, frequencia: 'semanal', dia_da_semana: 1 }))
    ).toContain('dia_da_semana');
    expect(
      nomes(montar({ ...base, frequencia: 'mensal', dia_do_mes: 5 }))
    ).toEqual(['frequencia', 'dia_do_mes', 'hora', 'selecao', 'conversa_nova']);
  });

  it('trocar a frequência troca o dia: segunda no semanal, e o do mês sai', () => {
    const wrapper = montar({
      tipo: 'card.recorrente',
      frequencia: 'mensal',
      dia_do_mes: 5,
      hora: 9,
      selecao: { situacao: 'aberto' },
    });
    seletorDe(wrapper, 'frequencia').vm.$emit('update:modelValue', 'semanal');

    expect(ultimo(wrapper)).toEqual({
      tipo: 'card.recorrente',
      frequencia: 'semanal',
      dia_da_semana: 1,
      hora: 9,
      selecao: { situacao: 'aberto' },
    });
  });

  it('a frase diz quando e em quem', () => {
    const t = (chave, valores) =>
      valores ? `${chave} ${Object.values(valores).join(' ')}` : chave;
    const semanal = {
      tipo: 'card.recorrente',
      frequencia: 'semanal',
      dia_da_semana: 4,
      hora: 9,
      selecao: { situacao: 'aberto' },
    };

    expect(fraseDoGatilho(semanal, CATALOGO, t)).toBe(
      'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.FRASE.SEMANAL AUTOMACAO_LIVRE.GATILHO_RECORRENTE.DIAS_DA_SEMANA.4 9 AUTOMACAO_LIVRE.GATILHO_RECORRENTE.CARDS'
    );
    expect(
      fraseDoGatilho({ ...semanal, dia_da_semana: undefined }, CATALOGO, t)
    ).toBe('AUTOMACAO_LIVRE.GATILHOS.CARD_RECORRENTE');
    expect(
      fraseDoGatilho(
        { tipo: 'conta.recorrente', frequencia: 'diaria', hora: 8 },
        CATALOGO,
        t
      )
    ).toBe(
      'AUTOMACAO_LIVRE.GATILHO_RECORRENTE.FRASE.DIARIA  8 AUTOMACAO_LIVRE.GATILHO_RECORRENTE.CONTA'
    );
  });
});

describe('seleção do recorrente', () => {
  const montarSelecao = (alvo, modelValue = {}) =>
    mount(LivreSelecao, {
      props: {
        modelValue,
        alvo,
        escolhas: { funis: [{ value: 3, label: 'Vendas' }], etapas: [] },
        opcoes: {
          pessoa: [{ value: 7, label: 'Ana' }],
          etiquetaPorNome: [{ value: 'vip', label: 'vip' }],
          atributoDoContato: [{ value: 'plano', label: 'Plano' }],
        },
      },
      global: { mocks: { $t: chave => chave } },
    });
  const condicao = (wrapper, nome) => wrapper.find(`[data-condicao="${nome}"]`);
  const ultimoDa = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

  it('card: a situação entra; "Qualquer" tira a condição', () => {
    const wrapper = montarSelecao('Crm::Card', { funil_id: 3 });
    const situacao = condicao(wrapper, 'situacao').findComponent({
      name: 'ChoiceSelect',
    });
    situacao.vm.$emit('update:modelValue', 'perdido');
    expect(ultimoDa(wrapper)).toEqual({ funil_id: 3, situacao: 'perdido' });

    condicao(wrapper, 'funil_id')
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', '');
    expect(ultimoDa(wrapper)).toEqual({});
  });

  it('card: "fechado entre" guarda a primeira ponta e entra com as duas', async () => {
    const wrapper = montarSelecao('Crm::Card');
    const pontas = () =>
      condicao(wrapper, 'fechado_entre_dias').findAllComponents({
        name: 'Input',
      });
    pontas()[0].vm.$emit('update:modelValue', '330');
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(pontas()[0].props('modelValue')).toBe('330');

    pontas()[1].vm.$emit('update:modelValue', '360');
    expect(ultimoDa(wrapper)).toEqual({
      fechado_entre_dias: { de: 330, ate: 360 },
    });

    await wrapper.setProps({ modelValue: ultimoDa(wrapper) });
    pontas()[1].vm.$emit('update:modelValue', '');
    expect(ultimoDa(wrapper)).toEqual({});
  });

  it('contato: só as condições do contato; o campo vai com o valor', () => {
    const wrapper = montarSelecao('Contact');
    expect(condicao(wrapper, 'funil_id').exists()).toBe(false);

    condicao(wrapper, 'atributo')
      .findComponent({ name: 'ChoiceSelect' })
      .vm.$emit('update:modelValue', 'plano');
    expect(ultimoDa(wrapper)).toEqual({
      atributo: { chave: 'plano', valor: '' },
    });
  });
});
