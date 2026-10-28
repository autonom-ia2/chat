import { mount } from '@vue/test-utils';
import PerdaDeAcesso from '../guiada/PerdaDeAcesso.vue';
import { global } from './montar';

// #2308, especificação 5.F: "5 pessoas vão deixar de mudar os contatos" / os nomes / "Essas pessoas têm a função
// Vendedor. A partir de agora, só vão olhar os contatos." (rodada 4: faltava a frase do que fica).
const montar = props =>
  mount(PerdaDeAcesso, {
    attachTo: document.body,
    props: {
      nome: 'Vendedor',
      pessoas: ['Ana', 'Beto'].map((name, id) => ({ id, name })),
      perdas: [{ id: 'MUDAR_CONTATOS' }],
      ...props,
    },
    global: global(),
  });

describe('PerdaDeAcesso', () => {
  it('uma perda numa queda de nível: diz o que fica', () => {
    const wrapper = montar({ fica: { area: 'CONTACTS', nivel: 'OLHA' } });
    expect(wrapper.find('h2').text()).toBe(
      '2 pessoas vão deixar de mudar os dados dos contatos'
    );
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essas pessoas têm a função Vendedor. A partir de agora, só vão olhar os contatos.'
    );
    wrapper.unmount();
  });

  it('uma pessoa e as próprias conversas: singular', () => {
    const wrapper = montar({
      pessoas: [{ id: 1, name: 'Ana' }],
      perdas: [{ id: 'LER_E_ATENDER_TODAS' }],
      fica: { area: 'CONVERSATIONS', nivel: 'PROPRIAS' },
    });
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essa pessoa tem a função Vendedor. A partir de agora, só vai atender as próprias conversas.'
    );
    wrapper.unmount();
  });

  it('sem queda de nível, só quem tem a função', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essas pessoas têm a função Vendedor.'
    );
    wrapper.unmount();
  });
});
