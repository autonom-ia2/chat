import { mount } from '@vue/test-utils';
import AgenteBotao from '../components/AgenteBotao.vue';
import AgenteStatus from '../components/AgenteStatus.vue';
import AgenteErro from '../components/AgenteErro.vue';
import AgenteInterruptor from '../components/AgenteInterruptor.vue';
import RespostasRapidas from '../components/RespostasRapidas.vue';
import { ESTADO } from '../utils/estadoDoAgente';

describe('AgenteBotao', () => {
  it('is the AA primary: blue 11, never the brand color with white text', () => {
    const wrapper = mount(AgenteBotao, { slots: { default: 'Começar' } });
    const classes = wrapper.get('button').classes();

    expect(classes).toContain('bg-n-blue-11');
    expect(classes).toContain('min-h-11');
    expect(classes.some(c => c.includes('bg-n-brand'))).toBe(false);
    expect(wrapper.text()).toBe('Começar');
  });

  it('uses a dark label on the light blue of the dark theme', () => {
    const wrapper = mount(AgenteBotao, { slots: { default: 'Começar' } });
    expect(wrapper.get('button').classes()).toContain('dark:text-n-slate-1');
  });

  it('grows to 48 and 56 px on the larger sizes', () => {
    const lg = mount(AgenteBotao, { props: { tamanho: 'lg' } });
    const xl = mount(AgenteBotao, { props: { tamanho: 'xl' } });
    expect(lg.get('button').classes()).toContain('min-h-12');
    expect(xl.get('button').classes()).toContain('min-h-14');
  });

  it('keeps focus while loading: aria-disabled, not disabled, and no click', async () => {
    const wrapper = mount(AgenteBotao, {
      props: { carregando: true, rotuloCarregando: 'Começando…' },
      slots: { default: 'Começar' },
    });
    const botao = wrapper.get('button');

    expect(botao.attributes('disabled')).toBeUndefined();
    expect(botao.attributes('aria-disabled')).toBe('true');
    expect(botao.attributes('aria-busy')).toBe('true');
    expect(wrapper.text()).toBe('Começando…');
    await botao.trigger('click');
    expect(wrapper.emitted('click')).toBeUndefined();
  });

  it('emits click when idle', async () => {
    const wrapper = mount(AgenteBotao, { slots: { default: 'Ir' } });
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('click')).toHaveLength(1);
  });

  it('has the outline and white variants', () => {
    const contorno = mount(AgenteBotao, { props: { variante: 'contorno' } });
    const branco = mount(AgenteBotao, { props: { variante: 'branco' } });
    expect(contorno.get('button').classes()).toContain('ring-1');
    expect(contorno.get('button').classes()).toContain('text-n-blue-11');
    expect(branco.get('button').classes()).toContain('bg-white');
  });
});

describe('AgenteStatus', () => {
  it.each([
    [ESTADO.ATENDENDO, 'AGENTS.JORNADA.STATUS.ATENDENDO', 'bg-n-teal-9'],
    [ESTADO.PARADO, 'AGENTS.JORNADA.STATUS.PARADO', 'bg-n-amber-9'],
    [
      ESTADO.FALTA_TERMINAR,
      'AGENTS.JORNADA.STATUS.FALTA_TERMINAR',
      'bg-n-amber-9',
    ],
    [ESTADO.COTACAO, 'AGENTS.JORNADA.STATUS.COTACAO', 'bg-n-slate-9'],
  ])('shows %s as text with a dot', (estado, texto, ponto) => {
    const wrapper = mount(AgenteStatus, { props: { estado } });
    expect(wrapper.text()).toBe(texto);
    expect(wrapper.get('[data-ponto]').classes()).toContain(ponto);
    expect(wrapper.get('[data-ponto]').attributes('aria-hidden')).toBe('true');
  });
});

describe('AgenteErro', () => {
  it('says what happened, what stays the same and offers one way out', async () => {
    const wrapper = mount(AgenteErro, {
      props: {
        titulo: 'Não deu para mostrar seus agentes agora.',
        garantia: 'Nenhum agente foi mudado.',
        acao: 'Tentar de novo',
      },
    });

    expect(wrapper.get('[role="alert"]').text()).toContain(
      'Não deu para mostrar seus agentes agora.'
    );
    expect(wrapper.text()).toContain('Nenhum agente foi mudado.');
    const botoes = wrapper.findAll('button');
    expect(botoes).toHaveLength(1);
    await botoes[0].trigger('click');
    expect(wrapper.emitted('acao')).toHaveLength(1);
  });

  it('has an amber variant for warnings such as being offline', () => {
    const wrapper = mount(AgenteErro, {
      props: { titulo: 'Você está sem internet.', tom: 'ambar' },
    });
    expect(wrapper.get('[role="alert"]').classes()).toContain('bg-n-amber-2');
    expect(wrapper.find('button').exists()).toBe(false);
  });
});

describe('AgenteInterruptor', () => {
  it('is a 44 px switch whose label says the state', async () => {
    const wrapper = mount(AgenteInterruptor, {
      props: { ligado: true, rotulo: 'Bia atende' },
    });
    const botao = wrapper.get('[role="switch"]');

    expect(botao.attributes('aria-checked')).toBe('true');
    expect(botao.attributes('aria-label')).toBe('Bia atende');
    expect(botao.classes()).toContain('min-h-11');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.ATENDENDO');

    await botao.trigger('click');
    expect(wrapper.emitted('alternar')).toEqual([[false]]);
  });

  it('reads "Parado" when off and does nothing while disabled', async () => {
    const wrapper = mount(AgenteInterruptor, {
      props: { ligado: false, rotulo: 'Bia atende', desabilitado: true },
    });
    const botao = wrapper.get('[role="switch"]');
    expect(botao.attributes('aria-checked')).toBe('false');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.PARADO');
    await botao.trigger('click');
    expect(wrapper.emitted('alternar')).toBeUndefined();
  });
});

describe('RespostasRapidas', () => {
  it('lists ideas as 44 px buttons inside a labelled group', async () => {
    const wrapper = mount(RespostasRapidas, {
      props: { opcoes: ['Preços', 'Entrega'], rotulo: 'Ideias' },
    });
    const grupo = wrapper.get('[role="group"]');
    expect(grupo.attributes('aria-label')).toBe('Ideias');

    const botoes = wrapper.findAll('button');
    expect(botoes).toHaveLength(2);
    expect(botoes[0].classes()).toContain('min-h-11');

    await botoes[1].trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([['Entrega']]);
  });

  it('does not emit while disabled', async () => {
    const wrapper = mount(RespostasRapidas, {
      props: { opcoes: ['Preços'], desabilitado: true },
    });
    await wrapper.get('button').trigger('click');
    expect(wrapper.emitted('escolher')).toBeUndefined();
  });
});
