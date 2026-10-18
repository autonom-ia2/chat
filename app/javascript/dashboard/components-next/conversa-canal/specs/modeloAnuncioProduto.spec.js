/* eslint-disable vue/one-component-per-file */
// Frente "modelo, anúncio e produto" (#1702): o balão do modelo com topo, rodapé,
// "Ver todas as opções" e a mídia do carrossel, lidos da foto do envio (#1717); e, no
// balão do cliente, a citação do anúncio e do produto do catálogo.
import { computed, defineComponent, h, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import {
  CONTENT_TYPES,
  MESSAGE_TYPES,
  MESSAGE_VARIANTS,
} from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import Message from '../../message/Message.vue';
import BotoesDoModelo from '../BotoesDoModelo.vue';
import OrigemDaMensagem from '../OrigemDaMensagem.vue';
import { PELES, fornecerFuso, fornecerPele } from '../pele';

// A tela recebe a mensagem da API em snake_case e a lista (MessageList) a converte
// inteira para camelCase antes de chegar ao balão: os specs passam pelo mesmo caminho.
const comoNaLista = mensagemDaApi =>
  useCamelCase(mensagemDaApi, { deep: true });

const BOTOES = n =>
  Array.from({ length: n }, (_, i) =>
    i === 0
      ? { type: 'URL', text: 'Site', url: 'https://loja.test/' }
      : { type: 'QUICK_REPLY', text: `Opção ${i}` }
  );
const MODELOS = [
  {
    name: 'completo',
    language: 'pt_BR',
    components: [
      { type: 'HEADER', format: 'TEXT', text: 'Oi, {{1}}!' },
      { type: 'BODY', text: 'Corpo' },
      { type: 'FOOTER', text: 'Rodapé do modelo de hoje' },
      { type: 'BUTTONS', buttons: BOTOES(5) },
    ],
  },
  {
    name: 'fixo',
    language: 'pt_BR',
    components: [
      { type: 'HEADER', format: 'TEXT', text: 'Novidade' },
      { type: 'FOOTER', text: 'Responda SAIR' },
      { type: 'BUTTONS', buttons: BOTOES(3) },
    ],
  },
  {
    name: 'foto',
    language: 'pt_BR',
    components: [{ type: 'HEADER', format: 'IMAGE' }],
  },
  {
    name: 'vitrine',
    language: 'pt_BR',
    components: [
      {
        type: 'CAROUSEL',
        cards: [
          {
            components: [
              { type: 'HEADER', format: 'IMAGE' },
              { type: 'BODY', text: 'Tênis {{1}}' },
            ],
          },
          {
            components: [
              { type: 'HEADER', format: 'VIDEO' },
              { type: 'BODY', text: 'Meia' },
            ],
          },
        ],
      },
    ],
  },
];

const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    messages: { en },
    missingWarn: false,
    fallbackWarn: false,
  });

const montar = ({
  nome = 'completo',
  enviado,
  parte = 'topo',
  pele = PELES.WHATSAPP,
  fuso = 'America/Sao_Paulo',
  painel = true,
} = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        fornecerFuso(computed(() => fuso));
        const mensagem = comoNaLista({
          inbox_id: 1,
          status: 'sent',
          additional_attributes: {
            template_params: { name: nome, language: 'pt_BR', enviado },
          },
        });
        provideMessageContext({
          inboxId: ref(mensagem.inboxId),
          status: ref(mensagem.status),
          additionalAttributes: ref(mensagem.additionalAttributes),
        });
        return () =>
          h('div', { class: painel ? 'conversation-panel' : '' }, [
            h(BotoesDoModelo, { parte }),
          ]);
      },
    }),
    {
      attachTo: document.body,
      global: {
        plugins: [
          createStore({
            getters: {
              'inboxes/getInbox': () => () => ({ message_templates: MODELOS }),
            },
          }),
          i18n(),
        ],
      },
    }
  );

