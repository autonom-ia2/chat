import { flushPromises } from '@vue/test-utils';
import { DialogoFalso } from '../lista/dialogoFalso';
import { TeleportFalso } from '../lista/teleportFalso';

// Apoio dos testes da carteira de seguros (#2897): as peças falsas, o seletor
// pelas marcas `data-carteira` e o jeito de esperar a fonte da demonstração.
export { DialogoFalso, TeleportFalso };

export const daCarteira = nome => `[data-carteira="${nome}"]`;

// A fonte da demonstração responde depois de um instante (`esperar`: 300 ms
// quando é a própria tela que cria a fonte) e de um import dinâmico, e uma
// leitura costuma puxar outra (o seguro e depois o histórico). Com o relógio
// falso, dois passos maiores que esse atraso vencem a fila toda.
const PASSO_MS = 400;
const passo = async () => {
  await vi.advanceTimersByTimeAsync(PASSO_MS);
  await flushPromises();
};
export const assentar = async () => {
  await passo();
  await passo();
};

// Uma recusa do servidor, como a fonte a entrega às peças.
export const recusa = codigo =>
  Object.assign(new Error('recusado'), { name: 'RECUSADO', codigo });

// Carrega os módulos da demonstração antes do teste: o import dinâmico da
// fonte passa a resolver na hora.
export const carregarDemonstracao = async () => {
  await import('../../demo/base.js');
  await import('../../demo/carteira.js');
};

// O jsdom não rola a tela.
export const semRolagem = () => {
  Element.prototype.scrollIntoView = vi.fn();
};

export const textoDe = (peca, seletor) => peca.find(seletor).text();

// O meio-dia de um dia, em segundos, no relógio de quem roda o teste: é como
// as peças guardam `comeca` e `termina`.
const MEIO_DIA = 12;
const MS_POR_SEGUNDO = 1000;
export const aoMeioDia = (ano, mes, dia) =>
  new Date(ano, mes - 1, dia, MEIO_DIA).getTime() / MS_POR_SEGUNDO;

// Uma falha do servidor, como o axios a entrega.
export const erroHttp = (status, data = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data },
  });
