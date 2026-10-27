import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import {
  criarAnuncio,
  enviarMidia,
  esquecerTentativas,
  lerOpcoesDeCriacao,
  lerOrcamento,
  lerPausadosEsperando,
  mudarOrcamento,
  novaChave,
  pedidoDoAnuncio,
} from '../criacaoNaMeta';
import { capaEmArquivo } from '../midiaDoAnuncio';
import { siteNormalizado, siteValido } from '../anuncioNovo';
import {
  amountCents,
  decimalAmount,
  money,
  parseAmount,
  todayOfAccount,
  withWords,
} from '../dinheiroDoAnuncio';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    createOptions: vi.fn(),
    uploadMedia: vi.fn(),
    createAd: vi.fn(),
    adBudget: vi.fn(),
    updateAdBudget: vi.fn(),
    pausedAds: vi.fn(),
  },
}));

const DRAFT = {
  name: ' Bolo · 27 out ',
  daily_amount: 'R$ 35,50',
  destination: 'WHATSAPP',
  page_id: '1',
  whatsapp_number: '+5511900002161',
  site_url: '',
  site_action: 'LEARN_MORE',
  text: ' Bolo de pote. ',
  headline: 'Bolo',
  ready_message: 'Olá!',
  placement: 'AUTO',
  region: 'STATES',
  states: ['SP', 'RJ'],
  age_min: 25,
  age_max: 45,
  special_category: true,
  start_date: '2026-10-27',
  end_date: '2026-11-02',
  media: { kind: 'image', hash: 'h1', url: 'blob:x', source: 'upload' },
  more_media: [
    {
      kind: 'video',
      video_id: '99',
      image_hash: 'cover',
      url: 'blob:y',
      poster: 'data:image/jpeg;base64,AA==',
    },
  ],
};

