import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import FerramentasProntasAPI from 'dashboard/api/autonomia/ferramentasProntas';
import { chaveDoTexto, oferecida } from './catalogo';
import { useVitrine } from './useVitrine';
import { useVitrineLigada } from './useVitrineLigada';

// #2858 F3 — as ferramentas prontas com que o agente novo nasce. Quem escolhe é o Construtor (`ferramentas_sugeridas`
// da conversa, ou do agente num rascunho reaberto); lista vazia = "nenhuma combina". A Confira mostra "Já vem com
// estas ferramentas" com "Tirar", e o "Começar" inclui as que ficaram pelo endpoint da vitrine: a pessoa real e a
// permissão dela (o administrador ou a chave "Ferramentas dos agentes"). O que a pessoa tirou vira "Agora não" (o
// cartão da página do agente não oferece de volta). Quem não tem a chave vê uma frase dizendo que as ferramentas
// ficam para quem cuida delas, e o agente nasce sem elas. O que o agente já tem (rascunho reaberto depois do
// "Começar") não aparece de novo. As que vieram depois das 4 primeiras (`ferramentas_tambem`) ficam na linha "Também
// combina": "Incluir também" as junta ao "Já vem com", num toque, e elas entram no "Começar" como as outras.
// #2881 — agente pronto por ramo de seguro: a frase "Use quando" de cada ferramenta é a do ramo (ou a que o dono
// alterou), que a página lê do servidor e passa em `frases` ({ fonte: frase }). Sem frase para a fonte, vai a frase
// geral da vitrine, como sempre. No ramo, quem guarda o que o dono tirou é o servidor (aqui o `tirar` não é chamado).
// Por isso a página passa em `ficaramFora` as ferramentas que o dono tirou do "Já vem com" do modelo: no "Começar"
// elas viram "Agora não", como as tiradas. As do "Também combina" que nunca entraram continuam oferecidas.
//   agenteId, sugeridas, tambem, frases, ficaramFora: refs (ou computeds) da página.
export function useProntasDoConstrutor({
  agenteId,
  sugeridas,
  tambem,
  frases,
  ficaramFora,
}) {
  const { t } = useI18n();
  const vitrine = useVitrine();
  const { construtor, construtorNaConta } = useVitrineLigada();
  const tiradas = ref([]);
  const adicionadas = ref([]);

  const servem = lista =>
    construtorNaConta.value
      ? (lista || []).filter(
          id =>
            oferecida(id) &&
            !tiradas.value.includes(id) &&
            !vitrine.tem(agenteId.value, id)
        )
      : [];

  const escolhidas = computed(() => [
    ...new Set(servem([...(sugeridas.value || []), ...adicionadas.value])),
  ]);
  const combinaTambem = computed(() =>
    construtor.value
      ? servem(tambem?.value).filter(id => !escolhidas.value.includes(id))
      : []
  );

  const visiveis = computed(() => (construtor.value ? escolhidas.value : []));
  const semPermissao = computed(
    () => !construtor.value && escolhidas.value.length > 0
  );

  const tirar = id => {
    tiradas.value = [...tiradas.value, id];
  };

  const incluirTambem = () => {
    adicionadas.value = [...adicionadas.value, ...combinaTambem.value];
  };

  const dispensarTiradas = () =>
    Promise.allSettled(
      [...tiradas.value, ...(ficaramFora?.value || [])].map(id =>
        FerramentasProntasAPI.dispensar(agenteId.value, id)
      )
    );

  const incluir = id =>
    vitrine.incluir({
      fonte: id,
      agenteId: agenteId.value,
      usarQuando:
        frases?.value?.[id] ||
        t(`AGENTS.VITRINE.FERRAMENTAS.${chaveDoTexto(id)}.USE_QUANDO`),
    });

  // Inclui as que ficaram e o agente ainda não tem. -> as que não entraram (a tela avisa; a pessoa inclui depois). Sem
  // o agente ou sem a lista da vitrine, nenhuma entrou: a tela avisa em vez de seguir calada. O que a pessoa tirou é
  // dispensado antes de tudo, inclusive quando ela tirou todas ou a lista da vitrine falhou.
  const incluirTodas = async () => {
    if (!construtor.value) return [];
    const queria = [...visiveis.value];
    if (!agenteId.value) return queria;
    dispensarTiradas();
    if (!queria.length) return [];
    await vitrine.carregar();
    if (vitrine.erro.value) return queria;
    const faltam = queria.filter(
      id =>
        vitrine.fontes.value.includes(id) && !vitrine.tem(agenteId.value, id)
    );
    const resultados = await Promise.allSettled(faltam.map(incluir));
    const naoLiberadas = queria.filter(
      id => !vitrine.fontes.value.includes(id)
    );
    return [
      ...naoLiberadas,
      ...faltam.filter((_, indice) => resultados[indice].status === 'rejected'),
    ];
  };

  onMounted(() => {
    if (construtor.value) vitrine.carregar();
  });

  return {
    visiveis,
    semPermissao,
    escolhidas,
    combinaTambem,
    podeIncluir: construtor,
    tirar,
    incluirTambem,
    incluirTodas,
  };
}
