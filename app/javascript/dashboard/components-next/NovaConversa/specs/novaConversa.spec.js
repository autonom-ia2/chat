import { describe, it, expect } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  MODOS,
  TELAS,
  TIPOS,
  aceitaAnexo,
  chaveDoCanal,
  contatoLegivel,
  linhaDoCanal,
  lugarDeOrigem,
  nomeLegivel,
  oQueFalta,
  ordenarCanais,
  podeCriarContato,
  primeiroNome,
  telaDaGaveta,
  telefoneLegivel,
  tipoDeMensagem,
  usaModelo,
} from '../novaConversa';

// #1459 — as regras da tela "Nova conversa".
const whatsapp = { id: 1, channelType: INBOX_TYPES.WHATSAPP };
const whatsappLivre = { ...whatsapp, whatsappApiStart: true };
const twilioWhatsapp = {
  id: 2,
  channelType: INBOX_TYPES.TWILIO,
  medium: 'whatsapp',
  phoneNumber: 'whatsapp:+5511999990000',
};
const twilioSms = { id: 3, channelType: INBOX_TYPES.TWILIO, medium: 'sms' };
const email = { id: 4, channelType: INBOX_TYPES.EMAIL, email: 'oi@loja.com' };
const site = { id: 5, channelType: INBOX_TYPES.WEB };
const api = { id: 6, channelType: INBOX_TYPES.API };
const contato = { id: 9, name: 'Ana' };

describe('tipoDeMensagem', () => {
  it('fica vazio enquanto não há canal', () => {
    expect(tipoDeMensagem(null)).toBe('');
  });

  it('pede mensagem pronta no WhatsApp oficial sem texto livre', () => {
    expect(tipoDeMensagem(whatsapp)).toBe(TIPOS.WHATSAPP_PRONTA);
    expect(tipoDeMensagem({ ...whatsapp, whatsappApiStart: false })).toBe(
      TIPOS.WHATSAPP_PRONTA
    );
  });

  it('libera escrever quando o servidor diz que o texto livre vale', () => {
    expect(tipoDeMensagem(whatsappLivre)).toBe(TIPOS.WHATSAPP_LIVRE);
  });

  it('separa o WhatsApp via Twilio do SMS via Twilio', () => {
    expect(tipoDeMensagem(twilioWhatsapp)).toBe(TIPOS.WHATSAPP_TWILIO);
    expect(tipoDeMensagem(twilioSms)).toBe(TIPOS.TEXTO);
  });

  it('trata e-mail como e-mail e o resto como texto simples', () => {
    expect(tipoDeMensagem(email)).toBe(TIPOS.EMAIL);
    expect(tipoDeMensagem(site)).toBe(TIPOS.TEXTO);
    expect(tipoDeMensagem(api)).toBe(TIPOS.TEXTO);
    expect(tipoDeMensagem({ channelType: INBOX_TYPES.SMS })).toBe(TIPOS.TEXTO);
  });
});

