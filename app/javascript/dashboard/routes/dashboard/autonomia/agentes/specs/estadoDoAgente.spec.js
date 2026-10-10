import {
  ESTADO,
  estadoDoAgente,
  ordenarAgentes,
  contarEstados,
  canaisDoAgente,
} from '../utils/estadoDoAgente';

const agente = (id, extra = {}) => ({
  id,
  name: `A${id}`,
  status: 'active',
  enabled: true,
  agent_type: 'support',
  ...extra,
});

describe('estadoDoAgente', () => {
  it('is "atendendo" only when active and enabled', () => {
    expect(estadoDoAgente(agente(1))).toBe(ESTADO.ATENDENDO);
    expect(estadoDoAgente(agente(1, { enabled: false }))).toBe(ESTADO.PARADO);
    expect(estadoDoAgente(agente(1, { status: 'paused' }))).toBe(ESTADO.PARADO);
  });

  it('keeps a draft as "falta terminar", even with an instruction', () => {
    expect(
      estadoDoAgente(agente(1, { status: 'draft', has_instruction: true }))
    ).toBe(ESTADO.FALTA_TERMINAR);
    expect(estadoDoAgente(agente(1, { status: undefined }))).toBe(
      ESTADO.FALTA_TERMINAR
    );
  });

  it('sends the quote agent to its own module', () => {
    expect(estadoDoAgente(agente(1, { agent_type: 'insurance_quote' }))).toBe(
      ESTADO.COTACAO
    );
  });
});

describe('ordenarAgentes', () => {
  it('lists atendendo, then parados, then cotação, then falta terminar', () => {
    const lista = [
      agente(1, { status: 'draft' }),
      agente(2, { status: 'paused' }),
      agente(3, { agent_type: 'insurance_quote' }),
      agente(4),
      agente(5, { status: 'draft' }),
      agente(6),
    ];
    expect(ordenarAgentes(lista).map(a => a.id)).toEqual([4, 6, 2, 3, 1, 5]);
  });

  it('does not change the list it received', () => {
    const lista = [agente(1, { status: 'draft' }), agente(2)];
    ordenarAgentes(lista);
    expect(lista.map(a => a.id)).toEqual([1, 2]);
  });
});

describe('contarEstados', () => {
  it('counts the regular agents that answer and the stopped ones', () => {
    const lista = [
      agente(1),
      agente(2),
      agente(3, { status: 'paused' }),
      agente(4, { status: 'draft' }),
      agente(5, { agent_type: 'insurance_quote' }),
    ];
    expect(contarEstados(lista)).toEqual({ atendendo: 2, parados: 1 });
  });
});

describe('canaisDoAgente', () => {
  const canais = [
    {
      inbox_id: 10,
      name: 'WhatsApp do Centro',
      occupied_by: { kind: 'agent', agent_id: 1, agent_name: 'Bia' },
    },
    { inbox_id: 11, name: 'Site', occupied_by: null },
    { inbox_id: 12, name: 'Instagram', occupied_by: { kind: 'external' } },
  ];

  it('returns the inboxes the agent occupies', () => {
    expect(canaisDoAgente(1, canais).map(c => c.inbox_id)).toEqual([10]);
    expect(canaisDoAgente(2, canais)).toEqual([]);
  });

  it('copes with a missing list', () => {
    expect(canaisDoAgente(1, null)).toEqual([]);
  });
});
