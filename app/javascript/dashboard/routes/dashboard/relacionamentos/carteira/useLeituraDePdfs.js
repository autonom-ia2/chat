// #2899 (E6.4) — o caminho de "Trazer por PDFs", do envio ao pronto. Fala com a
// fonte (fonte/trazerPdfsFonte.js) e guarda o estado; as telas só desenham.
//
//   enviar → lendo (pergunta até o lote sair de "lendo") → conferir → trazendo
//   (pergunta pelo andamento) → pronto
//
// O lote em que a pessoa está fica no endereço (`?lote=`), para ela voltar a
// ele. Recusa do servidor vira a frase do código (carteira/recusas.js); falha
// de rede, a frase de sempre. Nada daqui guarda o que foi lido fora da tela.
//
// Quando o acompanhamento falha (`semAcompanhar`) ou o lote para de andar
// (`parado`, o mesmo prazo em que o servidor aceita pôr a gravação na fila de
// novo), a tela mostra "Tentar de novo": `tentarDeNovo` retoma a leitura do
// mesmo lote, ou pede o "Trazer" outra vez (o servidor é idempotente).
// Enquanto envia, um segundo envio é ignorado: duas arrastadas seguidas nunca
// criam dois lotes.
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
const PARADO_MS = 10 * 60 * 1000;
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
  // O acompanhamento (da leitura ou da gravação) falhou: a pessoa decide tentar.
  const semAcompanhar = ref(false);
  // O lote está trazendo e não anda há tempo demais.
  const parado = ref(false);
  let relogio = null;
  let enviando = false;
  let ultimoAvanco = 0;
  let ultimaMarca = '';

  const parar = () => {
    clearTimeout(relogio);
    relogio = null;
  };

  const falhou = falha => {
    erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_DEU);
  };

  const falhouAoAcompanhar = falha => {
    falhou(falha);
    semAcompanhar.value = true;
  };

  // Lembra quando o lote andou pela última vez: parado é o que não muda há PARADO_MS.
  const marcarAvanco = atual => {
    const marca = `${atual.porcentagem}-${atual.seguros}`;
    if (marca !== ultimaMarca) {
      ultimaMarca = marca;
      ultimoAvanco = Date.now();
    }
    parado.value = Date.now() - ultimoAvanco >= PARADO_MS;
  };

  const comAndamento = async id => {
    andamento.value = await fonte.andamento(id);
    if (andamento.value.estado === 'trazendo') {
      marcarAvanco(andamento.value);
      relogio = setTimeout(
        () => comAndamento(id).catch(falhouAoAcompanhar),
        PERGUNTA_MS
      );
      return;
    }
    parado.value = false;
    etapa.value = ETAPAS_DOS_PDFS.PRONTO;
  };

  const comLote = async id => {
    const atual = await fonte.lote(id);
    lote.value = atual;
    etapa.value = ESTADO_DA_ETAPA[atual.estado] || ETAPAS_DOS_PDFS.PRONTO;
    if (etapa.value === ETAPAS_DOS_PDFS.LENDO) {
      relogio = setTimeout(
        () => comLote(id).catch(falhouAoAcompanhar),
        PERGUNTA_MS
      );
    } else if (etapa.value !== ETAPAS_DOS_PDFS.CONFERIR) {
      await comAndamento(id);
    }
  };

  const zerarAcompanhamento = () => {
    erro.value = '';
    semAcompanhar.value = false;
    parado.value = false;
    ultimaMarca = '';
    ultimoAvanco = Date.now();
  };

  const abrir = async id => {
    parar();
    zerarAcompanhamento();
    try {
      await comLote(id);
    } catch (falha) {
      // Quem já está na leitura ou no "Trazendo" fica ali, com "Tentar de novo";
      // quem não achou o lote fica no envio, com a frase.
      falhouAoAcompanhar(falha);
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
    if (enviando) return;
    enviando = true;
    try {
      const criado = await tentar(() => fonte.enviar(arquivos));
      if (!criado) return;
      aoMudarLote(criado.id);
      // Já na leitura, antes da primeira resposta: a zona de soltar não volta.
      lote.value = {
        id: criado.id,
        estado: 'lendo',
        total: arquivos.length,
        lidos: 0,
      };
      etapa.value = ETAPAS_DOS_PDFS.LENDO;
      await abrir(criado.id);
    } finally {
      enviando = false;
    }
  };

  const mudarItem = async (itemId, pedido) => {
    const conferir = await tentar(() =>
      fonte.mudarItem(lote.value.id, itemId, pedido)
    );
    if (conferir) lote.value = conferir;
  };

  const trazer = async () => {
    parar();
    const pedido = await tentar(() => fonte.trazer(lote.value.id));
    if (!pedido) {
      // Já no "Trazendo", a falha deixa a saída de tentar de novo.
      semAcompanhar.value = etapa.value === ETAPAS_DOS_PDFS.TRAZENDO;
      return;
    }
    zerarAcompanhamento();
    andamento.value = pedido;
    etapa.value = ETAPAS_DOS_PDFS.TRAZENDO;
    await comAndamento(lote.value.id).catch(falhouAoAcompanhar);
  };

  // "Tentar de novo": no "Trazendo", pede o Trazer outra vez; na leitura,
  // retoma o acompanhamento do mesmo lote.
  const tentarDeNovo = () =>
    etapa.value === ETAPAS_DOS_PDFS.TRAZENDO ? trazer() : abrir(lote.value.id);

  const recomecar = () => {
    parar();
    lote.value = null;
    andamento.value = null;
    zerarAcompanhamento();
    etapa.value = ETAPAS_DOS_PDFS.ENVIAR;
    aoMudarLote(null);
  };

  return {
    etapa,
    lote,
    andamento,
    erro,
    ocupado,
    semAcompanhar,
    parado,
    abrir,
    enviar,
    mudarItem,
    trazer,
    tentarDeNovo,
    recomecar,
    parar,
  };
};
