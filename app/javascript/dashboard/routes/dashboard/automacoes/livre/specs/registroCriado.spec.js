import { mount } from '@vue/test-utils';
import { comTextosDaIa, tipoCriado } from '../catalogo';
import {
  alvoDaLista,
  alvoDoRamo,
  fraseDoOutroRegistro,
} from '../outroRegistro';
import { registroPronto } from '../receita';
import LivreRegistro from '../components/LivreRegistro.vue';

// G49 — o registro que um passo cria (o card do "criar card", o contato de uma
// ação que cria contato) vira dado dos passos seguintes (`criado.<id>`) e lugar
// onde o "em outro registro" roda (`criado_no_passo`).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave}(${Object.values(valores).join(',')})` : chave,
  }),
}));

const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;

const ChoiceFalso = {
  name: 'ChoiceSelect',
  props: ['modelValue', 'options', 'ariaLabel', 'placeholder'],
  emits: ['update:modelValue'],
  template: '<div />',
};

const criarContato = {
  id: 'p3a',
  tipo: 'acao',
  acao: 'POST contacts',
  corpo: { name: 'João' },
};
const criarCard = { id: 'p3b', tipo: 'card', etapa_id: 7 };
const noCardCriado = {
  id: 'p5',
  tipo: 'em_outro_registro',
  registro: { de: 'criado_no_passo', passo: 'p3b' },
  passos: [{ id: 'm1', tipo: 'mensagem', texto: ['Oi'] }],
};

describe('os registros criados no catálogo do editor', () => {
  it('só o "criar card" e as ações que criam contato criam registro', () => {
    expect(tipoCriado(criarCard)).toBe('Crm::Card');
    expect(tipoCriado(criarContato)).toBe('Contact');
    expect(
      tipoCriado({ id: 'x', tipo: 'acao', acao: 'PATCH contacts/:id' })
    ).toBeNull();
    expect(tipoCriado({ id: 'm', tipo: 'mensagem' })).toBeNull();
  });

  it('cada registro criado vira um dado com o tipo e o rótulo pronto', () => {
    const valores = comTextosDaIa(
      { valores: [{ caminho: 'contato.nome', frase: 'NOME' }] },
      [criarContato, criarCard],
      t
    ).valores;

    expect(valores.slice(1)).toEqual([
      {
        caminho: 'criado.p3a',
        chave: 'p3a',
        criado: 'Contact',
        rotulo: 'AUTOMACAO_LIVRE.CRIADO.CONTATO',
      },
      {
        caminho: 'criado.p3b',
        chave: 'p3b',
        criado: 'Crm::Card',
        rotulo: 'AUTOMACAO_LIVRE.CRIADO.CARD',
      },
    ]);
  });
});

describe('o "em outro registro" no registro criado', () => {
  it('roda no tipo do registro que o passo escolhido cria, como o servidor', () => {
    const passos = [criarContato, criarCard, noCardCriado];

    expect(alvoDoRamo(noCardCriado, passos)).toBe('Crm::Card');
    expect(
      alvoDoRamo(
        { ...noCardCriado, registro: { de: 'criado_no_passo', passo: 'p3a' } },
        passos
      )
    ).toBe('Contact');
    expect(alvoDaLista(passos, 'p5:passos')).toBe('Crm::Card');
  });

  it('fica pronto com o passo escolhido e a frase diz qual registro', () => {
    expect(registroPronto({ de: 'criado_no_passo' })).toBe(false);
    expect(registroPronto(noCardCriado.registro)).toBe(true);
    expect(fraseDoOutroRegistro(noCardCriado, t, 'Card criado')).toBe(
      'AUTOMACAO_LIVRE.OUTRO_REGISTRO.FRASE.CRIADO(Card criado)'
    );
  });

  const montar = valores =>
    mount(LivreRegistro, {
      props: {
        rotulo: 'ONDE',
        modelValue: {},
        catalogo: { alvo: 'Conversation', alvos: {}, valores },
        atributosDo: () => [],
      },
      global: { stubs: { ChoiceSelect: ChoiceFalso, LivreMarcar: true } },
    });

  it('só oferece a ligação quando um passo da execução cria registro, e grava o passo escolhido', async () => {
    const sem = montar([]);
    expect(
      sem
        .findAllComponents(ChoiceFalso)[0]
        .props('options')
        .map(opcao => opcao.value)
    ).toEqual(['contato_do_campo']);

    const comCriado = montar([
      {
        caminho: 'criado.p3b',
        chave: 'p3b',
        criado: 'Crm::Card',
        rotulo: 'Card criado',
      },
    ]);
    await comCriado.setProps({ modelValue: { de: 'criado_no_passo' } });
    const escolha = comCriado.find('[data-criado]');
    expect(escolha.exists()).toBe(true);
    expect(comCriado.findComponent('[data-criado]').props('options')).toEqual([
      { value: 'p3b', label: 'Card criado' },
    ]);
    comCriado
      .findComponent('[data-criado]')
      .vm.$emit('update:modelValue', 'p3b');
    expect(comCriado.emitted('update:modelValue').at(-1)).toEqual([
      { de: 'criado_no_passo', passo: 'p3b' },
    ]);
  });
});
