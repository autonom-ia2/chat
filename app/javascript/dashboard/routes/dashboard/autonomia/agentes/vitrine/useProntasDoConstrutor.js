import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { chaveDoTexto, ferramentaPorId } from './catalogo';
import { useVitrine } from './useVitrine';
import { useVitrineLigada } from './useVitrineLigada';

// #2858 F3 — as ferramentas prontas com que o agente novo nasce. Quem escolhe é o Construtor (`ferramentas_sugeridas`
// da conversa, ou do agente num rascunho reaberto); lista vazia = "nenhuma combina". A Confira mostra "Já vem com
// estas ferramentas" com "Tirar", e o "Começar" inclui as que ficaram pelo endpoint da vitrine: a pessoa real e a
// permissão dela (o administrador ou a chave "Ferramentas dos agentes"). Quem não tem a chave vê uma frase dizendo que
// as ferramentas ficam para quem cuida delas, e o agente nasce sem elas.
//   agenteId, sugeridas: refs (ou computeds) da página.
export function useProntasDoConstrutor({ agenteId, sugeridas }) {
  const { t } = useI18n();
  const vitrine = useVitrine();
  const { construtor, construtorNaConta } = useVitrineLigada();
  const tiradas = ref([]);

  const escolhidas = computed(() =>
    construtorNaConta.value
      ? (sugeridas.value || []).filter(
          id => ferramentaPorId(id) && !tiradas.value.includes(id)
        )
      : []
  );

  const visiveis = computed(() => (construtor.value ? escolhidas.value : []));
  const semPermissao = computed(
    () => !construtor.value && escolhidas.value.length > 0
  );

  const tirar = id => {
    tiradas.value = [...tiradas.value, id];
  };

  // Inclui as que ficaram e o agente ainda não tem. -> as que falharam (a tela avisa; a pessoa inclui depois).
  const incluirTodas = async () => {
    if (!construtor.value || !agenteId.value) return [];
    await vitrine.carregar();
    const faltam = visiveis.value.filter(
      id =>
        vitrine.fontes.value.includes(id) && !vitrine.tem(agenteId.value, id)
    );
    const resultados = await Promise.allSettled(
      faltam.map(id =>
        vitrine.incluir({
          fonte: id,
          agenteId: agenteId.value,
          usarQuando: t(
            `AGENTS.VITRINE.FERRAMENTAS.${chaveDoTexto(id)}.USE_QUANDO`
          ),
        })
      )
    );
    return faltam.filter(
      (_, indice) => resultados[indice].status === 'rejected'
    );
  };

  return { visiveis, semPermissao, escolhidas, tirar, incluirTodas };
}
