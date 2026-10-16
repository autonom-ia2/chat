import {
  faltaEscolherLegado,
  faltaTriagem,
  mudancas,
  paraFormulario,
  paraSalvar,
  portaOuRobo,
  roboExterno,
} from '../helpers/caixa';

describe('porta ou robô (#1570)', () => {
  const ia = { id: 1, name: 'Clara', tipo_do_principal: 'ia' };
  const externo = { id: 2, name: 'Robô n8n', tipo_do_principal: 'externo' };

  it('never takes an external agent as the AI door', () => {
    expect(roboExterno(externo)).toBe(true);
    expect(roboExterno(ia)).toBe(false);
    expect(roboExterno(null)).toBe(false);
    expect(portaOuRobo(null, externo)).toBeNull();
    expect(portaOuRobo(null, ia)).toBe(ia);
    expect(portaOuRobo({ id: 9, name: 'Porta' }, externo)).toEqual({
      id: 9,
      name: 'Porta',
    });
  });
});

const FUNIS = [
  { id: 1, name: 'Vendas', stages: [{ id: 11, name: 'Novo' }] },
  { id: 2, name: 'Pós-venda', stages: [{ id: 21, name: 'Novo' }] },
];

const pessoa = (id, name, extra = {}) => ({
  id,
  name,
  administrator: false,
  triage: true,
  all_pipelines: true,
  pipeline_ids: [],
  only_own: false,
  ...extra,
});

const caixa = (extra = {}) => ({
  inbox: { id: 7, name: 'WhatsApp', channel_type: 'Channel::Whatsapp' },
  crm_enabled: true,
  pipeline_ids: [1, 2],
  default_stage_id: null,
  subject_ai_mode: 'auto',
  auto_create_card: false,
  visibility_mode: 'all_inbox_cards',
  people: [
    pessoa(1, 'Marta Alves', { administrator: true }),
    pessoa(2, 'Ana Ribeiro'),
  ],
  ...extra,
});

const opcoes = { semAssunto: 'conversas sem assunto', locale: 'pt_BR' };

describe('caixa helpers', () => {
  it('opens "all pipelines" as every pipeline of the inbox and keeps the mode', () => {
    const form = paraFormulario(caixa());
    expect(form.people[1].pipeline_ids).toEqual([1, 2]);
    expect(form.modo).toBe('auto');
  });

  it('sends only agents, with pipelines limited to the inbox', () => {
    const form = paraFormulario(caixa());
    form.pipeline_ids = [1];
    form.modo = 'chegou';
    form.default_stage_id = 11;
    expect(paraSalvar(form)).toEqual({
      pipeline_ids: [1],
      default_stage_id: 11,
      modo: 'chegou',
      people: [{ id: 2, triage: true, only_own: false, pipeline_ids: [1] }],
    });
  });

  it('blocks several pipelines when no agent sees conversations without a subject', () => {
    const form = paraFormulario(caixa());
    form.people[1].triage = false;
    expect(faltaTriagem(form)).toBe(true);
    form.pipeline_ids = [1];
    expect(faltaTriagem(form)).toBe(false);
  });

  it('describes what changes by name', () => {
    const antes = paraFormulario(caixa());
    const depois = paraFormulario(caixa());
    depois.people[1].triage = false;
    depois.people[1].only_own = true;
    depois.modo = 'suggest';
    expect(mudancas(antes, depois, FUNIS, opcoes)).toEqual([
      {
        chave: 'PESSOA_PERDE',
        valores: { nome: 'Ana', assuntos: 'conversas sem assunto' },
      },
      { chave: 'PESSOA_SO_SUAS', valores: { nome: 'Ana' } },
      { chave: 'MODO', valores: { modo: 'suggest' } },
    ]);
  });

  it('compares what the system does, not the saved mode (#1676)', () => {
    const varios = paraFormulario(caixa());
    varios.modo = 'auto';
    const um = { ...paraFormulario(caixa()), pipeline_ids: [1], modo: 'off' };
    const comIa = { ...opcoes, iaDeAssunto: true };

    // Vários funis em "criar ao entender" → 1 funil sem card na chegada: com a
    // IA de assunto em 1 funil, o sistema faz o mesmo; sem ela, passa a não
    // fazer nada.
    expect(
      mudancas(varios, um, FUNIS, comIa).filter(item => item.chave === 'MODO')
    ).toEqual([]);
    expect(
      mudancas(varios, um, FUNIS, opcoes).filter(item => item.chave === 'MODO')
    ).toEqual([{ chave: 'MODO', valores: { modo: 'off' } }]);

    // Vários funis "à mão" → 1 funil sem card na chegada: o valor gravado é o
    // mesmo ('off'), mas com a IA de assunto o sistema passa a criar o card.
    const variosAMao = { ...varios, modo: 'off' };
    expect(
      mudancas(variosAMao, um, FUNIS, comIa).filter(
        item => item.chave === 'MODO'
      )
    ).toEqual([{ chave: 'MODO', valores: { modo: 'off' } }]);
  });

  it('measures an "assigned only" inbox against what people see today', () => {
    const legado = caixa({ visibility_mode: 'assigned_only' });
    const antes = paraFormulario(legado);
    const mantido = paraFormulario(legado);
    mantido.people[1].only_own = true;
    expect(mudancas(antes, mantido, FUNIS, opcoes)).toEqual([]);
    expect(mudancas(antes, paraFormulario(legado), FUNIS, opcoes)).toEqual([
      { chave: 'PESSOA_TODAS', valores: { nome: 'Ana' } },
    ]);
  });

  it('asks for an explicit choice on an "assigned only" inbox and sends it', () => {
    const form = paraFormulario(caixa({ visibility_mode: 'assigned_only' }));
    expect(faltaEscolherLegado(form)).toBe(true);
    form.legado = 'manter';
    expect(faltaEscolherLegado(form)).toBe(false);
    expect(paraSalvar(form).legado).toBe('manter');
    expect(paraSalvar(paraFormulario(caixa()))).not.toHaveProperty('legado');
  });
});
