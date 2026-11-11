// #2894 — o estado de carregamento de uma ficha: carregando, pronto, erro ou
// "não achei". `carregar` recebe a função que busca e devolve `false` quando a
// pessoa (ou empresa) não existe. Cada pedido recebe `aindaVale()`: se saiu um
// pedido mais novo, a resposta velha é descartada e não mexe em nada.
import { ref } from 'vue';

export const ESTADOS_DA_FICHA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
  NAO_ACHEI: 'naoAchei',
};

// Ao sair da ficha o parâmetro da rota some e o id vira NaN: não é pedido.
export const idValido = id => Number.isInteger(id) && id > 0;

export const useEstadoDaFicha = () => {
  const estado = ref(ESTADOS_DA_FICHA.CARREGANDO);
  let ultimoPedido = 0;

  const carregar = async buscar => {
    ultimoPedido += 1;
    const meu = ultimoPedido;
    const aindaVale = () => meu === ultimoPedido;
    estado.value = ESTADOS_DA_FICHA.CARREGANDO;
    try {
      const achou = await buscar(aindaVale);
      if (!aindaVale()) return;
      estado.value = achou
        ? ESTADOS_DA_FICHA.PRONTO
        : ESTADOS_DA_FICHA.NAO_ACHEI;
    } catch {
      if (aindaVale()) estado.value = ESTADOS_DA_FICHA.ERRO;
    }
  };

  return { estado, carregar };
};
