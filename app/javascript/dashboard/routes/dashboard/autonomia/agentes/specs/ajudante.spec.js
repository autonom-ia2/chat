import { mount, flushPromises } from '@vue/test-utils';
import AgenteCartao from '../components/AgenteCartao.vue';
import AgenteStatus from '../components/AgenteStatus.vue';
import AjudantePassos from '../components/onde/AjudantePassos.vue';
import ResumoAjuda from '../components/onde/ResumoAjuda.vue';
import { estadoDeOperacao } from '../utils/pagina';
import {
  ESTADO,
  TRABALHANDO,
  contarEstados,
  estadoDoAgente,
  ordenarAgentes,
} from '../utils/estadoDoAgente';
import {
  BLOQUEIO_DE_PRINCIPAL,
  ehAjudante,
  principaisPossiveis,
} from '../utils/ajudante';
import {
  PAPEL_AJUDANTE_NA_QUERY,
  PAPEL_AREA_NA_QUERY,
  papelDaQuery,
  perguntasDeTeste,
  principaisDaQuery,
  quandoDaQuery,
} from '../constants/criacao';

// Tema 14 (#1434) — o ajudante ("Ajuda outros agentes"): estado "Ajudando", quem pode ser ajudado, a marca
// na query e os passos "Quem {nome} vai ajudar?" e "Quando chamar {nome}?", com o aviso decidido em 14/10.
const agente = extra => ({
  id: 5,
  name: 'Duda',
  status: 'active',
  enabled: true,
  agent_type: 'custom',
  actuation: 'external',
  channels_count: 1,
  tem_onde_trabalhar: true,
  ...extra,
});

const ajudante = extra =>
  agente({
    actuation: 'internal',
    channels_count: 0,
    ajudante: true,
    ajuda: [
      { id: 3, name: 'Clara' },
      { id: 4, name: 'Bruno' },
    ],
    ...extra,
  });

describe('estado do ajudante', () => {
  it('is "Ajudando" when on and helping someone, and counts as working', () => {
    expect(estadoDoAgente(ajudante())).toBe(ESTADO.AJUDANDO);
    expect(estadoDeOperacao(ajudante())).toBe(ESTADO.AJUDANDO);
    expect(TRABALHANDO).toContain(ESTADO.AJUDANDO);
  });

  it('is "Parado" when off, or on without anyone to help (never "Atendendo" like the copilot)', () => {
    expect(estadoDoAgente(ajudante({ status: 'paused' }))).toBe(ESTADO.PARADO);
    expect(estadoDoAgente(ajudante({ ajuda: [] }))).toBe(ESTADO.PARADO);
    expect(estadoDoAgente(ajudante({ status: 'draft' }))).toBe(
      ESTADO.FALTA_TERMINAR
    );
  });

  it('keeps the team copilot and the main agent as they were', () => {
    const copiloto = agente({
      actuation: 'internal',
      ajudante: false,
      ajuda: [],
    });
    expect(estadoDoAgente(copiloto)).toBe(ESTADO.ATENDENDO);
    expect(estadoDoAgente(agente())).toBe(ESTADO.ATENDENDO);
    expect(ehAjudante(copiloto)).toBe(false);
    expect(ehAjudante(agente())).toBe(false);
  });

  it('lists helpers after the team agents and counts them apart', () => {
    const lista = [
      agente({ id: 1, status: 'paused' }),
      ajudante({ id: 2 }),
      agente({ id: 3, na_equipe: true }),
      agente({ id: 4 }),
    ];
    expect(ordenarAgentes(lista).map(item => item.id)).toEqual([4, 3, 2, 1]);
    expect(contarEstados(lista)).toEqual({
      atendendo: 1,
      naEquipe: 1,
      ajudando: 1,
      parados: 1,
    });
  });
});

