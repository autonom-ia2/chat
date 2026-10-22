import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import CrmNumerosAPI from 'dashboard/api/crmNumeros';
import { P, comMaiuscula, nomeDoMes } from './numerosTextos';

// Os números "Só eu" de um mês (#1897): o mês vem do endereço (?mes=AAAA-MM) e
// só a última resposta vale (trocar de mês depressa não deixa a antiga por cima).
// `visao`: 'equipe' pede a visão "Equipe" (#1992); vazia, a "Só eu".
export function useNumerosDoMes({ t, locale, visao }) {
  const route = useRoute();
  const router = useRouter();
  const { currentAccount } = useAccount();

  const dados = ref(null);
  const carregando = ref(true);
  const falhou = ref(false);
  const mes = computed(() => route.query.mes || undefined);

  let pedido = 0;
  const carregar = async () => {
    pedido += 1;
    const este = pedido;
    carregando.value = true;
    falhou.value = false;
    try {
      const { data } = await CrmNumerosAPI.show({ mes: mes.value, visao });
      if (este === pedido) dados.value = data;
    } catch {
      if (este === pedido) falhou.value = true;
    } finally {
      if (este === pedido) carregando.value = false;
    }
  };
  watch(mes, carregar, { immediate: true });

  const irParaMes = chave =>
    router.replace({ query: { ...route.query, mes: chave } });

  const fuso = computed(() => fusoDaConta(currentAccount.value));
  const nomeMes = chave =>
    chave ? nomeDoMes(chave, { locale: locale(), fuso: fuso.value }) : '';
  const mesNome = computed(() => nomeMes(dados.value?.mes?.chave));
  const rotuloDoMes = computed(() => {
    const info = dados.value?.mes;
    if (!info) return '';
    const nome = comMaiuscula(mesNome.value);
    return info.fechado
      ? t(`${P}.MES.FECHADO`, { mes: nome })
      : t(
          `${P}.MES.ATUAL`,
          { mes: nome, n: info.diasRestantes },
          info.diasRestantes
        );
  });

  return {
    dados,
    carregando,
    falhou,
    carregar,
    irParaMes,
    fuso,
    nomeMes,
    mesNome,
    rotuloDoMes,
  };
}
