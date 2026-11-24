import { nextTick, ref } from 'vue';
import { larguraAoAbrir, useLarguraDoGuia } from '../useLarguraDoGuia';

const montar = ({ tela = 1440, menu = 200, guardada } = {}) => {
  const aberto = ref(false);
  const uiSettings = ref({
    sidebar_width: menu,
    autonomia_guide_width: guardada,
  });
  const updateUISettings = vi.fn(novos => {
    uiSettings.value = { ...uiSettings.value, ...novos };
  });
  const largura = useLarguraDoGuia({
    aberto,
    embutido: false,
    larguraDaTela: ref(tela),
    uiSettings,
    updateUISettings,
  });
  return { aberto, updateUISettings, ...largura };
};

describe('larguraAoAbrir (#3184)', () => {
  it('soma ao painel antigo o que o menu devolve', () => {
    expect(larguraAoAbrir({ menu: 200, tela: 1440 })).toBe(464);
  });

  it('fica entre 400 e 520 px', () => {
    expect(larguraAoAbrir({ menu: 56, tela: 1440 })).toBe(400);
    expect(larguraAoAbrir({ menu: 320, tela: 1600 })).toBe(520);
  });
});

describe('useLarguraDoGuia (#3184)', () => {
  it('ao abrir, recolhe o menu e guarda a largura do Guia', async () => {
    const { aberto, updateUISettings, estilo } = montar();

    aberto.value = true;
    await nextTick();

    expect(updateUISettings).toHaveBeenCalledWith({
      sidebar_width: 56,
      autonomia_guide_width: 464,
    });
    expect(estilo.value).toEqual({ width: '464px' });
  });

  it('ao fechar, não reabre o menu', async () => {
    const { aberto, updateUISettings } = montar();
    aberto.value = true;
    await nextTick();
    updateUISettings.mockClear();

    aberto.value = false;
    await nextTick();

    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('com o menu já recolhido, mantém a largura guardada', async () => {
    const { aberto, updateUISettings, estilo } = montar({
      menu: 56,
      guardada: 480,
    });

    aberto.value = true;
    await nextTick();

    expect(updateUISettings).not.toHaveBeenCalled();
    expect(estilo.value).toEqual({ width: '480px' });
  });

  it('no celular o Guia ocupa a tela: nada muda no menu', async () => {
    const { aberto, updateUISettings, estilo } = montar({ tela: 390 });

    aberto.value = true;
    await nextTick();

    expect(updateUISettings).not.toHaveBeenCalled();
    expect(estilo.value).toEqual({});
  });

  it('no tablet encolhe para a tela do meio manter 320 px', async () => {
    const { aberto, estilo } = montar({ tela: 768 });

    aberto.value = true;
    await nextTick();

    // 768 - 56 (menu recolhido) - 320 = 392
    expect(estilo.value).toEqual({ width: '392px' });
  });

  it('com o menu reaberto no tablet, nunca fica menor que o painel antigo', async () => {
    const { aberto, updateUISettings, estilo } = montar({
      tela: 768,
      menu: 56,
      guardada: 520,
    });
    aberto.value = true;
    await nextTick();

    updateUISettings({ sidebar_width: 200 });
    await nextTick();

    expect(estilo.value).toEqual({ width: '320px' });
  });
});
