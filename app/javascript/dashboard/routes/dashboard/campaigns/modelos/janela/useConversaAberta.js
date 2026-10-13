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
    if (!publicoId || !caixaId || !total) {
      contagem.value = null;
      return;
    }
    // Recontagem (ex.: o total do público chegou depois) mantém o número
    // anterior na tela até o novo chegar: a gaveta aberta não cai para zero.
    carregando.value = !contagem.value;
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

  // Outro público ou outra caixa: zera e conta de novo. Só o total mudou:
  // conta de novo mantendo o número na tela.
  watch(
    () => [entrada.value.publicoId, entrada.value.caixaId],
    () => {
      contagem.value = null;
      contar();
    },
    { immediate: true }
  );
  watch(() => entrada.value.total, contar);
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

  const limiteDaFranquia = computed(() => franquia.value?.limite ?? null);

  // Mensagem escrita (contrato da #1322, Whatsapp::Pricing.free_tier): grátis
  // até acabar a franquia do mês deste número; o que passar paga a tarifa de
  // serviço. Sem a franquia lida, conta tudo como pago (nunca promete grátis).
  const pagasNaEscrita = quantos =>
    Math.max(quantos - (gratisRestantes.value ?? 0), 0);
  const custoEscrita = quantos =>
    pagasNaEscrita(quantos) * (precoResposta.value?.valor || 0);
  const custoModelo = quantos => quantos * (precoModelo.value?.valor || 0);

  // O que a tela diz sobre o custo da mensagem escrita para `quantos`:
  // 'gratis' (cabe nas que sobram), 'passa' (parte cobrada) ou 'sem_franquia'.
  const resumoDaEscrita = quantos => {
    const sobram = gratisRestantes.value;
    const base = {
      sobram,
      limite: limiteDaFranquia.value,
      pagas: pagasNaEscrita(quantos),
      gratis: Math.min(quantos, sobram ?? 0),
      valor: dinheiro(custoEscrita(quantos)),
      preco: precoResposta.value ? dinheiro(precoResposta.value.valor, 4) : '',
    };
    if (sobram == null) return { ...base, tipo: 'sem_franquia' };
    return { ...base, tipo: quantos <= sobram ? 'gratis' : 'passa' };
  };

  return {
    contagem,
    carregando,
    precoModelo,
    precoResposta,
    gratisRestantes,
    limiteDaFranquia,
    dinheiro,
    pagasNaEscrita,
    custoEscrita,
    custoModelo,
    resumoDaEscrita,
    escrever: api.escrever,
  };
}
