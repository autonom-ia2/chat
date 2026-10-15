import { mount } from '@vue/test-utils';
import AgenteCartao from '../components/AgenteCartao.vue';
import AgenteStatus from '../components/AgenteStatus.vue';
import AgenteInterruptor from '../components/AgenteInterruptor.vue';
import ResumoOndeTrabalha from '../components/onde/ResumoOndeTrabalha.vue';
import { estadoDeOperacao } from '../utils/pagina';
import {
  ESTADO,
  TRABALHANDO,
  contarEstados,
  estadoDoAgente,
  ordenarAgentes,
} from '../utils/estadoDoAgente';
import {
  BLOQUEIO,
  bloqueioDaCaixa,
  caixasDaEquipe,
  mudancaDaEquipe,
} from '../utils/ondeTrabalha';
import { PAPEL_AREA_NA_QUERY, papelDaQuery } from '../constants/criacao';
import { fase2Ligada } from '../composables/useFase2';

// #1433 (tema 13) — o agente da equipe: secundário numa caixa ativa que já tem principal, recebe a
// conversa quando alguém passa. Estado "Na equipe", caixas bloqueadas com o motivo e a marca na query.
const agente = extra => ({
  id: 5,
  name: 'Duda',
  status: 'active',
  enabled: true,
  agent_type: 'support',
  actuation: 'external',
  channels_count: 1,
  tem_onde_trabalhar: true,
  na_equipe: false,
  ...extra,
});

const principal = (operating = true) => ({
  kind: 'agent',
  agent_id: 9,
  agent_name: 'Bia',
  operating,
  caixas: 1,
});

describe('estado do agente da equipe', () => {
  it('is "Na equipe" when it is on only as team, never "Atendendo" as a main agent', () => {
    const daEquipe = agente({ na_equipe: true });
    expect(estadoDoAgente(daEquipe)).toBe(ESTADO.NA_EQUIPE);
    expect(estadoDeOperacao(daEquipe)).toBe(ESTADO.NA_EQUIPE);
    expect(TRABALHANDO).toContain(ESTADO.NA_EQUIPE);
  });

  it('is not "Parado" by mistake for not holding any inbox, and is "Parado" when really stopped', () => {
    expect(estadoDoAgente(agente({ na_equipe: true }))).not.toBe(ESTADO.PARADO);
    expect(estadoDoAgente(agente({ na_equipe: true, status: 'paused' }))).toBe(
      ESTADO.PARADO
    );
    expect(
      estadoDoAgente(agente({ na_equipe: true, tem_onde_trabalhar: false }))
    ).toBe(ESTADO.PARADO);
  });

  it('keeps the main agent and the old payload (without na_equipe) as "Atendendo"', () => {
    expect(estadoDoAgente(agente())).toBe(ESTADO.ATENDENDO);
    const { na_equipe: _semCampo, ...antigo } = agente();
    expect(estadoDoAgente(antigo)).toBe(ESTADO.ATENDENDO);
  });

  it('lists team agents after the ones answering and counts them apart', () => {
    const lista = [
      agente({ id: 1, status: 'paused' }),
      agente({ id: 2, na_equipe: true }),
      agente({ id: 3 }),
    ];
    expect(ordenarAgentes(lista).map(item => item.id)).toEqual([3, 2, 1]);
    expect(contarEstados(lista)).toEqual({
      atendendo: 1,
      naEquipe: 1,
      ajudando: 0,
      parados: 1,
    });
  });
});