describe('quem o ajudante pode ajudar', () => {
  const conta = [
    agente({ id: 1, name: 'Clara' }),
    agente({ id: 2, name: 'Bruno', status: 'paused' }),
    agente({ id: 3, name: 'Ana', actuation: 'internal' }),
    ajudante({ id: 4, name: 'Outro ajudante' }),
    agente({ id: 6, name: 'Rascunho', status: 'draft' }),
    agente({ id: 7, name: 'Lia', agent_type: 'insurance_quote' }),
    agente({ id: 8, name: 'Nas duas', actuation: 'both' }),
    ajudante({ id: 9, name: 'Eu', ajuda: [] }),
  ];

  it('offers only finished agents that talk to customers; the quote agent is locked with the reason', () => {
    const opcoes = principaisPossiveis(conta, 9);
    expect(opcoes.map(item => item.agente.id)).toEqual([1, 2, 7, 8]);
    expect(opcoes.find(item => item.agente.id === 7).bloqueio).toBe(
      BLOQUEIO_DE_PRINCIPAL.COTACAO
    );
    expect(opcoes.filter(item => item.bloqueio)).toHaveLength(1);
  });

  it('reads the mark, who it helps and when to call from the query', () => {
    expect(papelDaQuery({ papel: 'ajudante' })).toBe(PAPEL_AJUDANTE_NA_QUERY);
    expect(papelDaQuery({ papel: 'area' })).toBe(PAPEL_AREA_NA_QUERY);
    expect(papelDaQuery({ papel: 'qualquer' })).toBeNull();
    expect(principaisDaQuery({ ajuda: '3,4,x,-1,0' })).toEqual([3, 4]);
    expect(principaisDaQuery({})).toEqual([]);
    expect(quandoDaQuery({ quando: '  Dúvida de troca ' })).toBe(
      'Dúvida de troca'
    );
    expect(quandoDaQuery({ quando: ['a'] })).toBe('');
  });

  it('tests the helper as the main agent would ask it', () => {
    expect(perguntasDeTeste('custom', true, true)).toEqual([
      'AJUDANTE_O_QUE_SABE',
      'AJUDANTE_CLIENTE',
      'AJUDANTE_NAO_SABE',
    ]);
    expect(perguntasDeTeste('custom', true)).toEqual([
      'COMO_RESPONDO',
      'PROXIMO_PASSO',
      'RASCUNHO',
    ]);
  });
});

describe('telas do ajudante', () => {
  const montarCartao = props =>
    mount(AgenteCartao, {
      props: {
        agente: ajudante(),
        numeros: { respondidas: 0, passadas: 0 },
        canais: [],
        podeGerenciar: true,
        href: '/app/agentes/5',
        ...props,
      },
    });

  it('the card says "Ajudando" and who it helps, without the copilot badge nor channel lines', () => {
    const wrapper = montarCartao();
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.AJUDANDO');
    expect(wrapper.get('[data-ajuda]').text()).toBe(
      'AGENTS.JORNADA.ONDE.AJUDA'
    );
    expect(wrapper.text()).not.toContain('AGENTS.HUB.INTERNAL_BADGE');
    expect(wrapper.find('[data-onde]').exists()).toBe(false);
    expect(wrapper.find('[data-semana]').exists()).toBe(false);
  });

  it('a stopped helper still says who it helps', () => {
    const wrapper = montarCartao({ agente: ajudante({ status: 'paused' }) });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.PARADO');
    expect(wrapper.get('[data-ajuda]').text()).toBe(
      'AGENTS.JORNADA.ONDE.AJUDA'
    );
  });

  it('the team copilot card keeps its badge (no regression)', () => {
    const wrapper = montarCartao({
      agente: agente({ actuation: 'internal', ajudante: false, ajuda: [] }),
    });
    expect(wrapper.text()).toContain('AGENTS.HUB.INTERNAL_BADGE');
    expect(wrapper.find('[data-ajuda]').exists()).toBe(false);
  });

  it('the status pill says "Ajudando"', () => {
    expect(
      mount(AgenteStatus, { props: { estado: ESTADO.AJUDANDO } }).text()
    ).toBe('AGENTS.JORNADA.STATUS.AJUDANDO');
  });

  it('the summary shows who it helps and when to call', () => {
    const wrapper = mount(ResumoAjuda, {
      props: {
        principais: [{ id: 3, name: 'Clara' }],
        quando: 'Dúvida de troca',
      },
    });
    expect(wrapper.get('[data-ajuda-nomes]').text()).toBe(
      'AGENTS.JORNADA.ONDE.AJUDA'
    );
    expect(wrapper.get('[data-ajuda-quando]').text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.QUANDO.RESUMO'
    );
  });
});

