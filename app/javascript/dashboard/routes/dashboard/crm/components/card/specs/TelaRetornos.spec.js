import { mount } from '@vue/test-utils';
import TelaRetornos from '../telas/TelaRetornos.vue';

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

// #1590: uma aberta (não saiu, celular desconectado) e uma fechada (o cliente recusou).
const RETORNOS = [
  {
    id: 1,
    title: 'Mensagem para Mariana',
    status: 'overdue',
    automation_mode: 'auto_send_message',
    due_at: '2026-10-14T12:00:00Z',
    send_error_code: 'celular_desconectado',
  },
  {
    id: 2,
    title: 'Mensagem para Paulo',
    status: 'canceled',
    automation_mode: 'auto_send_message',
    due_at: '2026-10-13T12:00:00Z',
    send_error_code: 'recusou',
  },
];

const montar = () =>
  mount(TelaRetornos, {
    props: {
      card: { id: 3 },
      retornos: RETORNOS,
      formato: { quando: () => 'ontem às 09:00' },
    },
    global: {
      provide: { cardRetorno: { contexto: {} } },
      stubs: {
        LembretesQueRepetem: true,
        CrmCardAutoFollowupStatus: true,
        CampoQuando: true,
        Button: true,
      },
    },
  });

describe('TelaRetornos — "Não saiu" (#1590)', () => {
  it('sem a flag crm_mensagem_marcada, não mostra o motivo, como antes', () => {
    conta.mensagemMarcada = false;
    const wrapper = montar();

    expect(wrapper.findAll('[data-retorno-falha]')).toHaveLength(0);
  });

  it('com a flag, mostra por que não saiu, na aberta e na fechada', () => {
    conta.mensagemMarcada = true;
    const wrapper = montar();

    const linhas = wrapper.findAll('[data-retorno-falha]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain(
      'CRM_MENSAGEM_MARCADA.FALHA.celular_desconectado'
    );
    expect(linhas[1].text()).toContain('CRM_MENSAGEM_MARCADA.FALHA.recusou');
  });
});
