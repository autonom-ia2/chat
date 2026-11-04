import {
  ATUACAO,
  atuacaoDaQuery,
  modeloDaQuery,
  idDaQuery,
  perguntasDeTeste,
  perguntasDoAgente,
  MAX_PERGUNTAS_DE_TESTE,
  exemploDoModelo,
  ETAPA,
  etapaDaQuery,
} from '../../constants/criacao';
import {
  canalSugerido,
  temCanalParaEscolher,
  tipoDoCanalParaTexto,
  horariosDasCaixas,
  textoDoHorario,
} from '../../utils/criacao';

const livre = (id, tipo = 'Channel::Whatsapp', nome = `Caixa ${id}`) => ({
  inbox_id: id,
  name: nome,
  channel_type: tipo,
  occupied_by: null,
});
const ocupada = (id, tipo = 'Channel::Whatsapp') => ({
  ...livre(id, tipo),
  occupied_by: { kind: 'agent', agent_id: 9, agent_name: 'Bia' },
});
const externa = id => ({ ...livre(id), occupied_by: { kind: 'external' } });

describe('modelo e etapa da query', () => {
  it('reads the model sent by the list (?modelo=), and the old ?type= link', () => {
    expect(modeloDaQuery({ modelo: 'sdr' })).toBe('sdr');
    expect(modeloDaQuery({ type: 'reception' })).toBe('reception');
  });

  it('falls back to "do meu jeito" (custom) for a missing or unknown model', () => {
    expect(modeloDaQuery({})).toBe('custom');
    expect(modeloDaQuery({ modelo: 'insurance_quote' })).toBe('custom');
    expect(modeloDaQuery({ modelo: ['sdr'] })).toBe('custom');
  });

  it('reads the agent id only when it is a positive integer', () => {
    expect(idDaQuery({ agente: '12' })).toBe(12);
    expect(idDaQuery({ agente: 'abc' })).toBeNull();
    expect(idDaQuery({ agente: '-3' })).toBeNull();
    expect(idDaQuery({})).toBeNull();
  });

  it('knows the four steps and defaults to Conte', () => {
    expect(etapaDaQuery({ etapa: 'confira' })).toBe(ETAPA.CONFIRA);
    expect(etapaDaQuery({ etapa: 'pronto' })).toBe(ETAPA.PRONTO);
    expect(etapaDaQuery({ etapa: 'outra' })).toBe(ETAPA.CONTE);
    expect(etapaDaQuery({})).toBe(ETAPA.CONTE);
  });

  it('has three test questions per model; "do meu jeito" uses the first model', () => {
    expect(perguntasDeTeste('sdr')).toHaveLength(3);
    expect(perguntasDeTeste('custom')).toEqual(perguntasDeTeste('support'));
    expect(exemploDoModelo('custom')).toBe('SUPPORT');
    expect(exemploDoModelo('reception')).toBe('RECEPTION');
  });
});

describe('Copiloto da equipe na query (#1494)', () => {
  it('reads ?atuacao=interno as the internal actuation, anything else as external', () => {
    expect(atuacaoDaQuery({ atuacao: 'interno' })).toBe(ATUACAO.INTERNA);
    expect(ATUACAO.INTERNA).toBe('internal');
    expect(atuacaoDaQuery({})).toBe('external');
    expect(atuacaoDaQuery({ atuacao: 'INTERNO' })).toBe('external');
    expect(atuacaoDaQuery({ atuacao: 'interno ' })).toBe('external');
    expect(atuacaoDaQuery({ atuacao: ['interno'] })).toBe('external');
    expect(atuacaoDaQuery({ atuacao: 'internal' })).toBe('external');
  });

  it('tests the copilot with three team questions, and keeps the customer ones for the others', () => {
    expect(perguntasDeTeste('custom', true)).toEqual([
      'COMO_RESPONDO',
      'PROXIMO_PASSO',
      'RASCUNHO',
    ]);
    expect(perguntasDeTeste('sdr', false)).toEqual(perguntasDeTeste('sdr'));
    expect(perguntasDeTeste('support')).toEqual([
      'QUANTO_CUSTA',
      'SABADO',
      'PESSOA',
    ]);
  });
});