describe('caixas do agente da equipe', () => {
  it('only an inbox whose main agent is answering can take a team agent', () => {
    expect(bloqueioDaCaixa({ occupied_by: principal() }, 90)).toBeNull();
    expect(bloqueioDaCaixa({ occupied_by: principal(false) }, 90)).toBe(
      BLOQUEIO.PRINCIPAL_PARADO
    );
    expect(bloqueioDaCaixa({ occupied_by: null }, 90)).toBe(
      BLOQUEIO.SEM_PRINCIPAL
    );
    expect(bloqueioDaCaixa({ occupied_by: { kind: 'external' } }, 90)).toBe(
      BLOQUEIO.SEM_PRINCIPAL
    );
    // O próprio principal da caixa não vira equipe dela.
    expect(bloqueioDaCaixa({ occupied_by: principal() }, 9)).toBe(
      BLOQUEIO.SEM_PRINCIPAL
    );
  });

  it('reads where the agent is on the team from the inbox reading', () => {
    const canais = [
      { inbox_id: 1, areas: [{ agent_id: 5 }] },
      { inbox_id: 2, areas: [{ agent_id: 6 }] },
      { inbox_id: 3 },
    ];
    expect(caixasDaEquipe(5, canais).map(canal => canal.inbox_id)).toEqual([1]);
  });

  it('says which inboxes come in and which go out', () => {
    expect(mudancaDaEquipe([1, 2], [2, 3])).toEqual({
      entram: [3],
      saem: [1],
    });
  });

  it('reads the mark from the query and the Fase 2 from the account', () => {
    expect(papelDaQuery({ papel: 'area' })).toBe(PAPEL_AREA_NA_QUERY);
    expect(papelDaQuery({ papel: 'porta' })).toBeNull();
    expect(papelDaQuery({})).toBeNull();
    expect(fase2Ligada({ autonomia_agents_fase2: true })).toBe(true);
    expect(fase2Ligada({ autonomia_agents_fase2: 'true' })).toBe(false);
    expect(fase2Ligada(null)).toBe(false);
  });
});

describe('telas do agente da equipe', () => {
  const montarCartao = props =>
    mount(AgenteCartao, {
      props: {
        agente: agente({ na_equipe: true }),
        numeros: { respondidas: 12, passadas: 3 },
        canais: [],
        podeGerenciar: true,
        href: '/app/agentes/5',
        ...props,
      },
    });

  it('the card says "Na equipe" and where it receives, without the main agent lines', () => {
    const wrapper = montarCartao({ equipe: ['WhatsApp do Centro'] });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.NA_EQUIPE');
    expect(wrapper.text()).not.toContain('AGENTS.JORNADA.STATUS.ATENDENDO');
    expect(wrapper.get('[data-equipe]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.RECEBE_EM'
    );
    expect(wrapper.find('[data-onde]').exists()).toBe(false);
    expect(wrapper.find('[data-semana]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('AGENTS.JORNADA.CARTAO.PARADO');
  });

  it('the card keeps the role when the inbox reading failed', () => {
    const wrapper = montarCartao({ equipe: null });
    expect(wrapper.get('[data-equipe]').text()).toBe(
      'AGENTS.JORNADA.ONDE.RECEBE'
    );
  });

  it('the main agent card does not change (no regression)', () => {
    const wrapper = montarCartao({
      agente: agente(),
      canais: [
        {
          inbox_id: 10,
          name: 'WhatsApp do Centro',
          occupied_by: { kind: 'agent', agent_id: 5 },
        },
      ],
    });
    expect(wrapper.text()).toContain('AGENTS.JORNADA.STATUS.ATENDENDO');
    expect(wrapper.find('[data-equipe]').exists()).toBe(false);
    expect(wrapper.get('[data-onde]').text()).toBe(
      'AGENTS.JORNADA.CARTAO.ONDE_CANAL'
    );
  });

  it('the status pill and the switch say "Na equipe"', () => {
    expect(
      mount(AgenteStatus, { props: { estado: ESTADO.NA_EQUIPE } }).text()
    ).toBe('AGENTS.JORNADA.STATUS.NA_EQUIPE');
    const interruptor = mount(AgenteInterruptor, {
      props: { ligado: true, rotulo: 'Duda', textoLigado: 'Na equipe' },
    });
    expect(interruptor.get('[role="switch"]').attributes('aria-checked')).toBe(
      'true'
    );
    expect(interruptor.text()).toBe('Na equipe');
  });

  it('"Onde trabalha" shows only the inbox and the role', () => {
    const wrapper = mount(ResumoOndeTrabalha, {
      props: {
        canais: [
          {
            inbox_id: 11,
            name: 'WhatsApp do Centro',
            channel_type: 'Channel::Whatsapp',
          },
        ],
        caixas: [
          {
            id: 11,
            name: 'WhatsApp do Centro',
            channel_type: 'Channel::Whatsapp',
            phone_number: '+55 11 99999-0000',
          },
        ],
      },
    });
    const linhas = wrapper.findAll('[data-linha-caixa]');
    expect(linhas).toHaveLength(1);
    expect(linhas[0].text()).toContain('WhatsApp do Centro');
    expect(linhas[0].text()).toContain('+55 11 99999-0000');
    expect(linhas[0].text()).toContain('AGENTS.JORNADA.ONDE.RECEBE');
    expect(wrapper.find('a').exists()).toBe(false);
  });
});
