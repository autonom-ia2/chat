import formatos from '../../../../../../spec/fixtures/whatsapp_templates/formatos_da_conversa.json';
import { getters } from 'dashboard/store/modules/inboxes';
import { levaProdutos } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/produtosNaCampanha';
import { envioCompleto } from '../envioNaConversa';

// #1705: os mesmos exemplos que o lado Ruby lê
// (spec/services/whatsapp/templates/formatos_da_conversa_spec.rb). Mudou a
// regra de um lado só, um dos dois falha.
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
