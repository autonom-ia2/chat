import { mount } from '@vue/test-utils';
import FaixaDoPainel from '../components/desempenho/FaixaDoPainel.vue';
import SecaoAcoes from '../components/desempenho/resumo/SecaoAcoes.vue';
import demo from '../utils/desempenhoDemo.json';

// #2301 — o que a leitura automática muda na tela, com a demonstração inventada: "Lido até" na faixa
// e as sugestões de outro período com as datas delas.
describe('leitura automática na tela', () => {
  it('mostra "Lido até" no lugar de "Dados até" quando há leitura automática', () => {
    const comLeitura = mount(FaixaDoPainel, {
      props: {
        nome: 'Atendente',
        dadosAte: '2026-10-22T18:30',
        lidoAte: '2026-10-23T04:00',
      },
    });
    expect(comLeitura.find('[data-lido-ate]').exists()).toBe(true);
    expect(comLeitura.find('[data-dados-ate]').exists()).toBe(false);

    const semLeitura = mount(FaixaDoPainel, {
      props: { nome: 'Atendente', dadosAte: '2026-10-22T18:30' },
    });
    expect(semLeitura.find('[data-lido-ate]').exists()).toBe(false);
    expect(semLeitura.find('[data-dados-ate]').exists()).toBe(true);
  });

  it('diz as datas das sugestões quando elas são de outro período', () => {
    // O link da conversa precisa do roteador; aqui só importa a frase das datas.
    const global = { stubs: { LinkDaConversa: true } };
    const deOutras = mount(SecaoAcoes, {
      global,
      props: {
        painel: {
          ...demo,
          meta: {
            ...demo.meta,
            recomendacoes_de: { inicio: '2026-10-10', fim: '2026-10-16' },
          },
        },
      },
    });
    expect(deOutras.find('[data-acoes-outras-datas]').exists()).toBe(true);

    const doPeriodo = mount(SecaoAcoes, { global, props: { painel: demo } });
    expect(doPeriodo.find('[data-acoes-outras-datas]').exists()).toBe(false);
  });
});
