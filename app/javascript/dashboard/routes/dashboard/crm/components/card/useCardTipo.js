import { computed } from 'vue';
import { countsAsSale } from '../../helpers/cardOutcome';
import { ehCobranca } from '../funil/funil';

const HORA = 60;
const DIA = 24 * HORA;

// #1498 — o card fala do jeito do funil. Vender: "Negócio", valor e
// urgência. Atender: "Assunto", prioridade e há quanto tempo está aberto. No
// modelo Cobrança: valor a receber, vencimento e promessa de pagamento.
// `chave('NEGOCIO.TITULO')` devolve a frase de Cobrança ou de Assunto quando
// a camada tem a sua; o que não muda continua com o texto de sempre.
const PROPRIAS = {
  ASSUNTO: [
    'TELA',
    'TITULO',
    'TEXTO',
    'NOME',
    'TITULO_EXEMPLO',
    'TITULO_FALTA',
    'URGENCIA',
  ],
  COBRANCA: [
    'TITULO',
    'TEXTO',
    'NOME',
    'TITULO_EXEMPLO',
    'VALOR',
    'FECHAR_ATE',
    'PROMESSA',
    'PROMESSA_DICA',
  ],
};

export const useCardTipo = ({ t, funil }) => {
  const atender = computed(() => !countsAsSale(funil.value));
  const cobranca = computed(() => atender.value && ehCobranca(funil.value));
  const camadas = computed(() => [
    ...(cobranca.value ? ['COBRANCA'] : []),
    ...(atender.value ? ['ASSUNTO'] : []),
  ]);

  const chave = caminho => {
    const [parte, nome] = caminho.split('.');
    if (parte !== 'NEGOCIO') return caminho;
    const camada = camadas.value.find(item => PROPRIAS[item].includes(nome));
    return camada ? `${camada}.${nome}` : caminho;
  };
  const texto = (caminho, valores) => t(`CRM_CARD.${chave(caminho)}`, valores);

  // "3 dias", "5 horas", "20 minutos": desde que o card foi aberto.
  const tempoAberto = (desde, agora = new Date()) => {
    const inicio = new Date(desde);
    if (Number.isNaN(inicio.getTime())) return '';
    const minutos = Math.max(Math.floor((agora - inicio) / 60000), 1);
    if (minutos >= DIA) {
      const n = Math.floor(minutos / DIA);
      return t('CRM_CARD.TEMPO.DIAS', { n }, n);
    }
    if (minutos >= HORA) {
      const n = Math.floor(minutos / HORA);
      return t('CRM_CARD.TEMPO.HORAS', { n }, n);
    }
    return t('CRM_CARD.TEMPO.MINUTOS', { n: minutos }, minutos);
  };

  return { atender, cobranca, chave, texto, tempoAberto };
};
