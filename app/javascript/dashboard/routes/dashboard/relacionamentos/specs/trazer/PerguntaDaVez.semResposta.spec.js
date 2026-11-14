import { effectScope } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import { useTrazerLista } from '../../trazer/useTrazerLista';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import PerguntaDaVez from '../../components/trazer/PerguntaDaVez.vue';
// #2894 — a pergunta de clientes nasce sem resposta: nada vem marcado, e o
// Continuar (sempre ligado) diz o que falta.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  esquecerMemoriaDaDemo();
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('pergunta de clientes nasce sem resposta', () => {
  it('nenhuma opção marcada e Continuar ligado, que diz o que falta', async () => {
    const w = mount(PerguntaDaVez, {
      props: {
        pergunta: { id: 'clientes' },
        respostas: {},
        colunas: leitura.colunas,
        podeContinuar: false,
      },
    });
    expect(w.findAll('[aria-checked="true"]')).toHaveLength(0);
    expect(w.findAll('[role="radio"]').length).toBe(3);
    expect(marca(w, 'continuar').attributes('disabled')).toBeUndefined();
    await marca(w, 'continuar').trigger('click');
    expect(w.emitted('continuar')).toBeUndefined();
    expect(w.get('[role="alert"]').text()).toBe('Escolha uma das respostas.');
  });

  it('na tela, depois de ler a planilha, nada vem marcado e o composable não deixa continuar', async () => {
    const escopo = effectScope();
    const tela = escopo.run(() =>
      useTrazerLista({
        fonte: trazerFonte({
          demo: 'cheio',
          carregarDemo: () => import('../../demo/trazer.js'),
          atraso: 0,
          atrasoDaLeitura: 0,
        }),
        avisar: vi.fn(),
      })
    );
    await tela.usarExemplo();
    expect(tela.respostas.value).toEqual({});
    expect(tela.podeContinuar.value).toBe(false);
    escopo.stop();
  });
});
