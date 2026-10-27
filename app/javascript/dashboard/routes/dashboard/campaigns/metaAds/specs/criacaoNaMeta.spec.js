import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import {
  criarAnuncio,
  enviarMidia,
  esquecerTentativas,
  lerOpcoesDeCriacao,
  lerOrcamento,
  lerPausadosEsperando,
  mudarOrcamento,
  pedidoDoAnuncio,
} from '../criacaoNaMeta';
import { capaEmArquivo } from '../midiaDoAnuncio';
import { siteNormalizado, siteValido } from '../anuncioNovo';
import { parseAmount } from '../dinheiroDoAnuncio';

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
    expect(pedidoDoAnuncio(DRAFT, 35.5)).toEqual({
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
      daily_amount: 35.5,
      start_date: '2026-10-27',
      end_date: '2026-11-02',
      media: { kind: 'image', hash: 'h1' },
      cards: [{ kind: 'video', video_id: '99', image_hash: 'cover' }],
    });
  });

  it('a website ad goes with https; all of Brazil sends no states', () => {
    const pedido = pedidoDoAnuncio(
      {
        ...DRAFT,
        destination: 'WEBSITE',
        site_url: 'loja.com.br',
        site_action: 'SHOP_NOW',
        region: 'BR',
        end_date: '',
        more_media: [],
      },
      20
    );

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

  it('reads the options, the budget and the paused ads; changes the budget', async () => {
    CrmMetaAdsConnectionAPI.createOptions.mockResolvedValue({
      data: { options: { kinds: ['ad'] } },
    });
    CrmMetaAdsConnectionAPI.adBudget.mockResolvedValue({
      data: { budget: { amount: 30 } },
    });
    CrmMetaAdsConnectionAPI.updateAdBudget.mockResolvedValue({
      data: { budget: { amount: 45 } },
    });
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [{ ad_id: '1' }] },
    });

    expect(await lerOpcoesDeCriacao()).toEqual({ kinds: ['ad'] });
    expect(await lerOrcamento('5')).toEqual({ amount: 30 });
    expect(await mudarOrcamento('5', { amount: 45, end_time: null })).toEqual({
      amount: 45,
    });
    expect(CrmMetaAdsConnectionAPI.updateAdBudget).toHaveBeenCalledWith('5', {
      amount: 45,
      end_time: null,
    });
    expect(await lerPausadosEsperando()).toEqual([{ ad_id: '1' }]);
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
    expect(parseAmount('')).toBeNull();
  });
});
