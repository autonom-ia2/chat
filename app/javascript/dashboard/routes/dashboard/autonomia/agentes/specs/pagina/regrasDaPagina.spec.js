import {
  GAVETA,
  enderecoDoSite,
  estadoDaFonte,
  fecharFrase,
  gavetaDaAba,
  gavetasPermitidas,
  idiomaDoNavegador,
  chaveDoMotivo,
  estadoDeOperacao,
  podeMudarConversando,
  quandoDoAgente,
} from '../../utils/pagina';
import { horarioDaCaixa } from '../../utils/horarios';

const t = (chave, params = {}) =>
  `${chave.split('.').pop()}(${Object.values(params).join('|')})`;

describe('regras da página do agente', () => {
  it('maps the old tabs to drawers, and tune/publish to the page itself', () => {
    expect(gavetaDaAba('test')).toBe(GAVETA.TESTAR);
    expect(gavetaDaAba('knowledge')).toBe(GAVETA.SABE);
    expect(gavetaDaAba('channels')).toBe(GAVETA.ONDE);
    expect(gavetaDaAba('performance')).toBe(GAVETA.CONVERSAS);
    expect(gavetaDaAba('tune')).toBeNull();
    expect(gavetaDaAba('publish')).toBeNull();
    expect(gavetaDaAba(undefined)).toBeNull();
  });

  it('reads the quoting agent as answering or stopped, like any other', () => {
    const cotacao = extra => ({ agent_type: 'insurance_quote', ...extra });
    expect(estadoDeOperacao(cotacao({ status: 'active', enabled: true }))).toBe(
      'atendendo'
    );
    expect(estadoDeOperacao(cotacao({ status: 'paused', enabled: true }))).toBe(
      'parado'
    );
    expect(estadoDeOperacao({ status: 'active', enabled: false })).toBe(
      'parado'
    );
    expect(estadoDeOperacao({ status: 'draft' })).toBe('falta_terminar');
  });

  it('lets only guided agents change by chatting', () => {
    expect(podeMudarConversando({ mode: 'guided' })).toBe(true);
    expect(podeMudarConversando({ mode: 'manual' })).toBe(false);
    expect(podeMudarConversando({ agent_type: 'insurance_quote' })).toBe(false);
  });

  it('gives view-only seats only reading drawers', () => {
    expect(gavetasPermitidas({ mode: 'guided' }, false)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.VERSOES,
    ]);
  });

  it('keeps the quoting agent to name, photo, hours and status', () => {
    const cotacao = { agent_type: 'insurance_quote' };
    expect(gavetasPermitidas(cotacao, true)).toEqual([
      GAVETA.ONDE,
      GAVETA.VOLTAR,
      GAVETA.FOTO,
    ]);
    expect(gavetasPermitidas(cotacao, false)).toEqual([]);
  });

  it('opens the booking drawer only for managers, with the new booking on the account', () => {
    const comAgenda = { agendaNova: true };
    expect(gavetasPermitidas({ mode: 'guided' }, true, comAgenda)).toContain(
      GAVETA.AGENDA
    );
    expect(gavetasPermitidas({ mode: 'guided' }, true)).not.toContain(
      GAVETA.AGENDA
    );
    expect(gavetasPermitidas({ mode: 'guided' }, false, comAgenda)).toEqual([
      GAVETA.TESTAR,
      GAVETA.SABE,
      GAVETA.VERSOES,
    ]);
    expect(
      gavetasPermitidas({ agent_type: 'insurance_quote' }, true, comAgenda)
    ).not.toContain(GAVETA.AGENDA);
    expect(
      gavetasPermitidas({ booking_available: false }, true, comAgenda)
    ).not.toContain(GAVETA.AGENDA);
  });

  it('has no where-and-when for an internal agent', () => {
    const permitidas = gavetasPermitidas({ actuation: 'internal' }, true);
    expect(permitidas).not.toContain(GAVETA.ONDE);
    expect(permitidas).not.toContain(GAVETA.VOLTAR);
    expect(permitidas).toContain(GAVETA.INSTRUCOES);
  });

  it('reads the response window with "always" as default', () => {
    expect(
      quandoDoAgente({ config: { response_window: 'business_hours' } })
    ).toBe('business_hours');
    expect(quandoDoAgente({ config: {} })).toBe('always');
    expect(quandoDoAgente(null)).toBe('always');
  });

  it.each([
    ['www.sualoja.com.br', 'https://www.sualoja.com.br/'],
    ['https://loja.com/cardapio', 'https://loja.com/cardapio'],
    ['  loja.com  ', 'https://loja.com/'],
  ])('accepts the website %s', (valor, esperado) => {
    expect(enderecoDoSite(valor)).toBe(esperado);
  });

  it.each(['', 'loja', 'minha loja.com', 'loja.', 'ftp://loja.com'])(
    'refuses the website "%s"',
    valor => {
      expect(enderecoDoSite(valor)).toBeNull();
    }
  );

  it('says reading, ready or could not read, never a score', () => {
    expect(estadoDaFonte({ status: 'processing' })).toBe('lendo');
    expect(estadoDaFonte({ status: 'pending' })).toBe('lendo');
    expect(
      estadoDaFonte({ status: 'ready', review: { status: 'accepted' } })
    ).toBe('pronto');
    expect(estadoDaFonte({ status: 'ready', review: { status: null } })).toBe(
      'pronto'
    );
    expect(estadoDaFonte({ status: 'failed' })).toBe('falha');
    expect(
      estadoDaFonte({ status: 'ready', review: { status: 'needs_resend' } })
    ).toBe('falha');
  });

  it('names each version reason and nothing else', () => {
    expect(chaveDoMotivo('kb_refresh')).toBe('KB_REFRESH');
    expect(chaveDoMotivo('manual_edit')).toBe('MANUAL_EDIT');
    expect(chaveDoMotivo('rollback')).toBe('ROLLBACK');
    expect(chaveDoMotivo('outro')).toBeNull();
  });

  it('closes a sentence for the wrong-answer draft', () => {
    expect(fecharFrase('Vocês abrem no sábado?')).toBe(
      'Vocês abrem no sábado?'
    );
    expect(fecharFrase(' Abrimos ')).toBe('Abrimos.');
    expect(fecharFrase('')).toBe('');
  });

  it('turns the i18n locale into a browser locale', () => {
    expect(idiomaDoNavegador('pt_BR')).toBe('pt-BR');
    expect(idiomaDoNavegador('en')).toBe('en');
  });
});

