// Barra de progresso da pesquisa acima da lista (#679). Portado de
// ResearchBatchProgress (ResearchStatePresentation.test.tsx, no Orth), sem o
// texto de cobrança, que ficou fora por decisão do Rodrigo.
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ResearchProgressBar from '../../components/search/ResearchProgressBar.vue';

withFullI18n();

const progress = (extra = {}) => ({
  total: 20,
  done: 0,
  running: 0,
  queued: 0,
  failed: 0,
  ...extra,
});

const mountBar = value =>
  mount(ResearchProgressBar, { props: { progress: value } });

describe('ResearchProgressBar', () => {
  it.each([
    [progress({ done: 20 }), '20 de 20 concluídos · concluído'],
    [
      progress({ total: 25, done: 20, running: 5 }),
      '20 de 25 concluídos · em andamento',
    ],
    [progress({ total: 31, queued: 31 }), '0 de 31 concluídos · em andamento'],
  ])('mostra %o sem inventar conclusão', (value, text) => {
    const wrapper = mountBar(value);

    expect(wrapper.find('[data-test="research-progress-text"]').text()).toBe(
      text
    );
  });

  it('falha conta como concluída e aparece à parte', () => {
    const wrapper = mountBar(
      progress({ total: 4, done: 2, failed: 1, running: 1 })
    );

    expect(wrapper.text()).toContain('3 de 4 concluídos · em andamento');
    expect(wrapper.text()).toContain('1 com falha');
  });

  it('barra acessível com os números da pesquisa', () => {
    const bar = mountBar(progress({ total: 25, done: 20, running: 5 })).find(
      '[role="progressbar"]'
    );

    expect(bar.attributes('aria-valuemin')).toBe('0');
    expect(bar.attributes('aria-valuemax')).toBe('25');
    expect(bar.attributes('aria-valuenow')).toBe('20');
    expect(bar.attributes('aria-label')).toBe('20 de 25 concluídos');
    expect(bar.find('div').attributes('style')).toContain('width: 80%');
  });

  it.each([null, undefined, progress({ total: 0 })])(
    'sem pesquisa (%o) não aparece',
    value => {
      const wrapper = mountBar(value);

      expect(wrapper.find('[role="progressbar"]').exists()).toBe(false);
      expect(wrapper.text()).toBe('');
    }
  );

  it('nenhum texto de crédito ou cobrança', () => {
    const text = mountBar(progress({ done: 3, queued: 17 }))
      .text()
      .toLowerCase();

    expect(text).not.toContain('crédito');
    expect(text).not.toContain('cobr');
  });
});
