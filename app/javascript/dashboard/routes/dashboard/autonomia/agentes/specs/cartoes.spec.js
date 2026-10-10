import { mount } from '@vue/test-utils';
import AgenteCartao from '../components/AgenteCartao.vue';
import ModeloCartao from '../components/ModeloCartao.vue';
import AgentesHeroi from '../components/AgentesHeroi.vue';
import { MODELOS } from '../constants/modelos';

const agente = extra => ({
  id: 5,
  name: 'Duda',
  status: 'active',
  enabled: true,
  agent_type: 'support',
  actuation: 'external',
  channels_count: 1,
  ...extra,
});

const canal = {
  inbox_id: 10,
  name: 'WhatsApp do Centro',
  occupied_by: { kind: 'agent', agent_id: 5, agent_name: 'Duda' },
};

const montarCartao = props =>
  mount(AgenteCartao, {
    props: {
      agente: agente(),
      numeros: { respondidas: 12, passadas: 3 },
      canais: [canal],
      podeGerenciar: true,
      href: '/app/agentes/5',
      ...props,
    },
    attachTo: document.body,
  });

describe('AgenteCartao', () => {
  it('opens the agent from anywhere on the card while it answers', async () => {
    const wrapper = montarCartao();
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.ATENDENDO');
    await wrapper.get('[data-abrir]').trigger('click');
    expect(wrapper.emitted('abrir')[0][0].id).toBe(5);
    wrapper.unmount();
  });

  it('names the single inbox it answers on', () => {
    const wrapper = montarCartao();
    expect(wrapper.get('[data-onde]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.ONDE_CANAL'
    );
    wrapper.unmount();
  });

  it('counts the inboxes when the inbox names could not be read', () => {
    const wrapper = montarCartao({ canais: null });
    expect(wrapper.get('[data-onde]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS'
    );
    wrapper.unmount();
  });

  it('counts the inboxes when it answers on more than one', () => {
    const wrapper = montarCartao({ agente: agente({ channels_count: 2 }) });
    expect(wrapper.get('[data-onde]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.ONDE_N_CANAIS'
    );
    wrapper.unmount();
  });

  it('says when it is on no inbox yet', () => {
    const wrapper = montarCartao({
      agente: agente({ channels_count: 0 }),
      canais: [],
    });
    expect(wrapper.get('[data-onde]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.ONDE_NENHUM'
    );
    wrapper.unmount();
  });

  it('shows the week numbers and hides the whole line without them', () => {
    const comNumeros = montarCartao();
    // O texto com os números em português está no copia.spec.js (i18n completo).
    expect(comNumeros.find('[data-semana]').exists()).toBe(true);
    comNumeros.unmount();

    const semNumeros = montarCartao({ numeros: null });
    expect(semNumeros.find('[data-semana]').exists()).toBe(false);
    expect(semNumeros.text()).not.toContain('—');
    semNumeros.unmount();
  });

  it('says there were no conversations instead of showing zeros', () => {
    const wrapper = montarCartao({ numeros: { respondidas: 0, passadas: 0 } });
    expect(wrapper.get('[data-semana]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.SEMANA_VAZIA'
    );
    wrapper.unmount();
  });

  it('shows a stopped agent without numbers', () => {
    const wrapper = montarCartao({ agente: agente({ status: 'paused' }) });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.PARADO');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CARTAO.PARADO');
    expect(wrapper.find('[data-semana]').exists()).toBe(false);
    wrapper.unmount();

    const semCanal = montarCartao({
      agente: agente({ status: 'paused', channels_count: 0 }),
    });
    expect(semCanal.text()).toContain('AGENTS.JORNADA.CARTAO.PARADO_SEM_CANAL');
    semCanal.unmount();
  });

  it('gives a draft the "Continuar" button and the delete menu', async () => {
    const wrapper = montarCartao({
      agente: agente({ status: 'draft', name: null }),
    });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.FALTA_TERMINAR');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.COMUM.NOVO_AGENTE');
    expect(wrapper.find('[data-abrir]').exists()).toBe(false);

    await wrapper.get('[data-continuar]').trigger('click');
    expect(wrapper.emitted('continuar')[0][0].id).toBe(5);

    await wrapper.get('[aria-haspopup="menu"]').trigger('click');
    await wrapper.get('[role="menuitem"]').trigger('click');
    expect(wrapper.emitted('excluir')[0][0].id).toBe(5);
    wrapper.unmount();
  });

  it('shows a draft without actions to a view only seat', () => {
    const wrapper = montarCartao({
      agente: agente({ status: 'draft' }),
      podeGerenciar: false,
    });
    expect(wrapper.find('[data-continuar]').exists()).toBe(false);
    expect(wrapper.find('[aria-haspopup="menu"]').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(0);
    wrapper.unmount();
  });

  it('sends the quote agent to the quotes module', async () => {
    const wrapper = montarCartao({
      agente: agente({ agent_type: 'insurance_quote' }),
    });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.COTACAO');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CARTAO.COTACAO');
    expect(wrapper.find('[data-semana]').exists()).toBe(false);
    await wrapper.get('[data-abrir]').trigger('click');
    expect(wrapper.emitted('abrirCotacao')).toHaveLength(1);
    expect(wrapper.emitted('abrir')).toBeUndefined();
    wrapper.unmount();
  });

  it('does not talk about inboxes for an internal agent', () => {
    const wrapper = montarCartao({ agente: agente({ actuation: 'internal' }) });
    expect(wrapper.find('[data-onde]').exists()).toBe(false);
    expect(wrapper.find('[data-semana]').exists()).toBe(false);
    expect(wrapper.text()).toContain('AGENTS.HUB.INTERNAL_BADGE');
    wrapper.unmount();
  });

  it('never tells a stopped internal agent it is missing an inbox', () => {
    // O backend não deixa agente interno entrar em canal (agent_internal_not_connectable).
    const wrapper = montarCartao({
      agente: agente({
        actuation: 'internal',
        status: 'paused',
        channels_count: 0,
      }),
    });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CARTAO.PARADO');
    expect(wrapper.text()).not.toContain('PARADO_SEM_CANAL');
    wrapper.unmount();
  });

  it('paints the avatar by state: solid teal while answering, muted otherwise', () => {
    const atendendo = montarCartao();
    const avatar = atendendo.get('[data-avatar]');
    expect(avatar.attributes('data-tom')).toBe('atendendo');
    expect(avatar.text()).toBe('D');
    atendendo.unmount();

    ['paused', 'draft'].forEach(status => {
      const outro = montarCartao({ agente: agente({ status }) });
      expect(outro.get('[data-avatar]').attributes('data-tom')).toBe('neutro');
      outro.unmount();
    });
  });

  it('keeps the week numbers on separate lines on a phone', () => {
    const wrapper = montarCartao();
    const ponto = wrapper.get('[data-semana] [data-separador]');
    expect(ponto.classes()).toEqual(expect.arrayContaining(['hidden']));
    expect(ponto.classes()).toContain('md:block');
    wrapper.unmount();
  });

  it('never says "Ligar" nor shows a percentage', () => {
    const wrapper = montarCartao();
    ['Ligar', 'Ligue', '%'].forEach(proibido =>
      expect(wrapper.text()).not.toContain(proibido)
    );
    wrapper.unmount();
  });
});

describe('ModeloCartao', () => {
  const montar = props =>
    mount(ModeloCartao, {
      props: { modelo: MODELOS[0], podeUsar: true, ...props },
    });

  it('shows the template with an example conversation on a phone', () => {
    const wrapper = montar();
    expect(wrapper.get('h3').text()).toBe(
      'AGENTS.JORNADA.MODELOS.SUPPORT.TITULO'
    );
    expect(wrapper.findAll('[data-balao]')).toHaveLength(2);
    expect(wrapper.get('[data-selo]').text()).toBe(
      'AGENTS.JORNADA.MODELOS.EXEMPLO'
    );
  });

  it('uses the template from the stretched button', async () => {
    const wrapper = montar();
    const usar = wrapper.get('[data-usar]');
    expect(usar.attributes('aria-label')).toBe(
      'AGENTS.JORNADA.MODELOS.USAR_ARIA'
    );
    expect(usar.classes()).toContain('after:absolute');
    // Contorno azul, como o .btn-outline do protótipo.
    expect(usar.classes()).toContain('text-n-blue-11');
    await usar.trigger('click');
    expect(wrapper.emitted('usar')).toEqual([['support']]);
  });

  it('shows the start failure under the template, with a retry', async () => {
    const wrapper = montar({ falhou: true });
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'AGENTS.JORNADA.ERRO.COMECAR_MODELO'
    );
    await wrapper.get('[role="alert"] button').trigger('click');
    expect(wrapper.emitted('usar')).toEqual([['support']]);
  });

  it('locks the other templates while one is starting', async () => {
    const wrapper = montar({ bloqueado: true });
    expect(wrapper.get('[data-usar]').attributes('disabled')).toBeDefined();
  });

  it('has no button for a view only seat', () => {
    const wrapper = montar({ podeUsar: false });
    expect(wrapper.find('button').exists()).toBe(false);
  });
});

describe('AgentesHeroi', () => {
  it('is the navy block of the screen with the title as h1', () => {
    const wrapper = mount(AgentesHeroi, {
      props: { titulo: 'Agentes', texto: 'Respondem seus clientes.' },
    });
    const heroi = wrapper.get('[data-heroi]');
    expect(heroi.classes()).toContain('bg-[#0D2344]');
    expect(heroi.attributes('aria-labelledby')).toBe(
      wrapper.get('h1').attributes('id')
    );
    expect(wrapper.text()).toContain('Respondem seus clientes.');
  });
});
