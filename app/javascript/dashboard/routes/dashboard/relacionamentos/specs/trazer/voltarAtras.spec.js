import { effectScope } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  leituraDeExemplo,
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarReabrir,
} from '../../demo/trazer';
import * as contagem from '../../trazer/contagem';
import { useTrazerLista } from '../../trazer/useTrazerLista';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import ProblemaDaLinha from '../../components/trazer/ProblemaDaLinha.vue';
import TelaConferir from '../../components/trazer/TelaConferir.vue';
// #2894 — "Voltar atrás" numa linha já resolvida ou deixada de fora: no
// cartão, no Conferir, na demonstração, na fonte e no estado da tela.
withFullI18n('pt_BR');

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

const problemaDe = (l, linha) => l.problemas.find(p => p.linha === linha);

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('Voltar atrás', () => {
  it('linha pronta ou deixada de fora ganha o botão, que emite a linha', async () => {
    const guardada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarConserto(leitura, 62, 'Ana'), 62) },
    });
    await marca(guardada, 'voltar-atras').trigger('click');
    expect(guardada.emitted('reabrir')).toEqual([[62]]);
    expect(marca(guardada, 'voltar-atras').text()).toBe('Voltar atrás');
    const deixada = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(aplicarDeixarDeFora(leitura, 62), 62) },
    });
    expect(marca(deixada, 'voltar-atras').exists()).toBe(true);
  });

  it('linha ainda aberta não tem Voltar atrás', () => {
    const w = mount(ProblemaDaLinha, {
      props: { problema: problemaDe(leitura, 62) },
    });
    expect(marca(w, 'voltar-atras').exists()).toBe(false);
  });

  it('a tela Conferir repassa o reabrir', async () => {
    const resolvida = aplicarDeixarDeFora(leitura, 62);
    const w = mount(TelaConferir, {
      props: {
        leitura: resolvida,
        resumo: contagem.resumoDaTela(resolvida),
        total: contagem.resumoDaTela(resolvida).entram,
      },
    });
    await w.getComponent(ProblemaDaLinha).vm.$emit('reabrir', 62);
    expect(w.emitted('reabrir')).toEqual([[62]]);
  });

  it('aplicarReabrir devolve a linha aberta, sem o valor corrigido', () => {
    const resolvida = aplicarConserto(leitura, 62, 'Ana');
    const nova = aplicarReabrir(resolvida, 62);
    expect(problemaDe(nova, 62)).toMatchObject({ estado: 'aberto' });
    expect(problemaDe(nova, 62).corrigido).toBeUndefined();
    expect(contagem.contarProblemas(nova.problemas).abertos).toBe(8);
    expect(contagem.resumoDaTela(nova).entram).toBe(195);
  });

  describe('na fonte e na tela', () => {
    beforeEach(() => esquecerMemoriaDaDemo());
    const fonte = () =>
      trazerFonte({
        demo: 'cheio',
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      });

    it('fonte.reabrir refaz os números', async () => {
      const f = fonte();
      const { id } = await f.ler(null);
      await f.deixarDeFora(id, 62);
      const nova = await f.reabrir(id, 62);
      expect(problemaDe(nova, 62).estado).toBe('aberto');
      expect(contagem.resumoDaTela(nova).precisamDeVoce).toBe(8);
    });

    // #2896, Fatia 2 — a fonte real já volta atrás; só não numa leitura que
    // ela não leu (trazerFonteReal.spec.js tem o resto).
    it('fonte real não volta atrás numa leitura que não leu', async () => {
      await expect(
        trazerFonte({ demo: null }).reabrir('x', 1)
      ).rejects.toMatchObject({ name: 'LEITURA_NAO_ENCONTRADA' });
    });

    it('useTrazerLista.reabrir troca a leitura e volta a contar', async () => {
      const escopo = effectScope();
      const tela = escopo.run(() =>
        useTrazerLista({ fonte: fonte(), avisar: vi.fn() })
      );
      await tela.usarExemplo();
      await tela.deixarDeFora(62);
      expect(tela.resumo.value.deixadas).toBe(1);
      await tela.reabrir(62);
      expect(tela.resumo.value.deixadas).toBe(0);
      expect(tela.resumo.value.precisamDeVoce).toBe(8);
      escopo.stop();
    });
  });
});
