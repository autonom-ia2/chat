import { mount, flushPromises } from '@vue/test-utils';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import BookingPageLinks from '../components/BookingPageLinks.vue';
import BookingQrDownload from '../components/BookingQrDownload.vue';
import { QR_PRINT_SIZE, qrFileName } from '../bookingQrFile';

// Baixar o QR code (#1290): aparece junto do QR, gera o arquivo com nome
// legível e avisa quando não dá.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({
  copyTextToClipboard: vi.fn(() => Promise.resolve()),
}));
vi.mock('qrcode', () => ({
  default: { toCanvas: vi.fn(), toString: vi.fn(), toDataURL: vi.fn() },
}));

const URL_PAGE = 'https://chat.exemplo.com/book/corte';
const PNG = new Blob(['png'], { type: 'image/png' });

const mountDownload = (props = {}) =>
  mount(BookingQrDownload, {
    props: { url: URL_PAGE, name: 'Corte de Cabelo', ...props },
  });

describe('BookingQrDownload', () => {
  let clicks;
  let createObjectURL;
  let revokeObjectURL;
  const originalUrl = {
    createObjectURL: URL.createObjectURL,
    revokeObjectURL: URL.revokeObjectURL,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    clicks = [];
    QRCode.toCanvas.mockResolvedValue({ toBlob: done => done(PNG) });
    QRCode.toString.mockResolvedValue('<svg xmlns="x"></svg>');
    QRCode.toDataURL.mockResolvedValue('data:image/png;base64,AAAA');
    createObjectURL = vi.fn(() => 'blob:qr-1');
    revokeObjectURL = vi.fn();
    Object.assign(URL, { createObjectURL, revokeObjectURL });
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      function record() {
        clicks.push({ file: this.download, href: this.getAttribute('href') });
      }
    );
  });

  afterEach(() => {
    vi.restoreAllMocks();
    Object.assign(URL, originalUrl);
  });

  describe('nome do arquivo', () => {
    it('usa o nome da página em minúsculas, sem acento e com hífens', () => {
      expect(qrFileName('Corte de Cabelo', 'png')).toBe(
        'qr-corte-de-cabelo.png'
      );
      expect(qrFileName('  Avaliação & Retorno — Dr. João  ', 'svg')).toBe(
        'qr-avaliacao-and-retorno-dr-joao.svg'
      );
    });

    it('sem nome aproveitável, cai em qr-code', () => {
      expect(qrFileName('', 'png')).toBe('qr-code.png');
      expect(qrFileName(undefined, 'png')).toBe('qr-code.png');
      expect(qrFileName('!!!', 'png')).toBe('qr-code.png');
    });
  });

  describe('onde aparece', () => {
    const open = async wrapper => {
      await wrapper.find('[data-qr-toggle]').trigger('click');
      await flushPromises();
    };

    it('página com um link: só aparece junto do QR, com o nome da página', async () => {
      const wrapper = mount(BookingPageLinks, {
        props: { page: { title: 'Corte de Cabelo', public_url: URL_PAGE } },
      });
      expect(wrapper.find('[data-qr-download]').exists()).toBe(false);

      await open(wrapper);
      expect(wrapper.find('[data-qr]').exists()).toBe(true);
      expect(wrapper.find('[data-qr-download-png]').exists()).toBe(true);
      expect(wrapper.find('[data-qr-download-svg]').exists()).toBe(true);

      await wrapper.find('[data-qr-download-png]').trigger('click');
      await flushPromises();
      expect(clicks).toEqual([
        { file: 'qr-corte-de-cabelo.png', href: 'blob:qr-1' },
      ]);

      await open(wrapper);
      expect(wrapper.find('[data-qr-download]').exists()).toBe(false);
    });

    it('um link para cada pessoa: cada QR tem o seu botão e o nome da pessoa no arquivo', async () => {
      const wrapper = mount(BookingPageLinks, {
        props: {
          page: {
            title: 'Corte de Cabelo',
            links: [
              { agent_id: 1, agent_name: 'João Silva', url: `${URL_PAGE}/1` },
              { agent_id: 2, agent_name: 'Ana', url: `${URL_PAGE}/2` },
            ],
          },
        },
      });
      const second = wrapper.find('[data-person-link="2"]');
      await open(second);
      expect(wrapper.findAll('[data-qr-download]')).toHaveLength(1);

      await second.find('[data-qr-download-png]').trigger('click');
      await flushPromises();
      expect(QRCode.toCanvas).toHaveBeenCalledWith(
        `${URL_PAGE}/2`,
        expect.any(Object)
      );
      expect(clicks[0].file).toBe('qr-corte-de-cabelo-ana.png');
    });
  });

  it('PNG: tamanho de impressão, margem de silêncio, fundo branco e aviso', async () => {
    const wrapper = mountDownload();
    const button = wrapper.find('[data-qr-download-png]');
    expect(button.attributes('aria-label')).toContain('qr-corte-de-cabelo.png');
    expect(button.classes()).toContain('min-h-11');

    await button.trigger('click');
    await flushPromises();

    expect(QR_PRINT_SIZE).toBe(1024);
    expect(QRCode.toCanvas).toHaveBeenCalledWith(URL_PAGE, {
      width: 1024,
      margin: 4,
      errorCorrectionLevel: 'Q',
      color: { dark: '#000000', light: '#ffffff' },
    });
    expect(createObjectURL).toHaveBeenCalledWith(PNG);
    expect(clicks).toEqual([
      { file: 'qr-corte-de-cabelo.png', href: 'blob:qr-1' },
    ]);
    expect(useAlert).toHaveBeenCalledWith(
      'BOOKING.LINK.QR_DOWNLOADING {"file":"qr-corte-de-cabelo.png"}'
    );
    expect(button.attributes('aria-disabled')).toBeUndefined();
  });

  it('bloqueio do navegador nem sempre avisa: fica o link para abrir a imagem', async () => {
    const wrapper = mountDownload();
    const status = wrapper.find('[data-qr-download-status]');
    expect(status.attributes('role')).toBe('status');
    expect(status.text()).toBe('');

    await wrapper.find('[data-qr-download-png]').trigger('click');
    await flushPromises();

    expect(status.text()).toContain('BOOKING.LINK.QR_DOWNLOAD_RETRY');
    expect(
      status
        .find('[data-qr-download-accepted]')
        .attributes('data-qr-download-accepted')
    ).toBe('true');
    const link = status.find('[data-qr-download-open]');
    expect(link.attributes('href')).toBe('blob:qr-1');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.text()).toContain('qr-corte-de-cabelo.png');
    expect(revokeObjectURL).not.toHaveBeenCalled();

    // Outro link (ex.: outra pessoa): o arquivo antigo some e é solto.
    await wrapper.setProps({ url: `${URL_PAGE}/2` });
    expect(status.text()).toBe('');
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:qr-1');
  });

  it('enquanto gera, um segundo clique não gera outro arquivo e o foco fica no botão', async () => {
    let finish;
    QRCode.toCanvas.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mountDownload();
    const button = wrapper.find('[data-qr-download-png]');

    await button.trigger('click');
    expect(button.attributes('aria-disabled')).toBe('true');
    expect(button.attributes('aria-busy')).toBe('true');
    expect(button.attributes('disabled')).toBeUndefined();
    await button.trigger('click');
    await wrapper.find('[data-qr-download-svg]').trigger('click');
    expect(QRCode.toCanvas).toHaveBeenCalledTimes(1);
    expect(QRCode.toString).not.toHaveBeenCalled();

    finish({ toBlob: done => done(PNG) });
    await flushPromises();
    expect(clicks).toHaveLength(1);
    expect(button.attributes('aria-disabled')).toBeUndefined();
  });

  it('saiu da tela enquanto gerava: não baixa nem deixa arquivo preso', async () => {
    let finish;
    QRCode.toCanvas.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = mountDownload();
    await wrapper.find('[data-qr-download-png]').trigger('click');

    wrapper.unmount();
    finish({ toBlob: done => done(PNG) });
    await flushPromises();

    expect(createObjectURL).not.toHaveBeenCalled();
    expect(clicks).toEqual([]);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('SVG: ação secundária que baixa o vetor com o mesmo nome', async () => {
    const wrapper = mountDownload();
    const button = wrapper.find('[data-qr-download-svg]');
    expect(button.classes()).toContain('min-h-11');

    await button.trigger('click');
    await flushPromises();

    expect(QRCode.toString).toHaveBeenCalledWith(
      URL_PAGE,
      expect.objectContaining({ type: 'svg', margin: 4 })
    );
    const blob = createObjectURL.mock.calls[0][0];
    expect(blob.type).toBe('image/svg+xml');
    expect(clicks[0].file).toBe('qr-corte-de-cabelo.svg');
    expect(useAlert).toHaveBeenCalledWith(
      'BOOKING.LINK.QR_DOWNLOADING {"file":"qr-corte-de-cabelo.svg"}'
    );
  });

  it('não deu para gerar: avisa o erro e não baixa nada', async () => {
    QRCode.toCanvas.mockRejectedValue(new Error('canvas'));
    const wrapper = mountDownload();

    await wrapper.find('[data-qr-download-png]').trigger('click');
    await flushPromises();

    expect(clicks).toEqual([]);
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith('BOOKING.LINK.QR_DOWNLOAD_ERROR');
    expect(wrapper.find('[data-qr-download-open]').exists()).toBe(false);
    expect(
      wrapper.find('[data-qr-download-png]').attributes('aria-disabled')
    ).toBeUndefined();
  });

  it('imagem vazia do navegador também é erro', async () => {
    QRCode.toCanvas.mockResolvedValue({ toBlob: done => done(null) });
    const wrapper = mountDownload();

    await wrapper.find('[data-qr-download-png]').trigger('click');
    await flushPromises();

    expect(clicks).toEqual([]);
    expect(useAlert).toHaveBeenCalledWith('BOOKING.LINK.QR_DOWNLOAD_ERROR');
  });

  it('navegador recusou o download: diz isso, mostra o link e solta o arquivo ao sair', async () => {
    HTMLAnchorElement.prototype.click.mockImplementation(() => {
      throw new Error('blocked');
    });
    const wrapper = mountDownload();

    await wrapper.find('[data-qr-download-png]').trigger('click');
    await flushPromises();

    expect(useAlert).not.toHaveBeenCalled();
    const notice = wrapper.find('[data-qr-download-status]');
    expect(notice.text()).toContain('BOOKING.LINK.QR_DOWNLOAD_BLOCKED');
    expect(
      notice
        .find('[data-qr-download-accepted]')
        .attributes('data-qr-download-accepted')
    ).toBe('false');
    expect(document.querySelector('a[download]')).toBeNull();
    const link = wrapper.find('[data-qr-download-open]');
    expect(link.attributes('href')).toBe('blob:qr-1');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.text()).toContain('qr-corte-de-cabelo.png');

    wrapper.unmount();
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:qr-1');
  });
});