describe('topo e rodapé do modelo (#1702)', () => {
  it('topo de texto da foto do envio, em negrito, com os valores', () => {
    const topo = montar({
      enviado: { versao: 1, topo: { tipo: 'text', texto: 'Oi, Ana!' } },
    });

    expect(topo.find('[data-topo-texto]').text()).toBe('Oi, Ana!');
    expect(topo.find('[data-topo-texto]').classes()).toContain('font-semibold');
  });

  it('sem a foto do envio, o topo do modelo de hoje só quando não sobra campo', () => {
    expect(montar({ nome: 'fixo' }).find('[data-topo-texto]').text()).toBe(
      'Novidade'
    );
    expect(
      montar({ nome: 'completo' }).find('[data-topo-texto]').exists()
    ).toBe(false);
  });

  it('foto da foto do envio vira imagem; sem endereço, o ícone do tipo', () => {
    const comFoto = montar({
      nome: 'foto',
      enviado: {
        versao: 1,
        topo: { tipo: 'image', url: 'https://app.test/blob/topo.png' },
      },
    });
    expect(comFoto.find('img[data-topo-midia="image"]').attributes('src')).toBe(
      'https://app.test/blob/topo.png'
    );

    const semFoto = montar({ nome: 'foto' });
    expect(semFoto.find('img').exists()).toBe(false);
    expect(semFoto.find('[data-topo-midia="image"]').attributes('role')).toBe(
      'img'
    );
  });

  it('documento: o nome do arquivo, como link quando o arquivo é nosso', () => {
    const topo = montar({
      enviado: {
        versao: 1,
        topo: {
          tipo: 'document',
          url: 'https://app.test/blob/proposta.pdf',
          nome: 'proposta.pdf',
        },
      },
    });

    const documento = topo.find('a[data-topo-midia="document"]');
    expect(documento.attributes('href')).toBe(
      'https://app.test/blob/proposta.pdf'
    );
    expect(documento.attributes('target')).toBe('_blank');
    expect(documento.text()).toContain('proposta.pdf');
  });

  it('endereço que não é http(s) não vira mídia', () => {
    const topo = montar({
      nome: 'foto',
      enviado: { versao: 1, topo: { tipo: 'image', url: 'data:text/html,oi' } },
    });

    expect(topo.find('img').exists()).toBe(false);
  });

  it('rodapé: o da foto do envio e, sem ele, o do modelo de hoje', () => {
    const doEnvio = montar({
      parte: 'rodape',
      enviado: { versao: 1, rodape: 'Responda PARAR' },
    });
    expect(doEnvio.find('[data-rodape-do-modelo]').text()).toBe(
      'Responda PARAR'
    );

    const doModelo = montar({ parte: 'rodape', enviado: { versao: 1 } });
    expect(doModelo.find('[data-rodape-do-modelo]').text()).toBe(
      'Rodapé do modelo de hoje'
    );
  });

  it('foto do envio sem topo (envios de 16/10): o topo do modelo de hoje', () => {
    const topo = montar({ nome: 'fixo', enviado: { versao: 1, rodape: 'x' } });

    expect(topo.find('[data-topo-texto]').text()).toBe('Novidade');
  });

  it('sem a pele, nem topo nem rodapé', () => {
    const enviado = {
      versao: 1,
      topo: { tipo: 'text', texto: 'Oi' },
      rodape: 'x',
    };
    expect(montar({ pele: null, enviado }).html()).not.toContain('Oi');
    expect(
      montar({ pele: null, parte: 'rodape', enviado })
        .find('[data-rodape-do-modelo]')
        .exists()
    ).toBe(false);
  });

  it('produto do topo (SPM) com o nome, o preço e a foto do envio', () => {
    const topo = montar({
      enviado: {
        versao: 1,
        produto: {
          retailer_id: 'SKU1',
          nome: 'Tênis Run',
          preco: 'R$ 199,90',
          foto_url: 'https://cdn.loja.test/tenis.jpg',
        },
      },
    });

    const produto = topo.find('[data-produto-do-modelo]');
    expect(produto.text()).toContain('Tênis Run');
    expect(produto.text()).toContain('R$ 199,90');
    expect(produto.find('img').attributes('src')).toBe(
      'https://cdn.loja.test/tenis.jpg'
    );
  });

  it('oferta com a validade no fuso da conta; sem fuso, sem a data', () => {
    const enviado = {
      versao: 1,
      oferta: { texto: 'Só hoje!', expira_em: 1760961600 },
    };
    const comFuso = montar({ enviado });
    expect(comFuso.find('[data-oferta-do-modelo]').text()).toContain(
      'Só hoje!'
    );
    expect(comFuso.find('[data-oferta-do-modelo]').text()).toContain('Ends ');
    expect(comFuso.find('[data-oferta-do-modelo]').text()).toContain('9:00 AM');

    const semFuso = montar({ enviado, fuso: null });
    expect(semFuso.find('[data-oferta-do-modelo]').text()).not.toContain(
      'Ends '
    );
  });
});

