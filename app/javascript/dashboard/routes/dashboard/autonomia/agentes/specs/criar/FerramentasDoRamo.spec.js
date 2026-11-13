import { mount, flushPromises } from '@vue/test-utils';
import FerramentasDoRamo from '../../components/criar/FerramentasDoRamo.vue';

// #2881 — as ferramentas prontas de um agente pronto por ramo: cada uma com a frase "Use quando" do ramo, que o dono
// pode alterar; tirar; incluir as do "Também combina"; e a nota das consultas pagas, que só leva à vitrine.
const FERRAMENTAS = [
  { fonte: 'cnpj', usar_quando: 'Use quando o cliente informar o CNPJ.' },
  { fonte: 'cep', usar_quando: 'Use quando o cliente informar o CEP.' },
];
const TAMBEM = [
  { fonte: 'cidades', usar_quando: 'Use quando o cliente disser a cidade.' },
];

const montadas = [];
const montar = (props = {}) => {
  const wrapper = mount(FerramentasDoRamo, {
    props: {
      nome: 'Assistente de Seguro Garantia',
      ferramentas: FERRAMENTAS,
      tambem: TAMBEM,
      podeMudar: true,
      linkDaVitrine: '/app/vitrine?agente=90',
      ...props,
    },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};
const ferramenta = (wrapper, fonte) =>
  wrapper.get(`[data-ferramenta="${fonte}"]`);

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('FerramentasDoRamo', () => {
  it('shows each tool with its name and the "Use when" sentence written for the line of insurance', () => {
    const wrapper = montar();

    expect(wrapper.findAll('[data-ferramenta]')).toHaveLength(2);
    const cnpj = ferramenta(wrapper, 'cnpj');
    expect(cnpj.text()).toContain('AGENTS.VITRINE.FERRAMENTAS.CNPJ.NOME');
    expect(cnpj.get('[data-quando]').text()).toBe(
      'Use quando o cliente informar o CNPJ.'
    );
  });

  it('"Remove" sends the whole "comes with" list without that tool', async () => {
    const wrapper = montar();

    await ferramenta(wrapper, 'cnpj')
      .get('[data-tirar-ferramenta]')
      .trigger('click');

    expect(wrapper.emitted('mudar')).toEqual([[[FERRAMENTAS[1]]]]);
  });

  it('"Change when to use" opens the sentence, and saving sends the whole list with the new one', async () => {
    const wrapper = montar();

    await ferramenta(wrapper, 'cep')
      .get('[data-alterar-quando]')
      .trigger('click');
    const campo = wrapper.get('[data-alterando] textarea');
    expect(campo.element.value).toBe('Use quando o cliente informar o CEP.');
    await campo.setValue(' Use quando o cliente disser o CEP da obra. ');
    await wrapper.get('[data-salvar-quando]').trigger('click');

    expect(wrapper.emitted('mudar')).toEqual([
      [
        [
          FERRAMENTAS[0],
          {
            fonte: 'cep',
            usar_quando: 'Use quando o cliente disser o CEP da obra.',
          },
        ],
      ],
    ]);
    expect(wrapper.find('[data-alterando]').exists()).toBe(false);
    expect(FERRAMENTAS[1].usar_quando).toBe(
      'Use quando o cliente informar o CEP.'
    );
  });

  it('does not save an empty sentence', async () => {
    const wrapper = montar();

    await ferramenta(wrapper, 'cep')
      .get('[data-alterar-quando]')
      .trigger('click');
    await wrapper.get('[data-alterando] textarea').setValue('  ');
    await wrapper.get('[data-salvar-quando]').trigger('click');

    expect(wrapper.emitted('mudar')).toBeUndefined();
  });

  it('"Add these too" sends the "comes with" list plus the "also fits" tools, each with its sentence', async () => {
    const wrapper = montar();

    await wrapper.get('[data-incluir-tambem]').trigger('click');

    expect(wrapper.emitted('mudar')).toEqual([[[...FERRAMENTAS, ...TAMBEM]]]);
  });

  it('when the "also fits" tools go in, the focus moves to the list instead of nowhere', async () => {
    const wrapper = montar();
    wrapper.get('[data-incluir-tambem]').element.focus();

    await wrapper.setProps({
      ferramentas: [...FERRAMENTAS, ...TAMBEM],
      tambem: [],
    });
    await flushPromises();

    expect(wrapper.find('[data-tambem-combina]').exists()).toBe(false);
    expect(document.activeElement.tagName).toBe('UL');
  });

  it('suggests the paid lookups only as a link to the showcase, never adding them', () => {
    const wrapper = montar({ pagas: ['certidoes_empresa', 'raio_x_empresa'] });
    const nota = wrapper.get('[data-quer-tambem]');

    expect(nota.text()).toContain('AGENTS.JORNADA.RAMOS.CONFIRA.QUER_TAMBEM');
    const link = nota.get('a');
    expect(link.attributes('href')).toBe('/app/vitrine?agente=90');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(nota.find('button').exists()).toBe(false);
  });

  it('without the showcase link, shows neither "Add another tool" nor the paid lookups', () => {
    const wrapper = montar({
      linkDaVitrine: '',
      pagas: ['certidoes_empresa'],
    });

    expect(wrapper.find('[data-ver-mais-ferramentas]').exists()).toBe(false);
    expect(wrapper.find('[data-quer-tambem]').exists()).toBe(false);
  });

  it('while a change is being saved, the buttons wait and nothing else is sent', async () => {
    const wrapper = montar({ gravando: true });

    await ferramenta(wrapper, 'cnpj')
      .get('[data-tirar-ferramenta]')
      .trigger('click');
    await wrapper.get('[data-incluir-tambem]').trigger('click');

    expect(wrapper.emitted('mudar')).toBeUndefined();
    expect(
      ferramenta(wrapper, 'cnpj')
        .get('[data-tirar-ferramenta]')
        .attributes('aria-disabled')
    ).toBe('true');
  });

  it('who cannot change only reads the tools and their sentences', () => {
    const wrapper = montar({ podeMudar: false });

    expect(wrapper.findAll('[data-quando]')).toHaveLength(2);
    expect(wrapper.find('[data-tirar-ferramenta]').exists()).toBe(false);
    expect(wrapper.find('[data-alterar-quando]').exists()).toBe(false);
    expect(wrapper.find('[data-tambem-combina]').exists()).toBe(false);
  });
});