describe('horário da caixa', () => {
  const dia = (d, extra = {}) => ({
    day_of_week: d,
    closed_all_day: false,
    open_all_day: false,
    open_hour: 9,
    open_minutes: 0,
    close_hour: 18,
    close_minutes: 0,
    ...extra,
  });

  it('is null when the inbox has no business hours on', () => {
    expect(horarioDaCaixa({ working_hours_enabled: false }, t)).toBeNull();
    expect(
      horarioDaCaixa(
        {
          working_hours_enabled: true,
          working_hours: [dia(1, { closed_all_day: true })],
        },
        t
      )
    ).toBeNull();
  });

  it('groups weekdays with the same hours into a range', () => {
    const texto = horarioDaCaixa(
      {
        working_hours_enabled: true,
        working_hours: [
          dia(0, { closed_all_day: true }),
          dia(1),
          dia(2),
          dia(3),
          dia(4),
          dia(5),
          dia(6, { close_hour: 13, open_minutes: 30 }),
        ],
      },
      t
    );
    expect(texto).toBe(
      'DIAS_E_HORAS(INTERVALO_DIAS(D1()|D5())|HORA(9)|HORA(18)); DIAS_E_HORAS(D6()|HORA_MINUTO(9|30)|HORA(13))'
    );
  });

  it('says all day', () => {
    const texto = horarioDaCaixa(
      {
        working_hours_enabled: true,
        working_hours: [dia(6, { open_all_day: true })],
      },
      t
    );
    expect(texto).toBe('DIA_TODO(D6())');
  });
});
