import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import api from '../api/modelosWhatsapp';
import { localeDoIntl } from './datas';

// Custo por envio de cada tipo, já em reais, para comparar sem disfarçar
// ("divulgação custa X, contra Y do aviso de serviço").
const TIPOS = ['aviso', 'divulgacao'];

export function useCustos() {
  const { locale } = useI18n();
  const custos = ref({});

  // Sem tabela de preço (ou sem permissão para ler), o custo só não aparece.
  onMounted(async () => {
    try {
      const valores = await Promise.all(
        TIPOS.map(tipo => api.custoPorEnvio(tipo))
      );
      custos.value = Object.fromEntries(
        TIPOS.map((tipo, indice) => [tipo, valores[indice]])
      );
    } catch {
      custos.value = {};
    }
  });

  const emReais = tipo => {
    const custo = custos.value[tipo];
    if (!custo) return '';
    return new Intl.NumberFormat(localeDoIntl(locale.value), {
      style: 'currency',
      currency: custo.moeda,
      maximumFractionDigits: 4,
    }).format(custo.valor);
  };

  return { custos, emReais };
}
