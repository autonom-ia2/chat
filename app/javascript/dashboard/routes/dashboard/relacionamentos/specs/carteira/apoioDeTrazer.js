import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';
import { esquecerAjustesDaDemo } from '../../demo/carteiraAjustes';
import { usarDemo } from '../../fonte/modoDemo';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { esquecerTrazerSeguros } from '../../fonte/trazerSegurosFonte';
import { daCarteira } from './apoio';

// Apoio dos testes de "trazer seguros" (#2897, telas 8, 9, 16 e 17): a página
// de verdade, com a demonstração entrando pelo endereço e o relógio do teste
// (a leitura dos PDFs, a busca no Agger e o andamento dependem da hora).
export const AGORA = Date.UTC(2026, 10, 11, 15);

export const ligarRelogio = () => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
};

// O tempo anda e as respostas da fonte chegam.
export const passar = async ms => {
  await vi.advanceTimersByTimeAsync(ms);
  await flushPromises();
};
const UM_INSTANTE_MS = 40;
export const assentarBem = async () => {
  await passar(UM_INSTANTE_MS);
  await passar(UM_INSTANTE_MS);
  await passar(UM_INSTANTE_MS);
};

export const carregarDemonstracaoDeTrazer = () =>
  Promise.all([
    import('../../demo/base.js'),
    import('../../demo/carteira.js'),
    import('../../demo/trazer.js'),
    import('../../demo/trazerSeguros.js'),
  ]);

let aberta = null;

// `rota` é a rota falsa do teste (reativa): a demonstração e o jeito de trazer
// entram por ela, como no navegador.
export const abrirTrazer = async (rota, query = {}) => {
  rota.name = 'relacionamentos_trazer';
  rota.query = { demo: 'sem-seguros', ...query };
  aberta = mount(TrazerListaPage, {
    attachTo: document.body,
    global: { stubs: { RouterLink: RouterLinkStub, transition: true } },
  });
  await assentarBem();
  return aberta;
};

export const fecharTrazer = () => {
  aberta?.unmount();
  aberta = null;
  esquecerMemoriaDaDemo();
  esquecerTrazerSeguros();
  esquecerAjustesDaDemo();
  usarDemo({ demo: 'desligado' });
};

export const clicar = async (w, nome) => {
  await w.get(daCarteira(nome)).trigger('click');
  await assentarBem();
};

// Na primeira vez que a conta traz seguros, antes de conferir vem "Onde ficam
// as renovações?". O padrão já vem respondido: é só continuar.
export const passarPelasRenovacoes = w => clicar(w, 'continuar-renovacoes');

export const contador = (w, chave) =>
  w
    .get(`${daCarteira('contadores')} [data-contador="${chave}"] .sr-only`)
    .text();

export const problema = (w, linha) =>
  w.get(`[data-relacionamentos="precisam-de-voce"] [data-linha="${linha}"]`);

export const emFoco = () => document.activeElement;
