import { mount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import pt from 'dashboard/i18n/locale/pt_BR/emailLists.json';

// G52 (#2760) — "Quem recebe" da campanha de e-mail: planilha ou lista.
const api = vi.hoisted(() => ({ index: vi.fn(), create: vi.fn() }));
vi.mock('dashboard/api/emailLists', () => ({ default: api }));

const { default: EmailListAudience } = await import('../EmailListAudience.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});
afterEach(() => vi.clearAllMocks());

const DICAS = {
  id: 5,
  name: 'Dicas do mês',
  contatos_count: 3,
  recebem_count: 2,
};

const montar = props =>
  mount(EmailListAudience, {
    props: { modo: 'lista', listaId: null, ...props },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: pt } }),
      ],
    },
  });

describe('EmailListAudience', () => {
  it('na planilha não carrega nada da lista na tela', async () => {
    api.index.mockResolvedValue({ data: [DICAS] });
    const wrapper = montar({ modo: 'planilha' });
    await flushPromises();

    expect(
      wrapper.find('[data-modo="planilha"]').attributes('aria-pressed')
    ).toBe('true');
    expect(wrapper.find('[data-lista-escolhida]').exists()).toBe(false);
  });

  it('com a lista escolhida, mostra quantos estão nela agora e a regra do envio', async () => {
    api.index.mockResolvedValue({ data: [DICAS] });
    const wrapper = montar({ listaId: 5 });
    await flushPromises();

    const escolhida = wrapper.find('[data-lista-escolhida]').text();
    expect(escolhida).toContain('3 pessoas na lista agora');
    expect(escolhida).toContain('2 com e-mail');
    expect(escolhida).toContain(
      'Vai para quem estiver na lista na hora do envio. Quem pediu para não receber fica de fora.'
    );
  });

  it('sem acesso aos contatos (números nulos), não mostra quantos estão na lista', async () => {
    api.index.mockResolvedValue({
      data: [{ ...DICAS, contatos_count: null, recebem_count: null }],
    });
    const wrapper = montar({ listaId: 5 });
    await flushPromises();

    expect(wrapper.find('[data-lista-numeros]').exists()).toBe(false);
    expect(wrapper.find('[data-lista-escolhida]').text()).toBe(
      'Vai para quem estiver na lista na hora do envio. Quem pediu para não receber fica de fora.'
    );
  });

  it('cria a lista pelo nome e já a escolhe', async () => {
    api.index.mockResolvedValue({ data: [] });
    api.create.mockResolvedValue({
      data: { id: 9, name: 'Novidades', contatos_count: 0, recebem_count: 0 },
    });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-sem-lista]').exists()).toBe(true);

    await wrapper.find('[data-criar-lista-abrir]').trigger('click');
    await wrapper.find('[data-criar-lista] input').setValue('Novidades');
    await wrapper.find('[data-confirmar-lista]').trigger('click');
    await flushPromises();

    expect(api.create).toHaveBeenCalledWith('Novidades');
    expect(wrapper.emitted('update:listaId')).toEqual([[9]]);
  });

  it('nome repetido diz isso, sem fechar o campo', async () => {
    api.index.mockResolvedValue({ data: [DICAS] });
    api.create.mockRejectedValue({
      response: {
        data: { error: 'email_list.invalid', errors: { name: ['taken'] } },
      },
    });
    const wrapper = montar();
    await flushPromises();

    await wrapper.find('[data-criar-lista-abrir]').trigger('click');
    await wrapper.find('[data-criar-lista] input').setValue('Dicas do mês');
    await wrapper.find('[data-confirmar-lista]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-criar-lista]').text()).toContain(
      'Já existe uma lista com esse nome.'
    );
  });

  it('sem lista escolhida, diz isso na tela e liga o aviso ao campo', async () => {
    api.index.mockResolvedValue({ data: [DICAS] });
    const wrapper = montar({ invalid: true });
    await flushPromises();

    const aviso = wrapper.find('[data-lista-obrigatoria]');
    expect(aviso.text()).toBe('Escolha uma lista.');
    expect(
      wrapper.find('[role="combobox"]').attributes('aria-describedby')
    ).toBe(aviso.attributes('id'));
    expect(wrapper.find('[role="combobox"]').attributes('aria-invalid')).toBe(
      'true'
    );
  });

  it('sem erro, o campo não aponta para aviso nenhum', async () => {
    api.index.mockResolvedValue({ data: [DICAS] });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-lista-obrigatoria]').exists()).toBe(false);
    expect(
      wrapper.find('[role="combobox"]').attributes('aria-describedby')
    ).toBeUndefined();
  });
});
