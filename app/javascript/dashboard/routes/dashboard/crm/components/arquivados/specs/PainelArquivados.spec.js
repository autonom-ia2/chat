import { flushPromises, mount } from '@vue/test-utils';
import CrmArquivadosAPI from 'dashboard/api/crmArquivados';
import PainelArquivados from '../PainelArquivados.vue';
import { limparAvisos, useAvisoCrm } from '../useAvisoCrm';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) =>
      params ? `${chave}${JSON.stringify(params)}` : chave,
    locale: { value: 'pt-BR' },
  }),
}));
vi.mock('dashboard/api/crmArquivados', () => ({
  default: {
    listar: vi.fn(),
    restaurar: vi.fn(),
    restaurarVarios: vi.fn(),
  },
}));
vi.mock('@vueuse/core', async original => ({
  ...(await original()),
  useDebounceFn: fn => fn,
}));

const funil = { id: 1, name: 'Vendas', counts_as_sale: true };
const linha = (id, extra = {}) => ({
  id,
  title: `Card ${id}`,
  status: 'archived',
  stage: { id: 11, name: 'Proposta' },
  pipeline: { id: 1, name: 'Vendas', status: 'active' },
  archived_at: '2026-10-19T10:00:00Z',
  archived_by: { type: 'user', id: 3, name: 'Rafael' },
  can_restore: true,
  value_cents: 250000,
  currency: 'BRL',
  desfecho: null,
  retornos_parados: 0,
  ...extra,
});