describe('chaveDoCanal e linhaDoCanal', () => {
  it('chama cada canal pelo nome que a pessoa conhece', () => {
    expect(chaveDoCanal(whatsapp)).toBe('WHATSAPP');
    expect(chaveDoCanal(twilioWhatsapp)).toBe('WHATSAPP');
    expect(chaveDoCanal(twilioSms)).toBe('SMS');
    expect(chaveDoCanal({ channelType: INBOX_TYPES.SMS })).toBe('SMS');
    expect(chaveDoCanal(email)).toBe('EMAIL');
    expect(chaveDoCanal(site)).toBe('SITE');
    expect(chaveDoCanal(api)).toBe('OUTRO');
    expect(chaveDoCanal(null)).toBe('OUTRO');
  });

  it('a caixa API ligada ao WAHA é o WhatsApp do celular (#2255)', () => {
    expect(chaveDoCanal({ ...api, wahaProvider: true })).toBe(
      'WHATSAPP_CELULAR'
    );
    expect(chaveDoCanal({ ...api, wahaProvider: false })).toBe('OUTRO');
  });

  it('mostra o e-mail ou o número legível, sem o prefixo do Twilio', () => {
    expect(linhaDoCanal(email)).toBe('oi@loja.com');
    expect(linhaDoCanal({ ...whatsapp, phoneNumber: '+5511988887777' })).toBe(
      '+55 11 98888-7777'
    );
    expect(linhaDoCanal(twilioWhatsapp)).toBe('+55 11 99999-0000');
    expect(linhaDoCanal(site)).toBe('');
    expect(linhaDoCanal(null)).toBe('');
  });

  it('WhatsApp pelo celular (caixa API do WAHA): o número da sessão, legível (#2255)', () => {
    const celular = {
      channelType: INBOX_TYPES.API,
      wahaProvider: true,
      wahaPhoneNumber: '+5511900003303',
    };
    expect(linhaDoCanal(celular)).toBe('+55 11 90000-3303');
    expect(linhaDoCanal({ channelType: INBOX_TYPES.API })).toBe('');
  });
});

describe('ordenarCanais', () => {
  const nomes = canais => ordenarCanais(canais).map(canal => canal.name);

  it('põe o WhatsApp primeiro, e o de texto livre antes do só pronta', () => {
    const canais = [
      { ...email, name: 'E-mail' },
      { ...site, name: 'Site' },
      { ...whatsapp, name: 'Zap só pronta' },
      { ...api, name: 'Outro' },
      { ...twilioSms, name: 'SMS' },
      { ...whatsappLivre, name: 'Zap livre' },
    ];

    expect(nomes(canais)).toEqual([
      'Zap livre',
      'Zap só pronta',
      'E-mail',
      'SMS',
      'Site',
      'Outro',
    ]);
  });

  it('trata o WhatsApp via Twilio como WhatsApp sem texto livre', () => {
    const canais = [
      { ...email, name: 'E-mail' },
      { ...twilioWhatsapp, name: 'Twilio' },
      { ...whatsappLivre, name: 'Oficial' },
    ];

    expect(nomes(canais)).toEqual(['Oficial', 'Twilio', 'E-mail']);
  });

  it('o WhatsApp do celular vem logo depois do oficial e antes do e-mail (#2255)', () => {
    const canais = [
      { ...api, name: 'API comum' },
      { ...email, name: 'E-mail' },
      { ...api, wahaProvider: true, name: 'Celular' },
      { ...whatsapp, name: 'Oficial' },
    ];

    expect(nomes(canais)).toEqual([
      'Oficial',
      'Celular',
      'E-mail',
      'API comum',
    ]);
  });

  it('ordena por nome dentro do mesmo tipo e não mexe na lista recebida', () => {
    const canais = [
      { ...whatsapp, name: 'Vendas' },
      { ...whatsapp, name: 'Atendimento' },
      { ...whatsapp },
    ];

    expect(nomes(canais)).toEqual([undefined, 'Atendimento', 'Vendas']);
    expect(canais[0].name).toBe('Vendas');
    expect(ordenarCanais()).toEqual([]);
  });
});

describe('aceitaAnexo', () => {
  it('só mantém anexo onde já existia: e-mail e site', () => {
    expect(aceitaAnexo(email)).toBe(true);
    expect(aceitaAnexo(site)).toBe(true);
    expect(aceitaAnexo(whatsappLivre)).toBe(false);
    expect(aceitaAnexo(twilioSms)).toBe(false);
    expect(aceitaAnexo(null)).toBe(false);
  });
});

