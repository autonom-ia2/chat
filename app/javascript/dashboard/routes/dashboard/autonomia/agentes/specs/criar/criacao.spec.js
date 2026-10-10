import {
  modeloDaQuery,
  idDaQuery,
  perguntasDeTeste,
  exemploDoModelo,
  ETAPA,
  etapaDaQuery,
} from '../../constants/criacao';
import {
  canalSugerido,
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

describe('canal sugerido no botão de começar', () => {
  it('prefers a free WhatsApp, then any free inbox', () => {
    expect(
      canalSugerido([livre(1, 'Channel::WebWidget'), livre(2), ocupada(3)], 5)
        .inbox_id
    ).toBe(2);
    expect(
      canalSugerido([ocupada(3), livre(1, 'Channel::Email')], 5).inbox_id
    ).toBe(1);
  });

  it('counts the inbox this agent already has as free', () => {
    const minha = {
      ...livre(4),
      occupied_by: { kind: 'agent', agent_id: 5, agent_name: 'Duda' },
    };
    expect(canalSugerido([ocupada(3), minha], 5).inbox_id).toBe(4);
  });

  it('falls back to a busy inbox (swap), never to another system', () => {
    expect(canalSugerido([externa(1), ocupada(3)], 5).inbox_id).toBe(3);
    expect(canalSugerido([externa(1)], 5)).toBeNull();
    expect(canalSugerido([], 5)).toBeNull();
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
