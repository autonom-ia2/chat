import {
  QUEM,
  comMudanca,
  faltaNoReenvio,
  mensagemDoCanal,
  modelosQueVao,
  quemPodeEscolher,
  reenvioDoCanal,
  reenvioNovo,
  reenvioParaEnvio,
} from '../reenvio/reenvio';
import { medicaoDaCampanha } from '../journeyChannelPayloads';
import { emptyDraft } from '../campaignDraft';

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

  it('sends the text on SMS and WhatsApp API, and the subject on e-mail', () => {
    const reenvio = { ...reenvioNovo(), texto: ' Ainda aí? ', assunto: 'Oi' };

    expect(reenvioParaEnvio({ channel: 'sms', reenvio })).toEqual({
      reenvio_quem: 'nao_respondeu',
      reenvio_dias: 3,
      reenvio_mensagem: { texto: 'Ainda aí?' },
    });
    expect(
      reenvioParaEnvio({ channel: 'email', reenvio }).reenvio_mensagem
    ).toEqual({ assunto: 'Oi' });
  });

  it('sends "did not read" only on WhatsApp Oficial, with the template the page built', () => {
    const reenvio = { ...reenvioNovo(), quem: QUEM.NAO_LEU, modeloId: 'm2' };
    const modelo = { modelo_id: 'm2', template_params: {}, ligacoes: {} };

    expect(
      reenvioParaEnvio({ channel: 'whatsapp_official', reenvio }, { modelo })
    ).toEqual({
      reenvio_quem: 'nao_leu',
      reenvio_dias: 3,
      reenvio_mensagem: modelo,
    });
    expect(
      reenvioParaEnvio({ channel: 'whatsapp_api', reenvio }).reenvio_quem
    ).toBe('nao_respondeu');
  });

  it('sends nothing when off, on live chat, or on WhatsApp Oficial without the template', () => {
    const reenvio = reenvioNovo();

    expect(reenvioParaEnvio({ channel: 'sms', reenvio: null })).toEqual({});
    expect(reenvioParaEnvio({ channel: 'live_chat', reenvio })).toEqual({});
    expect(reenvioParaEnvio({ channel: 'whatsapp_official', reenvio })).toEqual(
      {}
    );
  });

  it('goes in the creation together with the other review choices', () => {
    const draft = {
      ...emptyDraft(),
      channel: 'sms',
      reenvio: { ...reenvioNovo(), texto: 'Ainda aí?', dias: 5 },
    };

    expect(medicaoDaCampanha(draft)).toEqual({
      janela_de_compra_dias: 7,
      grupo_de_controle_pct: 0,
      reenvio_quem: 'nao_respondeu',
      reenvio_dias: 5,
      reenvio_mensagem: { texto: 'Ainda aí?' },
    });
  });
});
