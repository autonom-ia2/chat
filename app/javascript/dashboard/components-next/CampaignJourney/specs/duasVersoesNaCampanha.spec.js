import {
  buildPreviewPayload,
  duasVersoesParaEnvio,
  medicaoDaCampanha,
} from '../journeyChannelPayloads';
import { duasVersoesErrorKey } from '../journeyErrors';
import { mesmasInformacoes } from '../useDuasVersoesNaCampanha';
import { emptyDraft } from '../campaignDraft';
import { CAMPAIGN_CHANNELS } from '../campaignChannels';

// #3099 — a ligação das duas versões com a Nova campanha: o que vai para o servidor e o que volta dele.
const ligadas = (extra = {}) => ({
  ...emptyDraft().duasVersoes,
  ligado: true,
  ...extra,
});

describe('duasVersoesParaEnvio', () => {
  it('desligadas, nada muda no envio', () => {
    expect(duasVersoesParaEnvio(emptyDraft())).toEqual({});
    expect(medicaoDaCampanha(emptyDraft())).toEqual({
      janela_de_compra_dias: 7,
      grupo_de_controle_pct: 0,
    });
  });

  it('WhatsApp Oficial: a versão 2 é o nome e o idioma do outro modelo (D3)', () => {
    const draft = {
      ...emptyDraft(),
      channel: CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
      duasVersoes: ligadas({ templateId: 12, criterio: 'compras', espera: 24 }),
    };
    expect(
      duasVersoesParaEnvio(draft, {
        modelo: { id: 12, name: 'renovacao_b', language: 'pt_BR' },
      })
    ).toEqual({
      duas_versoes: {
        criterio: 'compras',
        divisao: 50,
        espera_horas: 24,
        segunda: { template_name: 'renovacao_b', template_language: 'pt_BR' },
      },
    });
  });

  it('WhatsApp API: o texto da versão 2 leva só os textos padrão que ele usa', () => {
    const draft = {
      ...emptyDraft(),
      channel: CAMPAIGN_CHANNELS.WHATSAPP_API,
      defaults: { 'contact.first_name': 'cliente', 'contact.company': 'sua' },
      duasVersoes: ligadas({ texto: 'Oi {{contact.first_name}}!' }),
    };
    expect(duasVersoesParaEnvio(draft).duas_versoes.segunda).toEqual({
      message_body: 'Oi {{contact.first_name}}!',
      variable_defaults: { 'contact.first_name': 'cliente' },
    });
  });

  it('e-mail: só o assunto, sem espaços nas pontas (D2)', () => {
    const draft = {
      ...emptyDraft(),
      channel: CAMPAIGN_CHANNELS.EMAIL,
      duasVersoes: ligadas({ assunto: '  Outro assunto ' }),
    };
    expect(duasVersoesParaEnvio(draft).duas_versoes.segunda).toEqual({
      subject: 'Outro assunto',
    });
  });
});

describe('buildPreviewPayload', () => {
  it('com as duas versões, pede o plano do teste já sem o grupo de controle', () => {
    const draft = {
      ...emptyDraft(),
      channel: CAMPAIGN_CHANNELS.EMAIL,
      grupoDeControle: 10,
      duasVersoes: ligadas({ divisao: 70 }),
    };
    expect(buildPreviewPayload({ audienceId: 5, draft })).toEqual({
      campaign_import_id: 5,
      channel: 'email',
      duas_versoes: { divisao: 70 },
      grupo_de_controle_pct: 10,
    });
  });

  it('sem as duas versões, o pedido fica como sempre', () => {
    const draft = { ...emptyDraft(), channel: CAMPAIGN_CHANNELS.EMAIL };
    expect(buildPreviewPayload({ audienceId: 5, draft })).toEqual({
      campaign_import_id: 5,
      channel: 'email',
    });
  });
});

describe('duasVersoesErrorKey', () => {
  const erro = code => ({ response: { status: 422, data: { code } } });

  it('traduz os códigos da versão 2', () => {
    expect(duasVersoesErrorKey(erro('segunda_versao_outras_informacoes'))).toBe(
      'OUTRAS_INFORMACOES'
    );
    expect(
      duasVersoesErrorKey(erro('segunda_versao_modelo_nao_aprovado'))
    ).toBe('MODELO');
    expect(duasVersoesErrorKey(erro('duas_versoes_indisponivel'))).toBe(
      'INDISPONIVEL'
    );
    expect(duasVersoesErrorKey(erro('segunda_versao_vazia'))).toBe('SEGUNDA');
  });

  it('outro erro fica com a mensagem de sempre', () => {
    expect(duasVersoesErrorKey(erro('invalid_schedule'))).toBeNull();
    expect(duasVersoesErrorKey({})).toBeNull();
  });
});

describe('mesmasInformacoes', () => {
  const modelo = (texto, extra = []) => ({
    components: [{ type: 'BODY', text: texto }, ...extra],
  });

  it('mesmas variáveis no texto: serve para a versão 2', () => {
    expect(
      mesmasInformacoes(
        modelo('Olá {{1}}, vence em {{2}}.'),
        modelo('Oi {{1}}! Seu seguro vence em {{2}}.')
      )
    ).toBe(true);
  });

  it('outra variável, outro topo ou outro formato: não serve', () => {
    const primeiro = modelo('Olá {{1}}.');
    expect(mesmasInformacoes(modelo('Olá {{1}} e {{2}}.'), primeiro)).toBe(
      false
    );
    expect(
      mesmasInformacoes(
        modelo('Olá {{1}}.', [{ type: 'HEADER', format: 'IMAGE' }]),
        primeiro
      )
    ).toBe(false);
    expect(
      mesmasInformacoes(
        modelo('Olá {{1}}.', [
          { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE' }] },
        ]),
        primeiro
      )
    ).toBe(false);
  });

  it('botões que não pedem nada da campanha não contam', () => {
    expect(
      mesmasInformacoes(
        modelo('Olá {{1}}.', [
          { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'Sim' }] },
        ]),
        modelo('Olá {{1}}.')
      )
    ).toBe(true);
  });
});
