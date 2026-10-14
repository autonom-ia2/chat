import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import PonteFormatoDaCampanha from '../ponte/PonteFormatoDaCampanha.vue';
import PontePrevia from '../ponte/PontePrevia.vue';
import { guardarPrevia } from '../api/arquivos';
import {
  extrasParaEnvio,
  formatoQueNaoVai,
  soModeloCompleto,
  oQuePedir,
  pendencias,
} from '../helpers/formatoNaCampanha';

// #1334: o que a campanha pede de cada formato novo, no contrato do servidor
// (Whatsapp::Templates::SendParams).
const api = vi.hoisted(() => ({ subirArquivoDaCampanha: vi.fn() }));
vi.mock('../api/modelosWhatsapp', () => ({ default: api }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { name: 'Hub2you' } } }),
}));

// #1465: a miniatura da foto escolhida é um object URL do próprio arquivo.
// jsdom não tem object URL; volta ao que era no fim do arquivo.
const urlOriginal = { criar: URL.createObjectURL, soltar: URL.revokeObjectURL };
URL.createObjectURL = vi.fn(arquivo => `blob:${arquivo.name}`);
URL.revokeObjectURL = vi.fn();
afterAll(() => {
  URL.createObjectURL = urlOriginal.criar;
  URL.revokeObjectURL = urlOriginal.soltar;
});

const ZONA = 'America/Sao_Paulo';
const AGORA = new Date('2026-10-13T12:00:00Z').getTime();

const cartao = formato => ({
  components: [
    { type: 'HEADER', format: formato },
    { type: 'BODY', text: 'Produto' },
  ],
});
const oferta = {
  name: 'oferta',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'IMAGE' },
    {
      type: 'LIMITED_TIME_OFFER',
      limited_time_offer: { text: 'Hoje', has_expiration: true },
    },
    { type: 'BODY', text: 'Oi {{1}}' },
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'COPY_CODE', example: 'CUPOM10' },
        { type: 'URL', text: 'Ver', url: 'https://a.com' },
      ],
    },
  ],
};
const carrossel = {
  name: 'vitrine',
  category: 'MARKETING',
  components: [
    { type: 'BODY', text: 'Veja' },
    { type: 'CAROUSEL', cards: [cartao('IMAGE'), cartao('IMAGE')] },
  ],
};