// #2489 (5a) — o teste pergunta o que o Construtor escreveu para este agente, não o genérico do ramo.
describe('perguntas do próprio agente no teste', () => {
  it('takes the first questions the Builder wrote, trimmed and without blanks', () => {
    const agente = {
      starter_questions: [
        ' Cobre cancelamento? ',
        '',
        null,
        'Quanto custa 10 dias?',
        'Tem para intercâmbio?',
        'E bagagem?',
      ],
    };
    expect(perguntasDoAgente(agente)).toEqual([
      'Cobre cancelamento?',
      'Quanto custa 10 dias?',
      'Tem para intercâmbio?',
    ]);
    expect(perguntasDoAgente(agente)).toHaveLength(MAX_PERGUNTAS_DE_TESTE);
  });

  it('drops repeated questions and also serves the team copilot (its questions are team requests)', () => {
    expect(
      perguntasDoAgente({
        starter_questions: ['Resuma', ' Resuma', 'Próximo passo?'],
      })
    ).toEqual(['Resuma', 'Próximo passo?']);
  });

  it('is empty without questions (the model ones stay) and for the helper agent', () => {
    expect(perguntasDoAgente(null)).toEqual([]);
    expect(perguntasDoAgente({ starter_questions: [] })).toEqual([]);
    expect(perguntasDoAgente({ starter_questions: ['Oi?'] }, true)).toEqual([]);
  });
});

describe('canal sugerido no botão de começar', () => {
  // #2489 (5b): o dono pode ter pedido Instagram; com dúvida, ninguém é sugerido e a pessoa escolhe.
  it('suggests nothing when more than one free inbox exists (no WhatsApp preference)', () => {
    expect(
      canalSugerido([livre(1, 'Channel::Instagram'), livre(2)], 5)
    ).toBeNull();
  });

  it('suggests the only free inbox the person reaches', () => {
    expect(
      canalSugerido([livre(1, 'Channel::Instagram'), ocupada(3)], 5).inbox_id
    ).toBe(1);
    expect(
      canalSugerido([{ ...livre(2), alcanca: false }, livre(4)], 5).inbox_id
    ).toBe(4);
  });

  it('never suggests a free inbox out of reach', () => {
    expect(canalSugerido([{ ...livre(1), alcanca: false }], 5)).toBeNull();
  });

  it('counts the inbox this agent already has as free', () => {
    const minha = {
      ...livre(4),
      occupied_by: { kind: 'agent', agent_id: 5, agent_name: 'Duda' },
    };
    expect(canalSugerido([ocupada(3), minha], 5).inbox_id).toBe(4);
  });

  it('never falls back to a busy inbox or another system', () => {
    expect(canalSugerido([ocupada(3)], 5)).toBeNull();
    expect(canalSugerido([externa(1), ocupada(3)], 5)).toBeNull();
    expect(canalSugerido([externa(1)], 5)).toBeNull();
    expect(canalSugerido([], 5)).toBeNull();
  });

  // #2490: o dono pediu um canal na conversa; só caixas dele entram, e a WAHA conta como WhatsApp.
  it('suggests only the free inbox of the channel the owner asked for', () => {
    const insta = { ...livre(1, 'Channel::Instagram'), canal: 'instagram' };
    const zap = { ...livre(2), canal: 'whatsapp' };
    const waha = { ...livre(3, 'Channel::Api', 'Celular'), canal: 'whatsapp' };
    expect(canalSugerido([insta, zap], 5, 'instagram').inbox_id).toBe(1);
    expect(canalSugerido([insta, waha], 5, 'whatsapp').inbox_id).toBe(3);
    expect(canalSugerido([insta, zap, waha], 5, 'whatsapp')).toBeNull();
  });

  it('lets the person choose when the asked channel is busy or missing', () => {
    const instaOcupado = {
      ...ocupada(1, 'Channel::Instagram'),
      canal: 'instagram',
    };
    const zap = { ...livre(2), canal: 'whatsapp' };
    expect(canalSugerido([instaOcupado, zap], 5, 'instagram')).toBeNull();
    expect(canalSugerido([zap], 5, 'site')).toBeNull();
    expect(temCanalParaEscolher([instaOcupado, zap], 5)).toBe(true);
  });

  it('does not filter when nothing was asked ("nenhum" or an old thread)', () => {
    const zap = { ...livre(2), canal: 'whatsapp' };
    expect(canalSugerido([zap], 5, 'nenhum').inbox_id).toBe(2);
    expect(canalSugerido([zap], 5, undefined).inbox_id).toBe(2);
    expect(canalSugerido([zap], 5, '').inbox_id).toBe(2);
  });

  it('has a channel to choose when any inbox is free or busy, never only other systems', () => {
    expect(temCanalParaEscolher([livre(1), livre(2)], 5)).toBe(true);
    expect(temCanalParaEscolher([ocupada(3)], 5)).toBe(true);
    expect(temCanalParaEscolher([externa(1)], 5)).toBe(false);
    expect(temCanalParaEscolher([{ ...livre(1), alcanca: false }], 5)).toBe(
      false
    );
    expect(
      temCanalParaEscolher([{ ...livre(1), alcanca: false }, ocupada(3)], 5)
    ).toBe(true);
    expect(
      temCanalParaEscolher(
        [
          { ...livre(1), alcanca: false },
          { ...ocupada(3), alcanca: false },
        ],
        5
      )
    ).toBe(false);
    expect(temCanalParaEscolher([], 5)).toBe(false);
  });

  it('names the channel by its kind, or by the inbox name when unknown', () => {
    expect(tipoDoCanalParaTexto(livre(1))).toEqual({ chave: 'WHATSAPP' });
    expect(tipoDoCanalParaTexto(livre(1, 'Channel::WebWidget'))).toEqual({
      chave: 'SITE',
    });
    expect(tipoDoCanalParaTexto(livre(1, 'Channel::Api', 'Loja'))).toEqual({
      nome: 'Loja',
    });
  });
});

