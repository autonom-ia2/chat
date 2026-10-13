import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import PonteFormatoDaCampanha from '../ponte/PonteFormatoDaCampanha.vue';
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
    const pedido = oQuePedir(oferta);
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

  it('código de verificação e produtos do catálogo não vão em campanha', () => {
    expect(formatoQueNaoVai({ category: 'AUTHENTICATION' })).toBe('CODIGO');
    expect(
      formatoQueNaoVai({
        components: [{ type: 'BUTTONS', buttons: [{ type: 'MPM' }] }],
      })
    ).toBe('PRODUTOS');
    expect(
      formatoQueNaoVai({
        components: [{ type: 'CAROUSEL', cards: [cartao('PRODUCT')] }],
      })
    ).toBe('PRODUTOS');
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
      en.MODELOS_WHATSAPP.PONTE.FORMATO.CARTAO_SEM_ARQUIVO_FOTO
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