describe('mais de 3 botões (#1702)', () => {
  it('mostra os 2 primeiros e "Ver todas as opções"', () => {
    const botoes = montar({ parte: 'botoes' });

    expect(botoes.findAll('[data-tipo-do-botao]')).toHaveLength(2);
    expect(botoes.find('[data-ver-todas-as-opcoes]').text()).toBe(
      en.CONVERSA_CANAL.MODELO.VER_TODAS
    );
  });

  it('com 3 botões, os 3 e sem "Ver todas as opções"', () => {
    const botoes = montar({ nome: 'fixo', parte: 'botoes' });

    expect(botoes.findAll('[data-tipo-do-botao]')).toHaveLength(3);
    expect(botoes.find('[data-ver-todas-as-opcoes]').exists()).toBe(false);
  });

  it('a janela lista todos; o link abre o endereço e a resposta rápida só mostra', async () => {
    const botoes = montar({
      parte: 'botoes',
      enviado: {
        versao: 1,
        botoes: [{ tipo: 'url', texto: 'Site', url: 'https://loja.test/' }],
      },
    });

    await botoes.find('[data-ver-todas-as-opcoes]').trigger('click');
    await nextTick();
    const janela = document.querySelector('[data-janela-das-opcoes]');

    expect(janela.getAttribute('role')).toBe('dialog');
    expect(janela.querySelectorAll('[data-tipo-do-botao]')).toHaveLength(5);
    expect(janela.querySelector('a').getAttribute('href')).toBe(
      'https://loja.test/'
    );
    expect(
      janela.querySelectorAll('div[data-tipo-do-botao="QUICK_REPLY"]')
    ).toHaveLength(4);
    expect(document.activeElement.getAttribute('aria-label')).toBe(
      en.CONVERSA_CANAL.MODELO.FECHAR
    );

    janela.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await nextTick();
    expect(document.querySelector('[data-janela-das-opcoes]')).toBeNull();
    botoes.unmount();
  });

  it('fora da conversa (sem .conversation-panel), a janela abre embaixo do botão', async () => {
    const botoes = montar({ parte: 'botoes', painel: false });

    await botoes.find('[data-ver-todas-as-opcoes]').trigger('click');
    await nextTick();

    const janela = botoes.find('[data-janela-das-opcoes]');
    expect(janela.exists()).toBe(true);
    expect(janela.findAll('[data-tipo-do-botao]')).toHaveLength(5);
    expect(janela.classes()).not.toContain('absolute');
    expect(botoes.find('[data-fundo-das-opcoes]').exists()).toBe(false);
    expect(
      botoes.find('[data-ver-todas-as-opcoes]').attributes('aria-expanded')
    ).toBe('true');

    await janela.trigger('keydown', { key: 'Escape' });
    expect(botoes.find('[data-janela-das-opcoes]').exists()).toBe(false);
    botoes.unmount();
  });

  it('modelo apagado na Meta: os botões saem da própria foto do envio', () => {
    const botoes = montar({
      nome: 'apagado',
      parte: 'botoes',
      enviado: {
        versao: 1,
        botoes: [
          { tipo: 'url', texto: 'Ver', url: 'https://loja.test/x' },
          { tipo: 'copy_code' },
        ],
      },
    });

    expect(botoes.find('a').attributes('href')).toBe('https://loja.test/x');
    expect(botoes.text()).toContain(en.CONVERSA_CANAL.MODELO.COPIAR_CODIGO);
  });
});

describe('carrossel com a mídia de cada cartão (#1702)', () => {
  it('foto e vídeo da foto do envio; texto com os valores', () => {
    const carrossel = montar({
      nome: 'vitrine',
      parte: 'carrossel',
      enviado: {
        versao: 1,
        cartoes: [
          {
            midia: { tipo: 'image', url: 'https://app.test/blob/tenis.png' },
            texto: 'Tênis Run',
          },
          { midia: { tipo: 'video', url: 'https://app.test/blob/meia.mp4' } },
        ],
      },
    });

    expect(
      carrossel.find('img[data-midia-do-cartao="image"]').attributes('src')
    ).toBe('https://app.test/blob/tenis.png');
    expect(
      carrossel.find('video[data-midia-do-cartao="video"]').attributes('src')
    ).toBe('https://app.test/blob/meia.mp4');
    expect(carrossel.text()).toContain('Tênis Run');
    expect(carrossel.text()).toContain('Meia');
  });

  it('sem endereço (mensagem anterior à foto), o ícone e nunca o campo {{1}}', () => {
    const carrossel = montar({ nome: 'vitrine', parte: 'carrossel' });

    expect(carrossel.find('img').exists()).toBe(false);
    expect(carrossel.text()).not.toContain('{{1}}');
  });
});

const montarOrigem = (contentAttributes, variant = MESSAGE_VARIANTS.USER) =>
  mount(
    defineComponent({
      setup() {
        provideMessageContext({
          variant: ref(variant),
          contentAttributes: ref(
            comoNaLista({ content_attributes: contentAttributes })
              .contentAttributes
          ),
        });
        return () => h(OrigemDaMensagem);
      },
    }),
    { global: { plugins: [i18n()] } }
  );

