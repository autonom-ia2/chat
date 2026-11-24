import { ref } from 'vue';
import {
  menuEGuia,
  recolherParaOGuia,
} from 'dashboard/components-next/sidebar/menuEGuia';
import { larguraDoGuia, useLarguraDoGuia } from '../useLarguraDoGuia';

const montar = ({
  tela = 1440,
  menu = 56,
  devolvida = 0,
  embutido = false,
}) => {
  menuEGuia.largura.value = menu;
  menuEGuia.devolvida.value = devolvida;
  return useLarguraDoGuia({ embutido, larguraDaTela: ref(tela) });
};

afterEach(() => {
  menuEGuia.largura.value = 0;
  menuEGuia.devolvida.value = 0;
});

describe('larguraDoGuia (#3184)', () => {
  it('soma ao painel antigo o que o menu devolveu', () => {
    // menu novo: 256 - 56 = 200 devolvidos; 320 + 200 = 520
    expect(larguraDoGuia({ tela: 1440, menu: 56, devolvida: 200 })).toBe(520);
    // menu de sempre: 200 - 56 = 144 devolvidos; 320 + 144 = 464
    expect(larguraDoGuia({ tela: 1440, menu: 56, devolvida: 144 })).toBe(464);
  });

  it('com o menu recolhido desde antes, abre com 400', () => {
    expect(larguraDoGuia({ tela: 1440, menu: 56, devolvida: 0 })).toBe(400);
  });

  it('nunca passa de 520', () => {
    expect(larguraDoGuia({ tela: 1600, menu: 56, devolvida: 264 })).toBe(520);
  });

  it('no tablet encolhe para a tela do meio manter 320 px', () => {
    // 768 - 56 - 320 = 392
    expect(larguraDoGuia({ tela: 768, menu: 56, devolvida: 0 })).toBe(392);
  });

  it('com o menu reaberto no tablet, fica no piso do painel antigo', () => {
    expect(larguraDoGuia({ tela: 768, menu: 200, devolvida: 200 })).toBe(320);
  });
});

describe('useLarguraDoGuia (#3184)', () => {
  it('na coluna, a largura vem do menu', () => {
    const { estilo } = montar({ devolvida: 200 });
    expect(estilo.value).toEqual({ width: '520px' });
  });

  it('acompanha o menu: reabrir o menu encolhe o Guia se não couber', () => {
    const { estilo } = montar({ tela: 1024, devolvida: 200 });
    // 1024 - 56 - 320 = 648 de teto; alvo 520
    expect(estilo.value).toEqual({ width: '520px' });

    menuEGuia.largura.value = 256;

    // 1024 - 256 - 320 = 448
    expect(estilo.value).toEqual({ width: '448px' });
  });

  it('no celular e no modo embutido não dá largura', () => {
    expect(montar({ tela: 390 }).estilo.value).toEqual({});
    expect(montar({ embutido: true }).estilo.value).toEqual({});
  });
});

describe('recolherParaOGuia (#3184)', () => {
  it('recolhe o menu e guarda quanto devolveu, sem tocar nas preferências', () => {
    const sidebarWidth = ref(256);

    recolherParaOGuia({ sidebarWidth, recolhido: false, celular: false });

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(200);
  });

  it('menu já recolhido: nada muda e a última devolvida continua', () => {
    menuEGuia.devolvida.value = 144;
    const sidebarWidth = ref(56);

    recolherParaOGuia({ sidebarWidth, recolhido: true, celular: false });

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(144);
  });

  it('no celular o menu é gaveta: não mexe', () => {
    const sidebarWidth = ref(256);

    recolherParaOGuia({ sidebarWidth, recolhido: false, celular: true });

    expect(sidebarWidth.value).toBe(256);
  });
});
