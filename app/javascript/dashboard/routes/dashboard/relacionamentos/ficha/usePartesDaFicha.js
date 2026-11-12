// #2895 — as partes da ficha que vêm em leituras separadas (conversas, cards,
// notas...). Cada uma guarda o próprio resultado: a que falha fica vazia e diz
// como falhou (ficha/falhas.js), sem derrubar a ficha nem as outras partes.
//   leitores: { nome: () => Promise } — uma leitura por parte;
//   vazias:   { nome: valor } — o que a parte vale enquanto não veio;
//   geracao:  a de useEstadoDaFicha, para a resposta de uma ficha não entrar em
//             outra.
import { ref } from 'vue';
import { falhaDaParte } from './falhas';

export const usePartesDaFicha = ({ leitores, vazias, geracao }) => {
  const nomes = Object.keys(leitores);
  const valores = ref(vazias);
  const falhas = ref({});

  const ler = async nome => {
    try {
      return { valor: await leitores[nome](), falha: '' };
    } catch (falha) {
      return { valor: vazias[nome], falha: falhaDaParte(falha) };
    }
  };

  const lerTodas = () => Promise.all(nomes.map(ler));

  const guardarTodas = lidas => {
    valores.value = Object.fromEntries(
      nomes.map((nome, posicao) => [nome, lidas[posicao].valor])
    );
    falhas.value = Object.fromEntries(
      nomes.map((nome, posicao) => [nome, lidas[posicao].falha])
    );
  };

  const trocar = (nome, valor) => {
    valores.value = { ...valores.value, [nome]: valor };
  };

  // "Tentar de novo" de uma parte só. Nunca rejeita: a falha fica na parte.
  const reler = async nome => {
    const geracaoDoPedido = geracao();
    const lida = await ler(nome);
    if (geracaoDoPedido !== geracao()) return;
    trocar(nome, lida.valor);
    falhas.value = { ...falhas.value, [nome]: lida.falha };
  };

  return { valores, falhas, lerTodas, guardarTodas, trocar, reler };
};
