import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { diaEMes } from '../utils/acharQuando';

// O nome sugerido da lista no Guardar lista: "{oQue} · {lugar} · {data}".
// Era montado uma vez, ao carregar a busca, e guardado pronto; se a língua do
// painel ainda não tinha chegado (o i18n começa em inglês e troca para a da
// conta depois), a data ficava no formato americano ("11/09" num 9 de
// novembro) e não mudava mais. Agora o nome é lido na hora, com a língua de
// agora; só o que a pessoa digita fica guardado, e vale no lugar do sugerido.
export function useNomeDaLista({ busca, hoje = () => new Date() }) {
  const { t, locale } = useI18n();
  const digitado = ref(null);
  // Outra busca na mesma tela volta ao nome sugerido dela.
  watch(
    () => busca.value?.id,
    () => {
      digitado.value = null;
    }
  );

  const sugerido = computed(() => {
    if (!busca.value) return '';
    return t('PROSPECTING_ACHAR.FOLHA.NOME_LISTA', {
      oQue: busca.value.oQue,
      lugar: busca.value.lugar.split(',')[0],
      data: diaEMes(hoje(), locale.value),
    });
  });

  return computed({
    get: () => digitado.value ?? sugerido.value,
    set: valor => {
      digitado.value = valor;
    },
  });
}