describe('citação do anúncio e do produto no balão do cliente (#1702)', () => {
  it('anúncio: título, miniatura e o toque abre o anúncio em outra aba', () => {
    const origem = montarOrigem({
      referral: {
        source_url: 'https://fb.me/anuncio',
        headline: 'Promoção de verão',
        body: 'Só esta semana',
        thumbnail_url: 'https://cdn.test/thumb.jpg',
        media_type: 'video',
      },
    });

    const citacao = origem.find('a[data-citacao-do-anuncio]');
    expect(citacao.attributes('href')).toBe('https://fb.me/anuncio');
    expect(citacao.attributes('target')).toBe('_blank');
    expect(citacao.text()).toContain(en.CONVERSA_CANAL.ORIGEM.ANUNCIO);
    expect(citacao.text()).toContain('Promoção de verão');
    expect(citacao.find('img').attributes('src')).toBe(
      'https://cdn.test/thumb.jpg'
    );
  });

  it('anúncio com endereço que não é http(s): citação sem link', () => {
    const origem = montarOrigem({
      referral: { source_url: 'data:text/html,oi', headline: 'X' },
    });

    expect(origem.find('a').exists()).toBe(false);
    expect(origem.find('[data-citacao-do-anuncio]').text()).toContain('X');
  });

  it('produto do catálogo com nome, preço e foto', () => {
    const origem = montarOrigem({
      referred_product: {
        catalog_id: 'cat-1',
        product_retailer_id: 'SKU1',
        nome: 'Tênis Run',
        preco: 'R$ 199,90',
        foto_url: 'https://cdn.loja.test/tenis.jpg',
      },
    });

    const citacao = origem.find('[data-citacao-do-produto]');
    expect(citacao.text()).toContain(en.CONVERSA_CANAL.ORIGEM.PRODUTO);
    expect(citacao.text()).toContain('Tênis Run');
    expect(citacao.text()).toContain('R$ 199,90');
    expect(citacao.find('img').attributes('src')).toBe(
      'https://cdn.loja.test/tenis.jpg'
    );
  });

  it('produto sem o catálogo: "Produto do catálogo" com o código', () => {
    const origem = montarOrigem({
      referred_product: { catalog_id: 'cat-1', product_retailer_id: 'SKU9' },
    });

    expect(origem.find('[data-citacao-do-produto]').text()).toContain(
      'Code SKU9'
    );
  });

  it('mensagem da empresa não leva a citação', () => {
    const origem = montarOrigem(
      { referral: { headline: 'X' } },
      MESSAGE_VARIANTS.AGENT
    );

    expect(origem.html()).not.toContain('data-citacao');
  });
});

const ANUNCIO = {
  referral: { headline: 'Promoção de verão', sourceUrl: 'https://fb.me/x' },
};
const montarRecebida = pele =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        return () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.INCOMING,
            status: 'sent',
            content: 'Quero saber mais',
            conversationId: 7,
            createdAt: AGORA,
            currentUserId: 1,
            sender: { id: 9, name: 'Ana', type: 'contact' },
            contentAttributes: ANUNCIO,
          });
      },
    }),
    { global: montagem }
  );

describe('anúncio na mensagem inteira (#1702)', () => {
  it('com a pele: citação dentro do balão, sem o cartão de fora nem a coluna', () => {
    const mensagem = montarRecebida(PELES.WHATSAPP);

    expect(mensagem.find('[data-testid="whatsapp-referral"]').exists()).toBe(
      false
    );
    expect(mensagem.find('[data-citacao-do-anuncio]').exists()).toBe(true);
    expect(mensagem.find('.group\\/linha').classes()).not.toContain('flex-col');
  });

  it('sem a pele: o cartão de sempre, fora do balão', () => {
    const mensagem = montarRecebida(null);

    expect(mensagem.find('[data-testid="whatsapp-referral"]').exists()).toBe(
      true
    );
    expect(mensagem.find('[data-citacao-do-anuncio]').exists()).toBe(false);
  });
});

describe('anúncio em balão que não desenha a citação (#1702)', () => {
  const ligacaoComAnuncio = pele =>
    mount(
      defineComponent({
        setup() {
          fornecerPele(computed(() => pele));
          return () =>
            h(Message, {
              id: 2,
              messageType: MESSAGE_TYPES.INCOMING,
              status: 'sent',
              content: 'WhatsApp call',
              contentType: CONTENT_TYPES.VOICE_CALL,
              call: { status: 'completed', direction: 'inbound' },
              conversationId: 7,
              createdAt: AGORA,
              currentUserId: 1,
              sender: { id: 9, name: 'Ana', type: 'contact' },
              contentAttributes: ANUNCIO,
            });
        },
      }),
      { global: montagem }
    );

  it('com a pele, o cartão da ligação fica e o anúncio segue no cartão de fora', () => {
    const mensagem = ligacaoComAnuncio(PELES.WHATSAPP);

    expect(mensagem.find('[data-ligacao-do-whatsapp]').exists()).toBe(true);
    expect(mensagem.find('[data-testid="whatsapp-referral"]').exists()).toBe(
      true
    );
  });
});