describe('usaModelo', () => {
  it('é sempre modelo no WhatsApp sem texto livre', () => {
    expect(
      usaModelo({ tipo: TIPOS.WHATSAPP_PRONTA, modo: MODOS.ESCREVER })
    ).toBe(true);
  });

  it('depende da escolha quando o texto livre vale', () => {
    expect(
      usaModelo({ tipo: TIPOS.WHATSAPP_LIVRE, modo: MODOS.ESCREVER })
    ).toBe(false);
    expect(usaModelo({ tipo: TIPOS.WHATSAPP_LIVRE, modo: MODOS.PRONTA })).toBe(
      true
    );
  });

  it('nunca é modelo fora do WhatsApp oficial', () => {
    expect(usaModelo({ tipo: TIPOS.EMAIL, modo: MODOS.PRONTA })).toBe(false);
    expect(usaModelo({ tipo: TIPOS.TEXTO, modo: MODOS.PRONTA })).toBe(false);
  });
});

describe('oQueFalta', () => {
  it('pede o contato e depois o canal, nessa ordem', () => {
    expect(oQueFalta({ contato: null, canal: null })).toBe('CONTATO');
    expect(oQueFalta({ contato: {}, canal: whatsapp })).toBe('CONTATO');
    expect(oQueFalta({ contato, canal: null })).toBe('CANAL');
  });

  it('pede a mensagem no texto simples e ignora só espaços', () => {
    expect(oQueFalta({ contato, canal: site })).toBe('MENSAGEM');
    expect(oQueFalta({ contato, canal: site, mensagem: '  \n ' })).toBe(
      'MENSAGEM'
    );
    expect(oQueFalta({ contato, canal: site, mensagem: 'Oi' })).toBe('');
  });

  it('pede o assunto antes da mensagem no e-mail', () => {
    expect(oQueFalta({ contato, canal: email, mensagem: 'Oi' })).toBe(
      'ASSUNTO'
    );
    expect(oQueFalta({ contato, canal: email, assunto: 'Proposta' })).toBe(
      'MENSAGEM'
    );
    expect(
      oQueFalta({ contato, canal: email, assunto: 'Proposta', mensagem: 'Oi' })
    ).toBe('');
  });

  it('pede o modelo e depois os campos no WhatsApp sem texto livre', () => {
    const modelo = { name: 'boas_vindas' };
    expect(oQueFalta({ contato, canal: whatsapp, mensagem: 'Oi' })).toBe(
      'MODELO'
    );
    expect(oQueFalta({ contato, canal: whatsapp, modelo })).toBe('CAMPOS');
    expect(
      oQueFalta({ contato, canal: whatsapp, modelo, camposProntos: true })
    ).toBe('');
  });

  it('segue a escolha da pessoa quando o texto livre vale', () => {
    const base = { contato, canal: whatsappLivre };
    expect(oQueFalta(base)).toBe('MENSAGEM');
    expect(oQueFalta({ ...base, mensagem: 'Oi' })).toBe('');
    expect(oQueFalta({ ...base, mensagem: 'Oi', modo: MODOS.PRONTA })).toBe(
      'MODELO'
    );
  });

  it('nunca libera o botão no WhatsApp via Twilio (envia pelo seletor)', () => {
    expect(oQueFalta({ contato, canal: twilioWhatsapp, mensagem: 'Oi' })).toBe(
      'MODELO'
    );
  });
});

describe('telefoneLegivel e contatoLegivel', () => {
  it('mostra fixo e celular do Brasil com país, DDD e hífen', () => {
    expect(telefoneLegivel('+551140000001')).toBe('+55 11 4000-0001');
    expect(telefoneLegivel('+5511988887777')).toBe('+55 11 98888-7777');
  });

  it('escreve o número de outro país do jeito daquele país', () => {
    expect(telefoneLegivel('+14155552671')).toBe('+1 415 555 2671');
    expect(telefoneLegivel('+351912345678')).toBe('+351 912 345 678');
  });

  it('devolve como veio o que a biblioteca não reconhece', () => {
    expect(telefoneLegivel('40000001')).toBe('40000001');
    expect(telefoneLegivel('+5511')).toBe('+5511');
    expect(telefoneLegivel('abc')).toBe('abc');
    expect(telefoneLegivel('')).toBe('');
    expect(telefoneLegivel()).toBe('');
  });

  it('prefere o telefone ao e-mail na linha da pessoa', () => {
    expect(
      contatoLegivel({ phoneNumber: '+551140000001', email: 'a@b.com' })
    ).toBe('+55 11 4000-0001');
    expect(contatoLegivel({ email: 'a@b.com' })).toBe('a@b.com');
    expect(contatoLegivel({})).toBe('');
    expect(contatoLegivel(null)).toBe('');
  });
});

