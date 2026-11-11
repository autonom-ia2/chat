import { quemRecebe } from './quemFicaDeFora';

// #2894 — "Vânia, Nádia e Bruno vão receber." Até 5 nomes; de 6 em diante, dois
// nomes e o resto em número ("Vânia, Nádia e mais 40"). A lista usa o jeito de
// juntar do idioma da tela (`Intl.ListFormat`).
const NOMES_A_MOSTRAR = 5;
const NOMES_DEPOIS_DE_CORTAR = 2;

const primeiroNome = nome =>
  String(nome ?? '')
    .trim()
    .split(' ')[0];

const juntar = (nomes, { idioma, eMais }) => {
  const itens =
    nomes.length > NOMES_A_MOSTRAR
      ? [
          ...nomes.slice(0, NOMES_DEPOIS_DE_CORTAR),
          eMais(nomes.length - NOMES_DEPOIS_DE_CORTAR),
        ]
      : nomes;
  return new Intl.ListFormat(idioma, {
    style: 'long',
    type: 'conjunction',
  }).format(itens);
};

export const nomesQueRecebem = (pessoas, opcoes) =>
  juntar(
    quemRecebe(pessoas).map(({ name }) => primeiroNome(name)),
    opcoes
  );

// Nomes de quem fica de fora por um motivo (poucos: não precisa de "e mais").
export const nomesDe = (pessoas, opcoes) =>
  juntar(
    pessoas.map(({ name }) => primeiroNome(name)),
    opcoes
  );
