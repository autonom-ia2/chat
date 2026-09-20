import { mount } from '@vue/test-utils';
import OpenAiKeyGuide from '../OpenAiKeyGuide.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave }),
}));

const montar = () => mount(OpenAiKeyGuide);

describe('OpenAiKeyGuide', () => {
  it('mostra os seis passos, na ordem, numerados', () => {
    const wrapper = montar();
    const passos = wrapper.findAll('ol li');

    expect(passos).toHaveLength(6);
    expect(passos.map(p => p.text().replace(/^\d+\s*/, ''))).toEqual([
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.ACCOUNT',
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.BILLING',
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.AUTO_RECHARGE',
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.CREATE_KEY',
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.COPY_NOW',
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.STEPS.PASTE_HERE',
    ]);
    expect(passos[0].text()).toMatch(/^1/);
    expect(passos[5].text()).toMatch(/^6/);
  });

  it('traz os dois avisos que mais travam o cliente', () => {
    const wrapper = montar();
    const avisos = wrapper.findAll('ul li');

    expect(avisos).toHaveLength(2);
    expect(wrapper.text()).toContain(
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.WARNINGS.SUBSCRIPTION'
    );
    expect(wrapper.text()).toContain(
      'INTEGRATION_APPS.OPENAI_KEY_GUIDE.WARNINGS.CARD'
    );
  });

  it('abre os links da OpenAI em outra aba, sem passar a janela original', () => {
    const wrapper = montar();
    const links = wrapper.findAll('a');

    expect(links.map(l => l.attributes('href'))).toEqual([
      'https://platform.openai.com/settings/organization/billing/overview',
      'https://platform.openai.com/api-keys',
    ]);
    links.forEach(link => {
      expect(link.attributes('target')).toBe('_blank');
      expect(link.attributes('rel')).toBe('noopener noreferrer');
    });
  });
});
