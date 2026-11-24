import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/reenvioHorario.json';
import LivreMelhorHorario from '../components/LivreMelhorHorario.vue';

const A = en.REENVIO_HORARIO.AUTOMACAO;

const montar = props =>
  mount(LivreMelhorHorario, {
    props: { rotulo: A.ROTULO, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

describe('LivreMelhorHorario (#3101)', () => {
  it('starts as "right away" and switches to the best time', async () => {
    const wrapper = montar({});
    expect(
      wrapper.find('[data-quando="na_hora"]').attributes('aria-checked')
    ).toBe('true');
    expect(wrapper.find('[data-quando-regras]').exists()).toBe(false);

    await wrapper.find('[data-quando="melhor_horario"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['melhor_horario']);
  });

  it('names the best time as the campaign does', () => {
    const wrapper = montar({});

    expect(wrapper.find('[data-quando="melhor_horario"]').text()).toContain(
      en.REENVIO_HORARIO.MELHOR_HORARIO.TITULO
    );
  });

  it('says the account hours when waiting for the best time', () => {
    const wrapper = montar({
      modelValue: 'melhor_horario',
      horarioPermitido: 'every day, 9am to 6pm',
    });

    expect(wrapper.find('[data-quando-regras]').text()).toContain(
      'every day, 9am to 6pm'
    );
  });
});
