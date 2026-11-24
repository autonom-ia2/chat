import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import reenvioHorario from 'dashboard/i18n/locale/en/reenvioHorario.json';
import MelhorHorarioDaCampanha from '../melhorHorario/MelhorHorarioDaCampanha.vue';

const en = reenvioHorario;
const M = reenvioHorario.REENVIO_HORARIO.MELHOR_HORARIO;

const montar = props =>
  mount(MelhorHorarioDaCampanha, {
    props: { total: 450, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

describe('MelhorHorarioDaCampanha (#3101)', () => {
  it('turns on and off through the switch', async () => {
    const wrapper = montar({ modelValue: false, conhecidos: 312 });

    await wrapper.find('input[role="switch"]').setValue(true);
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([true]);
    expect(wrapper.find('[data-melhor-horario-cobertura]').exists()).toBe(
      false
    );
  });

  it('splits the audience and says the account hours when on', () => {
    const wrapper = montar({
      modelValue: true,
      conhecidos: 312,
      horarioPermitido: 'Monday to Friday, 8am to 8pm',
    });

    const cobertura = wrapper.find('[data-melhor-horario-cobertura]').text();
    expect(cobertura).toContain('312 people');
    expect(cobertura).toContain('138 people');
    expect(wrapper.find('[data-melhor-horario-conta]').text()).toContain(
      'Monday to Friday, 8am to 8pm'
    );
  });

  it('shows it is counting while the number is not there', () => {
    const wrapper = montar({ modelValue: true, conhecidos: null });

    expect(wrapper.find('[data-melhor-horario-contando]').exists()).toBe(true);
  });

  it('is off limits when nobody in the audience ever replied', () => {
    const wrapper = montar({
      modelValue: false,
      conhecidos: 0,
      quando: 'later',
    });

    expect(wrapper.find('input[role="switch"]').element.disabled).toBe(true);
    expect(wrapper.find('[data-melhor-horario-ajuda]').text()).toContain(
      M.INICIO.LATER
    );
  });

  it('can still be turned off when it was on and nobody has a known hour anymore', () => {
    const wrapper = montar({ modelValue: true, conhecidos: 0 });

    expect(wrapper.find('input[role="switch"]').element.disabled).toBe(false);
  });

  it('says any time works when the account has no allowed hours', () => {
    const wrapper = montar({ modelValue: true, conhecidos: 10 });

    expect(wrapper.find('[data-melhor-horario-conta]').text()).toBe(
      M.QUALQUER_HORA
    );
  });
});
