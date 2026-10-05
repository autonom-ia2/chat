import { mount } from '@vue/test-utils';
import CentralAssuntos from '../components/CentralAssuntos.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (chave, valor) => `${chave}${valor ?? ''}` }),
}));

const capitulos = [
  {
    id: '10',
    titulo: 'CRM, funis e negócios',
    artigos: [
      { id: '10.01', ref: '10-01', titulo: 'Funil', video: true },
      { id: '10.02', ref: '10-02', titulo: 'Negócio', video: false },
    ],
  },
  { id: '13', titulo: 'Campanhas', artigos: [] },
];

const montar = () =>
  mount(CentralAssuntos, {
    props: { capitulos },
    global: {
      stubs: {
        RouterLink: {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });

describe('CentralAssuntos', () => {
  it('cada assunto é um link para a página dele, com as contagens', () => {
    const tela = montar();
    const links = tela.findAll('a');

    expect(links).toHaveLength(1);
    expect(links[0].attributes('data-to')).toBe(
      JSON.stringify({
        name: 'central_de_ajuda_assunto',
        params: { capitulo: '10' },
      })
    );
    expect(links[0].text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.CRM'
    );
    expect(links[0].text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.ARTIGOS_NO_CAPITULO2'
    );
    expect(links[0].text()).toContain(
      'HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.VIDEOS1'
    );
  });

  it('não abre lista embutida: sem botão nem aria-expanded', () => {
    const tela = montar();

    expect(tela.find('button').exists()).toBe(false);
    expect(tela.find('[aria-expanded]').exists()).toBe(false);
    expect(tela.text()).not.toContain('Funil');
  });
});
