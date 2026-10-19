// Ações da pele ligadas ao contrato do Híbrido (#1702 com o #1709): enquete no "+" e
// reação pela rota da mensagem. O álbum do WAHA fica no #1831 (albumDoWaha.spec.js).
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import MaisDoWhatsapp from '../mais/MaisDoWhatsapp.vue';
import PreviaDoMais from '../mais/PreviaDoMais.vue';
import {
  montarEnquete,
  textoParaQuemNaoTemFormato,
} from '../mais/montarMensagem';
import { ENQUETE, comoSaiAEnquete } from '../mais/enqueteNoMais';
import { acoesDaConversa, estadoDaReacao } from '../reacaoDoAtendente';

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', missingWarn: false });

describe('montarEnquete (#1702 com o #1709)', () => {
  const campos = extras => ({
    pergunta: ' Qual dia? ',
    opcoes: ['Segunda', ' Terça ', ''],
    variasRespostas: false,
    ...extras,
  });

  it('monta o rich_message poll do contrato, pergunta no content', () => {
    expect(montarEnquete(campos())).toEqual({
      pedido: {
        content: 'Qual dia?',
        richMessage: {
          type: 'poll',
          multiple: false,
          options: [
            { id: 'opcao_1', title: 'Segunda' },
            { id: 'opcao_2', title: 'Terça' },
          ],
        },
      },
    });
    expect(
      montarEnquete(campos({ variasRespostas: true })).pedido.richMessage
        .multiple
    ).toBe(true);
  });

  it('recusa na hora o que o servidor recusaria (limites do motor)', () => {
    const erro = extras => montarEnquete(campos(extras)).erros;
    expect(erro({ pergunta: '  ' })).toEqual({ pergunta: 'pergunta' });
    expect(erro({ pergunta: 'x'.repeat(256) })).toEqual({
      pergunta: 'perguntaLonga',
    });
    expect(erro({ opcoes: ['Só uma'] })).toEqual({ opcoes: 'opcoes' });
    expect(
      erro({ opcoes: Array.from({ length: 13 }, (_, i) => `O${i}`) })
    ).toEqual({ opcoes: 'opcoesDaEnqueteDemais' });
    expect(erro({ opcoes: ['a', 'b'.repeat(101)] })).toEqual({
      opcoes: 'opcaoDaEnqueteLonga',
    });
    expect(erro({ opcoes: ['Sim', ' Sim'] })).toEqual({
      opcoes: 'opcoesRepetidas',
    });
  });

  it('em texto: a pergunta e as opções numeradas (Poll#fallback_text)', () => {
    const { pedido } = montarEnquete(campos());
    expect(textoParaQuemNaoTemFormato(pedido)).toBe(
      'Qual dia?\n\n1. Segunda\n2. Terça'
    );
  });
});

describe('comoSaiAEnquete', () => {
  it('sem a flag não há enquete', () => {
    expect(
      comoSaiAEnquete({
        flagLigada: false,
        conversa: { whatsapp_api_rich_native: ['poll'] },
      })
    ).toBeNull();
  });

  it('nativa quando a conversa lista poll (snake ou camel); senão, texto', () => {
    expect(
      comoSaiAEnquete({
        flagLigada: true,
        conversa: { whatsapp_api_rich_native: ['poll'] },
      })
    ).toBe(ENQUETE.NATIVA);
    expect(
      comoSaiAEnquete({
        flagLigada: true,
        conversa: { whatsappApiRichNative: ['location', 'poll'] },
      })
    ).toBe(ENQUETE.NATIVA);
    expect(comoSaiAEnquete({ flagLigada: true, conversa: {} })).toBe(
      ENQUETE.TEXTO
    );
  });
});