describe('horário de cada caixa', () => {
  // Mesmos moldes do pt_BR, para o teste ler como a pessoa lê.
  const NS = 'AGENTS.JORNADA.CRIAR.HORARIO';
  const MOLDES = {
    [`${NS}.INTERVALO`]: '{inicio} a {fim}',
    [`${NS}.FAIXA`]: '{dias}, das {abre} às {fecha}',
    [`${NS}.DIA_TODO`]: '{dias}, o dia todo',
    [`${NS}.E`]: '{antes}, e {depois}',
    [`${NS}.HORA`]: '{h}h',
    [`${NS}.HORA_MIN`]: '{h}h{m}',
    ...Object.fromEntries(
      ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'].map((nome, i) => [
        `${NS}.DIAS.${i}`,
        nome,
      ])
    ),
  };
  const t = (chave, valores = {}) =>
    Object.entries(valores).reduce(
      (texto, [nome, valor]) => texto.replace(`{${nome}}`, valor),
      MOLDES[chave] ?? chave
    );
  const dia = (d, abre, fecha, extra = {}) => ({
    day_of_week: d,
    open_hour: abre,
    open_minutes: 0,
    close_hour: fecha,
    close_minutes: 0,
    closed_all_day: false,
    open_all_day: false,
    ...extra,
  });

  it('has no text (and no lock) for an inbox outside the store', () => {
    expect(textoDoHorario(undefined, t)).toBeUndefined();
  });

  it('is null when the inbox has no business hours', () => {
    expect(
      textoDoHorario({ id: 1, working_hours_enabled: false }, t)
    ).toBeNull();
    expect(
      textoDoHorario(
        {
          id: 1,
          working_hours_enabled: true,
          working_hours: [dia(1, 9, 18, { closed_all_day: true })],
        },
        t
      )
    ).toBeNull();
  });

  it('groups consecutive days with the same hours, Monday first', () => {
    const caixa = {
      id: 1,
      working_hours_enabled: true,
      working_hours: [
        dia(0, 0, 0, { closed_all_day: true }),
        ...[1, 2, 3, 4, 5].map(d => dia(d, 9, 18)),
        dia(6, 9, 13),
      ],
    };
    expect(textoDoHorario(caixa, t)).toBe(
      'seg a sex, das 9h às 18h, e sáb, das 9h às 13h'
    );
  });

  it('writes minutes and whole days', () => {
    const caixa = {
      id: 1,
      working_hours_enabled: true,
      working_hours: [
        { ...dia(1, 8, 17), open_minutes: 30 },
        dia(2, 0, 0, { open_all_day: true }),
      ],
    };
    expect(textoDoHorario(caixa, t)).toBe(
      'seg, das 8h30 às 17h, e ter, o dia todo'
    );
  });

  it('does not join days that are not next to each other', () => {
    const caixa = {
      id: 1,
      working_hours_enabled: true,
      working_hours: [dia(1, 9, 18), dia(3, 9, 18)],
    };
    expect(textoDoHorario(caixa, t)).toBe(
      'seg, das 9h às 18h, e qua, das 9h às 18h'
    );
  });

  it('maps the store inboxes by id, leaving out the ones it does not know', () => {
    const horarios = horariosDasCaixas(
      [livre(1), livre(2)],
      [{ id: 1, working_hours_enabled: false }],
      t
    );
    expect(horarios).toEqual({ 1: null });
  });
});
