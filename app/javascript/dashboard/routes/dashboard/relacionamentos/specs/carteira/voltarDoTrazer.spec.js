import { RouterLinkStub, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import ComoTrazer from '../../components/carteira/trazer/pdfs/ComoTrazer.vue';
import TrazerPdfs from '../../components/carteira/trazer/pdfs/TrazerPdfs.vue';
import TrazerDoAgger from '../../components/carteira/trazer/agger/TrazerDoAgger.vue';
import { DialogoFalso } from './apoio';

// #3057 — "Como trazer", "Trazer por PDFs" e "Do Agger" têm o caminho de volta
// à aba Seguros, o mesmo link de "Ajustar renovações" (‹ Seguros). Sem ele, no
// celular a única saída era o ☰. As fontes ficam esperando para sempre: aqui
// só importa o topo da tela.
vi.mock('dashboard/api/relacionamentosTrazerPdfs', () => ({ default: {} }));
vi.mock('dashboard/api/relacionamentosTrazerAgger', () => ({ default: {} }));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: {} }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => true) };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const roteador = useRouter();
// Uma fonte que nunca responde.
const fonteParada = () =>
  new Proxy(
    {},
    {
      get: (_, nome) =>
        nome === 'then' ? undefined : () => new Promise(() => {}),
    }
  );

const TELAS = [
  [
    'Como trazer',
    ComoTrazer,
    { rotas: { planilha: {}, pdfs: {} }, caminhos: ['planilha', 'pdfs'] },
  ],
  ['Trazer por PDFs', TrazerPdfs, { fonte: fonteParada() }],
  ['Do Agger', TrazerDoAgger, { fonte: fonteParada() }],
];

let aberta;
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  roteador.push.mockClear();
});

describe.each(TELAS)('%s', (_, Tela, props) => {
  const abrir = async () => {
    aberta = mount(Tela, {
      attachTo: document.body,
      props,
      global: {
        stubs: { RouterLink: RouterLinkStub, Dialog: DialogoFalso },
      },
    });
    await flushPromises();
    return aberta;
  };

  it('abre com "‹ Seguros", antes do título', async () => {
    const w = await abrir();
    const volta = w.get('[data-relacionamentos="voltar"]');

    expect(volta.text()).toBe('Seguros');
    expect(volta.attributes('aria-label')).toBe('Voltar aos seguros');
    expect(volta.element.compareDocumentPosition(w.get('h1').element)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING
    );
  });

  it('"Seguros" volta para a aba Seguros', async () => {
    const w = await abrir();

    await w.get('[data-relacionamentos="voltar"]').trigger('click');

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros' },
    });
  });
});
