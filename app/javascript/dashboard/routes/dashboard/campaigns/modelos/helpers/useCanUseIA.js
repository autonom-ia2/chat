import { computed } from 'vue';

// "Criar com IA", "Melhorar com IA" e a conferência inteligente são a entrega E
// (#1333). Os pontos de encaixe já estão na tela (EtapaObjetivo, EtapaTexto,
// ModeloCriarPage), escondidos enquanto isto responder false: nenhum botão
// aparece sem funcionar. A E troca esta resposta pela regra dela.
export function useCanUseIA() {
  return computed(() => false);
}
