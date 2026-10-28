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

  // Rodada 8 (L4): o singular das próprias com as novas e o link.
  it('uma pessoa nas próprias, com as novas e o link: singular', () => {
    const wrapper = montar({
      pessoas: [{ id: 1, name: 'Ana' }],
      perdas: [{ id: 'LER_E_ATENDER_TODAS' }],
      fica: { area: 'CONVERSATIONS', nivel: 'PROPRIAS_NOVAS_E_LINK' },
    });
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essa pessoa tem a função Vendedor. A partir de agora, vai atender as próprias conversas, pegar as novas sem ninguém e ajudar quando um colega manda o link.'
    );
    wrapper.unmount();
  });

  // Rodada 5: quem desce para as próprias e continua pegando as novas e ajudando pelo link não "só" atende as próprias.
  it.each([
    [
      'PROPRIAS_E_NOVAS',
      'Essas pessoas têm a função Vendedor. A partir de agora, vão atender as próprias conversas e pegar as novas que estão sem ninguém.',
    ],
    [
      'PROPRIAS_E_LINK',
      'Essas pessoas têm a função Vendedor. A partir de agora, vão atender as próprias conversas e ajudar quando um colega manda o link da conversa.',
    ],
    [
      'PROPRIAS_NOVAS_E_LINK',
      'Essas pessoas têm a função Vendedor. A partir de agora, vão atender as próprias conversas, pegar as novas sem ninguém e ajudar quando um colega manda o link.',
    ],
  ])('as próprias com mais (%s): sem "só"', (nivel, texto) => {
    const wrapper = montar({
      perdas: [{ id: 'LER_E_ATENDER_TODAS' }],
      fica: { area: 'CONVERSATIONS', nivel },
    });
    expect(wrapper.find('[data-texto-perda]').text()).toBe(texto);
    wrapper.unmount();
  });

  // Rodada 5: a área vai em minúscula no meio da frase ("as vendas", não "as Vendas").
  it('a área que fica só olhando vem em minúscula', () => {
    const wrapper = montar({
      perdas: [{ id: 'CRIAR_MOVER_VENDAS' }],
      fica: { area: 'CRM', nivel: 'OLHA' },
    });
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essas pessoas têm a função Vendedor. A partir de agora, só vão olhar as vendas.'
    );
    wrapper.unmount();
  });

  // Rodada 6: a área que some vem no título e na lista na mesma forma minúscula do texto ("ver os relatórios").
  it('a área que some vem em minúscula no título e na lista', () => {
    const umaSo = montar({ perdas: [{ area: 'REPORTS' }] });
    expect(umaSo.find('h2').text()).toBe(
      '2 pessoas vão deixar de ver os relatórios'
    );
    umaSo.unmount();

    const varias = montar({
      perdas: [{ area: 'REPORTS' }, { area: 'INBOXES' }],
    });
    expect(varias.findAll('[data-perdas] li').map(item => item.text())).toEqual(
      ['Ver os relatórios', 'Ver os canais']
    );
    varias.unmount();
  });

  it('sem queda de nível, só quem tem a função', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-texto-perda]').text()).toBe(
      'Essas pessoas têm a função Vendedor.'
    );
    wrapper.unmount();
  });
});
