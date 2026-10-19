import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import EmailsVizinhos from '../email/EmailsVizinhos.vue';
import { CONVERSAS_DO_CONTATO } from '../email/useConversaDeEmail';

// #1786 — no e-mail novo, a conversa anterior/seguinte do contato aparece no resumo do
// topo, com a data no fuso da conta, no lugar da pílula do Chatwoot que boiava na tela.
vi.mock('../email/useConversaDeEmail', async original => {
  const { computed: calculado } = await import('vue');
  return {
    ...(await original()),
    useEmailDaConversa: () => ({ fuso: calculado(() => 'America/Sao_Paulo') }),
  };
});
vi.mock('vue-i18n', async () => {
  const { ref: valor } = await import('vue');
  return {
    useI18n: () => ({
      t: (chave, { data } = {}) => `${chave} ${data}`,
      locale: valor('pt_BR'),
    }),
  };
});
vi.mock('../useAgora', async () => {
  const { ref: valor } = await import('vue');
  // 19/10/2026 12:00 UTC
  return { useAgora: () => valor(1792411200) };
});

// 17/10/2026 01:30 UTC = 16/10 22:30 em São Paulo: a data é a do fuso da conta.
const ANTERIOR = { id: 11, created_at: 1792200600 };
const SEGUINTE = { id: 14, created_at: 1792335600 };

describe('EmailsVizinhos', () => {
  it('mostra o anterior e o seguinte com o link e a data no fuso da conta', () => {
    const wrapper = mount(EmailsVizinhos, {
      global: {
        provide: {
          [CONVERSAS_DO_CONTATO]: {
            olderConversation: ref(ANTERIOR),
            newerConversation: ref(SEGUINTE),
            buildConversationPath: id => `/app/accounts/1/conversations/${id}`,
          },
        },
        stubs: {
          Icon: true,
          RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
        },
      },
    });

    const links = wrapper.findAll('[data-email-vizinho]');
    expect(links.map(l => l.attributes('data-email-vizinho'))).toEqual([
      'EMAIL_ANTERIOR',
      'EMAIL_SEGUINTE',
    ]);
    expect(links[0].attributes('href')).toBe(
      '/app/accounts/1/conversations/11'
    );
    // 16, não 17: o dia vem do fuso da conta, não do UTC.
    expect(links[0].text()).toBe(
      'CONVERSA_CANAL.EMAIL.EMAIL_ANTERIOR 16 de out.'
    );
    expect(links[1].attributes('href')).toBe(
      '/app/accounts/1/conversations/14'
    );
  });

  it('sem vizinha (ou fora do MessagesView), não mostra nada', () => {
    const semVizinha = mount(EmailsVizinhos, {
      global: {
        provide: {
          [CONVERSAS_DO_CONTATO]: {
            olderConversation: ref(null),
            newerConversation: ref(null),
            buildConversationPath: () => '',
          },
        },
        stubs: { Icon: true },
      },
    });
    expect(semVizinha.find('[data-email-vizinho]').exists()).toBe(false);

    const semProvide = mount(EmailsVizinhos, {
      global: { stubs: { Icon: true } },
    });
    expect(semProvide.find('[data-email-vizinho]').exists()).toBe(false);
  });
});
