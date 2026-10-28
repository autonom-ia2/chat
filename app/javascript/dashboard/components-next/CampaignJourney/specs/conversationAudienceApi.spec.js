import ConversationAudiencesAPI from 'dashboard/api/campaignJourneyConversationAudiences';
import { createConversationAudienceApi } from '../conversationAudienceApi';

vi.mock('dashboard/api/campaignJourneyConversationAudiences', () => ({
  default: {
    status: vi.fn(),
    create: vi.fn(),
    show: vi.fn(),
    answer: vi.fn(),
    start: vi.fn(),
    stop: vi.fn(),
    resume: vi.fn(),
    conversation: vi.fn(),
    save: vi.fn(),
  },
}));

const money = { usd: 0.4, brl: 2.16 };
const planned = {
  id: 7,
  status: 'planned',
  request: 'quem cotou',
  period: '3m',
  plan: {
    understood: 'Quem pediu cotação',
    name: 'Cotaram',
    minutes: 2,
    conversations: 702,
    cost: money,
    ceiling: { usd: 0.8, brl: 4.32 },
    question: null,
  },
  read: 0,
  total: 702,
  cost: { usd: 0.01, brl: 0.05 },
  people: [],
  left_aside: [],
};

describe('conversationAudienceApi (#2277)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('creates the search and waits for the plan', async () => {
    ConversationAudiencesAPI.create.mockResolvedValue({
      data: { id: 7, status: 'planning' },
    });
    ConversationAudiencesAPI.show.mockResolvedValue({ data: planned });

    const plan = await createConversationAudienceApi().plan({
      request: 'quem cotou',
      period: '3m',
    });

    expect(ConversationAudiencesAPI.create).toHaveBeenCalledWith({
      request: 'quem cotou',
      period: '3m',
    });
    expect(plan).toEqual({
      understood: 'Quem pediu cotação',
      name: 'Cotaram',
      conversations: 702,
      minutes: 2,
      cost: money,
      ceiling: { usd: 0.8, brl: 4.32 },
    });
  });

  it('shows the question with the options as choices, and sends "Tanto faz" in words', async () => {
    ConversationAudiencesAPI.create.mockResolvedValue({ data: { id: 7 } });
    ConversationAudiencesAPI.show.mockResolvedValueOnce({
      data: {
        ...planned,
        status: 'question',
        plan: { question: { text: 'Quantas vezes?', options: ['2', '3'] } },
      },
    });
    const api = createConversationAudienceApi();

    const first = await api.plan({ request: 'quem cota muito', period: '3m' });
    expect(first.question).toEqual({
      text: 'Quantas vezes?',
      options: [
        { id: '2', label: '2' },
        { id: '3', label: '3' },
      ],
    });

    ConversationAudiencesAPI.show.mockResolvedValueOnce({ data: planned });
    await api.plan({ answer: 'tanto-faz', anyLabel: 'Tanto faz' });
    expect(ConversationAudiencesAPI.answer).toHaveBeenCalledWith(
      7,
      'Tanto faz'
    );
  });

  it('turns a failed plan into an error the screen can show', async () => {
    ConversationAudiencesAPI.create.mockResolvedValue({ data: { id: 7 } });
    ConversationAudiencesAPI.show.mockResolvedValue({
      data: { ...planned, status: 'failed', error: 'no_key', plan: {} },
    });

    await expect(
      createConversationAudienceApi().plan({ request: 'x', period: '3m' })
    ).rejects.toMatchObject({ code: 'no_key' });
  });

  it('reopens a search being read with its progress and people', async () => {
    ConversationAudiencesAPI.show.mockResolvedValue({
      data: {
        ...planned,
        status: 'reading',
        read: 140,
        people: [
          {
            id: 3,
            name: 'Mariana',
            contact: '+55 11 9•••• 4321',
            confidence: 'certeza',
            reason: 'Cotou',
            conversation_id: 99,
          },
        ],
        left_aside: [['Fixo', 'sem_contato', 4]],
      },
    });

    const opened = await createConversationAudienceApi().open(7);

    expect(opened.progress).toMatchObject({
      state: 'lendo',
      read: 140,
      total: 702,
      leftAside: [['Fixo', 'sem_contato', 4]],
    });
    expect(opened.progress.people[0]).toEqual({
      id: 3,
      name: 'Mariana',
      contact: '+55 11 9•••• 4321',
      confidence: 'certeza',
      reason: 'Cotou',
      conversationId: 99,
    });
  });

  it('does not reopen a search already saved', async () => {
    ConversationAudiencesAPI.show.mockResolvedValue({
      data: { ...planned, status: 'saved' },
    });

    expect(await createConversationAudienceApi().open(7)).toBeNull();
  });

  describe('while the readers go', () => {
    const found = (id, confidence) => ({
      id,
      name: `P${id}`,
      contact: null,
      confidence,
      reason: 'Cotou',
      conversation_id: id * 10,
    });
    const reading = extra => ({
      data: { ...planned, status: 'reading', cursor: 'c', ...extra },
    });

    beforeEach(() => {
      vi.useFakeTimers();
    });
    afterEach(() => {
      vi.useRealTimers();
    });

    const opened = async () => {
      ConversationAudiencesAPI.show.mockResolvedValueOnce(
        reading({ people: [found(1, 'provavel')], cursor: 'c1' })
      );
      const api = createConversationAudienceApi();
      await api.open(7);
      return api;
    };

    it('asks only for who changed since the last cursor and merges them by id', async () => {
      const api = await opened();
      const onChange = vi.fn();
      ConversationAudiencesAPI.show.mockResolvedValueOnce(
        reading({
          people: [found(2, 'certeza')],
          left_aside: [['P1', 'nao_quer', 1]],
        })
      );

      api.watch(null, onChange);
      await vi.advanceTimersByTimeAsync(3000);

      expect(ConversationAudiencesAPI.show).toHaveBeenLastCalledWith(7, 'c1');
      const update = onChange.mock.calls[0][0];
      expect(update.people.map(person => person.id)).toEqual([2]);
      expect(update.leftAside).toEqual([['P1', 'nao_quer', 1]]);
    });

    it('after "Parar", keeps reading while the wave in flight ends, then reads the whole list once', async () => {
      const api = await opened();
      const onChange = vi.fn();
      ConversationAudiencesAPI.stop.mockResolvedValue({});
      ConversationAudiencesAPI.show
        .mockResolvedValueOnce(
          reading({
            status: 'stopped',
            finishing: true,
            people: [found(2, 'certeza')],
          })
        )
        .mockResolvedValueOnce(reading({ status: 'stopped' }))
        .mockResolvedValueOnce(
          reading({
            status: 'stopped',
            people: [found(1, 'provavel'), found(2, 'certeza')],
          })
        );

      api.watch(null, onChange);
      await api.stop();
      await vi.advanceTimersByTimeAsync(6000);

      expect(onChange).toHaveBeenCalledTimes(2);
      expect(ConversationAudiencesAPI.show).toHaveBeenLastCalledWith(7);
      expect(onChange.mock.calls[1][0]).toMatchObject({ state: 'parado' });
      expect(onChange.mock.calls[1][0].people.map(p => p.id)).toEqual([1, 2]);
    });

    it('gives up while in line without reading any more', async () => {
      const api = await opened();
      const onChange = vi.fn();
      ConversationAudiencesAPI.stop.mockResolvedValue({});

      api.watch(null, onChange);
      await api.giveUp();
      await vi.advanceTimersByTimeAsync(6000);

      expect(onChange).not.toHaveBeenCalled();
    });
  });

  it('says the search is in line only when another one of the account is reading', async () => {
    ConversationAudiencesAPI.start
      .mockResolvedValueOnce({
        data: { ...planned, status: 'queued', ahead_minutes: 4 },
      })
      .mockResolvedValueOnce({
        data: { ...planned, status: 'queued', ahead_minutes: null },
      });
    const api = createConversationAudienceApi();

    expect(await api.start()).toEqual({ queued: true, aheadMinutes: 4 });
    expect(await api.start()).toEqual({ queued: false, aheadMinutes: null });
  });
});
