import { shallowMount, flushPromises } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import BookingPageView from '../components/BookingPageView.vue';
import BookingPostMeeting from '../components/BookingPostMeeting.vue';

// A tela de quem só vê (agendamento_view, J8-A4) também mostra "Depois da
// reunião" (#1193), sem nenhum botão de mudar.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { show: vi.fn() },
}));

const PAGE = {
  id: 7,
  title: 'Consulta',
  enabled: false,
  people: [{ name: 'Ana' }],
  post_meeting: { mode: 'auto', stage_id: 21, pipeline_id: 2 },
};

describe('BookingPageView', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    BookingPagesAPI.show.mockResolvedValue({ data: { payload: PAGE } });
  });

  it('shows the after-the-meeting summary read-only', async () => {
    const wrapper = shallowMount(BookingPageView, { props: { pageId: 7 } });
    await flushPromises();

    const section = wrapper.findComponent(BookingPostMeeting);
    expect(section.exists()).toBe(true);
    expect(section.props()).toEqual({
      pageId: 7,
      postMeeting: PAGE.post_meeting,
      canManage: false,
    });
  });

  it('passes an empty setting when the page has none yet', async () => {
    BookingPagesAPI.show.mockResolvedValue({
      data: { payload: { ...PAGE, post_meeting: undefined } },
    });
    const wrapper = shallowMount(BookingPageView, { props: { pageId: 7 } });
    await flushPromises();

    expect(
      wrapper.findComponent(BookingPostMeeting).props('postMeeting')
    ).toEqual({});
  });
});
