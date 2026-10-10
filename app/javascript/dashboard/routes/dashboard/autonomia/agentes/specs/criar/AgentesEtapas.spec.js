import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgentesEtapas from '../../components/AgentesEtapas.vue';

withFullI18n('pt_BR');

const passos = wrapper => wrapper.findAll('[data-etapa]');

describe('AgentesEtapas', () => {
  it('names the three steps Conte · Confira · Comece, in order', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 1 } });
    expect(passos(wrapper).map(p => p.text())).toEqual([
      '1Conte',
      '2Confira',
      '3Comece',
    ]);
    expect(wrapper.get('ol').attributes('aria-label')).toBe('Etapas');
  });

  it('marks only the current step with aria-current', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 2 } });
    const atuais = passos(wrapper).map(p => p.attributes('aria-current'));
    expect(atuais).toEqual([undefined, 'step', undefined]);
  });

  it('says a past step is done, in text, not only with the check', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 2 } });
    const conte = passos(wrapper)[0];
    expect(conte.attributes('data-estado')).toBe('feito');
    expect(conte.get('.sr-only').text()).toBe('(feito)');
    expect(conte.find('.i-lucide-check').exists()).toBe(true);
  });

  it('keeps the step names in the readable gray-12 (contrast AA)', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 1 } });
    passos(wrapper).forEach(passo => {
      expect(passo.get('[data-nome]').classes()).toContain('text-n-slate-12');
    });
  });

  it('shows the compact phone line "Etapa N de 3 · Nome"', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 2 } });
    expect(wrapper.get('[data-compacto]').text()).toBe(
      'Etapa 2 de 3 · Confira'
    );
  });

  it('marks every step done when the agent is ready (step 4)', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 4 } });
    expect(passos(wrapper).map(p => p.attributes('data-estado'))).toEqual([
      'feito',
      'feito',
      'feito',
    ]);
    expect(wrapper.get('[data-compacto]').text()).toBe('Pronto');
  });

  it('is not a set of buttons: the steps only show where you are', () => {
    const wrapper = mount(AgentesEtapas, { props: { atual: 3 } });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('a').exists()).toBe(false);
  });
});
