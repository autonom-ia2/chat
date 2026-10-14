import { mount } from '@vue/test-utils';
import EtapaConfira from '../../components/criar/EtapaConfira.vue';

const respondido = [
  { de: 'cliente', texto: 'Vocês abrem no sábado?' },
  { de: 'agente', texto: 'Abrimos sim.', usou: ['Horários.pdf'] },
];

const montar = props =>
  mount(EtapaConfira, {
    props: {
      nome: 'Duda',
      empresa: 'Loja da Ana',
      perguntas: ['QUANTO_CUSTA', 'SABADO', 'PESSOA'],
      rotuloComecar: 'Começar a atender no WhatsApp',
      ...props,
    },
  });

describe('EtapaConfira', () => {
  it('says it is only a test and starts empty with ready questions', () => {
    const wrapper = montar();
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CRIAR.CONFIRA.TEXTO');
    expect(wrapper.get('[data-vazio]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.VAZIO'
    );
    const perguntas = wrapper.get('[data-perguntas]').findAll('button');
    expect(perguntas.map(b => b.text())).toEqual([
      'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.QUANTO_CUSTA',
      'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.SABADO',
      'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.PESSOA',
    ]);
  });

  it('asks a ready question right away', async () => {
    const wrapper = montar();
    await wrapper.get('[data-perguntas]').findAll('button')[1].trigger('click');
    expect(wrapper.emitted('perguntar')[0][0]).toEqual({
      texto: 'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.SABADO',
      anexos: [],
    });
  });

  it('the test clip takes only photos', () => {
    const wrapper = montar();
    expect(wrapper.get('input[type="file"]').attributes('accept')).toBe(
      'image/*'
    );
  });

  // #1504 — o teste não é obrigatório: Começar aparece sem nenhuma resposta vista.
  it('offers to start answering right away, without any test answer', async () => {
    const wrapper = montar();
    const botao = wrapper.get('[data-comecar] button');
    expect(botao.text()).toBe('Começar a atender no WhatsApp');
    expect(botao.classes()).toContain('min-h-14');
    await botao.trigger('click');
    expect(wrapper.emitted('comecar')).toHaveLength(1);
  });

  it('says the test is optional until one answer was seen, and keeps Começar after it', async () => {
    const wrapper = montar();
    expect(wrapper.get('[data-teste-opcional]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.TESTE_OPCIONAL'
    );

    await wrapper.setProps({ mensagens: respondido, respondidas: 1 });
    expect(wrapper.find('[data-teste-opcional]').exists()).toBe(false);
    expect(wrapper.get('[data-comecar] button').text()).toBe(
      'Começar a atender no WhatsApp'
    );
  });

  it('keeps Começar busy (and ignores the click) while the inboxes are still loading', async () => {
    const wrapper = montar({ carregandoCanais: true });
    const botao = wrapper.get('[data-comecar] button');
    expect(botao.attributes('aria-busy')).toBe('true');
    await botao.trigger('click');
    expect(wrapper.emitted('comecar')).toBeUndefined();

    await wrapper.setProps({ carregandoCanais: false });
    await wrapper.get('[data-comecar] button').trigger('click');
    expect(wrapper.emitted('comecar')).toHaveLength(1);
  });

  it('the copilot also starts without a test answer', () => {
    const wrapper = montar({
      interno: true,
      rotuloComecar: 'Começar a ajudar a equipe',
    });
    expect(wrapper.get('[data-comecar]').text()).toContain(
      'AGENTS.JORNADA.CRIAR.CONFIRA.COMECAR_TEXTO_COPILOTO'
    );
    expect(wrapper.find('[data-sem-canal]').exists()).toBe(false);
  });

  it('without a channel, offers to connect one (or to ask an admin), even before the test', async () => {
    const wrapper = montar({
      rotuloComecar: '',
      podeConectarCanal: true,
      linkConectarCanal: '/app/settings_inbox_new',
    });
    const link = wrapper.get('[data-conectar]');
    expect(link.attributes('href')).toBe('/app/settings_inbox_new');
    expect(link.attributes('target')).toBe('_blank');

    await wrapper.setProps({ podeConectarCanal: false });
    expect(wrapper.find('[data-conectar]').exists()).toBe(false);
    expect(wrapper.get('[data-sem-canal]').text()).toContain(
      'AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO'
    );
  });

  it('"Wrong answer?" sits under the last answer and goes to the conversation once', async () => {
    const wrapper = montar({ mensagens: respondido, respondidas: 1 });
    const link = wrapper.get('[data-respondeu-errado]');
    await link.trigger('click');
    expect(wrapper.emitted('respondeuErrado')).toHaveLength(1);
    expect(wrapper.find('[data-respondeu-errado]').exists()).toBe(false);

    await wrapper.setProps({ respondidas: 2 });
    expect(wrapper.find('[data-respondeu-errado]').exists()).toBe(true);
  });

  it('hides "Wrong answer?" while typing, on error or while the conversation thinks', async () => {
    const wrapper = montar({ mensagens: respondido, respondidas: 1 });
    await wrapper.setProps({ digitando: true });
    expect(wrapper.find('[data-respondeu-errado]').exists()).toBe(false);
    await wrapper.setProps({ digitando: false, conversaPensando: true });
    expect(wrapper.find('[data-respondeu-errado]').exists()).toBe(false);
    await wrapper.setProps({ conversaPensando: false, problema: 'falha' });
    expect(wrapper.find('[data-respondeu-errado]').exists()).toBe(false);
  });

  it.each([
    ['falha', 'AGENTS.JORNADA.CRIAR.CONFIRA.FALHA', true],
    ['demora', 'AGENTS.JORNADA.CRIAR.CONFIRA.DEMORA', true],
    ['offline', 'AGENTS.JORNADA.ERRO.OFFLINE', true],
    ['incompleto', 'AGENTS.JORNADA.CRIAR.CONFIRA.INCOMPLETO', false],
  ])('shows the %s card in the phone', async (problema, titulo, temAcao) => {
    const wrapper = montar({
      mensagens: [respondido[0]],
      problema,
    });
    const erro = wrapper.get('[data-erro-teste]');
    expect(erro.text()).toContain(titulo);
    expect(erro.find('button').exists()).toBe(temAcao);
    if (temAcao) {
      await erro.get('button').trigger('click');
      expect(wrapper.emitted('tentarDeNovo')).toHaveLength(1);
    }
  });

  it('on the phone, the "not enough" text does not point to the side', () => {
    const wrapper = montar({ problema: 'incompleto', celular: true });
    expect(wrapper.get('[data-erro-teste]').text()).toContain(
      'AGENTS.JORNADA.CRIAR.CONFIRA.INCOMPLETO_CELULAR'
    );
  });

  it('shows the hand-off band and "Updated", never a confidence', () => {
    const wrapper = montar({
      mensagens: [respondido[0], { ...respondido[1], passaria: true }],
      atualizado: false,
      respondidas: 1,
    });
    expect(wrapper.get('[data-aviso]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.PASSARIA'
    );
    expect(wrapper.get('[data-usou]').text()).toBe('AGENTS.JORNADA.COMUM.USOU');
    expect(wrapper.text()).not.toContain('%');

    const atualizado = montar({ atualizado: true });
    expect(atualizado.get('[data-atualizado]').attributes('role')).toBe(
      'status'
    );
  });

  it('clears the test from the phone header', async () => {
    const wrapper = montar({ mensagens: respondido, respondidas: 1 });
    await wrapper.get('[data-limpar]').trigger('click');
    expect(wrapper.emitted('limpar')).toHaveLength(1);
  });

  it('does not clear the test while the agent is typing', () => {
    const wrapper = montar({ mensagens: respondido, digitando: true });
    expect(wrapper.get('[data-limpar]').attributes('disabled')).toBeDefined();
  });

  // Só a conversa é anunciada: vazio, erro e "Respondeu errado?" ficam fora da região aria-live.
  it('announces only the conversation, not the notes under it', () => {
    const wrapper = montar({ problema: 'falha' });
    expect(
      wrapper.get('[data-vazio]').element.closest('[aria-live]')
    ).toBeNull();
    expect(
      wrapper.get('[data-erro-teste]').element.closest('[aria-live]')
    ).toBeNull();
  });

  // #1504 — "Agora não, terminar depois" virou "Fazer ajustes avançados" (terminar depois é o
  // "Voltar para Agentes" do topo).
  it('"Make advanced adjustments" asks the page to open the agent, and says it stays paused', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-depois]').exists()).toBe(false);
    const botao = wrapper.get('[data-ajustes-botao]');
    expect(botao.text()).toBe('AGENTS.JORNADA.CRIAR.CONFIRA.AJUSTES');
    expect(botao.classes()).toContain('min-h-11');
    expect(botao.attributes('aria-describedby')).toBe('confira-ajustes-texto');
    expect(wrapper.get('#confira-ajustes-texto').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.AJUSTES_TEXTO'
    );
    await botao.trigger('click');
    expect(wrapper.emitted('ajustes')).toHaveLength(1);
  });

  it('ignores a second click while the adjustments are opening', async () => {
    const wrapper = montar({ abrindoAjustes: true });
    const botao = wrapper.get('[data-ajustes-botao]');
    expect(botao.attributes('aria-busy')).toBe('true');
    expect(botao.attributes('aria-disabled')).toBe('true');
    await botao.trigger('click');
    expect(wrapper.emitted('ajustes')).toBeUndefined();
  });

  it('pins the questions, field and start button to the bottom on the phone', () => {
    const wrapper = montar({
      celular: true,
      mensagens: respondido,
      respondidas: 1,
    });
    const doca = wrapper.get('[data-comecar]').element.parentElement;
    expect(doca.className).toContain('fixed');
  });

  it('on the phone, the optional-test hint sits above the test, out of the bottom bar', () => {
    const wrapper = montar({ celular: true });
    const doca = wrapper.get('[data-comecar]').element.parentElement;
    expect(wrapper.findAll('[data-teste-opcional]')).toHaveLength(1);
    expect(doca.contains(wrapper.get('[data-teste-opcional]').element)).toBe(
      false
    );
  });

  it('keeps the advanced adjustments out of the bottom bar on the phone, so the bar stays short', () => {
    const wrapper = montar({ celular: true });
    const doca = wrapper.get('[data-comecar]').element.parentElement;
    expect(wrapper.findAll('[data-ajustes]')).toHaveLength(1);
    expect(doca.contains(wrapper.get('[data-ajustes]').element)).toBe(false);
  });
});

describe('EtapaConfira no celular', () => {
  it('keeps the section title only for screen readers (the screen title says it)', () => {
    const wrapper = mount(EtapaConfira, {
      props: { nome: 'Duda', celular: true },
    });
    expect(wrapper.get('#confira-titulo').classes()).toContain('sr-only');
  });
});
