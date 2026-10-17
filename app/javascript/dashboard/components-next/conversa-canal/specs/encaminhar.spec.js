import { nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import { useAlert } from 'dashboard/composables';
import BarraDeEncaminhar from '../encaminhar/BarraDeEncaminhar.vue';
import JanelaDeEncaminhar from '../encaminhar/JanelaDeEncaminhar.vue';
import EncaminharDaConversa from '../encaminhar/EncaminharDaConversa.vue';
import MarcaDeEncaminhar from '../encaminhar/MarcaDeEncaminhar.vue';
import {
  LIMITE_DE_MENSAGENS,
  alternarMensagem,
  comecarSelecao,
  encaminhamentoDireto,
  encaminhavel,
  estaMarcada,
  fecharJanela,
  sairDaSelecao,
  selecao,
  temBotaoAoLado,
} from '../encaminhar/selecaoParaEncaminhar';
import { resumoDoEnvio } from '../encaminhar/resultadoDoEncaminhar';
import en from '../../../i18n/locale/en/conversaCanal.json';

vi.mock('dashboard/api/conversaCanal', () => ({
  default: { destinosParaEncaminhar: vi.fn(), encaminhar: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } });
const global = {
  plugins: [i18n],
  stubs: { Icon: true, Avatar: true, Teleport: true },
  directives: { tooltip: {} },
};

const mensagem = (extras = {}) => ({
  id: 1,
  conversationId: 9,
  messageType: 0,
  contentType: 'text',
  status: 'sent',
  private: false,
  content: 'Oi',
  contentAttributes: {},
  attachments: [],
  ...extras,
});

const conversas = [
  { id: 11, nome: 'Ana Souza', ultima_linha: 'Bom dia', caixa: 'WhatsApp' },
  { id: 12, nome: 'Bruno Lima', ultima_linha: null, caixa: 'WhatsApp' },
  { id: 13, nome: 'Carla', ultima_linha: 'ok', caixa: 'WhatsApp' },
  { id: 14, nome: 'Davi', ultima_linha: 'ok', caixa: 'WhatsApp' },
  { id: 15, nome: 'Eva', ultima_linha: 'ok', caixa: 'WhatsApp' },
  { id: 16, nome: 'Fábio', ultima_linha: 'ok', caixa: 'WhatsApp' },
];

afterEach(() => {
  sairDaSelecao();
  vi.clearAllMocks();
});

describe('o que se encaminha (a mesma regra do servidor)', () => {
  it('texto do cliente e da empresa sim', () => {
    expect(encaminhavel(mensagem())).toBe(true);
    expect(encaminhavel(mensagem({ messageType: 1 }))).toBe(true);
  });

  it.each([
    ['nota privada', { private: true }],
    ['atividade', { messageType: 2 }],
    ['apagada', { contentAttributes: { deleted: true } }],
    [
      'apagada pelo cliente',
      { contentAttributes: { deletedByContactAt: '2026-10-16T18:00:00Z' } },
    ],
    ['não suportada', { contentAttributes: { isUnsupported: true } }],
    ['com falha', { status: 'failed' }],
    ['formulário', { contentType: 'form' }],
    [
      'visualização única',
      { attachments: [{ fileType: 'image', isViewOnce: true }] },
    ],
  ])('%s não', (_nome, extras) => {
    expect(encaminhavel(mensagem(extras))).toBe(false);
  });

  it('botão ao lado só em mídia (foto, vídeo, documento, localização, contato)', () => {
    expect(temBotaoAoLado(mensagem())).toBe(false);
    expect(
      temBotaoAoLado(mensagem({ attachments: [{ fileType: 'image' }] }))
    ).toBe(true);
    expect(
      temBotaoAoLado(mensagem({ attachments: [{ fileType: 'audio' }] }))
    ).toBe(false);
    expect(
      temBotaoAoLado(
        mensagem({ contentAttributes: { richMessage: { type: 'location' } } })
      )
    ).toBe(true);
  });
});

describe('seleção', () => {
  it('menu começa com a mensagem marcada; marcar e desmarcar várias', () => {
    comecarSelecao(9, [1]);
    expect(selecao.ativa).toBe(true);
    alternarMensagem([2, 3]);
    expect(estaMarcada([2, 3])).toBe(true);
    alternarMensagem([1]);
    expect(selecao.ids).toEqual([2, 3]);
  });

  it(`não passa de ${LIMITE_DE_MENSAGENS} mensagens`, () => {
    comecarSelecao(9, [...Array(LIMITE_DE_MENSAGENS).keys()]);
    expect(alternarMensagem([999])).toBe(false);
    expect(selecao.ids).toHaveLength(LIMITE_DE_MENSAGENS);
  });

  it('botão ao lado abre a janela direto; fechar limpa', () => {
    encaminhamentoDireto(9, [4]);
    expect(selecao.janelaAberta).toBe(true);
    expect(selecao.ativa).toBe(false);
    fecharJanela();
    expect(selecao.ids).toEqual([]);
  });

  it('a caixinha da linha é um checkbox acessível', async () => {
    const wrapper = mount(MarcaDeEncaminhar, {
      props: { marcada: true },
      global,
    });
    const botao = wrapper.find('[role=checkbox]');
    expect(botao.attributes('aria-checked')).toBe('true');
    expect(botao.attributes('aria-label')).toBe(
      en.CONVERSA_CANAL.ENCAMINHAR.MARCAR
    );
    await botao.trigger('click');
    expect(wrapper.emitted('alternar')).toHaveLength(1);
  });
});

describe('BarraDeEncaminhar', () => {
  it('mostra a contagem, sai pelo ✕ e encaminha pela seta', async () => {
    const wrapper = mount(BarraDeEncaminhar, {
      props: { quantidade: 2 },
      global,
    });
    expect(wrapper.text()).toContain('2 selected');
    const [sair, seta] = wrapper.findAll('button');
    await sair.trigger('click');
    await seta.trigger('click');
    expect(wrapper.emitted('sair')).toHaveLength(1);
    expect(wrapper.emitted('encaminhar')).toHaveLength(1);
  });

  it('sem mensagem marcada a seta fica desligada', () => {
    const wrapper = mount(BarraDeEncaminhar, {
      props: { quantidade: 0 },
      global,
    });
    expect(
      wrapper.find('[data-encaminhar-selecionadas]').attributes('disabled')
    ).toBeDefined();
  });
});

describe('JanelaDeEncaminhar', () => {
  const montar = () =>
    mount(JanelaDeEncaminhar, {
      props: { conversationId: 9, messageIds: [1, 2] },
      attachTo: document.body,
      global,
    });

  beforeEach(() => {
    ConversaCanalAPI.destinosParaEncaminhar.mockResolvedValue({
      data: { payload: conversas },
    });
  });

  it('lista as conversas recentes com nome e última linha', async () => {
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(en.CONVERSA_CANAL.ENCAMINHAR.TITULO);
    expect(wrapper.text()).toContain(en.CONVERSA_CANAL.ENCAMINHAR.RECENTES);
    const linhas = wrapper.findAll('[data-destino]');
    expect(linhas).toHaveLength(6);
    expect(linhas[0].text()).toContain('Ana Souza');
    expect(linhas[0].text()).toContain('Bom dia');
    expect(linhas[1].text()).toContain('WhatsApp');
    wrapper.unmount();
  });

  it('marcar mostra o rodapé com os nomes; o 6º destino é recusado', async () => {
    const wrapper = montar();
    await flushPromises();
    const linhas = wrapper.findAll('[data-destino]');
    expect(wrapper.find('[data-rodape-de-encaminhar]').exists()).toBe(false);

    await linhas[0].trigger('click');
    await linhas[1].trigger('click');
    expect(wrapper.find('[data-rodape-de-encaminhar]').text()).toContain(
      'Ana Souza, Bruno Lima'
    );
    const marcadas = () =>
      wrapper
        .findAll('[data-destino]')
        .map(linha => linha.attributes('aria-checked'));
    expect(marcadas()[0]).toBe('true');

    await Promise.all(linhas.slice(2).map(linha => linha.trigger('click')));
    expect(marcadas()).toEqual([
      'true',
      'true',
      'true',
      'true',
      'true',
      'false',
    ]);
    expect(useAlert).toHaveBeenCalled();
    wrapper.unmount();
  });

  it('enviar manda as mensagens e os destinos e avisa a falha por destino', async () => {
    ConversaCanalAPI.encaminhar.mockResolvedValue({
      data: {
        payload: [
          { conversation_id: 11, ok: true, erro: null },
          { conversation_id: 12, ok: false, erro: 'Fora da janela' },
        ],
      },
    });
    const wrapper = montar();
    await flushPromises();
    const linhas = wrapper.findAll('[data-destino]');
    await linhas[0].trigger('click');
    await linhas[1].trigger('click');
    await wrapper.find('[data-enviar-encaminhamento]').trigger('click');
    await flushPromises();

    expect(ConversaCanalAPI.encaminhar).toHaveBeenCalledWith(
      9,
      [1, 2],
      [11, 12]
    );
    expect(useAlert.mock.calls.at(-1)[0]).toContain(
      'Bruno Lima: Fora da janela'
    );
    expect(wrapper.emitted('enviado')).toHaveLength(1);
    wrapper.unmount();
  });

  it('Tab dá a volta dentro da janela e, ao fechar, o foco volta', async () => {
    const abridor = document.createElement('button');
    document.body.appendChild(abridor);
    abridor.focus();
    const wrapper = montar();
    await flushPromises();
    const janela = wrapper.find('[role=dialog]');
    const fechar = janela.find('button');
    const ultimo = wrapper.findAll('[data-destino]').at(-1);

    ultimo.element.focus();
    await janela.trigger('keydown', { key: 'Tab' });
    expect(document.activeElement).toBe(fechar.element);

    await janela.trigger('keydown', { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(ultimo.element);

    wrapper.unmount();
    expect(document.activeElement).toBe(abridor);
    abridor.remove();
  });

  it('Esc fecha', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-janela-de-encaminhar]').trigger('keydown', {
      key: 'Escape',
    });
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });
});