describe('passos do ajudante', () => {
  const CONTA = [
    agente({ id: 1, name: 'Clara' }),
    agente({ id: 2, name: 'Bruno', status: 'paused' }),
    agente({ id: 3, name: 'Ana', actuation: 'internal' }),
    agente({ id: 7, name: 'Lia', agent_type: 'insurance_quote' }),
  ];
  const montar = props =>
    mount(AjudantePassos, {
      attachTo: document.body,
      props: {
        nome: '',
        semNome: true,
        agentes: CONTA,
        textoFinal: 'Continuar',
        ...props,
      },
    });
  const opcao = (wrapper, valor) => wrapper.find(`[data-opcao="${valor}"]`);
  const seguir = async wrapper => {
    await wrapper.get('[data-seguir-ajudante]').trigger('click');
    await flushPromises();
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('asks who it will help, speaking of "the agent you are creating", with the warning tied to Continuar', async () => {
    const wrapper = montar();
    expect(wrapper.attributes('data-passo')).toBe('quem');
    expect(wrapper.get('h2').text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.QUEM.TITULO_SEM_NOME'
    );
    const aviso = wrapper.get('[data-aviso-ajudante]');
    expect(aviso.attributes('role')).toBe('note');
    expect(aviso.text()).toBe('AGENTS.JORNADA.AJUDANTE.AVISO_SEM_NOME');
    expect(
      wrapper.get('[data-seguir-ajudante]').attributes('aria-describedby')
    ).toBe(aviso.attributes('id'));
    // Só quem fala com cliente; o Copiloto fica fora e a Cotação, bloqueada com o motivo.
    expect(opcao(wrapper, 1).exists()).toBe(true);
    expect(opcao(wrapper, 2).text()).toContain('AGENTS.JORNADA.STATUS.PARADO');
    expect(opcao(wrapper, 3).exists()).toBe(false);
    const lia = opcao(wrapper, 7);
    expect(lia.attributes('aria-disabled')).toBe('true');
    expect(lia.attributes('aria-describedby')).toBe(
      lia.get('[data-motivo]').attributes('id')
    );
    expect(lia.text()).toContain('AGENTS.JORNADA.AJUDANTE.QUEM.COTACAO');
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('says the warning with the name once the agent has one', () => {
    const wrapper = montar({ nome: 'Duda', semNome: false });
    expect(wrapper.get('[data-aviso-ajudante]').text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.AVISO'
    );
    expect(wrapper.get('h2').text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.QUEM.TITULO'
    );
  });

  it('does not move without a main agent nor without "when to call", then hands both back', async () => {
    const wrapper = montar();
    await opcao(wrapper, 7).trigger('click');
    expect(opcao(wrapper, 7).attributes('aria-checked')).toBe('false');
    await seguir(wrapper);
    expect(wrapper.attributes('data-passo')).toBe('quem');

    await opcao(wrapper, 1).trigger('click');
    await opcao(wrapper, 2).trigger('click');
    await seguir(wrapper);
    expect(wrapper.attributes('data-passo')).toBe('quando');
    expect(wrapper.get('h2').text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.QUANDO.TITULO_SEM_NOME'
    );
    const campo = wrapper.get('[data-quando]');
    expect(campo.attributes('maxlength')).toBe('500');
    expect(wrapper.get(`label[for="${campo.attributes('id')}"]`).text()).toBe(
      'AGENTS.JORNADA.AJUDANTE.QUANDO.ROTULO'
    );
    await campo.setValue('   ');
    await seguir(wrapper);
    expect(wrapper.emitted('pronto')).toBeUndefined();

    await campo.setValue('  Quando a dúvida for de troca ');
    await seguir(wrapper);
    expect(wrapper.emitted('pronto')).toEqual([
      [{ principais: [1, 2], quando: 'Quando a dúvida for de troca' }],
    ]);
  });

  it('drops a stale choice from the URL (a locked or missing agent) and keeps the valid one', async () => {
    const wrapper = montar({
      inicial: { principais: [7, 99, 1], quando: 'x' },
    });
    await seguir(wrapper);
    await seguir(wrapper);
    expect(wrapper.emitted('pronto')).toEqual([
      [{ principais: [1], quando: 'x' }],
    ]);
  });

  it('says there is nobody to help yet, and offers to read again when the list fails', async () => {
    const vazia = montar({ agentes: [CONTA[2]] });
    expect(vazia.find('[data-nenhum-principal]').exists()).toBe(true);
    vazia.unmount();
    const falhou = montar({ leitura: 'erro' });
    await falhou.get('[data-erro-ler] button').trigger('click');
    expect(falhou.emitted('reler')).toHaveLength(1);
  });

  it('goes back from the first step to whoever opened it', async () => {
    const wrapper = montar();
    await wrapper.get('[data-voltar-ajudante]').trigger('click');
    expect(wrapper.emitted('voltar')).toHaveLength(1);
  });
});
