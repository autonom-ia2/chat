import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { localeDoIntl } from '../helpers/datas';
import api from './api/janela';

// Conversa aberta na campanha (#1335): quantas pessoas do público falaram com a
// caixa nas últimas 24 horas, o preço do modelo, o da mensagem escrita depois
// das grátis do mês e quantas grátis ainda restam neste número. Tudo vem do
// endpoint próprio (não depende da tela de Modelos).
// `entrada` é um computed com { publicoId, caixaId, categoria }.
export function useConversaAberta(entrada) {
  const { locale } = useI18n();
  const contagem = ref(null);
  const carregando = ref(false);

  const contar = async () => {
    const { publicoId, caixaId, categoria } = entrada.value;
    if (!publicoId || !caixaId) {
      contagem.value = null;
      return;
    }
    // Recontagem mantém o número anterior na tela até o novo chegar.
    carregando.value = !contagem.value;
    try {
      contagem.value = await api.contarJanela({
        publicoId,
        caixaId,
        categoria,
      });
    } catch {
      contagem.value = null;
    } finally {
      carregando.value = false;
    }
  };

  // Outro público ou outra caixa: zera e conta de novo. Outro modelo: conta de
  // novo (o preço do modelo muda) mantendo o número na tela.
  watch(
    () => [entrada.value.publicoId, entrada.value.caixaId],
    () => {
      contagem.value = null;
      contar();
    },
    { immediate: true }
  );
  watch(() => entrada.value.categoria, contar);

  const precoModelo = computed(() => contagem.value?.precos.modelo || null);
  const precoResposta = computed(() => contagem.value?.precos.escrita || null);
  const limiteDaFranquia = computed(
    () => contagem.value?.franquia?.limite ?? null
  );
  const campos = computed(() => contagem.value?.campos || []);

  // Grátis que ainda restam neste número no mês.
  const gratisRestantes = computed(() => {
    const franquia = contagem.value?.franquia;
    if (!franquia) return null;
    return Math.max(franquia.limite - franquia.usadas, 0);
  });

  const dinheiro = (valor, casas = 2) =>
    new Intl.NumberFormat(localeDoIntl(locale.value), {
      style: 'currency',
      currency: precoModelo.value?.moeda || precoResposta.value?.moeda || 'BRL',
      maximumFractionDigits: casas,
    }).format(valor);

  // Mensagem escrita (contrato da #1322): grátis até acabar a franquia do mês
  // deste número; o que passar paga a tarifa de serviço. Sem a franquia lida,
  // conta tudo como pago (nunca promete grátis).
  const pagasNaEscrita = quantos =>
    Math.max(quantos - (gratisRestantes.value ?? 0), 0);
  const custoEscrita = quantos =>
    pagasNaEscrita(quantos) * (precoResposta.value?.valor || 0);
  const custoModelo = quantos => quantos * (precoModelo.value?.valor || 0);

  // O que a tela diz do custo da mensagem escrita para `quantos`: 'gratis'
  // (cabe nas que sobram), 'passa' (parte cobrada) ou 'sem_franquia'.
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

  const escrever = pedido =>
    api.escrever({
      publicoId: entrada.value.publicoId,
      caixaId: entrada.value.caixaId,
      categoria: entrada.value.categoria,
      ...pedido,
    });

  return {
    contagem,
    carregando,
    campos,
    precoModelo,
    precoResposta,
    gratisRestantes,
    limiteDaFranquia,
    dinheiro,
    pagasNaEscrita,
    custoEscrita,
    custoModelo,
    resumoDaEscrita,
    escrever,
  };
}
