import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import UltimaMudanca from '../../components/pagina/UltimaMudanca.vue';

// #1428 (parte 3) — a faixa "Última mudança", com a cópia real em pt_BR.
withFullI18n('pt_BR');

const montar = (ultima, props = {}) =>
  mount(UltimaMudanca, { props: { ultima, nome: 'Bia', ...props } });

describe('UltimaMudanca', () => {
  it('lists the summaries of what went in and offers to undo', async () => {
    const wrapper = montar({ thread_id: 4, linhas: ['Curto', 'Formal'] });

    expect(wrapper.text()).toContain('Última mudança: Curto; Formal.');
    await wrapper.find('[data-desfazer-ultima]').trigger('click');
    expect(wrapper.emitted('desfazer')).toHaveLength(1);
  });

  it('has a plain text when there is no summary', () => {
    expect(montar({ thread_id: 4, linhas: [] }).text()).toContain(
      'Última mudança feita conversando.'
    );
  });

  it('after a 409 tells the agent changed and hides the undo', () => {
    const wrapper = montar(
      { thread_id: 4, linhas: ['Curto'] },
      { erro: 'mudou' }
    );

    expect(wrapper.find('[data-desfazer-ultima]').exists()).toBe(false);
    expect(wrapper.find('[data-erro-desfazer]').text()).toContain(
      'Bia mudou depois desta conversa'
    );
  });

  it('keeps the undo after a generic failure', () => {
    const wrapper = montar(
      { thread_id: 4, linhas: ['Curto'] },
      { erro: 'falhou' }
    );

    expect(wrapper.find('[data-desfazer-ultima]').exists()).toBe(true);
    expect(wrapper.find('[data-erro-desfazer]').text()).toBe(
      'Não consegui desfazer agora. Tente de novo.'
    );
  });
});
