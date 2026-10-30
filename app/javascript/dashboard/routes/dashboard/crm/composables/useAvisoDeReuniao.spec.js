import { flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  ESPERA_MAXIMA_MS,
  dataDaReuniao,
  useAvisoDeReuniao,
} from './useAvisoDeReuniao';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => `${key} ${JSON.stringify(params)}`,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { upcomingMeetings: vi.fn() },
}));

const resposta = cards => ({
  data: { payload: { timezone: 'America/Sao_Paulo', cards } },
});

describe('useAvisoDeReuniao', () => {
  beforeEach(() => vi.clearAllMocks());

  it('escreve a data no fuso da conta, com o idioma do painel (pt_BR)', () => {
    expect(
      dataDaReuniao('2026-10-24T13:00:00Z', 'America/Sao_Paulo', 'pt_BR')
    ).toBe('24/10/2026, 10:00');
  });

  it('um card com reunião: o aviso traz a data', async () => {
    CrmKanbanAPI.upcomingMeetings.mockResolvedValue(
      resposta([{ card_id: 7, starts_at: '2026-10-24T10:00:00-03:00' }])
    );
    const { aviso, consultar } = useAvisoDeReuniao();

    await consultar([7]);

    expect(CrmKanbanAPI.upcomingMeetings).toHaveBeenCalledWith([7]);
    expect(aviso.value).toBe(
      'CRM_CARD.ARQUIVAR.REUNIAO {"quando":"24/10/2026, 10:00"}'
    );
  });

  it('lote: o aviso conta quantos cards têm reunião', async () => {
    CrmKanbanAPI.upcomingMeetings.mockResolvedValue(
      resposta([
        { card_id: 1, starts_at: '2026-10-24T10:00:00-03:00' },
        { card_id: 3, starts_at: '2026-10-25T10:00:00-03:00' },
      ])
    );
    const { aviso, consultar } = useAvisoDeReuniao();

    await consultar([1, 2, 3]);

    expect(aviso.value).toBe('CRM_KANBAN.BULK.DELETE_MEETINGS {"count":2}');
  });

  it('sem reunião, ou se a consulta falhar, não há aviso', async () => {
    const { aviso, consultar } = useAvisoDeReuniao();
    CrmKanbanAPI.upcomingMeetings.mockResolvedValue(resposta([]));
    await consultar([1]);
    expect(aviso.value).toBe('');

    CrmKanbanAPI.upcomingMeetings.mockRejectedValue(new Error('falhou'));
    await consultar([1]);
    await flushPromises();
    expect(aviso.value).toBe('');
  });

  it('carrega até a resposta chegar; se falhar, libera sem aviso', async () => {
    let responder;
    CrmKanbanAPI.upcomingMeetings.mockReturnValueOnce(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const { aviso, carregando, consultar } = useAvisoDeReuniao();

    const consulta = consultar([7]);
    expect(carregando.value).toBe(true);
    responder(resposta([]));
    await consulta;
    expect(carregando.value).toBe(false);

    CrmKanbanAPI.upcomingMeetings.mockRejectedValueOnce(new Error('falhou'));
    await consultar([7]);
    expect([carregando.value, aviso.value]).toEqual([false, '']);
  });

  it('a consulta que não responde libera o botão depois do teto', async () => {
    vi.useFakeTimers();
    CrmKanbanAPI.upcomingMeetings.mockReturnValueOnce(new Promise(() => {}));
    const { carregando, consultar } = useAvisoDeReuniao();

    consultar([7]);
    expect(carregando.value).toBe(true);
    vi.advanceTimersByTime(ESPERA_MAXIMA_MS);
    expect(carregando.value).toBe(false);
    vi.useRealTimers();
  });
});