describe('MaisDoWhatsapp: item Enquete', () => {
  const CLOUD = {
    id: 1,
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  };
  const montar = ({ flag, conversa = {} }) => {
    const store = createStore({
      getters: {
        getSelectedChat: () => conversa,
        getCurrentAccountId: () => 3,
        'accounts/isFeatureEnabledonAccount': () => (conta, nome) =>
          flag && conta === 3 && nome === 'whatsapp_rich_native',
      },
    });
    return mount(MaisDoWhatsapp, {
      props: { caixa: CLOUD, enviar: vi.fn() },
      global: {
        plugins: [store, i18n()],
        stubs: { JanelaDoMais: true, Icon: true },
      },
    });
  };
  const abrir = async wrapper => {
    await wrapper.find('[data-mais-do-whatsapp]').trigger('click');
    return wrapper;
  };

  it('sem a flag o item não aparece', async () => {
    const wrapper = await abrir(montar({ flag: false }));
    expect(wrapper.find('[data-item="enquete"]').exists()).toBe(false);
  });

  it('com a flag na Cloud aparece e a janela sabe que vai em texto', async () => {
    const wrapper = await abrir(montar({ flag: true }));
    expect(wrapper.find('[data-item="enquete"]').exists()).toBe(true);
    expect(
      wrapper.findComponent({ name: 'JanelaDoMais' }).props('enqueteEmTexto')
    ).toBe(true);
  });

  it('com poll nos tipos nativos da conversa, a janela não promete texto', async () => {
    const wrapper = await abrir(
      montar({ flag: true, conversa: { whatsapp_api_rich_native: ['poll'] } })
    );
    expect(
      wrapper.findComponent({ name: 'JanelaDoMais' }).props('enqueteEmTexto')
    ).toBe(false);
  });
});

describe('PreviaDoMais: enquete', () => {
  const campos = {
    pergunta: 'Qual dia?',
    opcoes: ['Segunda', 'Terça'],
    variasRespostas: false,
  };
  const montar = viraTexto =>
    mount(PreviaDoMais, {
      props: { tipo: 'enquete', campos, viraTexto },
      global: { plugins: [i18n()], stubs: { Icon: true } },
    });

  it('nativa: pergunta e opções para votar', () => {
    const wrapper = montar(false);
    const previa = wrapper.find('[data-previa-enquete]');
    expect(previa.text()).toContain('Qual dia?');
    expect(previa.findAll('li').map(li => li.text())).toEqual([
      'Segunda',
      'Terça',
    ]);
  });

  it('em texto: avisa e mostra a versão numerada', () => {
    const wrapper = montar(true);
    expect(wrapper.find('[data-previa-enquete]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'CONVERSA_CANAL.PREVIA.ENQUETE_VIRA_TEXTO'
    );
    expect(wrapper.text()).toContain('1. Segunda');
    expect(wrapper.text()).toContain('2. Terça');
  });
});

describe('estadoDaReacao com as ações do motor (#1709)', () => {
  const WAHA = { channel_type: 'Channel::Api', waha_provider: 'waha' };
  const conversa = { whatsapp_api_message_actions: ['react', 'edit'] };
  const mensagem = extras => ({
    messageType: 0,
    isPrivate: false,
    status: 'sent',
    sourceId: null,
    contentAttributes: {},
    ...extras,
  });

  it('lê as ações em snake ou camel', () => {
    expect(acoesDaConversa(conversa)).toEqual(['react', 'edit']);
    expect(acoesDaConversa({ whatsappApiMessageActions: ['react'] })).toEqual([
      'react',
    ]);
    expect(acoesDaConversa({})).toEqual([]);
  });

  it('com react: reage sem sourceId, recebida ou enviada, pela caixa', () => {
    expect(
      estadoDaReacao({ caixa: WAHA, conversa, mensagem: mensagem() })
    ).toEqual({ visivel: true, bloqueado: false, pelaCaixa: true });
    expect(
      estadoDaReacao({
        caixa: WAHA,
        conversa,
        mensagem: mensagem({ messageType: 1 }),
      }).visivel
    ).toBe(true);
  });

  it('com react: falhada, com erro, nota, apagada e aviso de visualização única não reagem', () => {
    const casos = [
      mensagem({ status: 'failed' }),
      mensagem({ contentAttributes: { externalError: 'x' } }),
      mensagem({ isPrivate: true }),
      mensagem({ deleted: true }),
      mensagem({ contentAttributes: { viewOnceUnavailable: true } }),
      mensagem({ messageType: 2 }),
    ];
    casos.forEach(caso =>
      expect(
        estadoDaReacao({ caixa: WAHA, conversa, mensagem: caso }).visivel
      ).toBe(false)
    );
  });

  it('sem react nas ações: a regra de antes (WAHA exige sourceId)', () => {
    const estado = estadoDaReacao({
      caixa: WAHA,
      conversa: {},
      mensagem: mensagem(),
    });
    expect(estado.visivel).toBe(false);
    expect(
      estadoDaReacao({
        caixa: WAHA,
        conversa: {},
        mensagem: mensagem({ sourceId: 'true_x@c.us_1' }),
      }).pelaCaixa
    ).toBeUndefined();
  });
});
