import { flushPromises, mount } from '@vue/test-utils';
import CrmExcluirAPI from 'dashboard/api/crmExcluir';
import ExcluirFunilDialogo from '../ExcluirFunilDialogo.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) =>
      params ? `${chave}${JSON.stringify(params)}` : chave,
    locale: { value: 'pt-BR' },
  }),
}));
vi.mock('dashboard/api/crmExcluir', () => ({
  default: { previaDoFunil: vi.fn(), excluirFunil: vi.fn() },
}));

const DialogStub = {
  props: ['title'],
  template: '<div><slot /><slot name="footer" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};
const arquivado = { id: 5, name: 'Feira 2025' };
const vendas = { id: 1, name: 'Vendas', counts_as_sale: true };
const posVenda = { id: 2, name: 'Pós-venda', counts_as_sale: false };

const montar = () =>
  mount(ExcluirFunilDialogo, {
    props: {
      ativos: [vendas, posVenda],
      carregarEtapas: vi.fn().mockResolvedValue([
        { id: 11, name: 'Novo contato' },
        { id: 12, name: 'Proposta' },
      ]),
    },
    global: { stubs: { Dialog: DialogStub } },
  });
const abrir = async wrapper => {
  await wrapper.vm.open(arquivado);
  await flushPromises();
};
const confirmar = async wrapper => {
  await wrapper.find('[data-campo-confirmar]').setValue('Feira 2025');
  await wrapper.find('[data-excluir-confirmar]').trigger('click');
  await flushPromises();
};

describe('ExcluirFunilDialogo', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmExcluirAPI.previaDoFunil.mockResolvedValue({
      data: {
        payload: {
          cards_count: 3,
          open_cards_count: 1,
          closed_or_archived_count: 2,
          won_values: [{ currency: 'BRL', value_cents: 300000 }],
          upcoming_meetings_count: 0,
          upcoming_meetings: [],
          timezone: 'America/Sao_Paulo',
        },
      },
    });
    CrmExcluirAPI.excluirFunil.mockResolvedValue({
      data: { payload: { status: 'queued' } },
    });
  });

  it('mover já vem marcado e manda o modo que o servidor entende (move) com a etapa', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    expect(
      wrapper.find('[role="radio"][aria-checked="true"]').text()
    ).toContain('CRM_EXCLUIR.FUNIL.MOVER');
    expect(wrapper.find('[data-excluir-funil-vendas]').text()).toContain(
      'CRM_EXCLUIR.FUNIL.VENDAS_SOBEM'
    );
    await confirmar(wrapper);
    expect(CrmExcluirAPI.excluirFunil).toHaveBeenCalledWith(5, {
      confirmation: 'Feira 2025',
      cards: 'move',
      targetStageId: 11,
    });
  });

  it('excluir junto: avisa a venda e manda delete, sem etapa', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    await wrapper.findAll('[role="radio"]')[1].trigger('click');
    expect(wrapper.find('[data-excluir-funil-vendas]').text()).toContain(
      'CRM_EXCLUIR.FUNIL.VENDAS_JUNTO'
    );
    await confirmar(wrapper);
    expect(CrmExcluirAPI.excluirFunil).toHaveBeenCalledWith(5, {
      confirmation: 'Feira 2025',
      cards: 'delete',
      targetStageId: undefined,
    });
  });

  it('o nome tem de conferir', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    await wrapper.find('[data-campo-confirmar]').setValue('feira 2025');
    expect(
      wrapper.find('[data-excluir-confirmar]').attributes('disabled')
    ).toBeDefined();
  });
});
