import { mount } from '@vue/test-utils';
import LivreData from '../components/LivreData.vue';
import { dataCompleta, temDataIncompleta } from '../texto';

// #2414 G16b — o atributo do tipo data numa ação: um dia certo ou uma data
// calculada (a partir de hoje ou de outro campo de data). Uma pergunta por vez;
// a data pela metade segura o "Salvar".
const t = (chave, valores, n) =>
  `${chave}${valores && Object.keys(valores).length ? `(${Object.values(valores).join(',')})` : ''}${n === undefined ? '' : `#${n}`}`;

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));

const CATALOGO = {
  valores: [
    { caminho: 'contato.nome', frase: 'NOME' },
    {
      caminho: 'contato.atributos',
      atributos: 'contact_attribute',
      frase: 'CONTATO',
    },
  ],
};
const ATRIBUTOS = [
  {
    attribute_key: 'nascimento',
    attribute_display_name: 'Nascimento',
    attribute_display_type: 'date',
  },
  {
    attribute_key: 'apelido',
    attribute_display_name: 'Apelido',
    attribute_display_type: 'text',
  },
];

const montar = (modelValue, atributos = ATRIBUTOS) =>
  mount(LivreData, {
    props: {
      rotulo: 'Revisão',
      modelValue,
      catalogo: CATALOGO,
      atributosDo: () => atributos,
    },
    global: {
      mocks: { $t: t },
      stubs: {
        ChoiceSelect: {
          props: ['modelValue', 'options'],
          emits: ['update:modelValue'],
          template:
            '<div data-escolha :data-valor="modelValue"><button v-for="o in options" :key="o.value" :data-opcao="o.value" @click="$emit(\'update:modelValue\', o.value)">{{ o.label }}</button></div>',
        },
        Input: {
          props: ['modelValue', 'type', 'message'],
          emits: ['update:modelValue'],
          template:
            '<input :type="type" :value="modelValue" :data-mensagem="message" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

const escolher = (wrapper, onde, valor) =>
  wrapper.find(`[${onde}] [data-opcao="${valor}"]`).trigger('click');
const ultimo = wrapper => wrapper.emitted('update:modelValue').at(-1)[0];

describe('LivreData', () => {
  it('começa só com a primeira pergunta', () => {
    const wrapper = montar(null);

    expect(wrapper.findAll('[data-escolha]')).toHaveLength(1);
    expect(wrapper.find('[data-data-quanto]').exists()).toBe(false);
    expect(wrapper.find('[data-data-frase]').exists()).toBe(false);
  });

  it('um dia certo grava "AAAA-MM-DD" e mostra a frase', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'dia');
    await wrapper.find('input[type="date"]').setValue('2027-05-04');

    expect(ultimo(wrapper)).toBe('2027-05-04');
    await wrapper.setProps({ modelValue: '2027-05-04' });
    const dia = new Date(2027, 4, 4, 12).toLocaleDateString();
    expect(wrapper.find('[data-data-frase]').text()).toBe(
      `AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.GRAVA(${dia})`
    );
  });

  it('a partir de hoje: pergunta quanto, com N vazio fica pela metade', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'hoje');

    expect(wrapper.find('[data-data-quanto]').exists()).toBe(true);
    const dica = wrapper.find('[data-data-zero]');
    expect(dica.text()).toBe('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.ZERO');
    expect(
      wrapper.find('[data-data-numero]').attributes('aria-describedby')
    ).toBe(dica.attributes('id'));
    expect(ultimo(wrapper)).toEqual({
      $data: { de: 'hoje', mais: { valor: null, unidade: 'dias' } },
    });
    expect(temDataIncompleta({ x: ultimo(wrapper) })).toBe(true);
  });

  it('hoje + 6 meses vira { $data } e a frase "Grava: …"', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'hoje');
    await wrapper.find('[data-data-numero]').setValue('6');
    await escolher(wrapper, 'data-data-unidade', 'meses');

    const valor = ultimo(wrapper);
    expect(valor).toEqual({
      $data: { de: 'hoje', mais: { valor: 6, unidade: 'meses' } },
    });
    await wrapper.setProps({ modelValue: valor });
    expect(wrapper.find('[data-data-frase]').text()).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.GRAVA(AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA_MAIS(AUTOMACAO_LIVRE.ALTERAR_PAINEL.HOJE,6,AUTOMACAO_LIVRE.UNIDADES.MESES#6))'
    );
  });

  it('com o Input de verdade, a dica descreve o <input> do número', () => {
    const wrapper = mount(LivreData, {
      props: {
        rotulo: 'Revisão',
        modelValue: { $data: { de: 'hoje' } },
        catalogo: CATALOGO,
        atributosDo: () => ATRIBUTOS,
      },
      global: {
        mocks: { $t: t },
        stubs: { ChoiceSelect: { template: '<div />' } },
      },
    });

    const numero = wrapper.find('input[type="number"]');
    expect(numero.attributes('aria-describedby')).toBe(
      wrapper.find('[data-data-zero]').attributes('id')
    );
  });

  it('"antes" grava o número negativo; zero tira o "mais"', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'hoje');
    await wrapper.find('[data-data-numero]').setValue('2');
    await escolher(wrapper, 'data-data-sentido', 'antes');
    expect(ultimo(wrapper).$data.mais).toEqual({ valor: -2, unidade: 'dias' });

    await wrapper.find('[data-data-numero]').setValue('0');
    expect(ultimo(wrapper)).toEqual({ $data: { de: 'hoje' } });
  });

  it('reabre o zero salvo como 0, não como número vazio', () => {
    const wrapper = montar({ $data: { de: 'hoje' } });

    expect(wrapper.find('[data-data-numero]').element.value).toBe('0');
    expect(wrapper.find('[data-data-frase]').exists()).toBe(true);
  });

  it('o número que não vale ganha a mensagem; o válido e o vazio, não', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'hoje');
    const numero = () => wrapper.find('[data-data-numero]');
    expect(numero().attributes('data-mensagem')).toBeFalsy();

    await numero().setValue('-3');
    expect(numero().attributes('data-mensagem')).toBe(
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.DATA.NUMERO_INVALIDO(3650)'
    );
    await numero().setValue('12');
    expect(numero().attributes('data-mensagem')).toBeFalsy();
  });

  it('campo de data apagado da conta: continua na escolha, marcado, com o aviso', () => {
    const wrapper = montar(
      {
        $data: {
          de: { $valor: 'contato.atributos.vencimento' },
          mais: { valor: 1, unidade: 'anos' },
        },
      },
      ATRIBUTOS
    );

    expect(
      wrapper.find('[data-opcao="contato.atributos.vencimento"]').text()
    ).toContain('AUTOMACAO_LIVRE.ALTERAR_PAINEL.DADO_APAGADO');
    expect(wrapper.find('[data-data-campo-apagado]').exists()).toBe(true);

    const valido = montar({
      $data: { de: { $valor: 'contato.atributos.nascimento' } },
    });
    expect(valido.find('[data-data-campo-apagado]').exists()).toBe(false);
  });

  it('número quebrado, negativo ou acima do teto não vale', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'hoje');
    await wrapper.find('[data-data-numero]').setValue('1.5');
    expect(ultimo(wrapper).$data.mais.valor).toBeNull();
    await wrapper.find('[data-data-numero]').setValue('-3');
    expect(ultimo(wrapper).$data.mais.valor).toBeNull();
    await wrapper.find('[data-data-numero]').setValue('3651');
    expect(ultimo(wrapper).$data.mais.valor).toBeNull();
    await wrapper.find('[data-data-numero]').setValue('3650');
    expect(ultimo(wrapper).$data.mais.valor).toBe(3650);
  });

  it('a partir de um campo: só campos de data; "quanto" só depois de escolher', async () => {
    const wrapper = montar(null);
    await escolher(wrapper, 'data-data-modo', 'campo');

    const campos = wrapper.findAll('[data-data-campo] [data-opcao]');
    expect(campos.map(c => c.attributes('data-opcao'))).toEqual([
      'contato.atributos.nascimento',
    ]);
    expect(wrapper.find('[data-data-quanto]').exists()).toBe(false);
    expect(temDataIncompleta(ultimo(wrapper))).toBe(true);

    await escolher(wrapper, 'data-data-campo', 'contato.atributos.nascimento');
    expect(wrapper.find('[data-data-quanto]').exists()).toBe(true);
    await wrapper.find('[data-data-numero]').setValue('1');
    await escolher(wrapper, 'data-data-unidade', 'anos');
    expect(ultimo(wrapper)).toEqual({
      $data: {
        de: { $valor: 'contato.atributos.nascimento' },
        mais: { valor: 1, unidade: 'anos' },
      },
    });
    await wrapper.setProps({ modelValue: ultimo(wrapper) });
    expect(wrapper.find('[data-data-frase]').text()).toContain(
      'AUTOMACAO_LIVRE.FRASES.ATRIBUTO(CONTATO,Nascimento)'
    );
  });

  it('sem outro campo de data, diz isso em vez de abrir a escolha', async () => {
    const wrapper = montar(null, [ATRIBUTOS[1]]);
    await escolher(wrapper, 'data-data-modo', 'campo');

    expect(wrapper.find('[data-data-campo]').exists()).toBe(false);
    expect(wrapper.find('[data-data-sem-campo]').exists()).toBe(true);
  });

  it('reabre o que foi salvo: modo, número, unidade e sentido', () => {
    const wrapper = montar({
      $data: {
        de: { $valor: 'contato.atributos.nascimento' },
        mais: { valor: -3, unidade: 'semanas' },
      },
    });

    expect(wrapper.find('[data-data-modo]').attributes('data-valor')).toBe(
      'campo'
    );
    expect(wrapper.find('[data-data-numero]').element.value).toBe('3');
    expect(wrapper.find('[data-data-unidade]').attributes('data-valor')).toBe(
      'semanas'
    );
    expect(wrapper.find('[data-data-sentido]').attributes('data-valor')).toBe(
      'antes'
    );
  });

  it('reescolher "um dia certo" não apaga o dia já gravado', async () => {
    const wrapper = montar('2027-05-04');
    await escolher(wrapper, 'data-data-modo', 'dia');

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('reabre a data pela metade sem inventar: campo sem escolha, número vazio', () => {
    const semCampo = montar({ $data: { de: '' } });
    expect(semCampo.find('[data-data-modo]').attributes('data-valor')).toBe(
      'campo'
    );

    const semNumero = montar({
      $data: { de: 'hoje', mais: { valor: null, unidade: 'meses' } },
    });
    expect(semNumero.find('[data-data-numero]').element.value).toBe('');
    expect(semNumero.find('[data-data-frase]').exists()).toBe(false);
  });

  it('o número salvo acima do teto conta como pela metade', () => {
    expect(
      temDataIncompleta({
        a: { $data: { de: 'hoje', mais: { valor: 5000, unidade: 'dias' } } },
      })
    ).toBe(true);
    expect(
      temDataIncompleta({
        a: { $data: { de: 'hoje', mais: { valor: -3650, unidade: 'dias' } } },
      })
    ).toBe(false);
  });

  it('voltar para "um dia certo" tira a data calculada', async () => {
    const wrapper = montar({ $data: { de: 'hoje' } });
    await escolher(wrapper, 'data-data-modo', 'dia');

    expect(ultimo(wrapper)).toBeNull();
  });
});

describe('dataCompleta e temDataIncompleta', () => {
  it('pede o ponto de partida e, com "mais", um número inteiro', () => {
    expect(dataCompleta({ de: 'hoje' })).toBe(true);
    expect(
      dataCompleta({ de: 'hoje', mais: { valor: -1, unidade: 'dias' } })
    ).toBe(true);
    expect(dataCompleta({ de: '' })).toBe(false);
    expect(
      dataCompleta({ de: 'hoje', mais: { valor: null, unidade: 'dias' } })
    ).toBe(false);
  });

  it('acha a data pela metade em qualquer nível do corpo', () => {
    expect(
      temDataIncompleta({
        contact: { custom_attributes: { a: { $data: { de: '' } } } },
      })
    ).toBe(true);
    expect(
      temDataIncompleta({ a: '2027-01-01', b: { $data: { de: 'hoje' } } })
    ).toBe(false);
    expect(temDataIncompleta(undefined)).toBe(false);
  });
});
