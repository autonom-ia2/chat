import { computed, ref } from 'vue';
import { RESULTADOS } from './catalogo';

// #2776 — ADAPTADOR FALSO do protótipo. Nada vai ao servidor: o que foi incluído em cada agente fica no navegador
// (localStorage), para a jornada atravessar páginas. Quando a vitrine virar produto, este arquivo troca pela API; as
// telas não mudam. A chave interna da conta (decisão 3 do Rodrigo) é da plataforma e nunca aparece aqui.
const GUARDA = 'autonomia-vitrine-prototipo';
const ESPERA_DO_TESTE = 700;

const ler = () => {
  try {
    return JSON.parse(window.localStorage.getItem(GUARDA) || '{}');
  } catch {
    return {};
  }
};

const incluidas = ref(ler());

const gravar = proximo => {
  incluidas.value = proximo;
  try {
    window.localStorage.setItem(GUARDA, JSON.stringify(proximo));
  } catch {
    // Sem armazenamento (janela privada): o protótipo segue só nesta página.
  }
};

const doAgente = agenteId => incluidas.value[String(agenteId)] || [];

const trocarDoAgente = (agenteId, lista) =>
  gravar({ ...incluidas.value, [String(agenteId)]: lista });

export const useVitrine = () => {
  const naoTem = (agenteId, ferramentaId) =>
    !doAgente(agenteId).some(item => item.id === ferramentaId);

  const incluir = (agenteId, ferramentaId, useQuando) => {
    if (!naoTem(agenteId, ferramentaId)) return;
    trocarDoAgente(agenteId, [
      ...doAgente(agenteId),
      { id: ferramentaId, useQuando, ligada: true },
    ]);
  };

  const mudarLigada = (agenteId, ferramentaId, ligada) =>
    trocarDoAgente(
      agenteId,
      doAgente(agenteId).map(item =>
        item.id === ferramentaId ? { ...item, ligada } : item
      )
    );

  const tirar = (agenteId, ferramentaId) =>
    trocarDoAgente(
      agenteId,
      doAgente(agenteId).filter(item => item.id !== ferramentaId)
    );

  // O "Experimente": o resultado fictício do catálogo, depois de uma espera curta, como uma consulta de verdade.
  const experimentar = ferramentaId =>
    new Promise(resolve => {
      window.setTimeout(
        () => resolve(RESULTADOS[ferramentaId] || []),
        ESPERA_DO_TESTE
      );
    });

  return {
    doAgente,
    tem: (agenteId, ferramentaId) => !naoTem(agenteId, ferramentaId),
    incluir,
    mudarLigada,
    tirar,
    experimentar,
    incluidas: computed(() => incluidas.value),
  };
};
