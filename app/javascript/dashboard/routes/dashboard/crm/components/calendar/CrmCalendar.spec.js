import { h } from 'vue';
import { mount } from '@vue/test-utils';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import CrmCalendar from './CrmCalendar.vue';

vi.mock('vue-i18n');

// O cabeçalho real traz popovers e seletores de data; aqui basta o seletor de
// funil, que é o ChoiceSelect de verdade.
const HeaderWithPipelinePicker = {
  name: 'CrmCalendarHeader',
  setup() {
    return () =>
      h(ChoiceSelect, {
        modelValue: '1',
        options: [
          { value: '1', label: 'Atendimento' },
          { value: '2', label: 'Comercial' },
        ],
        ariaLabel: 'Funil',
      });
  },
};

let wrapper;

const mountCalendar = () =>
  mount(CrmCalendar, {
    props: { pipelines: [] },
    attachTo: document.body,
    global: {
      stubs: {
        CrmCalendarHeader: HeaderWithPipelinePicker,
        CrmCalendarMonthGrid: true,
        CrmCalendarWeekGrid: true,
        CrmCalendarDayGrid: true,
        CrmCalendarAgenda: true,
      },
    },
  });

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

beforeEach(() => {
  useI18n.mockReturnValue({ t: key => key, locale: { value: 'pt_BR' } });
});

afterEach(() => wrapper?.unmount());

describe('CrmCalendar — atalhos de teclado', () => {
  it('abre o quick-add com "c" fora de campo', async () => {
    wrapper = mountCalendar();
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'c', bubbles: true })
    );
    expect(wrapper.emitted('quickAdd')).toHaveLength(1);
  });

  it('não dispara atalhos com o foco no seletor de funil', async () => {
    wrapper = mountCalendar();
    const trigger = wrapper.get('[role="combobox"]');
    trigger.element.focus();
    const rangesBefore = wrapper.emitted('rangeChange')?.length ?? 0;
    ['c', 'C', 'ArrowLeft', 'ArrowRight'].forEach(key =>
      trigger.element.dispatchEvent(
        new KeyboardEvent('keydown', { key, bubbles: true })
      )
    );
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('quickAdd')).toBeUndefined();
    expect(wrapper.emitted('rangeChange')?.length ?? 0).toBe(rangesBefore);
  });

  it('muda o período com ArrowRight fora de campo (controle do teste acima)', async () => {
    wrapper = mountCalendar();
    const rangesBefore = wrapper.emitted('rangeChange')?.length ?? 0;
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true })
    );
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('rangeChange')?.length ?? 0).toBeGreaterThan(
      rangesBefore
    );
  });
});