const montar = (props = {}) =>
  mount(PainelArquivados, {
    props: {
      show: true,
      funil,
      funis: [funil],
      podeArquivar: true,
      restaurar: vi.fn().mockResolvedValue({ restaurado: true }),
      ...props,
    },
    global: {
      stubs: {
        Teleport: true,
        Transition: false,
        Input: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input data-busca :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });

describe('PainelArquivados', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    limparAvisos();
    CrmArquivadosAPI.listar.mockResolvedValue({
      data: {
        payload: [linha(10), linha(9, { desfecho: 'won' })],
        meta: { count: 2 },
      },
    });
  });

  it('carrega os arquivados do funil e avisa antes do clique que o ganho vai para a Lista', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(CrmArquivadosAPI.listar).toHaveBeenCalledWith(
      expect.objectContaining({ pipeline_id: 1, page: 1 })
    );
    const dicas = wrapper.findAll('[data-arquivado-dica]');
    expect(dicas).toHaveLength(1);
    expect(dicas[0].text()).toContain('DICA_FECHADO');
  });

  it('"Procurar em todos os funis" tira o funil do pedido', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-arquivados-todos]').trigger('click');
    await flushPromises();
    expect(CrmArquivadosAPI.listar).toHaveBeenLastCalledWith(
      expect.objectContaining({ pipeline_id: undefined })
    );
  });

  it('sem "Arquivar cards": só leitura, sem Restaurar e sem seleção', async () => {
    const wrapper = montar({ podeArquivar: false });
    await flushPromises();
    expect(wrapper.find('[data-so-leitura]').text()).toContain('SEM_PERMISSAO');
    expect(wrapper.find('[data-arquivado-restaurar]').exists()).toBe(false);
    expect(wrapper.find('[data-arquivados-selecao]').exists()).toBe(false);
  });

  it('restaurar um tira a linha e avisa a página', async () => {
    const restaurar = vi.fn().mockResolvedValue({ restaurado: true });
    const wrapper = montar({ restaurar });
    await flushPromises();
    await wrapper.find('[data-arquivado-restaurar]').trigger('click');
    await flushPromises();
    expect(restaurar).toHaveBeenCalledWith(expect.objectContaining({ id: 10 }));
    expect(wrapper.findAll('[data-arquivado-linha]')).toHaveLength(1);
    expect(wrapper.emitted('mudou')).toHaveLength(1);
  });

  it('erro ao restaurar fica na linha', async () => {
    const restaurar = vi
      .fn()
      .mockResolvedValue({ restaurado: false, erro: 'Não deu' });
    const wrapper = montar({ restaurar });
    await flushPromises();
    await wrapper.find('[data-arquivado-restaurar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-arquivado-erro]').text()).toBe('Não deu');
  });

  it('restaurar vários: restaura os sem conflito e lista lado a lado os do cliente que já voltou', async () => {
    CrmArquivadosAPI.restaurarVarios.mockResolvedValue({
      data: {
        payload: {
          restored: [9],
          skipped: [
            {
              id: 10,
              error: 'crm.card_restore_conflict',
              open_card_id: 40,
              open_card: { id: 40, title: 'Card novo', stage_name: 'Novo' },
            },
          ],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .find('[data-arquivados-selecionar-todos] input')
      .trigger('change');
    await wrapper.find('[data-arquivados-restaurar-varios]').trigger('click');
    await flushPromises();
    expect(CrmArquivadosAPI.restaurarVarios).toHaveBeenCalledWith([10, 9]);
    const conflito = wrapper.find('[data-conflito-linha]');
    expect(conflito.text()).toContain('Card 10');
    expect(conflito.text()).toContain('Proposta');
    expect(conflito.text()).toContain('Card novo');
    expect(conflito.text()).toContain('Novo');
    const { avisos } = useAvisoCrm();
    expect(avisos.value[0].mensagem).toContain('NAO_VOLTARAM');
    expect(avisos.value[0].mensagem).toContain('FECHADOS');
  });

  it('lote em que todos dão conflito: uma frase só, sem "0 cards restaurados"', async () => {
    CrmArquivadosAPI.restaurarVarios.mockResolvedValue({
      data: {
        payload: {
          restored: [],
          skipped: [
            { id: 10, error: 'crm.card_restore_conflict', open_card_id: 40 },
            { id: 9, error: 'crm.card_restore_conflict', open_card_id: 41 },
          ],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .find('[data-arquivados-selecionar-todos] input')
      .trigger('change');
    await wrapper.find('[data-arquivados-restaurar-varios]').trigger('click');
    await flushPromises();
    const { avisos } = useAvisoCrm();
    expect(avisos.value[0].mensagem).toBe(
      'CRM_ARQUIVADOS.LOTE.NENHUM_VOLTOU_CONFLITOS{"count":2}'
    );
  });

  it('lote sem nenhum restaurado mas com outro motivo mantém a frase de sempre', async () => {
    CrmArquivadosAPI.restaurarVarios.mockResolvedValue({
      data: {
        payload: {
          restored: [],
          skipped: [
            { id: 10, error: 'crm.card_restore_conflict', open_card_id: 40 },
            { id: 9, error: 'forbidden' },
          ],
        },
      },
    });
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .find('[data-arquivados-selecionar-todos] input')
      .trigger('change');
    await wrapper.find('[data-arquivados-restaurar-varios]').trigger('click');
    await flushPromises();
    const { avisos } = useAvisoCrm();
    expect(avisos.value[0].mensagem).toContain('RESTAURADOS');
    expect(avisos.value[0].mensagem).toContain('NAO_VOLTARAM');
  });

  it('"Restaurar mesmo assim" na linha do conflito força só aquele card', async () => {
    CrmArquivadosAPI.restaurarVarios.mockResolvedValue({
      data: {
        payload: {
          restored: [],
          skipped: [
            {
              id: 10,
              error: 'crm.card_restore_conflict',
              open_card: { id: 40, title: 'Card novo', stage_name: 'Novo' },
            },
          ],
        },
      },
    });
    CrmArquivadosAPI.restaurar.mockResolvedValue({ data: { payload: {} } });
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .findAll('[data-arquivado-selecionar] input')[0]
      .trigger('change');
    await wrapper.find('[data-arquivados-restaurar-varios]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-conflito-forcar-um]').trigger('click');
    await flushPromises();
    expect(CrmArquivadosAPI.restaurar).toHaveBeenCalledWith(10, {
      force: true,
    });
    expect(wrapper.find('[data-conflito-linha]').exists()).toBe(false);
  });

  it('erro no lote: nada mudou e a lista fica igual', async () => {
    CrmArquivadosAPI.restaurarVarios.mockRejectedValue(new Error('rede'));
    const wrapper = montar();
    await flushPromises();
    await wrapper
      .find('[data-arquivados-selecionar-todos] input')
      .trigger('change');
    await wrapper.find('[data-arquivados-restaurar-varios]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('LOTE.ERRO');
    expect(wrapper.findAll('[data-arquivado-linha]')).toHaveLength(2);
  });

  it('busca sem resultado oferece limpar e procurar em todos os funis', async () => {
    const wrapper = montar();
    await flushPromises();
    CrmArquivadosAPI.listar.mockResolvedValue({
      data: { payload: [], meta: { count: 0 } },
    });
    await wrapper.find('[data-busca]').setValue('zzz');
    await flushPromises();
    expect(wrapper.find('[data-arquivados-busca-vazia]').text()).toContain(
      'NADA_ACHADO'
    );
  });

  it('card guardado em funil arquivado aponta para Funis arquivados', async () => {
    CrmArquivadosAPI.listar.mockResolvedValue({
      data: {
        payload: [
          linha(20, {
            status: 'open',
            pipeline: { id: 3, name: 'Parcerias', status: 'archived' },
            archived_at: null,
            archived_by: null,
            can_restore: false,
          }),
        ],
        meta: { count: 1 },
      },
    });
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-arquivado-quando]').text()).toBe(
      'CRM_ARQUIVADOS.LINHA.GUARDADO_COM_O_FUNIL'
    );
    expect(wrapper.find('[data-arquivado-restaurar]').exists()).toBe(false);
    expect(wrapper.find('[data-arquivados-selecao]').exists()).toBe(false);
    expect(wrapper.text()).toContain('VER_FUNIS_ARQUIVADOS');
  });
});
