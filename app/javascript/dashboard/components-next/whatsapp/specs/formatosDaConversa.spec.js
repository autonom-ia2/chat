import formatos from '../../../../../../spec/fixtures/whatsapp_templates/formatos_da_conversa.json';
import { getters } from 'dashboard/store/modules/inboxes';
import { levaProdutos } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/produtosNaCampanha';
import {
  montarEnvio,
  tipoNaConversa,
} from 'dashboard/routes/dashboard/campaigns/modelos/conversa/modeloNaConversa';
import { envioCompleto, validadeFaltando } from '../envioNaConversa';

// #1705: os mesmos exemplos que o lado Ruby lê (spec/services/whatsapp/
// templates/conversation_send_guard_formatos_spec.rb). Mudou a regra de um
// lado só, um dos dois falha. #1716: a conversa do WhatsApp oficial completa
// produto e carrossel; o servidor recusa só o pedido incompleto.
const { agora_ms: agora, casos } = formatos;

const modelosDaCaixa = (inboxId, opcoes) => {
  const state = {
    records: [
      { id: inboxId, message_templates: casos.map(caso => caso.template) },
    ],
  };
  return getters.getConversationWhatsAppTemplates(state, {
    getFilteredWhatsAppTemplates: getters.getFilteredWhatsAppTemplates(state),
  })(inboxId, opcoes);
};

// O que a tela manda: no modelo comum, o preenchedor; com tipo, o pedido que
// `montarEnvio` monta com os produtos e os cartões escolhidos.
const telaLibera = caso => {
  if (!caso.tipo) {
    return envioCompleto(caso.template, caso.processed_params, agora);
  }
  if (!caso.tela) return false;
  const { templateParams } = montarEnvio({
    template: caso.template,
    tipo: caso.tipo,
    ...caso.tela,
  });
  expect(templateParams.processed_params).toEqual(caso.processed_params);
  return true;
};

describe('formatos da conversa (fixture compartilhada com o Ruby)', () => {
  const comAFlag = modelosDaCaixa(7, {
    completa: { fotos: true, produtos: true },
  });
  const semAFlag = modelosDaCaixa(7, {
    completa: { fotos: true, produtos: false },
  });
  const outrasTelas = modelosDaCaixa(7);

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
    const semFlag = caso.conversa_sem_a_flag ?? caso.conversa;

    it(`o seletor da conversa ${caso.conversa ? 'oferece' : 'esconde'}`, () => {
      expect(comAFlag.includes(caso.template)).toBe(caso.conversa);
      expect(tipoNaConversa(caso.template)).toBe(caso.tipo || '');
    });

    it(`sem a flag de produtos, ${semFlag ? 'oferece' : 'esconde'}`, () => {
      expect(semAFlag.includes(caso.template)).toBe(semFlag);
    });

    it('as outras telas (sem completar) oferecem só o modelo comum', () => {
      expect(outrasTelas.includes(caso.template)).toBe(
        caso.conversa && !caso.tipo
      );
    });

    it(`${caso.produtos ? 'leva' : 'não leva'} produtos do catálogo`, () => {
      expect(levaProdutos(caso.template)).toBe(caso.produtos);
    });

    if (caso.conversa) {
      it(`o botão de enviar ${caso.pronto ? 'libera' : 'fica desligado'}`, () => {
        expect(telaLibera(caso)).toBe(caso.pronto);
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
    expect(validadeFaltando('2030-01-01T10:00', undefined)).toBe('SEM_FUSO');
    expect(validadeFaltando('2030-01-01T10:00', 'America/Sao_Paulo')).toBe('');
  });
});
