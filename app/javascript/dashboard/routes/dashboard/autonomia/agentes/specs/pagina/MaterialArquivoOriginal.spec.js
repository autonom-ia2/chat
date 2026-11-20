import { mount, flushPromises } from '@vue/test-utils';
import MaterialLinha from '../../components/pagina/MaterialLinha.vue';
import SourcesAPI from 'dashboard/api/autonomia/sources';

vi.mock('dashboard/api/autonomia/sources', () => ({
  default: { getFile: vi.fn() },
}));
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const source = {
  id: 3,
  autonomia_agent_id: 7,
  reference: 'guide.pdf',
  source_type: 'pdf',
  status: 'ready',
  file_attached: true,
};
const lineProps = { fonte: source, nomeAgente: 'Bia', mostrarOriginal: true };

describe('MaterialLinha original file', () => {
  let tab;
  let wrapper;

  beforeEach(() => {
    tab = { opener: {}, location: { replace: vi.fn() }, close: vi.fn() };
    vi.spyOn(window, 'open').mockReturnValue(tab);
    SourcesAPI.getFile.mockResolvedValue({
      data: { url: 'https://files.example.org/guide.pdf?signature=temporary' },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    vi.restoreAllMocks();
  });

  it('lets a read-only viewer open the original without fetching or exposing links in advance', async () => {
    wrapper = mount(MaterialLinha, {
      props: { ...lineProps, podeGerenciar: false },
    });

    expect(SourcesAPI.getFile).not.toHaveBeenCalled();
    expect(wrapper.html()).not.toContain('signature=');
    expect(wrapper.find('[aria-haspopup="menu"]').exists()).toBe(false);
    const button = wrapper.get('[data-open-original]');
    expect(button.attributes('aria-label')).toBeTruthy();
    expect(button.classes()).toContain('size-11');

    await button.trigger('click');
    await flushPromises();

    expect(SourcesAPI.getFile).toHaveBeenCalledWith(7, 3);
    expect(window.open).toHaveBeenCalledWith('', '_blank');
    expect(tab.opener).toBeNull();
    expect(tab.location.replace).toHaveBeenCalledWith(
      'https://files.example.org/guide.pdf?signature=temporary'
    );
  });

  it.each([
    { file_attached: false },
    { file_attached: undefined },
    { source_type: 'link', file_attached: false },
  ])(
    'does not offer a missing file or a website as an uploaded original: %j',
    overrides => {
      wrapper = mount(MaterialLinha, {
        props: { ...lineProps, fonte: { ...source, ...overrides } },
      });

      expect(wrapper.find('[data-open-original]').exists()).toBe(false);
    }
  );

  it('can recover the original even when ingestion failed', () => {
    wrapper = mount(MaterialLinha, {
      props: { ...lineProps, fonte: { ...source, status: 'failed' } },
    });

    expect(wrapper.find('[data-open-original]').exists()).toBe(true);
  });

  it('closes the temporary tab and reports an unavailable file', async () => {
    SourcesAPI.getFile.mockRejectedValue({ response: { status: 404 } });
    wrapper = mount(MaterialLinha, { props: lineProps });

    await wrapper.get('[data-open-original]').trigger('click');
    await flushPromises();

    expect(tab.close).toHaveBeenCalledOnce();
    expect(tab.location.replace).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.PAGINA.SABE.ORIGINAL_UNAVAILABLE'
    );
  });

  it('reports an API failure without exposing technical details or the signed URL', async () => {
    SourcesAPI.getFile.mockRejectedValue(new Error('private technical detail'));
    wrapper = mount(MaterialLinha, { props: lineProps });

    await wrapper.get('[data-open-original]').trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.PAGINA.SABE.ORIGINAL_ERROR'
    );
    expect(wrapper.text()).not.toContain('private technical detail');
  });

  it('ignores a second click while obtaining the link', async () => {
    let finish;
    SourcesAPI.getFile.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    wrapper = mount(MaterialLinha, { props: lineProps });
    const button = wrapper.get('[data-open-original]');

    await button.trigger('click');
    await button.trigger('click');
    expect(button.attributes('aria-busy')).toBe('true');
    expect(SourcesAPI.getFile).toHaveBeenCalledOnce();

    finish({ data: { url: 'https://files.example.org/guide.pdf' } });
    await flushPromises();
    expect(button.attributes('aria-busy')).toBe('false');
  });

  it('does not expose the agent file action in other material screens', () => {
    wrapper = mount(MaterialLinha, {
      props: { ...lineProps, mostrarOriginal: false },
    });

    expect(wrapper.find('[data-open-original]').exists()).toBe(false);
  });
});
