import { mount } from '@vue/test-utils';
import LivreRetornoPara from '../components/LivreRetornoPara.vue';
import LivreRetornoEnvio from '../components/LivreRetornoEnvio.vue';
import LivreRetornoQuando from '../components/LivreRetornoQuando.vue';
import {
  envioPronto,
  fraseDoRetorno,
  paraPronto,
  quandoDoRetorno,
  quandoPronto,
} from '../retorno';

// G3 (#2629) — o passo "criar retorno" no editor: a frase diz para quem, quando
// e se manda mensagem; o "Salvar" espera a escolha de pessoas ou do time e a
// mensagem escrita; desligar a mensagem tira o campo da receita.
const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const R = 'AUTOMACAO_LIVRE.RETORNO';
const palavras = { quando: '2 dias', titulo: 'Ligar', mensagem: 'Oi' };

describe('fraseDoRetorno', () => {
  it.each([
    [undefined, `${R}.QUEM.RESPONSAVEL`],
    [{ quem: 'pessoas', pessoas: [1, 2] }, `${R}.QUEM.PESSOAS(2)`],
    [{ quem: 'time', time: 3 }, `${R}.QUEM.TIME`],
  ])('para %o diz %s', (para, quem) => {
    expect(fraseDoRetorno({ para }, t, palavras)).toBe(
      `${R}.FRASE(${quem},2 dias,Ligar,Oi)`
    );
  });

  it('com a mensagem, usa a frase que fala dela', () => {
    expect(
      fraseDoRetorno({ envio: { mensagem: ['Oi'] } }, t, palavras)
    ).toContain(`${R}.FRASE_COM_MENSAGEM(`);
  });
});

describe('pronto para salvar', () => {
  it.each([
    [undefined, true],
    [{ quem: 'responsavel' }, true],
    [{ quem: 'pessoas', pessoas: [] }, false],
    [{ quem: 'pessoas', pessoas: [4] }, true],
    [{ quem: 'time' }, false],
    [{ quem: 'time', time: 3 }, true],
  ])('para %o: %s', (para, pronto) => {
    expect(paraPronto(para)).toBe(pronto);
  });

  it.each([
    [null, true],
    [{ mensagem: [] }, false],
    [{ mensagem: ['  '] }, false],
    [{ mensagem: [{ $valor: 'contato.nome' }] }, true],
  ])('envio %o: %s', (envio, pronto) => {
    expect(envioPronto(envio)).toBe(pronto);
  });
});

const global = { mocks: { $t: t } };

describe('LivreRetornoPara', () => {
  const montar = modelValue =>
    mount(LivreRetornoPara, {
      props: {
        rotulo: 'PARA',
        modelValue,
        opcoes: {
          pessoa: [{ value: 4, label: 'Bia' }],
          time: [{ value: 3, label: 'Vendas' }],
        },
      },
      global,
    });

  it('sem escolha vale o responsável, sem pedir pessoas nem time', () => {
    const wrapper = montar(null);

    expect(wrapper.find('[data-pessoas]').exists()).toBe(false);
    expect(wrapper.find('[data-time]').exists()).toBe(false);
  });

  it('trocar quem recebe recomeça a escolha', () => {
    const wrapper = montar({ quem: 'pessoas', pessoas: [4] });

    wrapper.findComponent('[data-quem]').vm.$emit('update:modelValue', 'time');

    expect(wrapper.emitted('update:modelValue')).toEqual([[{ quem: 'time' }]]);
  });

  it('pessoas e time mostram a escolha de cada um', () => {
    expect(
      montar({ quem: 'pessoas', pessoas: [] }).find('[data-pessoas]').exists()
    ).toBe(true);
    expect(montar({ quem: 'time' }).find('[data-time]').exists()).toBe(true);
  });
});