describe('formatoNaCampanha', () => {
  it('pede cupom (com o exemplo do modelo) e validade na oferta', () => {
    const pedido = oQuePedir(oferta, [], { nome: 'oferta.png' });
    expect(pedido.cupom).toEqual({ indice: 0, exemplo: 'CUPOM10' });
    expect(pedido.validade).toBe(true);
    expect(pendencias(pedido, {}, { timeZone: ZONA, agora: AGORA })).toEqual([
      'CUPOM',
      'VALIDADE',
    ]);
    expect(
      pendencias(
        pedido,
        { cupom: 'A'.repeat(16), validade: '2026-10-01T10:00' },
        { timeZone: ZONA, agora: AGORA }
      )
    ).toEqual(['CUPOM', 'VALIDADE_PASSADA']);
    const pronto = { cupom: ' OUTUBRO ', validade: '2026-10-20T18:00' };
    expect(
      pendencias(pedido, pronto, { timeZone: ZONA, agora: AGORA })
    ).toEqual([]);
    expect(extrasParaEnvio(pedido, pronto, { timeZone: ZONA })).toEqual({
      buttons: [{ type: 'copy_code', parameter: 'OUTUBRO' }],
      limited_time_offer: {
        expiration_time_ms: new Date('2026-10-20T21:00:00Z').getTime(),
      },
    });
  });

  it('no carrossel, cada cartão usa o arquivo aprovado ou o escolhido agora', () => {
    const pedido = oQuePedir(carrossel, [{ nome: 'a.jpg' }]);
    expect(pedido.cartoes.map(item => item.guardado)).toEqual([
      { nome: 'a.jpg' },
      null,
    ]);
    expect(pendencias(pedido, {}, { timeZone: ZONA })).toEqual(['CARTAO']);
    const valores = { cartoes: { 1: { referencia: 'sig2', nome: 'b.png' } } };
    expect(pendencias(pedido, valores, { timeZone: ZONA })).toEqual([]);
    expect(extrasParaEnvio(pedido, valores, { timeZone: ZONA })).toEqual({
      carousel: { cards: [{ header: {} }, { header: { media_blob: 'sig2' } }] },
    });
  });

  // #1465: topo com foto, vídeo ou documento — o aprovado com o modelo, ou um
  // arquivo escolhido agora, que vai como referência (o servidor gera o link).
  it('no topo, usa o arquivo aprovado ou o escolhido agora, conforme o tipo', () => {
    const comTopo = formato => ({
      components: [
        { type: 'HEADER', format: formato },
        { type: 'BODY', text: 'Oi' },
      ],
    });
    expect(oQuePedir(comTopo('IMAGE')).topo).toEqual({
      midia: 'foto',
      guardado: null,
    });
    expect(oQuePedir(comTopo('VIDEO')).topo.midia).toBe('video');
    expect(oQuePedir(comTopo('DOCUMENT')).topo.midia).toBe('documento');
    expect(oQuePedir(comTopo('TEXT')).topo).toBeNull();
    expect(oQuePedir({ components: [] }).topo).toBeNull();

    const semGuardado = oQuePedir(comTopo('DOCUMENT'));
    expect(pendencias(semGuardado, {}, { timeZone: ZONA })).toEqual(['TOPO']);
    const valores = { topo: { referencia: 'sig1', nome: 'tabela.pdf' } };
    expect(pendencias(semGuardado, valores, { timeZone: ZONA })).toEqual([]);
    expect(extrasParaEnvio(semGuardado, valores, { timeZone: ZONA })).toEqual({
      header: { media_blob: 'sig1' },
    });

    const guardado = oQuePedir(comTopo('IMAGE'), [], { nome: 'topo.png' });
    expect(guardado.topo.guardado).toEqual({ nome: 'topo.png' });
    expect(pendencias(guardado, {}, { timeZone: ZONA })).toEqual([]);
    expect(extrasParaEnvio(guardado, {}, { timeZone: ZONA })).toEqual({});
  });

  // #1418: produtos do catálogo vão com a flag da conta e o catálogo conectado.
  it('código de verificação não vai; produtos só com a flag e o catálogo', () => {
    expect(formatoQueNaoVai({ category: 'AUTHENTICATION' })).toBe('CODIGO');
    const varios = {
      components: [{ type: 'BUTTONS', buttons: [{ type: 'MPM' }] }],
    };
    const cartoesDeProduto = {
      components: [{ type: 'CAROUSEL', cards: [cartao('PRODUCT')] }],
    };
    const ligados = { produtosLigados: true };
    expect(formatoQueNaoVai(varios, { comCatalogo: true })).toBe('PRODUTOS');
    expect(formatoQueNaoVai(varios, ligados)).toBe('SEM_CATALOGO');
    expect(formatoQueNaoVai(cartoesDeProduto, ligados)).toBe('SEM_CATALOGO');
    const comTudo = { ...ligados, comCatalogo: true };
    expect(formatoQueNaoVai(varios, comTudo)).toBe('');
    expect(formatoQueNaoVai(cartoesDeProduto, comTudo)).toBe('');
    const comCampo = {
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
          ],
        },
      ],
    };
    expect(formatoQueNaoVai(comCampo)).toBe('CARTAO_COM_CAMPO');
    expect(formatoQueNaoVai(carrossel)).toBe('');
    expect(formatoQueNaoVai(oferta)).toBe('');
  });

  // #1456: quem recebe a mensagem escrita perderia o cupom, a oferta ou o carrossel.
  it('cupom, oferta com prazo ou carrossel: todos recebem o modelo completo', () => {
    const cupom = {
      components: [
        { type: 'BODY', text: 'Oi' },
        { type: 'BUTTONS', buttons: [{ type: 'copy_code' }] },
      ],
    };
    const ofertaSemPrazo = {
      components: [
        { type: 'BODY', text: 'Oi' },
        { type: 'limited_time_offer', limited_time_offer: { text: 'Hoje' } },
      ],
    };
    const simples = {
      components: [
        { type: 'BODY', text: 'Oi {{1}}' },
        { type: 'BUTTONS', buttons: [{ type: 'URL', url: 'https://a.com' }] },
      ],
    };
    expect(soModeloCompleto(cupom)).toBe(true);
    expect(soModeloCompleto(ofertaSemPrazo)).toBe(true);
    expect(soModeloCompleto(carrossel)).toBe(true);
    expect(soModeloCompleto(oferta)).toBe(true);
    expect(soModeloCompleto(simples)).toBe(false);
    expect(soModeloCompleto(null)).toBe(false);
  });
});

