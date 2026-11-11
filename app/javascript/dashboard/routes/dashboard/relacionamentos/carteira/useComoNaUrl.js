// #2897 — como a pessoa quer trazer mora no endereço (`?como=planilha|pdfs|
// agger`): o link e o print abrem direto no passo, e o Voltar do navegador
// devolve à escolha. Mudar só troca esse pedaço do endereço.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { comoValido } from './passosDeTrazerSeguros';

export const useComoNaUrl = () => {
  const route = useRoute();
  const router = useRouter();

  const como = computed(() => comoValido(route.query?.como));

  const semComo = () =>
    Object.fromEntries(
      Object.entries(route.query ?? {}).filter(([chave]) => chave !== 'como')
    );

  return {
    como,
    mudar: valor =>
      router.push({
        query: valor ? { ...semComo(), como: valor } : semComo(),
      }),
  };
};
