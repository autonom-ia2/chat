// #2894 — o estado de carregamento de uma ficha: carregando, pronto, erro ou
// "não achei". `carregar` recebe a função que busca e devolve `false` quando a
// pessoa (ou empresa) não existe.
import { ref } from 'vue';

export const ESTADOS_DA_FICHA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
  NAO_ACHEI: 'naoAchei',
};

export const useEstadoDaFicha = () => {
  const estado = ref(ESTADOS_DA_FICHA.CARREGANDO);

  const carregar = async buscar => {
    estado.value = ESTADOS_DA_FICHA.CARREGANDO;
    try {
      const achou = await buscar();
      estado.value = achou
        ? ESTADOS_DA_FICHA.PRONTO
        : ESTADOS_DA_FICHA.NAO_ACHEI;
    } catch {
      estado.value = ESTADOS_DA_FICHA.ERRO;
    }
  };

  return { estado, carregar };
};
