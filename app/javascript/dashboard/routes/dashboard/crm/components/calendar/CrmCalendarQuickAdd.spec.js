import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from '../../../../../../../../vitest.i18n';
import CrmCalendarQuickAdd from './CrmCalendarQuickAdd.vue';
import crmBookingPagesAPI from 'dashboard/api/crmBookingPages';

// Dica do primeiro passo de Calendário › + Novo › Reunião (#1285): com o
// agendamento novo e uma página que serve, fala dos dias e horários livres da
// janela seguinte; sem a flag ou sem página, continua a dica antiga.
withFullI18n('pt_BR');

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getCards: vi.fn(() => Promise.resolve({ data: {} })) },
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { bookable: vi.fn() },
}));

const OLD_HINT =
  'Escolha o card e clique em Continuar para configurar a reunião (caixa de entrada, convidados, horário).';
const NEW_HINT =
  'Escolha o card e toque em Continuar para ver os dias e horários livres.';

const openQuickAdd = async (props = {}) => {
  const wrapper = mount(CrmCalendarQuickAdd, {
    props: {
      show: false,
      date: '2099-10-20',
      defaultType: 'meeting',
      meetingsEnabled: true,
      ...props,
    },
    attachTo: document.body,
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
  await wrapper.setProps({ show: true });
  await flushPromises();
  return wrapper;
};

const hint = wrapper => wrapper.get('[data-quick-add-hint]').text();

describe('CrmCalendarQuickAdd', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    crmBookingPagesAPI.bookable.mockResolvedValue({
      data: { payload: [{ id: 3 }] },
    });
  });

  afterEach(() => {
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('with the new scheduling and a usable page, the hint speaks of free days and times', async () => {
    const wrapper = await openQuickAdd({ bookingV2: true });

    expect(hint(wrapper)).toBe(NEW_HINT);
  });

  it('without the account flag, keeps the old hint and asks nothing', async () => {
    const wrapper = await openQuickAdd({ bookingV2: false });

    expect(hint(wrapper)).toBe(OLD_HINT);
    expect(crmBookingPagesAPI.bookable).not.toHaveBeenCalled();
  });

  it('with the flag but no usable page, keeps the old hint', async () => {
    crmBookingPagesAPI.bookable.mockResolvedValue({ data: { payload: [] } });
    const wrapper = await openQuickAdd({ bookingV2: true });

    expect(hint(wrapper)).toBe(OLD_HINT);
  });

  it('when the pages cannot be read, keeps the old hint', async () => {
    crmBookingPagesAPI.bookable.mockRejectedValue({
      response: { status: 401 },
    });
    const wrapper = await openQuickAdd({ bookingV2: true });

    expect(hint(wrapper)).toBe(OLD_HINT);
  });

  it('shows no hint while it does not know which window comes next', async () => {
    crmBookingPagesAPI.bookable.mockReturnValue(new Promise(() => {}));
    const wrapper = await openQuickAdd({ bookingV2: true });

    expect(wrapper.find('[data-quick-add-hint]').exists()).toBe(false);
  });

  it('only asks for the pages when the type is meeting', async () => {
    const wrapper = await openQuickAdd({
      bookingV2: true,
      defaultType: 'whatsapp',
    });

    expect(crmBookingPagesAPI.bookable).not.toHaveBeenCalled();
    expect(hint(wrapper)).toContain('para configurar os detalhes nele');
  });
});
