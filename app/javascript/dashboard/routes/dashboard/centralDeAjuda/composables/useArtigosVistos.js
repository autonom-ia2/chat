import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

// Artigos da Central que a pessoa já abriu ("10.01"), no perfil dela: vale em todos os aparelhos e o
// assunto mostra o que falta ver. O mais novo fica no fim; passando do limite, saem os mais antigos.
// Id de artigo que deixou de existir pode ficar: o limite segura o tamanho.
export const LIMITE_DE_VISTOS = 500;
const CHAVE = 'central_de_ajuda_vistos';

export function useArtigosVistos() {
  const { uiSettings, updateUISettings } = useUISettings();

  const lista = computed(() => {
    const salvo = uiSettings.value?.[CHAVE];
    return Array.isArray(salvo) ? salvo : [];
  });
  const vistos = computed(() => new Set(lista.value));

  const foiVisto = id => vistos.value.has(id);

  // Já visto não grava de novo: cada abertura de artigo viraria um PUT à toa.
  // Limite conhecido: o perfil troca as ui_settings inteiras a cada PUT. Dois PUTs em voo (abrir A e
  // logo B) que o servidor grave fora de ordem perdem o mais novo, como em toda ui_setting.
  const marcarVisto = id => {
    if (!id || foiVisto(id)) return;
    updateUISettings({
      [CHAVE]: [...lista.value, id].slice(-LIMITE_DE_VISTOS),
    });
  };

  return { vistos, foiVisto, marcarVisto };
}
