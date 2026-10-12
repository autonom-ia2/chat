import {
  ESTADO_PAGINA,
  MODO_RECEBE,
  estadoComLiberacao,
  estadoDaPagina,
  fusoLegivel,
  idsLiberados,
  liberacaoParaSalvar,
  outraPaginaDeAgenda,
  pessoasDaPagina,
  quemRecebe,
} from '../utils/agendaDaPagina';

// #1181 (item A) — o estado real da página e quem fica com a reunião, pelos campos novos do
// servidor (#1305: ai_status e recebe) quando vêm, e pela lista de hoje quando não vêm.
describe('estadoDaPagina', () => {
  it('is "none" without a chosen page', () => {
    expect(estadoDaPagina(false, undefined)).toBe(ESTADO_PAGINA.NENHUMA);
  });

  it('is "no longer exists" when the saved page is not in the list', () => {
    expect(estadoDaPagina(true, undefined)).toBe(ESTADO_PAGINA.NAO_EXISTE);
  });

  describe('with the server ai_status', () => {
    it.each([
      ['ativa', ESTADO_PAGINA.ATIVA],
      ['pausada', ESTADO_PAGINA.PAUSADA],
      ['sem_responsavel', ESTADO_PAGINA.SEM_NINGUEM],
      ['agenda_pausada', ESTADO_PAGINA.AGENDA_PAUSADA],
    ])('maps %s', (aiStatus, esperado) => {
      expect(estadoDaPagina(true, { ai_status: aiStatus })).toBe(esperado);
    });

    it('prefers it over the fields of today', () => {
      const pagina = {
        ai_status: 'ativa',
        enabled: false,
        assignment_mode: 'per_agent',
        links: [],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.ATIVA);
    });
  });

  describe('without ai_status (the list of today)', () => {
    it('is paused when the page is off', () => {
      const pagina = {
        enabled: false,
        assignment_mode: 'per_agent',
        links: [],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.PAUSADA);
    });

    it('has nobody when the single host cannot take meetings (attention)', () => {
      const pagina = {
        enabled: true,
        assignment_mode: 'fixed',
        attention: true,
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.SEM_NINGUEM);
    });

    // P2-2 — o responsável único pausou "Meus horários": a IA não acha horário (Slots#host_paused?).
    it('has the host calendar paused when the single host paused own hours', () => {
      const pagina = {
        enabled: true,
        assignment_mode: 'fixed',
        attention: false,
        paused_people: [{ id: 1, name: 'Rita' }],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.AGENDA_PAUSADA);
    });

    it('keeps a per-person page active while someone with a link has hours', () => {
      const pagina = {
        enabled: true,
        assignment_mode: 'per_agent',
        links: [
          { agent_id: 1, agent_name: 'Ana' },
          { agent_id: 2, agent_name: 'Caio' },
        ],
        paused_people: [{ id: 1, name: 'Ana' }],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.ATIVA);
    });

    it('has the calendar paused when everyone with a link paused own hours', () => {
      const pagina = {
        enabled: true,
        assignment_mode: 'per_agent',
        links: [{ agent_id: 1, agent_name: 'Ana' }],
        paused_people: [{ id: 1, name: 'Ana' }],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.AGENDA_PAUSADA);
    });

    it('lets ai_status win over paused_people', () => {
      const pagina = {
        ai_status: 'ativa',
        assignment_mode: 'fixed',
        paused_people: [{ id: 1, name: 'Rita' }],
      };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.ATIVA);
    });

    it('has nobody when a per-person page has no active link', () => {
      const pagina = { enabled: true, assignment_mode: 'per_agent', links: [] };
      expect(estadoDaPagina(true, pagina)).toBe(ESTADO_PAGINA.SEM_NINGUEM);
    });

    it('is active with a single host in order or an active link', () => {
      expect(
        estadoDaPagina(true, {
          enabled: true,
          assignment_mode: 'fixed',
          attention: false,
        })
      ).toBe(ESTADO_PAGINA.ATIVA);
      expect(
        estadoDaPagina(true, {
          enabled: true,
          assignment_mode: 'per_agent',
          links: [{ agent_name: 'Ana' }],
        })
      ).toBe(ESTADO_PAGINA.ATIVA);
    });

    it('does not claim "nobody" when the API says nothing about it', () => {
      expect(estadoDaPagina(true, { enabled: true })).toBe(ESTADO_PAGINA.ATIVA);
    });
  });
});

