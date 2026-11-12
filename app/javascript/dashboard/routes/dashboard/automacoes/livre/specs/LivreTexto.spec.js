import { mount } from '@vue/test-utils';
import LivreTexto from '../components/LivreTexto.vue';

// #2486 — o dado de um campo que a conta apagou fica no texto, marcado, com o
// aviso no painel; não volta para a lista do "Pôr um dado".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) => (valores ? `${chave} ${valores.dado}` : chave),
  }),
}));

const CATALOGO = {
  valores: [
    { caminho: 'contato.nome', frase: 'NOME' },
    {
      caminho: 'contato.atributos',
      atributos: 'contact_attribute',
      frase: 'ATRIB',
    },
  ],
};

const montar = (modelValue, extra = {}) =>
  mount(LivreTexto, {
    props: {
      rotulo: 'TEXTO',
      modelValue,
      catalogo: CATALOGO,
      atributosDo: () => [],
      ...extra,
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        TextArea: {
          props: ['modelValue'],
          template: '<textarea :value="modelValue" />',
        },
        Input: {
          props: ['modelValue', 'message'],
          template:
            '<input data-uma-linha :value="modelValue" :data-contagem="message" />',
        },
        ChoiceSelect: {
          props: ['options'],
          template: '<div data-opcoes>{{ options.map(o => o.label) }}</div>',
        },
      },
    },
  });

describe('LivreTexto', () => {
  it('campo apagado aparece marcado, com aviso, e fica fora do "Pôr um dado"', () => {
    const wrapper = montar(['Placa: ', { $valor: 'contato.atributos.placa' }]);

    expect(wrapper.find('textarea').element.value).toContain(
      '[AUTOMACAO_LIVRE.ALTERAR_PAINEL.DADO_APAGADO'
    );
    expect(wrapper.find('[data-dado-apagado]').exists()).toBe(true);
    expect(wrapper.find('[data-opcoes]').text()).not.toContain('DADO_APAGADO');
  });

  // G2: o assunto do e-mail é uma linha curta, e o "Pôr um dado" diz em qual
  // caixa o dado entra.
  it('em uma linha: input de 150 com contagem, e o rótulo do dado vem de fora', () => {
    const wrapper = montar(['Oi ', { $valor: 'contato.nome' }], {
      umaLinha: true,
      rotuloDoDado: 'Pôr um dado em Assunto',
    });

    const linha = wrapper.find('[data-uma-linha]');
    expect(linha.element.value).toBe('Oi [NOME]');
    expect(linha.attributes('maxlength')).toBe('150');
    expect(linha.attributes('data-contagem')).toBe('9 / 150');
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.find('label').text()).toBe('Pôr um dado em Assunto');
  });

  // #2744: no gatilho de card, o "Pôr um dado" fala do card, não da conversa;
  // no de contato, do contato; sem gatilho, só "Pôr um dado".
  it.each([
    [{ alvo: 'Crm::Card' }, 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO.CARD'],
    [
      {
        gatilho: 'contato.criado',
        gatilhos: [{ tipo: 'contato.criado', alvo: 'Contact' }],
      },
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO.CONTATO',
    ],
    [
      { alvo: 'Conversation' },
      'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO.CONVERSA',
    ],
    [{}, 'AUTOMACAO_LIVRE.ALTERAR_PAINEL.POR_DADO.OUTRO'],
  ])('o "Pôr um dado" acompanha o alvo %o', (doAlvo, rotulo) => {
    const wrapper = montar([], { catalogo: { ...CATALOGO, ...doAlvo } });

    expect(wrapper.find('label').text()).toBe(rotulo);
  });

  it('sem dado apagado, sem aviso', () => {
    const wrapper = montar(['Oi ', { $valor: 'contato.nome' }]);

    expect(wrapper.find('textarea').element.value).toBe('Oi [NOME]');
    expect(wrapper.find('[data-dado-apagado]').exists()).toBe(false);
  });
});
