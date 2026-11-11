// #2894 — o estado de carregamento de uma ficha: carregando, pronto, erro, "não
// achei" ou "sem acesso". `carregar` recebe a função que busca e devolve `false`
// quando a pessoa (ou empresa) não existe. Cada pedido recebe `aindaVale()`: se
// saiu um pedido mais novo, a resposta velha é descartada e não mexe em nada.
// Quando a busca falha, o nome do erro (ficha/falhas.js) escolhe o estado.
import { ref } from 'vue';
import { NAO_ACHEI, SEM_ACESSO } from './falhas';

export const ESTADOS_DA_FICHA = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
  NAO_ACHEI: 'naoAchei',
  SEM_ACESSO: 'semAcesso',
};

const ESTADO_DA_FALHA = new Map([
  [NAO_ACHEI, ESTADOS_DA_FICHA.NAO_ACHEI],
  [SEM_ACESSO, ESTADOS_DA_FICHA.SEM_ACESSO],
]);

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
    } catch (falha) {
      if (!aindaVale()) return;
      estado.value = ESTADO_DA_FALHA.get(falha?.name) ?? ESTADOS_DA_FICHA.ERRO;
    }
  };

  // A geração muda a cada `carregar`: quem faz uma escrita guarda a de antes e
  // confere depois (se o id trocou no meio, a resposta velha não vale).
  const geracao = () => ultimoPedido;

  return { estado, carregar, geracao };
};
