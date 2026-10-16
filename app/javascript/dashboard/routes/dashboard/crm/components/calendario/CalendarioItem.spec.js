import { mount } from '@vue/test-utils';
import CalendarioItem from './CalendarioItem.vue';
import { paraItem } from './itensDoCalendario';

const conta = vi.hoisted(() => ({ mensagemMarcada: false }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: chave =>
      chave === 'crm_mensagem_marcada' && conta.mensagemMarcada,
  }),
}));

// O item como o calendário o monta, a partir do evento do servidor.
const ITEM = paraItem(
  {
    id: 'follow_up_9',
    event_type: 'follow_up_auto_send_message',
    title: 'Mensagem para Mariana',
    starts_at: '2026-10-14T12:00:00Z',
    status: 'overdue',
    send_error_code: 'sem_modelo',
  },
  { fuso: 'America/Sao_Paulo', agora: new Date('2026-10-15T12:00:00Z') }
);

const montar = () =>
  mount(CalendarioItem, {
    props: {
      item: ITEM,
      hoje: '2026-10-15',
      fuso: 'America/Sao_Paulo',
      idioma: 'pt-BR',
    },
  });

describe('CalendarioItem — "Não saiu" (#1590)', () => {
  it('sem a flag crm_mensagem_marcada, não mostra o motivo, como antes', () => {
    conta.mensagemMarcada = false;

    expect(montar().find('[data-item-falha]').exists()).toBe(false);
  });

  it('com a flag, mostra por que a mensagem não saiu', () => {
    conta.mensagemMarcada = true;
    const linha = montar().find('[data-item-falha]');

    expect(linha.exists()).toBe(true);
    expect(linha.text()).toContain('CRM_MENSAGEM_MARCADA.FALHA.sem_modelo');
  });
});
