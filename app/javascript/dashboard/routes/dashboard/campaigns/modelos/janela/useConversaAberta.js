import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import apiModelos from '../api/modelosWhatsapp';
import { localeDoIntl } from '../helpers/datas';
import api from './api/janela';

// Conversa aberta na campanha (#1335): quantas pessoas do público falaram com a
// caixa nas últimas 24 horas, o preço do modelo, o preço da mensagem escrita
// depois das grátis do mês e quantas grátis ainda restam neste número.
// `entrada` é um computed com { publicoId, caixaId, total, tipoDoModelo }.
export function useConversaAberta(entrada) {
  const { locale } = useI18n();
  const contagem = ref(null);
  const carregando = ref(false);
  const precoModelo = ref(null);
  const precoResposta = ref(null);
  const franquia = ref(null);

  const contar = async () => {
    const { publicoId, caixaId, total } = entrada.value;
    contagem.value = null;
    if (!publicoId || !caixaId || !total) return;
    carregando.value = true;
    try {
      contagem.value = await api.contarJanela({ publicoId, caixaId, total });
    } catch {
      contagem.value = null;
    } finally {
      carregando.value = false;
    }
  };

  // Sem tabela de preço ou sem franquia, o valor só não aparece.
  const lerPrecos = async () => {
    const { tipoDoModelo } = entrada.value;
    try {
      [precoModelo.value, precoResposta.value, franquia.value] =
        await Promise.all([
          tipoDoModelo ? apiModelos.custoPorEnvio(tipoDoModelo) : null,
          apiModelos.custoPorEnvio('resposta'),
          apiModelos.obterFranquia(),
        ]);
    } catch {
      precoModelo.value = null;
    }
  };

  watch(
    () => [entrada.value.publicoId, entrada.value.caixaId, entrada.value.total],
    contar,
    { immediate: true }
  );
  watch(() => entrada.value.tipoDoModelo, lerPrecos, { immediate: true });

  // Grátis que ainda restam neste número no mês.
  const gratisRestantes = computed(() => {
    if (!franquia.value) return null;
    const usadas =
      franquia.value.numeros.find(item => item.id === entrada.value.caixaId)
        ?.usadas || 0;
    return Math.max(franquia.value.limite - usadas, 0);
  });

  const dinheiro = (valor, casas = 2) =>
    new Intl.NumberFormat(localeDoIntl(locale.value), {
      style: 'currency',
      currency: precoModelo.value?.moeda || precoResposta.value?.moeda || 'BRL',
      maximumFractionDigits: casas,
    }).format(valor);

  // Mensagem escrita: grátis até acabar a franquia; o que passar paga a tarifa.
  const custoEscrita = quantos => {
    const pagas = Math.max(quantos - (gratisRestantes.value ?? quantos), 0);
    return pagas * (precoResposta.value?.valor || 0);
  };
  const custoModelo = quantos => quantos * (precoModelo.value?.valor || 0);

  return {
    contagem,
    carregando,
    precoModelo,
    precoResposta,
    gratisRestantes,
    dinheiro,
    custoEscrita,
    custoModelo,
    escrever: api.escrever,
  };
}
