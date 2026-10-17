import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import api from '../api/autorizacao';
import { localeDoIntl } from './datas';

// A autorização do dono para o sistema criar modelos (#1586): carrega, liga,
// desliga e formata preço e data. Data e hora no fuso da conta, com o rótulo
// que a plataforma mostra em Configurações (nunca o nome longo do Intl).
export function useAutorizacao() {
  const { locale } = useI18n();
  const { currentAccount } = useAccount();

  const estado = ref('carregando');
  const autorizacao = ref(null);

  const carregar = async () => {
    estado.value = 'carregando';
    try {
      autorizacao.value = await api.obterAutorizacao();
      estado.value = 'pronto';
    } catch {
      estado.value = 'erro';
    }
  };
  onMounted(carregar);

  // `marcas`: ['utility'] e/ou ['marketing']. A versão é a do aviso na tela:
  // se o preço mudou no meio, o servidor recusa (aviso_mudou) e nada é gravado.
  const mudar = async (acao, marcas) => {
    autorizacao.value = await api.mudar({
      acao,
      marcas,
      versao: autorizacao.value?.versao,
    });
  };

  const dinheiro = (preco, casas = 4) =>
    new Intl.NumberFormat(localeDoIntl(locale.value), {
      style: 'currency',
      currency: preco.moeda,
      minimumFractionDigits: 2,
      maximumFractionDigits: casas,
    }).format(preco.valor);

  const fuso = computed(() => fusoDaConta(currentAccount.value));

  const noFuso = (iso, opcoes) =>
    new Intl.DateTimeFormat(localeDoIntl(locale.value), {
      ...opcoes,
      ...(fuso.value ? { timeZone: fuso.value } : {}),
    }).format(new Date(iso));

  // Data sem hora (a vigência da tabela da Meta): o mesmo dia em qualquer fuso.
  const diaDaData = data =>
    new Intl.DateTimeFormat(localeDoIntl(locale.value), {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      timeZone: 'UTC',
    }).format(new Date(`${data}T00:00:00Z`));

  const quando = iso => ({
    dia: noFuso(iso, { day: '2-digit', month: '2-digit', year: 'numeric' }),
    hora: noFuso(iso, { hour: '2-digit', minute: '2-digit' }),
    fuso: rotuloDoFuso(fuso.value),
  });

  return {
    estado,
    autorizacao,
    carregar,
    mudar,
    dinheiro,
    quando,
    diaDaData,
  };
}