describe('resumoDoEnvio', () => {
  it('diz se algum saiu e nomeia as falhas', () => {
    const resumo = resumoDoEnvio(
      [
        { conversation_id: 11, ok: false, erro: 'x' },
        { conversation_id: 99, ok: false, erro: 'y' },
      ],
      conversas
    );
    expect(resumo.algumEnviado).toBe(false);
    expect(resumo.falhas).toEqual([
      { nome: 'Ana Souza', erro: 'x' },
      { nome: '#99', erro: 'y' },
    ]);
  });
});

describe('EncaminharDaConversa', () => {
  // A área da conversa, como a MessagesView marca, com a barra dentro.
  const montarNaConversa = () => {
    const area = document.createElement('div');
    area.setAttribute('data-conversa-da-pele', '');
    document.body.appendChild(area);
    const wrapper = mount(EncaminharDaConversa, {
      props: { conversationId: 9 },
      attachTo: area,
      global,
    });
    return { area, wrapper };
  };
  const esc = alvo => {
    const evento = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
    });
    alvo.dispatchEvent(evento);
    return evento;
  };

  it('mostra a barra no modo seleção e Esc na barra sai', async () => {
    const { area, wrapper } = montarNaConversa();
    comecarSelecao(9, [1]);
    await nextTick();
    const barra = wrapper.find('[data-barra-de-encaminhar]');
    expect(barra.exists()).toBe(true);

    const ouvinteDeFora = vi.fn();
    document.addEventListener('keydown', ouvinteDeFora);
    esc(barra.element);
    document.removeEventListener('keydown', ouvinteDeFora);
    await nextTick();

    expect(selecao.ativa).toBe(false);
    expect(wrapper.find('[data-barra-de-encaminhar]').exists()).toBe(false);
    // O Esc segue para os outros ouvintes (nada de stopPropagation global).
    expect(ouvinteDeFora).toHaveBeenCalled();
    wrapper.unmount();
    area.remove();
  });

  it('Esc sem nada focado (no body) também sai', async () => {
    const { area, wrapper } = montarNaConversa();
    comecarSelecao(9, [1]);
    esc(document.body);
    expect(selecao.ativa).toBe(false);
    wrapper.unmount();
    area.remove();
  });

  it('Esc de outro (menu, fora da conversa ou já tratado) fica com ele', async () => {
    const { area, wrapper } = montarNaConversa();
    comecarSelecao(9, [1]);

    const menu = document.createElement('div');
    menu.setAttribute('role', 'menu');
    area.appendChild(menu);
    esc(menu);
    expect(selecao.ativa).toBe(true);

    const fora = document.createElement('input');
    document.body.appendChild(fora);
    esc(fora);
    expect(selecao.ativa).toBe(true);

    const tratado = new KeyboardEvent('keydown', {
      key: 'Escape',
      bubbles: true,
      cancelable: true,
    });
    tratado.preventDefault();
    area.dispatchEvent(tratado);
    expect(selecao.ativa).toBe(true);

    fora.remove();
    wrapper.unmount();
    area.remove();
  });

  it('trocar de conversa limpa a seleção', async () => {
    const wrapper = mount(EncaminharDaConversa, {
      props: { conversationId: 9 },
      global,
    });
    comecarSelecao(9, [1]);
    await wrapper.setProps({ conversationId: 10 });
    expect(selecao.ativa).toBe(false);
    wrapper.unmount();
  });
});
