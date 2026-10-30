import { mount } from '@vue/test-utils';
import NovaConversaHeroi from '../NovaConversaHeroi.vue';

vi.mock('vue-i18n', () => ({
  I18nT: {
    props: ['keypath'],
    template: '<span>{{ keypath }}:<slot name="nome" /></span>',
  },
}));

// #2255 — o nome entra no título por slot: telefone não quebra no hífen; nome com espaço quebra.
const montar = titulo =>
  mount(NovaConversaHeroi, {
    props: { tituloId: 'titulo', titulo },
    global: {
      mocks: { $t: chave => chave },
    },
  });

const nomeNoTitulo = wrapper => wrapper.find('[data-view-title] span span');

describe('NovaConversaHeroi', () => {
  it('não deixa o telefone quebrar a linha no hífen', () => {
    const wrapper = montar({
      chave: 'NOVA_CONVERSA.TITULO',
      nome: '+55 11 95555-4444',
    });

    expect(wrapper.find('[data-view-title]').text()).toBe(
      'NOVA_CONVERSA.TITULO:+55 11 95555-4444'
    );
    expect(nomeNoTitulo(wrapper).classes()).toContain('whitespace-nowrap');
  });

  it('deixa o nome com espaços quebrar normalmente', () => {
    const wrapper = montar({
      chave: 'NOVA_CONVERSA.TITULO',
      nome: 'Maria Aparecida dos Santos',
    });

    expect(nomeNoTitulo(wrapper).classes()).not.toContain('whitespace-nowrap');
  });

  it('sem nome, mostra só o título da chave', () => {
    const wrapper = montar({
      chave: 'NOVA_CONVERSA.TITULO_SEM_CONTATO',
      nome: '',
    });

    expect(wrapper.find('[data-view-title]').text()).toBe(
      'NOVA_CONVERSA.TITULO_SEM_CONTATO'
    );
  });
});