describe('quemRecebe', () => {
  it('uses the server recebe when it comes', () => {
    expect(
      quemRecebe({
        assignment_mode: 'per_agent',
        links: [{ agent_name: 'Ana' }],
        recebe: { modo: 'fixo', nome: 'Caio' },
      })
    ).toEqual({ modo: MODO_RECEBE.FIXO, nome: 'Caio' });
    expect(quemRecebe({ recebe: { modo: 'por_pessoa', nome: 'Ana' } })).toEqual(
      { modo: MODO_RECEBE.POR_PESSOA, nome: 'Ana' }
    );
  });

  it('falls back to the first active link of a per-person page', () => {
    expect(
      quemRecebe({
        assignment_mode: 'per_agent',
        links: [{ agent_name: 'Ana' }, { agent_name: 'Caio' }],
      })
    ).toEqual({ modo: MODO_RECEBE.POR_PESSOA, nome: 'Ana' });
  });

  it('has no name for a single-host page of today (the list does not bring it)', () => {
    expect(quemRecebe({ assignment_mode: 'fixed' })).toEqual({
      modo: MODO_RECEBE.FIXO,
      nome: '',
    });
  });

  it('is null without the mode or the page', () => {
    expect(quemRecebe({})).toBeNull();
    expect(quemRecebe(undefined)).toBeNull();
  });
});

describe('fusoLegivel', () => {
  it('names the zone for a lay reader in the screen language', () => {
    // O texto exato é do ICU do navegador ("Horário Padrão de Brasília" no Node 24).
    const fuso = fusoLegivel('America/Sao_Paulo', 'pt-BR');
    expect(fuso.startsWith('Horário')).toBe(true);
    expect(fuso.endsWith('de Brasília')).toBe(true);
  });

  it('is empty without a zone and the raw name for an unknown one', () => {
    expect(fusoLegivel(undefined, 'en')).toBe('');
    expect(fusoLegivel('Lua/Base', 'en')).toBe('Lua/Base');
  });
});

// #1307 — as pessoas da página liberadas para a IA (`booking_agent_ids`; vazio = todas).
describe('pessoas liberadas (#1307)', () => {
  const PESSOAS = [
    { id: 1, nome: 'Ana', ai_status: 'ativa' },
    { id: 2, nome: 'Caio', ai_status: 'agenda_pausada' },
    { id: 3, nome: 'Lia', ai_status: 'ativa' },
  ];

  it('reads the people of a page, empty when the server does not send them', () => {
    expect(pessoasDaPagina({ pessoas: PESSOAS })).toBe(PESSOAS);
    expect(pessoasDaPagina({})).toEqual([]);
    expect(pessoasDaPagina(undefined)).toEqual([]);
  });

  it.each([[undefined], [null], [[]]])(
    'saved %s means everyone on the page',
    gravados => {
      expect(idsLiberados(gravados, PESSOAS)).toEqual([1, 2, 3]);
    }
  );

  it('a saved value that is not a list means nobody, like the server', () => {
    expect(idsLiberados('x', PESSOAS)).toEqual([]);
    expect(idsLiberados({ a: 1 }, PESSOAS)).toEqual([]);
  });

  it('keeps only the saved ids still on the page, in the page order, as numbers', () => {
    expect(idsLiberados(['3', 1, 99], PESSOAS)).toEqual([1, 3]);
    expect(idsLiberados([99], PESSOAS)).toEqual([]);
  });

  it('saves [] with everyone checked and the checked ids in page order otherwise', () => {
    expect(liberacaoParaSalvar([3, 1, 2], PESSOAS)).toEqual([]);
    expect(liberacaoParaSalvar([3, 1], PESSOAS)).toEqual([1, 3]);
  });

  it('turns an active page into "nobody" or "calendar paused" by the released people', () => {
    const { ATIVA, SEM_NINGUEM, AGENDA_PAUSADA, PAUSADA } = ESTADO_PAGINA;
    expect(estadoComLiberacao(ATIVA, PESSOAS, [1])).toBe(ATIVA);
    expect(estadoComLiberacao(ATIVA, PESSOAS, [])).toBe(SEM_NINGUEM);
    expect(estadoComLiberacao(ATIVA, PESSOAS, [2])).toBe(AGENDA_PAUSADA);
    expect(estadoComLiberacao(PAUSADA, PESSOAS, [])).toBe(PAUSADA);
    expect(estadoComLiberacao(ATIVA, [], [])).toBe(ATIVA);
  });
});

describe('outraPaginaDeAgenda (#1307, painel antigo)', () => {
  it('is true only for a real page different from the saved one', () => {
    expect(outraPaginaDeAgenda(5, 3)).toBe(true);
    expect(outraPaginaDeAgenda(5, null)).toBe(true);
    expect(outraPaginaDeAgenda(5, '5')).toBe(false);
    expect(outraPaginaDeAgenda(null, 3)).toBe(false);
  });
});
