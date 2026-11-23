import { ref } from 'vue';
import { lerPrograma } from './fonte';

// #3100 — o cartão fidelidade da conta para quem só precisa dele de passagem
// (o passo "Dar carimbos ou pontos" e a frase dele na Automação livre). Lido
// uma vez por tela; o erro (ou quem não pode ver o cartão) deixa "sem cartão",
// e a próxima abertura tenta de novo.
const programa = ref(null);
let lido = null;

export const programaDaConta = () => programa.value;

export const carregarProgramaDaConta = () => {
  lido ||= lerPrograma()
    .then(dado => {
      programa.value = dado || null;
      return programa.value;
    })
    .catch(() => {
      lido = null;
      programa.value = null;
      return null;
    });
  return lido;
};

// Depois de criar ou mudar o cartão em outra aba, a próxima leitura vai ao
// servidor de novo.
export const esquecerProgramaDaConta = () => {
  lido = null;
  programa.value = null;
};
