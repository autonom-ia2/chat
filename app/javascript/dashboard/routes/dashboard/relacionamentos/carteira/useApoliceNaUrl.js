// #2897 — o seguro aberto mora no endereço (`?apolice=<id>`): o link e o print
// abrem a gaveta direto. Abrir e fechar só trocam esse pedaço do endereço.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';

export const useApoliceNaUrl = () => {
  const route = useRoute();
  const router = useRouter();

  const apolice = computed(() => {
    const id = Number(route.query?.apolice);
    return Number.isInteger(id) && id > 0 ? id : null;
  });

  const semApolice = () =>
    Object.fromEntries(
      Object.entries(route.query ?? {}).filter(([chave]) => chave !== 'apolice')
    );

  return {
    apolice,
    abrir: id =>
      router.push({ query: { ...semApolice(), apolice: String(id) } }),
    fechar: () => router.push({ query: semApolice() }),
  };
};
