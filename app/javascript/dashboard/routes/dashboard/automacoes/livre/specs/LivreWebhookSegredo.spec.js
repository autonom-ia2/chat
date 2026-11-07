import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import LivreWebhookSegredo from '../components/LivreWebhookSegredo.vue';

// G13 (#2670) — o segredo de conferência: o administrador ou a função com
// token_manage vê e troca, com a automação salva, e a troca pede confirmação.
const admin = ref(true);
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => admin,
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { segredoDoWebhook: vi.fn(), trocarSegredoDoWebhook: vi.fn() },
}));

const montar = automacaoId =>
  mount(LivreWebhookSegredo, {
    props: { automacaoId },
    global: { mocks: { $t: chave => chave } },
  });

describe('LivreWebhookSegredo', () => {
  beforeEach(() => {
    admin.value = true;
    vi.clearAllMocks();
  });

  it('sem a chave de tokens, só lê o aviso', () => {
    admin.value = false;
    const wrapper = montar(9);
    expect(wrapper.find('[data-sem-acesso]').exists()).toBe(true);
    expect(wrapper.find('[data-ver-segredo]').exists()).toBe(false);
  });

  it('sem a automação salva, pede para salvar antes', () => {
    const wrapper = montar(null);
    expect(wrapper.find('[data-salvar-antes]').exists()).toBe(true);
  });

  it('o administrador vê o segredo que a API devolve em secret', async () => {
    AutomacoesAPI.segredoDoWebhook.mockResolvedValue({
      data: { secret: 'abc123' },
    });
    const wrapper = montar(9);
    await wrapper.find('[data-ver-segredo]').trigger('click');
    await flushPromises();
    expect(AutomacoesAPI.segredoDoWebhook).toHaveBeenCalledWith(9);
    expect(wrapper.find('[data-segredo]').element.value).toBe('abc123');
  });

  it('trocar pede confirmação antes de chamar a API', async () => {
    AutomacoesAPI.trocarSegredoDoWebhook.mockResolvedValue({
      data: { secret: 'novo' },
    });
    const wrapper = montar(9);
    await wrapper.find('[data-trocar-segredo]').trigger('click');
    expect(AutomacoesAPI.trocarSegredoDoWebhook).not.toHaveBeenCalled();
    await wrapper.find('[data-trocar-sim]').trigger('click');
    await flushPromises();
    expect(AutomacoesAPI.trocarSegredoDoWebhook).toHaveBeenCalledWith(9);
    expect(wrapper.find('[data-segredo]').element.value).toBe('novo');
  });

  it('troca que falha tira o segredo da tela e pede para ver de novo', async () => {
    AutomacoesAPI.segredoDoWebhook.mockResolvedValue({
      data: { secret: 'velho' },
    });
    AutomacoesAPI.trocarSegredoDoWebhook.mockRejectedValue(new Error('rede'));
    const wrapper = montar(9);
    await wrapper.find('[data-ver-segredo]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-trocar-segredo]').trigger('click');
    await wrapper.find('[data-trocar-sim]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-segredo]').exists()).toBe(false);
    expect(wrapper.find('[data-segredo-falhou]').text()).toContain(
      'TROCAR_FALHOU'
    );
  });

  it('erro da API avisa sem mostrar segredo', async () => {
    AutomacoesAPI.segredoDoWebhook.mockRejectedValue(new Error('403'));
    const wrapper = montar(9);
    await wrapper.find('[data-ver-segredo]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-segredo-falhou]').exists()).toBe(true);
    expect(wrapper.find('[data-segredo]').exists()).toBe(false);
  });
});
