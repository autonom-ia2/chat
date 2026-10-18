import {
  dataCompletaDoEmail,
  dataCurtaDoEmail,
  destinatariosDoEmail,
  ehRastreioDeCampanha,
  lerEndereco,
  nomeCurto,
  remetenteDoEmail,
  semRastreio,
} from '../email/dadosDoEmail';
import { montarRespostaDoEmail } from '../email/respostaDoEmail';
import { semCitacaoDosLeitores } from '../email/citacaoDosLeitores';
import {
  MODOS_DE_RESPOSTA,
  emailNovoNaCaixa,
} from '../email/useConversaDeEmail';

describe('conversa de e-mail (#1786)', () => {
  it('só liga na caixa de e-mail com a chave da conta', () => {
    expect(emailNovoNaCaixa({ channel_type: 'Channel::Email' }, true)).toBe(
      true
    );
    expect(emailNovoNaCaixa({ channel_type: 'Channel::Email' }, false)).toBe(
      false
    );
    expect(emailNovoNaCaixa({ channel_type: 'Channel::Whatsapp' }, true)).toBe(
      false
    );
    expect(emailNovoNaCaixa(undefined, true)).toBe(false);
  });

  it('lê "Nome <endereço>" sem regex', () => {
    expect(lerEndereco('Paulo Sócio <paulo@ex.com>')).toEqual({
      nome: 'Paulo Sócio',
      endereco: 'paulo@ex.com',
    });
    expect(lerEndereco('"Ana" <ana@ex.com>').nome).toBe('Ana');
    expect(lerEndereco('ana@ex.com')).toEqual({
      nome: '',
      endereco: 'ana@ex.com',
    });
    expect(nomeCurto('paulo.socio@ex.com')).toBe('paulo.socio');
    expect(nomeCurto('Paulo Sócio <p@ex.com>')).toBe('Paulo');
  });

  describe('quem escreveu', () => {
    const contato = {
      name: 'Marina Costa',
      email: 'marina@ex.com',
      thumbnail: 'f.png',
    };

    it('o contato da conversa: nome e foto dele', () => {
      expect(
        remetenteDoEmail({
          contentAttributes: { email: { from: ['marina@ex.com'] } },
          sender: contato,
          recebido: true,
        })
      ).toEqual({
        nome: 'Marina Costa',
        endereco: 'marina@ex.com',
        foto: 'f.png',
        emCopia: false,
      });
    });

    it('alguém em cópia: o remetente real, sem a foto do contato, e o selo', () => {
      // O Chatwoot grava sender = contato mesmo quando quem escreveu foi outro.
      expect(
        remetenteDoEmail({
          contentAttributes: { email: { from: ['Paulo <PAULO@ex.com>'] } },
          sender: contato,
          recebido: true,
        })
      ).toEqual({
        nome: 'Paulo',
        endereco: 'PAULO@ex.com',
        foto: '',
        emCopia: true,
      });
    });

    it('enviado pelo painel nunca é "em cópia"', () => {
      expect(
        remetenteDoEmail({
          contentAttributes: {},
          sender: { name: 'Ana', email: 'ana@loja.com' },
          recebido: false,
        }).emCopia
      ).toBe(false);
    });
  });

  it('destinatários aceitam a lista do e-mail ou o texto do painel', () => {
    expect(
      destinatariosDoEmail({
        email: { to: ['a@x.com'], cc: ['b@x.com'] },
      })
    ).toEqual({ para: ['a@x.com'], cc: ['b@x.com'], cco: [] });
    expect(
      destinatariosDoEmail({
        toEmails: 'a@x.com, c@x.com',
        bccEmails: 'd@x.com',
      })
    ).toEqual({ para: ['a@x.com', 'c@x.com'], cc: [], cco: ['d@x.com'] });
  });

  describe('data no fuso da conta', () => {
    // 17/10/2026 15:00 em São Paulo (18:00 UTC).
    const agora = Date.UTC(2026, 9, 17, 18, 0) / 1000;
    const fuso = 'America/Sao_Paulo';

    it('hoje: só a hora', () => {
      const quando = Date.UTC(2026, 9, 17, 12, 20) / 1000;
      expect(dataCurtaDoEmail({ quando, agora, fuso })).toBe('09:20');
    });

    it('este ano: dia e mês; ano anterior: com o ano', () => {
      const ontem = Date.UTC(2026, 9, 16, 15, 20) / 1000;
      expect(dataCurtaDoEmail({ quando: ontem, agora, fuso })).toBe(
        '16 de out.'
      );
      const antigo = Date.UTC(2025, 2, 3, 15, 0) / 1000;
      expect(dataCurtaDoEmail({ quando: antigo, agora, fuso })).toContain(
        '2025'
      );
    });

    it('a data completa diz há quanto tempo', () => {
      const ontem = Date.UTC(2026, 9, 16, 15, 20) / 1000;
      const texto = dataCompletaDoEmail({ quando: ontem, agora, fuso });
      expect(texto).toContain('12:20');
      expect(texto).toContain('(ontem)');
    });
  });

  it('não carrega pixel nem segue link de rastreio das campanhas', () => {
    const pixel = 'https://chat.exemplo.com/email_campaigns/t/o/abc';
    const clique = 'https://chat.exemplo.com/email_campaigns/t/c/abc';
    expect(ehRastreioDeCampanha(pixel)).toBe(true);
    expect(semRastreio(pixel)).toBe('');
    expect(semRastreio(clique)).toBe('');
    expect(semRastreio('https://site.com/logo.png')).toBe(
      'https://site.com/logo.png'
    );
  });

  describe('o que cada ação põe na resposta', () => {
    const mensagem = {
      message_type: 0,
      content: 'Oi',
      content_attributes: {
        email: {
          from: ['marina@ex.com'],
          to: ['comercial@loja.com'],
          cc: ['paulo@ex.com'],
          subject: 'Proposta',
          date: '2026-10-16',
          text_content: { reply: 'Segue a proposta.' },
        },
      },
    };
    const caixa = { email: 'comercial@loja.com' };

    it('Responder: só quem escreveu', () => {
      const r = montarRespostaDoEmail({
        modo: MODOS_DE_RESPOSTA.RESPONDER,
        mensagem,
        contato: 'marina@ex.com',
        caixa,
      });
      expect(r.para).toContain('marina@ex.com');
      expect(r.cc).toBe('');
    });

    it('Responder a todos: quem estava em cópia vai junto', () => {
      const r = montarRespostaDoEmail({
        modo: MODOS_DE_RESPOSTA.TODOS,
        mensagem,
        contato: 'marina@ex.com',
        caixa,
      });
      expect(`${r.para}, ${r.cc}`).toContain('paulo@ex.com');
      expect(`${r.para}, ${r.cc}`).not.toContain('comercial@loja.com');
    });

    it('Encaminhar: destinatário em branco; o original vai pelo servidor, formatado', () => {
      expect(
        montarRespostaDoEmail({
          modo: MODOS_DE_RESPOSTA.ENCAMINHAR,
          mensagem,
          contato: 'marina@ex.com',
          caixa,
        })
      ).toEqual({ para: '', cc: '', cco: '' });
    });
  });

  describe('semCitacaoDosLeitores', () => {
    it('tira o histórico do iPhone (blockquote type=cite)', () => {
      const { html, achou } = semCitacaoDosLeitores(
        '<div>Perfeito, vou ler hoje.</div><div>Enviado do meu iPhone</div><blockquote type="cite">Em 17 de out., Ana escreveu: oi</blockquote>'
      );
      expect(achou).toBe(true);
      expect(html).toContain('Enviado do meu iPhone');
      expect(html).not.toContain('Ana escreveu');
    });

    it('corta do bloco "De:" do Outlook (divRplyFwdMsg) até o fim', () => {
      const { html, achou } = semCitacaoDosLeitores(
        '<div><p>Segue a lista.</p><div id="divRplyFwdMsg"><b>De:</b> Ana</div><p>texto antigo</p></div>'
      );
      expect(achou).toBe(true);
      expect(html).toContain('Segue a lista.');
      expect(html).not.toContain('De:');
      expect(html).not.toContain('texto antigo');
    });

    it('reconhece o fio do Outlook para Windows, em qualquer idioma', () => {
      const { html, achou } = semCitacaoDosLeitores(
        '<p>Bom dia</p><div style="border:none; border-top:solid #E1E1E1 1.0pt; padding:3pt"><b>De:</b> Ana</div><p>antigo</p>'
      );
      expect(achou).toBe(true);
      expect(html).toContain('Bom dia');
      expect(html).not.toContain('antigo');
    });

    it('e-mail sem citação fica igual', () => {
      const { html, achou } = semCitacaoDosLeitores('<p>Oi, tudo bem?</p>');
      expect(achou).toBe(false);
      expect(html).toBe('<p>Oi, tudo bem?</p>');
    });
  });
});
