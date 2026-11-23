import { mount } from '@vue/test-utils';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import GuideResposta from '../GuideResposta.vue';
import { pedacosDaResposta } from '../graficosNaResposta';
import fonteDoEncaixe from '../graficosNaResposta.js?raw';

// #3158 (B8a) — o gráfico do relatório entra na resposta no lugar do marcador
// `[grafico:<id>]`. Sem marcador, vai para o fim: o gráfico nunca some.
const grafico = (id, titulo = `Gráfico ${id}`) => ({
  id,
  modo: 'ranking',
  titulo,
  medida: 'Conversas',
  de: '2026-10-01',
  ate: '2026-10-31',
  barras: [{ rotulo: 'Ana', valor: 1 }],
});

const tipos = pedacos =>
  pedacos.map(pedaco =>
    pedaco.tipo === 'grafico' ? `G${pedaco.grafico.id}` : pedaco.texto
  );

describe('pedacosDaResposta', () => {
  it('põe o gráfico no lugar do marcador, no meio do texto', () => {
    const pedacos = pedacosDaResposta(
      'Em outubro a Ana resolveu mais.\n\n[grafico:1]\n\nQuase um terço.',
      [grafico('1')]
    );

    expect(tipos(pedacos)).toEqual([
      'Em outubro a Ana resolveu mais.',
      'G1',
      'Quase um terço.',
    ]);
  });

  it('gráfico sem marcador vai para o fim da resposta', () => {
    const pedacos = pedacosDaResposta('A Ana resolveu mais. [grafico:1]', [
      grafico('1'),
      grafico('2'),
    ]);

    expect(tipos(pedacos)).toEqual(['A Ana resolveu mais.', 'G1', 'G2']);
  });

  it('marcador trocado pelo modelo sai do texto e o gráfico vai para o fim', () => {
    const pedacos = pedacosDaResposta('Veja: [grafico:7] e pronto.', [
      grafico('1'),
    ]);

    expect(tipos(pedacos)).toEqual(['Veja:  e pronto.', 'G1']);
  });

  it('o mesmo marcador duas vezes desenha o gráfico uma vez', () => {
    const pedacos = pedacosDaResposta('[grafico:1] e [grafico:1]', [
      grafico('1'),
    ]);

    expect(tipos(pedacos)).toEqual(['G1', 'e']);
  });

  it('sem gráfico, o texto fica como veio', () => {
    expect(tipos(pedacosDaResposta('São 3.', null))).toEqual(['São 3.']);
  });

  it('lê o marcador sem expressão regular', () => {
    expect(fonteDoEncaixe).not.toContain('RegExp');
    expect(fonteDoEncaixe).not.toContain('.match(');
    expect(fonteDoEncaixe).not.toContain('.replace(');
    expect(fonteDoEncaixe).not.toContain('.test(');
    expect(fonteDoEncaixe).toContain('indexOf');
  });
});

describe('GuideResposta', () => {
  const montar = props =>
    mount(GuideResposta, {
      props: { senderName: 'Guia', ...props },
      global: {
        plugins: [VueDOMPurifyHTML],
        mocks: { $t: key => key },
        stubs: {
          CopilotAssistantMessage: {
            props: ['message'],
            template:
              '<div data-mensagem-de-sempre>{{ message.content }}</div>',
          },
          GuideGrafico: {
            props: ['titulo', 'modo'],
            template: '<figure data-grafico>{{ titulo }}</figure>',
          },
        },
      },
    });

  it('sem gráfico, é a mensagem de sempre', () => {
    const wrapper = montar({ message: { content: 'São 3.' } });

    expect(wrapper.find('[data-mensagem-de-sempre]').text()).toBe('São 3.');
    expect(wrapper.find('[data-grafico]').exists()).toBe(false);
  });

  it('com gráfico, desenha no lugar do marcador e o que sobrou vai para o fim', () => {
    const wrapper = montar({
      message: { content: 'Antes. [grafico:1] Depois.' },
      graficos: [grafico('1', 'Resolvidas'), grafico('2', 'Sem marcador')],
    });

    const ordem = wrapper
      .findAll('[data-trecho], [data-grafico]')
      .map(item => item.text());
    expect(ordem).toEqual(['Antes.', 'Resolvidas', 'Depois.', 'Sem marcador']);
    expect(wrapper.text()).not.toContain('[grafico:');
    expect(wrapper.text()).toContain('Guia');
  });

  it('na resposta retida, o aviso fica e o gráfico aparece embaixo', () => {
    const wrapper = montar({
      message: { content: 'Não consegui responder agora.' },
      graficos: [grafico('1', 'Resolvidas')],
    });

    expect(
      wrapper.findAll('[data-trecho], [data-grafico]').map(item => item.text())
    ).toEqual(['Não consegui responder agora.', 'Resolvidas']);
  });

  it('sem texto, mostra o mesmo aviso da mensagem de sempre acima do gráfico', () => {
    const wrapper = montar({
      message: { content: '' },
      graficos: [grafico('1', 'Resolvidas')],
    });

    expect(wrapper.find('[data-sem-texto]').text()).toBe(
      'CAPTAIN.COPILOT.EMPTY_MESSAGE'
    );
    expect(wrapper.find('[data-grafico]').text()).toBe('Resolvidas');
  });
});
