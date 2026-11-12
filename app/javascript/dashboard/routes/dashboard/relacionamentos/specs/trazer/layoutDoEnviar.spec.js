import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import SoltarArquivo from '../../components/trazer/SoltarArquivo.vue';
import TelaEnviar from '../../components/trazer/TelaEnviar.vue';

// #2894 — o desenho da página e do Enviar que o jsdom não mede: o contêiner
// centrado com folga para o menu, a área de soltar o arquivo e o link de
// exemplo alinhado à borda dos outros blocos.
withFullI18n('pt_BR');

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

afterEach(() => {
  document.body.innerHTML = '';
});

describe('contêiner centrado e respiro embaixo', () => {
  it('a página e o conteúdo têm a mesma largura em toda etapa e folga para o menu', async () => {
    // jsdom não mede largura: confere as classes do contêiner no arquivo.
    const texto = (await import('../../pages/TrazerListaPage.vue?raw')).default;
    const inicio = texto.indexOf('data-relacionamentos="trazer-conteudo"');
    const conteudo = texto.slice(inicio, texto.indexOf('>', inicio));
    ['w-full', 'max-w-3xl', 'mx-auto', 'pb-24', 'md:pb-10'].forEach(classe => {
      expect(conteudo).toContain(classe);
    });
    expect(texto).not.toContain('max-w-4xl');
  });
});

describe('soltar arquivo', () => {
  it('foco por teclado tem anel e arrastar por cima enche a borda e o fundo', async () => {
    const w = mount(SoltarArquivo);
    const area = marca(w, 'soltar-arquivo');
    expect(area.classes()).toContain('focus-visible:outline-2');
    expect(area.classes()).toContain('focus-visible:outline-offset-2');
    await area.trigger('dragenter');
    expect(area.classes()).toEqual(
      expect.arrayContaining(['border-solid', 'border-n-blue-9', 'bg-n-blue-2'])
    );
    expect(area.classes()).not.toContain('border-dashed');
    await area.trigger('dragleave');
    expect(area.classes()).toContain('border-dashed');
  });
});

describe('alinhamento à borda esquerda dos outros blocos', () => {
  it('"Usar uma planilha de exemplo" não tem padding próprio', () => {
    const w = mount(TelaEnviar, { props: { mostrarExemplo: true } });
    const botao = marca(w, 'usar-exemplo');
    expect(botao.classes()).toEqual(
      expect.arrayContaining(['p-0', 'min-h-11', 'bg-transparent', 'border-0'])
    );
  });
});
