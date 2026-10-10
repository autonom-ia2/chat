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

  it('only offers to start answering after one answer was seen', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-comecar]').exists()).toBe(false);
    expect(wrapper.get('[data-pergunte]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTE'
    );

    await wrapper.setProps({ mensagens: respondido, respondidas: 1 });
    const botao = wrapper.get('[data-comecar] button');
    expect(botao.text()).toBe('Começar a atender no WhatsApp');
    expect(botao.classes()).toContain('min-h-14');
    await botao.trigger('click');
    expect(wrapper.emitted('comecar')).toHaveLength(1);
  });

  it('without a channel, offers to connect one (or to ask an admin)', async () => {
    const wrapper = montar({
      rotuloComecar: '',
      respondidas: 1,
      mensagens: respondido,
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

  it('"Not now, finish later" leaves the draft', async () => {
    const wrapper = montar();
    await wrapper.get('[data-depois]').trigger('click');
    expect(wrapper.emitted('depois')).toHaveLength(1);
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

  it('keeps "Not now" out of the bottom bar on the phone, so the bar stays short', () => {
    const wrapper = montar({
      celular: true,
      mensagens: respondido,
      respondidas: 1,
    });
    const doca = wrapper.get('[data-comecar]').element.parentElement;
    expect(wrapper.findAll('[data-depois]')).toHaveLength(1);
    expect(doca.contains(wrapper.get('[data-depois]').element)).toBe(false);
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