describe('PonteFormatoDaCampanha', () => {
  const montar = props =>
    mount(PonteFormatoDaCampanha, {
      props: { timeZone: ZONA, caixa: 7, ...props },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });

  // Corpo em bloco: o vitest chama como limpeza a função que o beforeEach devolve
  // (mockReset devolve o próprio mock, que seria chamado ao fim do teste).
  beforeEach(() => {
    api.subirArquivoDaCampanha.mockReset();
  });

  // Regra do Rodrigo (#1456): o fuso da conta como Configurações o mostra,
  // nunca o nome longo do navegador.
  it('a validade da oferta diz o fuso da conta como a plataforma o mostra', () => {
    const wrapper = montar({ modelo: { template: oferta } });

    const rotulo = wrapper.find('[data-formato-validade]').text();
    expect(rotulo).toContain(
      'The offer is valid until (account time zone: America/Sao Paulo)'
    );
    expect(rotulo).not.toContain('Standard Time');
  });

  it('sobe a foto escolhida para o cartão pela caixa e guarda a referência', async () => {
    api.subirArquivoDaCampanha.mockResolvedValue({
      referencia: 'sig2',
      nome: 'b.png',
    });
    const wrapper = montar({
      modelo: { template: carrossel, cartoesGuardados: [{ nome: 'a.jpg' }] },
    });
    const cartoes = wrapper.findAll('[data-formato-cartao]');
    expect(cartoes[0].text()).toContain('a.jpg');
    expect(cartoes[1].text()).toContain(
      en.MODELOS_WHATSAPP.PONTE.FORMATO.ARQUIVO.SEM_ARQUIVO.foto
    );

    const input = cartoes[1].find('input[type="file"]');
    const arquivo = new File(['x'], 'b.png', { type: 'image/png' });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');
    await flushPromises();

    expect(api.subirArquivoDaCampanha).toHaveBeenCalledWith(7, arquivo);
    expect(wrapper.emitted('update').at(-1)).toEqual([
      { cartoes: { 1: { referencia: 'sig2', nome: 'b.png' } } },
    ]);
  });

  // O código de exemplo do modelo nunca vai sozinho para o público: o campo começa
  // vazio, com o exemplo só como dica, e sem código a campanha não continua.
  it('começa com o cupom vazio, o exemplo só como dica, e pede o código', async () => {
    const wrapper = montar({ modelo: { template: oferta } });
    const campo = wrapper.find('[data-formato-cupom] input');

    expect(campo.element.value).toBe('');
    expect(campo.attributes('placeholder')).toBe('E.g. CUPOM10');
    expect(wrapper.find('[data-formato-cupom]').text()).toContain(
      en.MODELOS_WHATSAPP.PONTE.FORMATO.CUPOM_VAZIO
    );
    expect(
      pendencias(oQuePedir(oferta), {}, { timeZone: ZONA, agora: AGORA })
    ).toContain('CUPOM');

    await campo.setValue('OUTUBRO15');
    expect(wrapper.emitted('update').at(-1)).toEqual([{ cupom: 'OUTUBRO15' }]);
  });

  // #1465: o topo do modelo no lugar do campo de link.
  const comTopo = formato => ({
    name: 'aviso',
    category: 'MARKETING',
    components: [
      { type: 'HEADER', format: formato },
      { type: 'BODY', text: 'Oi' },
    ],
  });
  const FORMATO = en.MODELOS_WHATSAPP.PONTE.FORMATO;
  const textoCom = (texto, arquivo) => texto.replace('{arquivo}', arquivo);

  it('topo com arquivo aprovado: diz que vai a foto aprovada e oferece trocar', () => {
    const wrapper = montar({
      modelo: {
        template: comTopo('IMAGE'),
        topoGuardado: { nome: 'topo.png', url: 'https://s/topo.png' },
      },
    });
    const topo = wrapper.find('[data-formato-topo]');
    // A miniatura da foto aprovada, no lugar do ícone.
    expect(topo.find('img').attributes()).toMatchObject({
      src: 'https://s/topo.png',
      alt: '',
    });

    expect(topo.text()).toContain(FORMATO.TOPO.foto);
    expect(topo.text()).toContain(
      textoCom(FORMATO.ARQUIVO.GUARDADO.foto, 'topo.png')
    );
    expect(topo.find('[data-escolher-arquivo]').text()).toBe(
      FORMATO.ARQUIVO.TROCAR.foto
    );
    expect(topo.find('input[type="file"]').attributes('accept')).toBe(
      'image/jpeg,image/png'
    );
  });

  it('topo sem arquivo guardado: pede para escolher, com o tipo do modelo', () => {
    const video = montar({
      modelo: {
        template: comTopo('VIDEO'),
        // Mesmo com link de leitura (arquivo guardado que é imagem), vídeo e
        // documento ficam no ícone: a miniatura é só de topo de foto.
        topoGuardado: { nome: 'v.mp4', url: 'https://s/v.png' },
      },
    });
    expect(video.find('[data-formato-topo] img').exists()).toBe(false);
    const documentoComLink = montar({
      modelo: {
        template: comTopo('DOCUMENT'),
        topoGuardado: { nome: 'a.pdf', url: 'https://s/a.png' },
      },
    });
    expect(documentoComLink.find('[data-formato-topo] img').exists()).toBe(
      false
    );
    const semVideo = montar({ modelo: { template: comTopo('VIDEO') } });
    expect(semVideo.find('[data-formato-topo]').text()).toContain(
      FORMATO.ARQUIVO.SEM_ARQUIVO.video
    );
    expect(
      semVideo.find('[data-formato-topo] [data-escolher-arquivo]').text()
    ).toBe(FORMATO.ARQUIVO.ESCOLHER.video);

    const documento = montar({ modelo: { template: comTopo('DOCUMENT') } });
    const topo = documento.find('[data-formato-topo]');
    expect(topo.text()).toContain(FORMATO.ARQUIVO.SEM_ARQUIVO.documento);
    expect(topo.find('input[type="file"]').attributes('accept')).toBe(
      'application/pdf'
    );
  });

  it('sobe o arquivo do topo pela caixa, guarda a referência e volta para o aprovado', async () => {
    api.subirArquivoDaCampanha.mockResolvedValue({
      referencia: 'sig9',
      nome: 'nova.png',
    });
    const wrapper = montar({
      modelo: {
        template: comTopo('IMAGE'),
        topoGuardado: { nome: 'topo.png' },
      },
    });
    const input = wrapper.find('[data-formato-topo] input[type="file"]');
    const arquivo = new File(['x'], 'nova.png', { type: 'image/png' });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');
    await flushPromises();

    expect(api.subirArquivoDaCampanha).toHaveBeenCalledWith(7, arquivo);
    expect(wrapper.emitted('update').at(-1)).toEqual([
      { topo: { referencia: 'sig9', nome: 'nova.png' } },
    ]);

    await wrapper.setProps({
      valores: { topo: { referencia: 'sig9', nome: 'nova.png' } },
    });
    const topo = wrapper.find('[data-formato-topo]');
    expect(topo.text()).toContain(
      textoCom(FORMATO.ARQUIVO.ESCOLHIDO, 'nova.png')
    );
    // A miniatura vem do próprio arquivo escolhido, sem baixar nada.
    expect(URL.createObjectURL).toHaveBeenCalledWith(arquivo);
    expect(topo.find('img').attributes('src')).toBe('blob:nova.png');
    await topo.find('[data-usar-aprovado]').trigger('click');
    // Desfeito: a miniatura local sai da memória.
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:nova.png');
    expect(wrapper.emitted('update').at(-1)).toEqual([{}]);
  });

  it('diz quando o arquivo não subiu, com o motivo do servidor', async () => {
    api.subirArquivoDaCampanha.mockRejectedValue({
      mensagem: 'Use JPG ou PNG',
    });
    const wrapper = montar({ modelo: { template: carrossel } });
    const input = wrapper.find('[data-formato-cartao="0"] input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      value: [new File(['x'], 'b.png', { type: 'image/png' })],
    });
    await input.trigger('change');
    await flushPromises();

    expect(
      wrapper.find('[data-formato-cartao="0"] [role="alert"]').text()
    ).toBe('Use JPG ou PNG');
    expect(wrapper.emitted('update')).toBeUndefined();
  });
});