describe('Anúncios da Meta · pedidos ao servidor (#2198)', () => {
  it('turns the draft into the new ad request, only with what the destination uses', () => {
    expect(pedidoDoAnuncio(DRAFT)).toEqual({
      name: 'Bolo · 27 out',
      destination: 'WHATSAPP',
      page_id: '1',
      whatsapp_number: '+5511900002161',
      site_url: null,
      site_action: null,
      text: 'Bolo de pote.',
      headline: 'Bolo',
      ready_message: 'Olá!',
      placement: 'AUTO',
      region: 'STATES',
      states: ['SP', 'RJ'],
      age_min: 25,
      age_max: 45,
      special_category: true,
      // Texto decimal, sem passar por float.
      daily_amount: '35.50',
      start_date: '2026-10-27',
      end_date: '2026-11-02',
      media: { kind: 'image', hash: 'h1' },
      cards: [{ kind: 'video', video_id: '99', image_hash: 'cover' }],
    });
  });

  it('a website ad goes with https; all of Brazil sends no states', () => {
    const pedido = pedidoDoAnuncio({
      ...DRAFT,
      destination: 'WEBSITE',
      site_url: 'loja.com.br',
      site_action: 'SHOP_NOW',
      region: 'BR',
      end_date: '',
      more_media: [],
    });

    expect(pedido).toMatchObject({
      site_url: 'https://loja.com.br',
      site_action: 'SHOP_NOW',
      whatsapp_number: null,
      ready_message: null,
      region: 'BR',
      states: [],
      end_date: '',
      cards: [],
    });
  });

  describe('idempotency key of each attempt', () => {
    beforeEach(() => {
      esquecerTentativas();
      let count = 0;
      vi.spyOn(crypto, 'randomUUID').mockImplementation(() => {
        count += 1;
        return `key-${count}`;
      });
    });
    afterEach(() => vi.restoreAllMocks());

    const keys = () =>
      CrmMetaAdsConnectionAPI.createAd.mock.calls.map(
        ([body]) => body.idempotency_key
      );
    const refusal = (status, data) =>
      Object.assign(new Error('refused'), { response: { status, data } });
    const tryTwice = async error => {
      CrmMetaAdsConnectionAPI.createAd
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce({ data: { ad_id: '9', status: 'PAUSED' } });
      await expect(criarAnuncio({ name: 'x' })).rejects.toBe(error);
      return criarAnuncio({ name: 'x' });
    };

    it('sends the key with the request and returns the paused ad', async () => {
      CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({
        data: { ad_id: '9', status: 'PAUSED' },
      });

      const result = await criarAnuncio({ name: 'x' });

      expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenCalledWith({
        name: 'x',
        idempotency_key: 'key-1',
      });
      expect(result).toEqual({ ad_id: '9', status: 'PAUSED' });
    });

    it('keeps the key after no answer, a 5xx, a 409 or nothing_created false', async () => {
      await tryTwice(new Error('Network Error'));
      await tryTwice(refusal(502, {}));
      await tryTwice(refusal(409, { error: 'in_progress' }));
      await tryTwice(
        refusal(422, { error: 'meta_refused', nothing_created: false })
      );

      expect(keys()).toEqual([
        'key-1',
        'key-1',
        'key-2',
        'key-2',
        'key-3',
        'key-3',
        'key-4',
        'key-4',
      ]);
    });

    it('a refusal with nothing created frees a new key; a success too', async () => {
      CrmMetaAdsConnectionAPI.createAd.mockResolvedValue({
        data: { ad_id: '9', status: 'PAUSED' },
      });
      await tryTwice(
        refusal(422, { error: 'meta_refused', nothing_created: true })
      );
      await criarAnuncio({ name: 'x' });

      expect(keys()).toEqual(['key-1', 'key-2', 'key-3']);
    });

    it('the key lives only in memory: nothing of the request goes to the browser storage', async () => {
      CrmMetaAdsConnectionAPI.createAd.mockRejectedValue(new Error('Network'));
      await expect(
        criarAnuncio({ name: 'x', whatsapp_number: '+5511987654321' })
      ).rejects.toThrow();
      await expect(
        criarAnuncio({ name: 'x', whatsapp_number: '+5511987654321' })
      ).rejects.toThrow();

      expect(keys()).toEqual(['key-1', 'key-1']);
      expect(window.sessionStorage.length).toBe(0);
      expect(window.localStorage.length).toBe(0);
    });

    it('when the server points to the attempt that already handles this request, goes on with its key', async () => {
      const twin = '0f1e2d3c-4b5a-4987-8a6b-5c4d3e2f1a0b';
      CrmMetaAdsConnectionAPI.createAd
        .mockRejectedValueOnce(
          refusal(422, {
            error: 'unconfirmed',
            nothing_created: false,
            idempotency_key: twin,
          })
        )
        .mockResolvedValueOnce({ data: { ad_id: '9', status: 'PAUSED' } });
      await expect(criarAnuncio({ name: 'x' })).rejects.toThrow();
      await criarAnuncio({ name: 'x' }, { recriar: true });

      expect(keys()).toEqual(['key-1', twin]);
    });

    it('without crypto.randomUUID (page outside HTTPS), still makes a valid UUID v4', () => {
      vi.restoreAllMocks();
      const original = crypto.randomUUID;
      Object.defineProperty(crypto, 'randomUUID', {
        value: undefined,
        configurable: true,
      });
      try {
        const key = novaChave();
        const groups = key.split('-');
        expect(groups.map(group => group.length)).toEqual([8, 4, 4, 4, 12]);
        expect(
          [...groups.join('')].every(char => '0123456789abcdef'.includes(char))
        ).toBe(true);
        expect(groups[2][0]).toBe('4');
        expect('89ab').toContain(groups[3][0]);
        expect(novaChave()).not.toBe(key);
      } finally {
        Object.defineProperty(crypto, 'randomUUID', {
          value: original,
          configurable: true,
        });
      }
    });

    it("create again after unconfirmed goes with the same key and the person's release", async () => {
      CrmMetaAdsConnectionAPI.createAd
        .mockRejectedValueOnce(
          refusal(422, { error: 'unconfirmed', nothing_created: false })
        )
        .mockResolvedValueOnce({ data: { ad_id: '9', status: 'PAUSED' } });
      await expect(criarAnuncio({ name: 'x' })).rejects.toThrow();
      await criarAnuncio({ name: 'x' }, { recriar: true });

      expect(CrmMetaAdsConnectionAPI.createAd).toHaveBeenLastCalledWith({
        name: 'x',
        idempotency_key: 'key-1',
        recreate_unconfirmed: true,
      });
    });

    it('a different request is another attempt', async () => {
      CrmMetaAdsConnectionAPI.createAd.mockRejectedValue(new Error('Network'));
      await expect(criarAnuncio({ name: 'x' })).rejects.toThrow();
      await expect(criarAnuncio({ name: 'y' })).rejects.toThrow();

      expect(keys()).toEqual(['key-1', 'key-2']);
    });
  });

  it('a photo goes up once and comes back with its hash', async () => {
    CrmMetaAdsConnectionAPI.uploadMedia.mockResolvedValue({
      data: { media: { kind: 'image', hash: 'abc', url: 'https://meta/1' } },
    });
    const file = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });

    const media = await enviarMidia({ kind: 'image', url: 'blob:1' }, file);

    expect(CrmMetaAdsConnectionAPI.uploadMedia).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.uploadMedia).toHaveBeenCalledWith(file);
    expect(media).toEqual({ kind: 'image', url: 'blob:1', hash: 'abc' });
  });

  it('a video goes up with its cover as a JPEG, and keeps the cover hash', async () => {
    CrmMetaAdsConnectionAPI.uploadMedia
      .mockResolvedValueOnce({
        data: { media: { kind: 'video', video_id: '77' } },
      })
      .mockResolvedValueOnce({
        data: { media: { kind: 'image', hash: 'capa' } },
      });
    const file = new File(['v'], 'video.mp4', { type: 'video/mp4' });

    const media = await enviarMidia(
      { kind: 'video', url: 'blob:2', poster: 'data:image/jpeg;base64,/9j/' },
      file
    );

    const [[first], [cover]] = CrmMetaAdsConnectionAPI.uploadMedia.mock.calls;
    expect(first).toBe(file);
    expect(cover.type).toBe('image/jpeg');
    expect(media).toMatchObject({ video_id: '77', image_hash: 'capa' });
  });

  it('reads the options, the budget and the paused ads; changes the budget (amounts come as decimal text)', async () => {
    CrmMetaAdsConnectionAPI.createOptions.mockResolvedValue({
      data: { options: { kinds: ['ad'] } },
    });
    CrmMetaAdsConnectionAPI.adBudget.mockResolvedValue({
      data: { budget: { amount: '30.00' } },
    });
    CrmMetaAdsConnectionAPI.updateAdBudget.mockResolvedValue({
      data: { budget: { amount: '45.50' } },
    });
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [{ ad_id: '1', budget: { amount: '20.57' } }] },
    });

    expect(await lerOpcoesDeCriacao()).toEqual({ kinds: ['ad'] });
    // Número só para mostrar; as contas usam os centavos inteiros.
    expect(await lerOrcamento('5')).toEqual({ amount: 30, amount_cents: 3000 });
    expect(await mudarOrcamento('5', { amount: 45, end_time: null })).toEqual({
      amount: 45.5,
      amount_cents: 4550,
    });
    expect(CrmMetaAdsConnectionAPI.updateAdBudget).toHaveBeenCalledWith('5', {
      amount: 45,
      end_time: null,
    });
    expect(await lerPausadosEsperando()).toEqual([
      { ad_id: '1', budget: { amount: 20.57, amount_cents: 2057 } },
    ]);
  });
});

