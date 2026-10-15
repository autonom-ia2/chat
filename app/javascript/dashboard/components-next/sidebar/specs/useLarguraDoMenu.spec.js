import { mount } from '@vue/test-utils';
import { computed, defineComponent, ref } from 'vue';
import {
  LARGURA_PADRAO,
  LARGURA_RECOLHIDA,
  useLarguraDoMenu,
} from '../fork/useLarguraDoMenu';

// Largura do menu novo (#1617): recolher e abrir pelo botão e pelo Ctrl/Cmd+\, voltar na última largura,
// recolher sozinho em tela média só sem escolha da pessoa.
const montar = ({ janela = 1440, salvo = {} } = {}) => {
  window.innerWidth = janela;
  const sidebarWidth = ref(200);
  const uiSettings = ref({ ...salvo });
  const updateUISettings = vi.fn(novo => {
    uiSettings.value = { ...uiSettings.value, ...novo };
  });
  const isCollapsed = computed(() => sidebarWidth.value < 160);
  let api;
  const wrapper = mount(
    defineComponent({
      setup() {
        api = useLarguraDoMenu({
          sidebarWidth,
          isCollapsed,
          uiSettings,
          updateUISettings,
        });
        return () => null;
      },
    }),
    { attachTo: document.body }
  );
  return { wrapper, api, sidebarWidth, uiSettings, updateUISettings };
};

const atalho = (alvo = document.body, extra = {}) =>
  alvo.dispatchEvent(
    new KeyboardEvent('keydown', {
      key: '\\',
      ctrlKey: true,
      bubbles: true,
      ...extra,
    })
  );

describe('useLarguraDoMenu', () => {
  it('tecla segurada (repeat) não alterna de novo', () => {
    const { sidebarWidth, wrapper } = montar({ salvo: { sidebar_width: 256 } });
    atalho(document.body, { repeat: true });
    expect(sidebarWidth.value).toBe(256);
    atalho();
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    atalho(document.body, { repeat: true });
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('sem escolha: tela grande abre em 256px, tela média começa recolhida', () => {
    expect(montar({ janela: 1440 }).sidebarWidth.value).toBe(LARGURA_PADRAO);
    expect(montar({ janela: 1024 }).sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
  });

  it('a escolha da pessoa sempre vence, também em tela média', () => {
    expect(
      montar({ janela: 1024, salvo: { sidebar_width: 300 } }).sidebarWidth.value
    ).toBe(300);
  });

  it('recolher guarda a largura aberta e abrir volta nela, com aviso para o leitor de tela', () => {
    const { api, sidebarWidth, updateUISettings } = montar({
      salvo: { sidebar_width: 290 },
    });
    api.alternar();
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    expect(updateUISettings).toHaveBeenLastCalledWith({
      sidebar_width: LARGURA_RECOLHIDA,
      menu_largura_aberta: 290,
    });
    expect(api.anuncio.value).toBe('FORK_SIDEBAR.ANUNCIO_RECOLHIDO');
    api.alternar();
    expect(sidebarWidth.value).toBe(290);
    expect(api.anuncio.value).toBe('FORK_SIDEBAR.ANUNCIO_ABERTO');
  });

  it('Ctrl+\\ alterna; dentro de campo de texto não faz nada', () => {
    const { sidebarWidth, wrapper } = montar({ salvo: { sidebar_width: 256 } });
    atalho();
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    const campo = document.createElement('input');
    document.body.appendChild(campo);
    atalho(campo);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    atalho(document.body, { ctrlKey: false, metaKey: true });
    expect(sidebarWidth.value).toBe(256);
    campo.remove();
    wrapper.unmount();
  });
});
