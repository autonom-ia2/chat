// #2899 (E6.4) — o caminho de "Trazer por PDFs", do envio ao pronto. Fala com a
// fonte (fonte/trazerPdfsFonte.js) e guarda o estado; as telas só desenham.
//
//   enviar → lendo (pergunta até o lote sair de "lendo") → conferir → trazendo
//   (pergunta pelo andamento) → pronto
//
// O lote em que a pessoa está fica no endereço (`?lote=`), para ela voltar a
// ele. Recusa do servidor vira a frase do código (carteira/recusas.js); falha
// de rede, a frase de sempre. Nada daqui guarda o que foi lido fora da tela.
import { ref } from 'vue';
import { chaveDaRecusa, codigoDaRecusa } from './recusas';

export const ETAPAS_DOS_PDFS = {
  ENVIAR: 'enviar',
  LENDO: 'lendo',
  CONFERIR: 'conferir',
  TRAZENDO: 'trazendo',
  PRONTO: 'pronto',
};
const PERGUNTA_MS = 2000;
const NAO_DEU = 'RELACIONAMENTOS_CARTEIRA.PDFS.NAO_DEU';
const ESTADO_DA_ETAPA = {
  lendo: ETAPAS_DOS_PDFS.LENDO,
  lida: ETAPAS_DOS_PDFS.CONFERIR,
  trazendo: ETAPAS_DOS_PDFS.TRAZENDO,
};

export const useLeituraDePdfs = (fonte, { aoMudarLote = () => {} } = {}) => {
  const etapa = ref(ETAPAS_DOS_PDFS.ENVIAR);
  const lote = ref(null);
  const andamento = ref(null);
  const erro = ref('');
  const ocupado = ref(false);
  let relogio = null;

  const parar = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  const falhou = falha => {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
  };

  const comAndamento = async id => {
    andamento.value = await fonte.andamento(id);
    if (andamento.value.estado === 'trazendo') {
      relogio = setTimeout(() => comAndamento(id).catch(falhou), PERGUNTA_MS);
      return;
    }
    etapa.value = ETAPAS_DOS_PDFS.PRONTO;
  };

  const comLote = async id => {
    const atual = await fonte.lote(id);
    lote.value = atual;
    etapa.value = ESTADO_DA_ETAPA[atual.estado] || ETAPAS_DOS_PDFS.PRONTO;
    if (etapa.value === ETAPAS_DOS_PDFS.LENDO) {
      relogio = setTimeout(() => comLote(id).catch(falhou), PERGUNTA_MS);
    } else if (etapa.value !== ETAPAS_DOS_PDFS.CONFERIR) {
      await comAndamento(id);
    }
  };

  const abrir = async id => {
    parar();
    erro.value = '';
    try {
      await comLote(id);
    } catch (falha) {
      falhou(falha);
      etapa.value = ETAPAS_DOS_PDFS.ENVIAR;
    }
  };

  const tentar = async pedido => {
    ocupado.value = true;
    erro.value = '';
    try {
      return await pedido();
    } catch (falha) {
      falhou(falha);
      return null;
    } finally {
      ocupado.value = false;
    }
  };

  const enviar = async arquivos => {
    const criado = await tentar(() => fonte.enviar(arquivos));
    if (!criado) return;
    aoMudarLote(criado.id);
    await abrir(criado.id);
  };

  const mudarItem = async (itemId, pedido) => {
    const conferir = await tentar(() =>
      fonte.mudarItem(lote.value.id, itemId, pedido)
    );
    if (conferir) lote.value = conferir;
  };

  const trazer = async () => {
    const pedido = await tentar(() => fonte.trazer(lote.value.id));
    if (!pedido) return;
    andamento.value = pedido;
    etapa.value = ETAPAS_DOS_PDFS.TRAZENDO;
    await comAndamento(lote.value.id).catch(falhou);
  };

  const recomecar = () => {
    parar();
    lote.value = null;
    andamento.value = null;
    erro.value = '';
    etapa.value = ETAPAS_DOS_PDFS.ENVIAR;
    aoMudarLote(null);
  };

  return {
    etapa,
    lote,
    andamento,
    erro,
    ocupado,
    abrir,
    enviar,
    mudarItem,
    trazer,
    recomecar,
    parar,
  };
};
