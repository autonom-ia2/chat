import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import AcoesSoLeitura from './AcoesSoLeitura.vue';
import ParticipantesSoLeitura from './ParticipantesSoLeitura.vue';
import en from 'dashboard/i18n/locale/en/conversation.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/conversation.json';

// #1804: quem só lê vê responsável, time, prioridade, etiquetas e
// participantes no painel, sem nenhum controle de edição.
const montar = (componente, { chat, labels = [], participantes = [] } = {}) => {
  const show = vi.fn();
  const store = createStore({
    getters: {
      getSelectedChat: () => chat,
      'labels/getLabels': () => [
        { id: 1, title: 'vip', color: '#f00' },
        { id: 2, title: 'atraso', color: '#0f0' },
      ],
      'conversationLabels/getConversationLabels': () => () => labels,
      'conversationWatchers/getByConversationId': () => () => participantes,
    },
    actions: { 'conversationWatchers/show': show },
  });
  const wrapper = mount(componente, {
    props: componente === ParticipantesSoLeitura ? { conversationId: 9 } : {},
    global: {
      plugins: [
        store,
        createI18n({ legacy: false, locale: 'pt_BR', messages: { en, pt_BR } }),
      ],
      stubs: { Avatar: true },
    },
  });
  return { wrapper, show };
};

describe('painel de quem só lê (#1804)', () => {
  it('mostra responsável, time, prioridade e etiquetas sem controles', () => {
    const { wrapper } = montar(AcoesSoLeitura, {
      chat: {
        id: 9,
        priority: 'high',
        meta: { assignee: { name: 'Ana Atendente' }, team: { name: 'Vendas' } },
      },
      labels: ['vip'],
    });

    const texto = wrapper.text();
    expect(texto).toContain('Ana Atendente');
    expect(texto).toContain('Vendas');
    expect(texto).toContain('Alta');
    expect(texto).toContain('vip');
    expect(texto).not.toContain('atraso');
    expect(wrapper.findAll('button, input')).toHaveLength(0);
  });

  it('diz "Ninguém" e "Nenhuma etiqueta" quando não há', () => {
    const { wrapper } = montar(AcoesSoLeitura, { chat: { id: 9, meta: {} } });

    const texto = wrapper.text();
    expect(texto).toContain('Ninguém');
    expect(texto).toContain('Nenhuma');
    expect(texto).toContain('Nenhuma etiqueta');
  });

  it('busca e lista os participantes, sem botão de participar', async () => {
    const { wrapper, show } = montar(ParticipantesSoLeitura, {
      participantes: [
        { id: 2, name: 'Ana Atendente' },
        { id: 7, name: 'Leitora' },
      ],
    });
    await flushPromises();

    expect(show).toHaveBeenCalledWith(expect.anything(), { conversationId: 9 });
    expect(wrapper.findAll('li').map(li => li.text())).toEqual([
      'Ana Atendente',
      'Leitora',
    ]);
    expect(wrapper.findAll('button')).toHaveLength(0);
  });

  it('diz que ninguém participa quando a lista está vazia', () => {
    const { wrapper } = montar(ParticipantesSoLeitura);

    expect(wrapper.text()).toBe('Ninguém participa');
  });
});
