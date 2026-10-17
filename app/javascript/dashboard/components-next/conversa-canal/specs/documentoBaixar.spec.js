/* eslint-disable vue/one-component-per-file */
import { defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { useAlert } from 'dashboard/composables';
import { provideMessageContext } from '../../message/provider.js';
import DocumentoDoWhatsapp from '../midia/DocumentoDoWhatsapp.vue';
import { baixarArquivo } from '../midia/baixarArquivo';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Pedido do Rodrigo (17/10, conta 16): foto mandada como documento abria noutra aba
// em vez de baixar. O botão agora salva o arquivo com o nome dele.
describe('baixar documento (#1702)', () => {
  const URL_DO_ARQUIVO =
    'https://s3.test/blob?response-content-disposition=inline';
  let clicados;

  beforeEach(() => {
    clicados = [];
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      blob: () => Promise.resolve(new Blob(['png'])),
    });
    URL.createObjectURL = vi.fn(() => 'blob:local/1');
    URL.revokeObjectURL = vi.fn();
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      function registrar() {
        clicados.push({ href: this.href, download: this.download });
      }
    );
  });

  afterEach(() => vi.restoreAllMocks());

  it('busca o arquivo e salva com o nome dele, sem abrir outra aba', async () => {
    await baixarArquivo({ url: URL_DO_ARQUIVO, nome: 'foto.png' });

    expect(global.fetch).toHaveBeenCalledWith(URL_DO_ARQUIVO, {
      cache: 'no-store',
    });
    expect(clicados).toEqual([{ href: 'blob:local/1', download: 'foto.png' }]);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:local/1');
  });

  it('resposta com erro não salva nada e avisa quem chamou', async () => {
    global.fetch.mockResolvedValue({ ok: false, status: 403 });

    await expect(
      baixarArquivo({ url: URL_DO_ARQUIVO, nome: 'foto.png' })
    ).rejects.toThrow('403');
    expect(clicados).toEqual([]);
  });

  const montar = () =>
    mount(
      defineComponent({
        setup() {
          provideMessageContext({
            orientation: ref('right'),
            attachments: ref([
              {
                dataUrl: URL_DO_ARQUIVO,
                fileType: 'file',
                fileSize: 2048,
                extension: 'png',
              },
            ]),
          });
          return () => h(DocumentoDoWhatsapp);
        },
      }),
      {
        global: {
          plugins: [
            createI18n({
              legacy: false,
              locale: 'en',
              messages: { en },
              missingWarn: false,
              fallbackWarn: false,
            }),
          ],
        },
      }
    );

  it('o cartão tem um botão (não um link para o armazenamento) que baixa', async () => {
    const cartao = montar();

    expect(cartao.find('a[href]').exists()).toBe(false);
    await cartao.find('[data-baixar-documento]').trigger('click');
    await flushPromises();

    expect(global.fetch).toHaveBeenCalledTimes(1);
    expect(clicados).toHaveLength(1);
    expect(clicados[0].href).toBe('blob:local/1');
  });

  it('falha ao baixar mostra o aviso e libera o botão', async () => {
    global.fetch.mockRejectedValue(new Error('rede'));
    const cartao = montar();

    await cartao.find('[data-baixar-documento]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalled();
    expect(
      cartao.find('[data-baixar-documento]').attributes('disabled')
    ).toBeUndefined();
  });
});
