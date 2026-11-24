import {
  QUEM,
  comMudanca,
  faltaNoReenvio,
  mensagemDoCanal,
  modelosQueVao,
  quemPodeEscolher,
  reenvioDoCanal,
  reenvioNovo,
} from '../reenvio/reenvio';

describe('reenvio (#3101)', () => {
  it('picks the kind of second message by channel', () => {
    expect(mensagemDoCanal('whatsapp_official')).toBe('modelo');
    expect(mensagemDoCanal('whatsapp_api')).toBe('texto');
    expect(mensagemDoCanal('sms')).toBe('texto');
    expect(mensagemDoCanal('email')).toBe('assunto');
    expect(mensagemDoCanal('live_chat')).toBeNull();
  });

  it('offers "did not read" only where the channel reports reading', () => {
    expect(quemPodeEscolher('whatsapp_official')).toEqual([
      QUEM.NAO_RESPONDEU,
      QUEM.NAO_LEU,
    ]);
    expect(quemPodeEscolher('sms')).toEqual([QUEM.NAO_RESPONDEU]);
    expect(quemPodeEscolher('email')).toEqual([QUEM.NAO_RESPONDEU]);
  });

  it('starts as "did not reply, 3 days later", with the example the screen gives', () => {
    expect(reenvioNovo()).toEqual({
      quem: 'nao_respondeu',
      dias: 3,
      modeloId: null,
      ligacoes: {},
      texto: '',
      assunto: '',
    });
    expect(reenvioNovo({ texto: 'Oi' }).texto).toBe('Oi');
  });

  it('keeps only the templates that can go', () => {
    expect(
      modelosQueVao([{ value: 'a' }, { value: 'b', disabled: true }])
    ).toEqual([{ value: 'a' }]);
  });

  it('changes one part without touching the object it got', () => {
    const antes = reenvioNovo();
    const depois = comMudanca(antes, { dias: 7 });

    expect(depois.dias).toBe(7);
    expect(antes.dias).toBe(3);
    expect(comMudanca(null, { texto: 'Oi' }).texto).toBe('Oi');
  });

  it('says what is missing for each channel, and nothing when off', () => {
    const vazio = reenvioNovo();

    expect(faltaNoReenvio(null, 'sms')).toBeNull();
    expect(faltaNoReenvio(vazio, 'whatsapp_official')).toBe('SEM_MODELO');
    expect(faltaNoReenvio(vazio, 'sms')).toBe('SEM_TEXTO');
    expect(faltaNoReenvio({ ...vazio, texto: '   ' }, 'whatsapp_api')).toBe(
      'SEM_TEXTO'
    );
    expect(faltaNoReenvio(vazio, 'email')).toBe('SEM_ASSUNTO');
    expect(
      faltaNoReenvio({ ...vazio, modeloId: 'lembrete' }, 'whatsapp_official')
    ).toBeNull();
    expect(faltaNoReenvio({ ...vazio, assunto: 'Oi' }, 'email')).toBeNull();
  });

  it('asks where each variable of the second template comes from', () => {
    const modelo = { variaveis: [{ key: '1' }, { key: '2' }] };
    const escolhido = { ...reenvioNovo(), modeloId: 'lembrete' };
    const nome = { source: 'contact', value: 'name' };

    expect(
      faltaNoReenvio(
        { ...escolhido, ligacoes: { 1: nome } },
        'whatsapp_official',
        modelo
      )
    ).toBe('SEM_LIGACAO');
    expect(
      faltaNoReenvio(
        { ...escolhido, ligacoes: { 1: nome, 2: nome } },
        'whatsapp_official',
        modelo
      )
    ).toBeNull();
  });

  it('turns "did not read" into "did not reply" on a channel without reading', () => {
    const naoLeu = { ...reenvioNovo(), quem: QUEM.NAO_LEU };

    expect(reenvioDoCanal(naoLeu, 'sms').quem).toBe(QUEM.NAO_RESPONDEU);
    expect(reenvioDoCanal(naoLeu, 'whatsapp_official')).toBe(naoLeu);
    expect(reenvioDoCanal(null, 'sms')).toBeNull();
  });
});