describe('Anúncios da Meta · ajudas do anúncio novo (#2198)', () => {
  it('turns the video cover into a JPEG file', () => {
    // "AAEC" em base64 são 3 bytes: 0, 1 e 2.
    const file = capaEmArquivo('data:image/jpeg;base64,AAEC');

    expect(file.name).toBe('capa.jpg');
    expect(file.type).toBe('image/jpeg');
    expect(file.size).toBe(3);
  });

  it('completes the site address with https and checks it has a domain', () => {
    expect(siteNormalizado(' loja.com.br ')).toBe('https://loja.com.br');
    expect(siteNormalizado('http://loja.com.br')).toBe('http://loja.com.br');
    expect(siteValido('loja.com.br')).toBe(true);
    expect(siteValido('http://loja.com.br')).toBe(false);
    expect(siteValido('loja')).toBe(false);
  });

  it('reads the amount the way people type it', () => {
    expect(parseAmount('20,00')).toBe(20);
    expect(parseAmount('R$ 1.000,50')).toBe(1000.5);
    expect(parseAmount('45.5')).toBe(45.5);
    expect(parseAmount('6,50')).toBe(6.5);
    expect(parseAmount('25.57')).toBe(25.57);
    expect(parseAmount('')).toBeNull();
  });

  it("uses the ad account's today from the server, not the browser clock", () => {
    expect(todayOfAccount('2030-01-15')).toBe('2030-01-15');
  });

  it('any character outside digits, comma and dot is a refusal (only the leading R$ goes)', () => {
    expect(parseAmount('-10')).toBeNull();
    expect(parseAmount('1e2')).toBeNull();
    expect(parseAmount('10abc')).toBeNull();
    expect(parseAmount('R$ 10')).toBe(10);
    expect(parseAmount('US$ 10')).toBeNull();
  });

  it('without a confirmed currency, formats nothing (never assumes reais)', () => {
    expect(money(20, null, 'pt_BR')).toBe('');
    expect(withWords(20, undefined, 'pt_BR')).toBe('');
  });

  it('a dot before the comma is a thousands separator only in groups of 3', () => {
    expect(parseAmount('1.500,00')).toBe(1500);
    expect(parseAmount('1.000.000,50')).toBe(1000000.5);
    expect(parseAmount('1.5,00')).toBeNull();
    expect(parseAmount('10,5.5')).toBeNull();
    expect(parseAmount('.500,00')).toBeNull();
  });

  it('spaces only at the edges: a space inside is a refusal', () => {
    expect(parseAmount('  R$ 25,00  ')).toBe(25);
    expect(parseAmount('2 5')).toBeNull();
    expect(parseAmount('1 000')).toBeNull();
  });

  it('sends the amount as decimal text with 2 places, never through float', () => {
    expect(amountCents('R$ 1.500,00')).toBe(150000);
    expect(amountCents('20.57')).toBe(2057);
    expect(amountCents(20.57)).toBe(2057);
    expect(amountCents('0,1')).toBe(10);
    expect(amountCents('1e2')).toBeNull();
    expect(decimalAmount('6,5')).toBe('6.50');
    expect(decimalAmount('R$ 1.500,00')).toBe('1500.00');
    expect(decimalAmount('25.57')).toBe('25.57');
    expect(decimalAmount('-1')).toBeNull();
  });

  it('refuses what could be read wrong, never rounds in silence', () => {
    // Ponto com 3 casas é milhar para quem digita em português: não vira R$ 6,00.
    expect(parseAmount('6.000')).toBeNull();
    expect(parseAmount('1.000.000')).toBeNull();
    expect(parseAmount('20.005')).toBeNull();
    expect(parseAmount('20,005')).toBeNull();
    expect(parseAmount('6.')).toBeNull();
    expect(parseAmount('1,2,3')).toBeNull();
  });
});