describe('LivreRetornoEnvio', () => {
  const montar = modelValue =>
    mount(LivreRetornoEnvio, {
      props: {
        rotulo: 'ENVIO',
        modelValue,
        catalogo: { valores: [] },
        atributosDo: () => [],
      },
      global,
    });

  it('desligado, avisa que é só o lembrete; ligar abre a mensagem vazia', () => {
    const wrapper = montar(null);

    expect(wrapper.text()).toContain(`${R}.SO_LEMBRETE`);
    wrapper.findComponent('[data-mandar]').vm.$emit('update:modelValue', true);

    expect(wrapper.emitted('update:modelValue')).toEqual([[{ mensagem: [] }]]);
  });

  it('desligar tira a mensagem da receita', () => {
    const wrapper = montar({ mensagem: ['Oi'] });

    expect(wrapper.find('[data-mensagem]').exists()).toBe(true);
    wrapper.findComponent('[data-mandar]').vm.$emit('update:modelValue', false);

    expect(wrapper.emitted('update:modelValue')).toEqual([[null]]);
  });
});

// G57 (#2769): o retorno vence daqui a um tempo, ou hoje/amanhã numa hora ou no
// fim do dia, no fuso da conta.
describe('quando do retorno', () => {
  it.each([
    [{ daqui: { valor: 2 } }, `${R}.QUANDO.FRASE_DAQUI(2 dias)`],
    [{ quando: { dia: 'hoje' } }, `${R}.QUANDO.FRASE_HOJE`],
    [{ quando: { dia: 'hoje', hora: 14 } }, `${R}.QUANDO.FRASE_HOJE_AS(14)`],
    [{ quando: { dia: 'amanha' } }, `${R}.QUANDO.FRASE_AMANHA`],
    [{ quando: { dia: 'amanha', hora: 0 } }, `${R}.QUANDO.FRASE_AMANHA_AS(0)`],
  ])('%o diz %s', (passo, frase) => {
    expect(quandoDoRetorno(passo, t, '2 dias')).toBe(frase);
  });

  it.each([
    [{ daqui: { valor: 1, unidade: 'dias' } }, true],
    [{ daqui: { valor: null } }, false],
    [{ quando: { dia: 'hoje' } }, true],
    [{ quando: {} }, false],
  ])('%o pronto: %s', (passo, pronto) => {
    expect(quandoPronto(passo)).toBe(pronto);
  });

  const montar = props =>
    mount(LivreRetornoQuando, {
      props: {
        rotulo: 'QUANDO',
        unidades: [],
        daqui: null,
        quando: null,
        ...props,
      },
      global,
    });

  it('do "daqui" para "hoje" tira o daqui e começa no fim do dia', () => {
    const wrapper = montar({ daqui: { valor: 2, unidade: 'dias' } });

    wrapper
      .findComponent('[data-quando-modo]')
      .vm.$emit('update:modelValue', 'hoje');

    expect(wrapper.emitted('update')).toEqual([
      [{ daqui: null, quando: { dia: 'hoje' } }],
    ]);
  });

  it('a hora escolhida entra; "até o fim do dia" a tira', () => {
    const wrapper = montar({ quando: { dia: 'amanha', hora: 9 } });
    const hora = wrapper.findComponent('[data-quando-hora]');

    hora.vm.$emit('update:modelValue', '14');
    hora.vm.$emit('update:modelValue', 'fim');

    expect(wrapper.emitted('update')).toEqual([
      [{ daqui: null, quando: { dia: 'amanha', hora: 14 } }],
      [{ daqui: null, quando: { dia: 'amanha' } }],
    ]);
  });

  it('voltar para "daqui" volta a um dia, sem o quando', () => {
    const wrapper = montar({ quando: { dia: 'hoje' } });

    wrapper
      .findComponent('[data-quando-modo]')
      .vm.$emit('update:modelValue', 'daqui');

    expect(wrapper.emitted('update')).toEqual([
      [{ daqui: { valor: 1, unidade: 'dias' }, quando: null }],
    ]);
  });
});
