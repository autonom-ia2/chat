import formatos from '../../../../../../spec/fixtures/whatsapp_templates/formatos_da_conversa.json';
import { getters } from 'dashboard/store/modules/inboxes';
import { levaProdutos } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/produtosNaCampanha';
import { envioCompleto, validadeFaltando } from '../envioNaConversa';

// #1705: os mesmos exemplos que o lado Ruby lê (spec/services/whatsapp/
// templates/conversation_send_guard_formatos_spec.rb). Mudou a regra de um
// lado só, um dos dois falha.
const { agora_ms: agora, casos } = formatos;

const modelosDaCaixa = inboxId => {
  const state = {
    records: [
      { id: inboxId, message_templates: casos.map(caso => caso.template) },
    ],
  };
  return getters.getConversationWhatsAppTemplates(state, {
    getFilteredWhatsAppTemplates: getters.getFilteredWhatsAppTemplates(state),
  })(inboxId);
};

describe('formatos da conversa (fixture compartilhada com o Ruby)', () => {
  const oferecidos = modelosDaCaixa(7);

  it('a conversa só oferece o modelo cujo envio sai (pronto <=> o servidor envia)', () => {
    casos
      .filter(caso => caso.conversa)
      .forEach(caso => {
        expect([caso.nome, caso.pronto]).toEqual([
          caso.nome,
          caso.envio === null,
        ]);
      });
  });

  describe.each(casos.map(caso => [caso.nome, caso]))('%s', (_nome, caso) => {
    it(`o seletor da conversa ${caso.conversa ? 'oferece' : 'esconde'}`, () => {
      expect(oferecidos.includes(caso.template)).toBe(caso.conversa);
    });

    it(`${caso.produtos ? 'leva' : 'não leva'} produtos do catálogo`, () => {
      expect(levaProdutos(caso.template)).toBe(caso.produtos);
    });

    if (caso.conversa) {
      it(`o botão de enviar ${caso.pronto ? 'libera' : 'fica desligado'}`, () => {
        expect(envioCompleto(caso.template, caso.processed_params, agora)).toBe(
          caso.pronto
        );
      });
    }
  });
});

describe('envioNaConversa (#1705, revisão)', () => {
  const linkComCampo = {
    name: 'rastreio',
    language: 'pt_BR',
    components: [
      { type: 'BODY', text: 'Seu pedido saiu.' },
      {
        type: 'BUTTONS',
        buttons: [
          { type: 'URL', text: 'Rastrear', url: 'https://x.com/{{1}}' },
        ],
      },
    ],
  };

  it('botão com fim de endereço variável só libera preenchido, mesmo sem campo no texto', () => {
    const vazio = { buttons: [{ type: 'url', parameter: ' ' }] };
    const cheio = { buttons: [{ type: 'url', parameter: 'AB12' }] };

    expect(envioCompleto(linkComCampo, vazio)).toBe(false);
    expect(envioCompleto(linkComCampo, cheio)).toBe(true);
  });

  it('sem o fuso da conta a validade fica faltando (nunca o do navegador)', () => {
    expect(validadeFaltando('2030-01-01T10:00', undefined)).toBe('VALIDADE');
    expect(validadeFaltando('2030-01-01T10:00', 'America/Sao_Paulo')).toBe('');
  });
});
