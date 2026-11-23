import { ref } from 'vue';
import { lerCupons } from './fonte';

// #3100 — os cupons da conta para quem só precisa deles de passagem (o passo
// "Mandar cupom" e a frase dele na Automação livre). Lidos uma vez por tela; o
// erro (ou quem não pode ver os cupons) deixa a lista vazia, e a próxima
// abertura tenta de novo. O mesmo jeito de programaDaConta.js.
const cupons = ref([]);
let lido = null;

export const cuponsDaConta = () => cupons.value;
export const cupomDaConta = id =>
  cupons.value.find(cupom => cupom.id === id) || null;

export const carregarCuponsDaConta = () => {
  lido ||= lerCupons()
    .then(dados => {
      cupons.value = Array.isArray(dados) ? dados : [];
      return cupons.value;
    })
    .catch(() => {
      lido = null;
      cupons.value = [];
      return [];
    });
  return lido;
};

// Depois de criar um cupom em outra aba, a próxima leitura vai ao servidor.
export const esquecerCuponsDaConta = () => {
  lido = null;
  cupons.value = [];
};