// #1465: "Como o cliente vê" mostra o arquivo do topo que vai.
describe('PontePrevia', () => {
  const montarPrevia = props =>
    mount(PontePrevia, {
      props,
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en } }),
        ],
      },
    });
  const modelo = {
    conteudo: {
      formato: 'padrao',
      topo: { tipo: 'foto', arquivo: '' },
      texto: [{ t: 'texto', v: 'Oi' }],
      exemplos: {},
      rodape: '',
      botoes: [],
    },
    campos: {},
    topoGuardado: { nome: 'aprovada.png' },
  };

  const topoDe = props => montarPrevia(props).find('[data-celular-topo]');

  it('foto aprovada sem link: ícone e nome do arquivo', () => {
    expect(topoDe({ modelo }).text()).toBe('aprovada.png');
    expect(topoDe({ modelo }).find('img').exists()).toBe(false);
  });

  it('mostra a foto de verdade: a aprovada e, escolhida outra, a escolhida', () => {
    const comLink = {
      ...modelo,
      topoGuardado: { nome: 'aprovada.png', url: 'https://s/aprovada.png' },
    };
    expect(topoDe({ modelo: comLink }).find('img').attributes()).toMatchObject({
      src: 'https://s/aprovada.png',
      alt: 'aprovada.png',
    });

    guardarPrevia('sig5', new File(['x'], 'nova.png', { type: 'image/png' }));
    const escolhida = topoDe({
      modelo: comLink,
      valores: { topo: { referencia: 'sig5', nome: 'nova.png' } },
    });
    expect(escolhida.find('img').attributes('src')).toBe('blob:nova.png');

    // Recarregou a página: a miniatura local some, fica o nome do escolhido.
    const semPrevia = topoDe({
      modelo: comLink,
      valores: { topo: { referencia: 'outra', nome: 'outra.png' } },
    });
    expect(semPrevia.find('img').exists()).toBe(false);
    expect(semPrevia.text()).toBe('outra.png');
  });

  it('link da foto aprovada que não abre (expirou): volta ao ícone com o nome', async () => {
    const wrapper = montarPrevia({
      modelo: {
        ...modelo,
        topoGuardado: { nome: 'aprovada.png', url: 'https://s/velho.png' },
      },
    });
    await wrapper.find('[data-celular-topo] img').trigger('error');
    expect(wrapper.find('[data-celular-topo] img').exists()).toBe(false);
    expect(wrapper.find('[data-celular-topo]').text()).toBe('aprovada.png');
  });

  it('documento: ícone e nome, nunca imagem', () => {
    const documento = {
      ...modelo,
      conteudo: { ...modelo.conteudo, topo: { tipo: 'documento' } },
      topoGuardado: { nome: 'tabela.pdf', url: '' },
    };
    expect(topoDe({ modelo: documento }).find('img').exists()).toBe(false);
    expect(topoDe({ modelo: documento }).text()).toBe('tabela.pdf');
  });
});
