// #2897 — o seguro aberto mora no endereço (`?apolice=<id>`), e a renovação
// dele também (`?renovacao=<id do seguro>`): o link e o print abrem a gaveta
// direto. Abrir e fechar só trocam esse pedaço do endereço. As duas gavetas não
// ficam abertas juntas: abrir uma tira a outra do endereço.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const CHAVES = ['apolice', 'renovacao'];

export const useApoliceNaUrl = () => {
  const route = useRoute();
  const router = useRouter();

  const idEm = chave =>
    computed(() => {
      const id = Number(route.query?.[chave]);
      return Number.isInteger(id) && id > 0 ? id : null;
    });

  const semGaveta = () =>
    Object.fromEntries(
      Object.entries(route.query ?? {}).filter(
        ([chave]) => !CHAVES.includes(chave)
      )
    );
  const abrirEm = chave => id =>
    router.push({ query: { ...semGaveta(), [chave]: String(id) } });

  return {
    apolice: idEm('apolice'),
    renovacao: idEm('renovacao'),
    abrir: abrirEm('apolice'),
    abrirRenovacao: abrirEm('renovacao'),
    fechar: () => router.push({ query: semGaveta() }),
  };
};