describe('nomeLegivel', () => {
  it('troca os traços do nome do modelo por espaços', () => {
    expect(nomeLegivel('boas_vindas_cliente')).toBe('Boas vindas cliente');
    expect(nomeLegivel('lembrete-de-pagamento')).toBe('Lembrete de pagamento');
    expect(nomeLegivel('')).toBe('');
  });
});

describe('primeiroNome', () => {
  it('fica com a primeira palavra do nome', () => {
    expect(primeiroNome('  Mariana Souza Lima ')).toBe('Mariana');
    expect(primeiroNome('Ana')).toBe('Ana');
    expect(primeiroNome('')).toBe('');
    expect(primeiroNome()).toBe('');
  });

  it('nome que é só telefone vai inteiro, não "+55" (#2255)', () => {
    expect(primeiroNome('+55 11 95555-4444')).toBe('+55 11 95555-4444');
  });
});

describe('telaDaGaveta', () => {
  const comCanal = { contato, canais: [site] };

  it('pede o contato antes de tudo', () => {
    expect(telaDaGaveta({})).toBe(TELAS.SEM_CONTATO);
    expect(telaDaGaveta({ canais: [site] })).toBe(TELAS.SEM_CONTATO);
  });

  it('só diz que não há canal depois de o servidor responder', () => {
    expect(telaDaGaveta({ contato, carregandoCanais: true })).toBe(
      TELAS.ESCREVENDO
    );
    expect(telaDaGaveta({ contato, erroNosCanais: true })).toBe(
      TELAS.ESCREVENDO
    );
    expect(telaDaGaveta({ contato })).toBe(TELAS.SEM_CANAL);
  });

  it('fica em escrever com canal e passa a enviada depois do envio', () => {
    expect(telaDaGaveta(comCanal)).toBe(TELAS.ESCREVENDO);
    expect(telaDaGaveta({ ...comCanal, enviada: true })).toBe(TELAS.ENVIADA);
  });
});

describe('podeCriarContato', () => {
  it('aceita telefone com + e só números', () => {
    expect(podeCriarContato('+5511999990000')).toBe(true);
    expect(podeCriarContato(' +5511999990000 ')).toBe(true);
    expect(podeCriarContato('+55 11 9999')).toBe(false);
    expect(podeCriarContato('+123')).toBe(false);
    expect(podeCriarContato('11999990000')).toBe(false);
  });

  it('aceita e-mail com um @ e um ponto depois dele', () => {
    expect(podeCriarContato('ana@loja.com')).toBe(true);
    expect(podeCriarContato('ana@loja')).toBe(false);
    expect(podeCriarContato('@loja.com')).toBe(false);
    expect(podeCriarContato('ana@@loja.com')).toBe(false);
    expect(podeCriarContato('Ana Souza')).toBe(false);
    expect(podeCriarContato('')).toBe(false);
  });
});

describe('lugarDeOrigem', () => {
  it('diz "Contatos" nas telas de contato', () => {
    expect(lugarDeOrigem({ rota: 'contacts_dashboard_index' })).toBe(
      'CONTATOS'
    );
    expect(lugarDeOrigem({ rota: 'relacionamento', comContato: true })).toBe(
      'CONTATOS'
    );
  });

  it('diz "Conversas" na conversa e no menu lateral', () => {
    expect(
      lugarDeOrigem({ rota: 'inbox_conversation', comContato: true })
    ).toBe('CONVERSAS');
    expect(lugarDeOrigem({ rota: 'home' })).toBe('CONVERSAS');
    expect(lugarDeOrigem({})).toBe('CONVERSAS');
  });
});
