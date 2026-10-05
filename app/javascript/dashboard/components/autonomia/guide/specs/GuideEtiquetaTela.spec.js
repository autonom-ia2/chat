import { mount } from '@vue/test-utils';
import GuideEtiquetaTela from '../GuideEtiquetaTela.vue';

// O texto final em pt_BR, sem montar o vue-i18n de verdade (as mesmas strings de crm.json).
const { traduzir } = vi.hoisted(() => {
  const MENSAGENS = {
    'AUTONOMIA_GUIDE.TELA.SELECTED.CARDS': [
      'Vendo: {count} card selecionado',
      'Vendo: {count} cards selecionados',
    ],
    'AUTONOMIA_GUIDE.TELA.OPEN.CONVERSAS': 'Vendo: a conversa aberta',
    'AUTONOMIA_GUIDE.TELA.REMOVE': 'Perguntar sem usar o que está na tela',
    'AUTONOMIA_GUIDE.TELA.REMOVED':
      'A próxima pergunta vai sem o que está na tela.',
  };
  return {
    traduzir: (chave, params, quantos) => {
      const modelo = MENSAGENS[chave] || chave;
      const texto = Array.isArray(modelo)
        ? modelo[quantos === 1 ? 0 : 1]
        : modelo;
      return texto.split('{count}').join(String(params?.count));
    },
  };
});

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: traduzir }) }));

const montar = props =>
  mount(GuideEtiquetaTela, { props, global: { mocks: { $t: traduzir } } });

describe('GuideEtiquetaTela', () => {
  it('diz quantos estão selecionados, com o × acessível de 44 px', () => {
    const wrapper = montar({
      tela: {
        rota: 'crm_kanban_index',
        selecionados: { recurso: 'crm/cards', ids: [1, 2], total: 12 },
      },
    });

    expect(wrapper.find('[data-etiqueta-tela] [role="status"]').text()).toBe(
      'Vendo: 12 cards selecionados'
    );
    const remover = wrapper.find('[data-etiqueta-tela-remover]');
    expect(remover.attributes('aria-label')).toBe(
      'Perguntar sem usar o que está na tela'
    );
    expect(remover.classes()).toEqual(expect.arrayContaining(['h-11', 'w-11']));
  });

  it('com só um registro aberto, diz qual é', () => {
    const wrapper = montar({
      tela: { aberto: [{ recurso: 'conversations', id: 7 }] },
    });

    expect(wrapper.text()).toContain('Vendo: a conversa aberta');
  });

  it('tela sem nada aberto ou selecionado não mostra etiqueta', () => {
    const wrapper = montar({
      tela: { rota: 'crm_kanban_index', filtros: { pipeline_id: 3 } },
    });

    expect(wrapper.find('[data-etiqueta-tela]').exists()).toBe(false);
  });

  it('o × avisa o leitor de tela e pede para tirar', async () => {
    const wrapper = montar({
      tela: { selecionados: { recurso: 'crm/cards', ids: [1], total: 1 } },
    });

    await wrapper.find('[data-etiqueta-tela-remover]').trigger('click');

    expect(wrapper.emitted('remover')).toHaveLength(1);
    expect(wrapper.find('.sr-only[role="status"]').text()).toBe(
      'A próxima pergunta vai sem o que está na tela.'
    );
    await wrapper.setProps({ oculta: true });
    expect(wrapper.find('[data-etiqueta-tela]').exists()).toBe(false);
  });
});
