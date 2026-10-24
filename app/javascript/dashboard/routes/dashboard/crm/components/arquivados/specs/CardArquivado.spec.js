import { mount } from '@vue/test-utils';
import CardArquivado from '../CardArquivado.vue';
import ArquivarCardDialogo from '../ArquivarCardDialogo.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, params) =>
      params ? `${chave}${JSON.stringify(params)}` : chave,
  }),
}));

const formato = {
  diaCurto: () => '19 de outubro',
  dinheiro: centavos => `R$ ${centavos / 100}`,
};
const card = extra => ({
  id: 1,
  status: 'archived',
  stage: { name: 'Proposta' },
  value_cents: 120000,
  currency: 'BRL',
  metadata: { desfecho_arquivado: 'won' },
  activities: [
    {
      event_type: 'archive',
      actor_type: 'user',
      actor_name: 'Ana',
      created_at: '2026-10-19T10:00:00Z',
      payload: { lembretes_cancelados: 2 },
    },
  ],
  ...extra,
});
const montar = props =>
  mount(CardArquivado, {
    props: {
      card: card(),
      funil: { counts_as_sale: true },
      formato,
      ...props,
    },
  });

describe('CardArquivado', () => {
  it('diz quem arquivou, a venda que continua, a aba e os retornos que pararam', () => {
    const wrapper = montar({ podeArquivar: true });
    expect(wrapper.find('[data-card-arquivado-quem]').text()).toContain('Ana');
    expect(wrapper.find('[data-card-arquivado-venda]').text()).toContain(
      'R$ 1200'
    );
    expect(wrapper.find('[data-card-arquivado-aba]').exists()).toBe(true);
    expect(wrapper.find('[data-card-arquivado-retornos]').exists()).toBe(true);
    expect(wrapper.find('[data-card-restaurar]').exists()).toBe(true);
  });

  it('sem "Arquivar cards": a frase de quem pedir, sem Restaurar', () => {
    const wrapper = montar({ podeArquivar: false });
    expect(wrapper.find('[data-card-restaurar]').exists()).toBe(false);
    expect(wrapper.find('[data-sem-permissao]').text()).toBe(
      'CRM_ARQUIVADOS.SEM_PERMISSAO'
    );
  });

  it('valor oculto: não fala da venda', () => {
    const wrapper = montar({ card: card({ value_hidden: true }) });
    expect(wrapper.find('[data-card-arquivado-venda]').exists()).toBe(false);
  });
});

describe('ArquivarCardDialogo', () => {
  const abrir = props =>
    mount(ArquivarCardDialogo, {
      props: { nome: 'Mariana Costa', ...props },
      global: {
        stubs: {
          Dialog: {
            props: ['title', 'description'],
            template:
              '<div data-dialog :data-title="title"><slot /><slot name="footer" /></div>',
          },
        },
      },
    });

  it('título da decisão 6 e o que para', () => {
    const wrapper = abrir({ retornos: 2, avisoDeReuniao: 'Reunião em 24/10' });
    expect(wrapper.find('[data-dialog]').attributes('data-title')).toBe(
      'CRM_ARQUIVADOS.ARQUIVAR.TITULO{"nome":"Mariana Costa"}'
    );
    expect(wrapper.find('[data-arquivar-retornos]').text()).toContain(
      '"count":2'
    );
    expect(wrapper.find('[data-aviso-reuniao]').text()).toBe(
      'Reunião em 24/10'
    );
  });

  it('sem retornos nem reunião, só o texto', () => {
    const wrapper = abrir({});
    expect(wrapper.find('[data-arquivar-retornos]').exists()).toBe(false);
    expect(wrapper.find('[data-aviso-reuniao]').exists()).toBe(false);
  });

  it('erro aparece na janela', () => {
    const wrapper = abrir({ erro: 'Não deu para arquivar' });
    expect(wrapper.find('[data-arquivar-erro]').text()).toBe(
      'Não deu para arquivar'
    );
  });
});
