import { flushPromises, mount } from '@vue/test-utils';
import CrmExcluirAPI from 'dashboard/api/crmExcluir';
import ExcluirContatoDialogo from '../ExcluirContatoDialogo.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) =>
      params ? `${chave}${JSON.stringify(params)}` : chave,
    locale: { value: 'pt-BR' },
  }),
}));
vi.mock('dashboard/api/crmExcluir', () => ({
  default: { previaDoContato: vi.fn(), excluirContato: vi.fn() },
}));

const funil = { id: 1, name: 'Vendas', status: 'active', counts_as_sale: true };
const cardDaPrevia = (id, extra = {}) => ({
  id,
  pipeline: funil,
  stage_name: 'Proposta',
  value_cents: 300000,
  currency: 'BRL',
  status: 'open',
  desfecho: null,
  upcoming_meeting: null,
  ...extra,
});

const DialogStub = {
  props: ['title', 'description'],
  template:
    '<div data-dialogo><p data-titulo>{{ title }}</p><slot /><slot name="footer" /></div>',
  methods: { open: vi.fn(), close: vi.fn() },
};

const montar = () =>
  mount(ExcluirContatoDialogo, {
    props: { contato: { id: 7, name: 'Pedro' } },
    global: { stubs: { Dialog: DialogStub } },
  });

const abrir = async wrapper => {
  await wrapper.vm.open();
  await flushPromises();
};
const botaoExcluir = wrapper => wrapper.find('[data-excluir-confirmar]');
const digitar = async (wrapper, texto) =>
  wrapper.find('[data-campo-confirmar]').setValue(texto);

describe('ExcluirContatoDialogo', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmExcluirAPI.previaDoContato.mockResolvedValue({
      data: {
        payload: {
          timezone: 'America/Sao_Paulo',
          cards: [
            cardDaPrevia(1, { status: 'won' }),
            cardDaPrevia(2, {
              upcoming_meeting: {
                starts_at: '2026-10-30T13:00:00Z',
                provider: 'google',
              },
            }),
          ],
        },
      },
    });
    CrmExcluirAPI.excluirContato.mockResolvedValue({ data: { payload: {} } });
  });

  it('lista os cards e não deixa nada marcado: sem escolher, não exclui', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    expect(CrmExcluirAPI.previaDoContato).toHaveBeenCalledWith(7);
    expect(wrapper.findAll('[data-excluir-contato-cards] li')).toHaveLength(2);
    expect(wrapper.findAll('[role="radio"][aria-checked="true"]')).toHaveLength(
      0
    );
    await digitar(wrapper, 'EXCLUIR');
    expect(botaoExcluir(wrapper).attributes('disabled')).toBeDefined();
  });

  it('"Sim, apagar": avisa a venda que sai e a reunião cancelada, e manda delete', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    await wrapper.findAll('[role="radio"]')[0].trigger('click');
    expect(wrapper.find('[data-excluir-venda]').text()).toContain(
      'CRM_EXCLUIR.CONTATO.VENDA_SAI'
    );
    expect(wrapper.find('[data-excluir-reuniao]').text()).toContain(
      'CRM_EXCLUIR.REUNIAO.CLIENTE_AVISADO'
    );
    await digitar(wrapper, 'excluir');
    await botaoExcluir(wrapper).trigger('click');
    await flushPromises();
    expect(CrmExcluirAPI.excluirContato).toHaveBeenCalledWith(7, {
      confirmation: 'EXCLUIR',
      cards: 'delete',
    });
    expect(wrapper.emitted('excluido')[0][0]).toEqual({
      nome: 'Pedro',
      cards: 2,
      modo: 'delete',
    });
  });

  it('"Não, manter": a venda continua, a reunião também é cancelada, e manda keep', async () => {
    const wrapper = montar();
    await abrir(wrapper);
    await wrapper.findAll('[role="radio"]')[1].trigger('click');
    expect(wrapper.find('[data-excluir-venda]').text()).toContain(
      'CRM_EXCLUIR.CONTATO.VENDA_FICA'
    );
    expect(wrapper.find('[data-excluir-reuniao]').exists()).toBe(true);
    await digitar(wrapper, 'EXCLUIR');
    await botaoExcluir(wrapper).trigger('click');
    await flushPromises();
    expect(CrmExcluirAPI.excluirContato).toHaveBeenCalledWith(7, {
      confirmation: 'EXCLUIR',
      cards: 'keep',
    });
  });

  it('contato sem card: sem pergunta, só EXCLUIR', async () => {
    CrmExcluirAPI.previaDoContato.mockResolvedValue({
      data: { payload: { cards: [] } },
    });
    const wrapper = montar();
    await abrir(wrapper);
    expect(wrapper.find('[role="radiogroup"]').exists()).toBe(false);
    await digitar(wrapper, 'EXCLUIR');
    await botaoExcluir(wrapper).trigger('click');
    await flushPromises();
    expect(CrmExcluirAPI.excluirContato).toHaveBeenCalledWith(7, {
      confirmation: 'EXCLUIR',
      cards: undefined,
    });
  });

  it('recusa do servidor: diz o motivo e que nada foi apagado, e não fecha', async () => {
    CrmExcluirAPI.excluirContato.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'crm.permanent_delete.meeting_cancel_failed' },
      },
    });
    const wrapper = montar();
    await abrir(wrapper);
    await wrapper.findAll('[role="radio"]')[1].trigger('click');
    await digitar(wrapper, 'EXCLUIR');
    await botaoExcluir(wrapper).trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-excluir-erro]').text()).toBe(
      'CRM_EXCLUIR.ERROS.NADA_MUDOU{"motivo":"CRM_EXCLUIR.ERROS.REUNIAO"}'
    );
    expect(wrapper.emitted('excluido')).toBeUndefined();
  });

  it('prévia falhou: mostra o motivo e não deixa excluir', async () => {
    CrmExcluirAPI.previaDoContato.mockRejectedValue(new Error('rede'));
    const wrapper = montar();
    await abrir(wrapper);
    expect(wrapper.find('[role="alert"]').text()).toContain(
      'CRM_EXCLUIR.ERROS.PREVIA'
    );
    expect(botaoExcluir(wrapper).attributes('disabled')).toBeDefined();
  });
});
