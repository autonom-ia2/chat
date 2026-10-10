import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsQuoteMessage from '../components/MetaAdsQuoteMessage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import MessageApi from 'dashboard/api/inbox/message';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { quoteMessage: vi.fn() },
}));
vi.mock('dashboard/api/inbox/message', () => ({
  default: { create: vi.fn() },
}));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));

const CARD = { id: 77, conversation_id: 901, title: 'Maria', value: 1500 };
const SUGGESTION = {
  card_id: 77,
  conversation_id: 901,
  applies: true,
  reason: null,
  message: 'Oi! Consegui o valor com a instalação inclusa. Posso te mandar?',
  source_quote: 'o valor com a instalação inclusa',
};

const mountMessage = () =>
  mount(MetaAdsQuoteMessage, {
    props: { card: CARD },
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
    },
  });

const suggest = async wrapper => {
  await wrapper.find('[data-quote-suggest]').trigger('click');
  await flushPromises();
};

describe('Anúncios da Meta · mensagem sugerida para proposta parada (#1100, F4a)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.quoteMessage.mockResolvedValue({
      data: { quote_message: SUGGESTION },
    });
    MessageApi.create.mockResolvedValue({ data: { id: 1 } });
  });

  it('asks only on click and shows "writing" meanwhile', async () => {
    let answer;
    CrmMetaAdsConnectionAPI.quoteMessage.mockReturnValue(
      new Promise(resolve => {
        answer = resolve;
      })
    );
    const wrapper = mountMessage();
    expect(CrmMetaAdsConnectionAPI.quoteMessage).not.toHaveBeenCalled();
    expect(wrapper.find('[data-quote-suggest]').classes()).toContain(
      'min-h-11'
    );

    await wrapper.find('[data-quote-suggest]').trigger('click');

    expect(CrmMetaAdsConnectionAPI.quoteMessage).toHaveBeenCalledWith(77);
    expect(wrapper.find('[data-quote-suggest]').text()).toContain(
      'AI.QUOTE.WRITING'
    );
    answer({ data: { quote_message: SUGGESTION } });
    await flushPromises();
    expect(wrapper.find('[data-quote-draft]').exists()).toBe(true);
  });

  it('shows the suggestion, editable, with where it came from, and sends only on click', async () => {
    const wrapper = mountMessage();
    await suggest(wrapper);

    const draft = wrapper.find('[data-quote-draft]');
    expect(draft.element.value).toBe(SUGGESTION.message);
    expect(wrapper.find('[data-quote-source]').text()).toContain(
      'o valor com a instalação inclusa'
    );
    expect(MessageApi.create).not.toHaveBeenCalled();

    await draft.setValue('Oi, Maria! Posso te mandar o valor com instalação?');
    await wrapper.find('[data-quote-send]').trigger('click');
    await flushPromises();

    expect(MessageApi.create).toHaveBeenCalledTimes(1);
    expect(MessageApi.create).toHaveBeenCalledWith({
      conversationId: 901,
      message: 'Oi, Maria! Posso te mandar o valor com instalação?',
    });
    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SENT'
    );
    expect(wrapper.find('[data-quote-send]').exists()).toBe(false);
    expect(wrapper.find('[data-quote-sent]').exists()).toBe(true);
  });

  it('copies the edited text', async () => {
    const wrapper = mountMessage();
    await suggest(wrapper);

    await wrapper.find('[data-quote-draft]').setValue('Texto editado');
    await wrapper.find('[data-quote-copy]').trigger('click');
    await flushPromises();

    expect(copyTextToClipboard).toHaveBeenCalledWith('Texto editado');
    expect(MessageApi.create).not.toHaveBeenCalled();
  });

  it('says so when the browser refuses the clipboard', async () => {
    copyTextToClipboard.mockRejectedValueOnce(new Error('denied'));
    const wrapper = mountMessage();
    await suggest(wrapper);

    await wrapper.find('[data-quote-copy]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.QUOTE.COPY_FAILED'
    );
    expect(useAlert).not.toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.QUOTE.COPIED'
    );
  });

  it('the draft field is tall enough to review the message', async () => {
    const wrapper = mountMessage();
    await suggest(wrapper);

    expect(wrapper.find('[data-quote-draft]').classes()).toEqual(
      expect.arrayContaining(['!h-auto', 'min-h-40'])
    );
  });

  it('when it does not apply, says why in words and offers nothing to send', async () => {
    CrmMetaAdsConnectionAPI.quoteMessage.mockResolvedValue({
      data: {
        quote_message: {
          ...SUGGESTION,
          applies: false,
          reason: 'window_closed',
          message: null,
          source_quote: null,
        },
      },
    });
    const wrapper = mountMessage();
    await suggest(wrapper);

    expect(wrapper.find('[data-quote-declined]').text()).toContain(
      'AI.QUOTE.REASONS.WINDOW_CLOSED'
    );
    expect(wrapper.find('[data-quote-draft]').exists()).toBe(false);
    expect(wrapper.find('[data-quote-send]').exists()).toBe(false);
  });

  it('a failed request can be tried again', async () => {
    CrmMetaAdsConnectionAPI.quoteMessage.mockRejectedValueOnce(
      new Error('ai_request_failed')
    );
    const wrapper = mountMessage();
    await suggest(wrapper);

    expect(wrapper.find('[data-quote-declined]').text()).toContain(
      'AI.QUOTE.FAILED'
    );
    await suggest(wrapper);

    expect(wrapper.find('[data-quote-draft]').exists()).toBe(true);
  });

  it('a failed send keeps the draft and the button', async () => {
    MessageApi.create.mockRejectedValue(new Error('422'));
    const wrapper = mountMessage();
    await suggest(wrapper);

    await wrapper.find('[data-quote-send]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.META_ADS_HUB.AI.QUOTE.SEND_FAILED'
    );
    expect(wrapper.find('[data-quote-send]').exists()).toBe(true);
    expect(wrapper.find('[data-quote-draft]').element.value).toBe(
      SUGGESTION.message
    );
  });
});
