// #2897 — guardar o PDF de um seguro: a pessoa escolhe (ou solta) o arquivo e
// ele já sobe. Fala com a fonte e guarda o estado; o diálogo só desenha.
// Arquivo grande demais nem é enviado (carteira/useLimiteDoPdf.js). Quando o
// servidor recusa, a frase sai do código da recusa (carteira/recusas.js) e
// nunca traz o nome do arquivo.
//
// #2899 (E6.2) — na conta com a leitura de PDF liberada (`ler`), o PDF é lido
// antes de guardar e a tela mostra o que ele diz de diferente (`mudancas`).
// Cada linha já vem escolhida ou não como o servidor manda (`usar`: o campo
// sem certeza, o corrigido à mão e tudo, quando o PDF pode ser de outra
// apólice, vêm sem escolha) e a pessoa troca. Nada mudou: o PDF já é guardado.
// O arquivo que não é apólice e o que não deu para ler voltam ao começo com a
// frase do que fazer; o que não deu para ler pode ser guardado sem leitura.
// Guardar o que foi lido que falha também volta ao começo, com a frase.
// Cada leitura é do seguro que a pediu: a resposta de um seguro nunca preenche
// a tela de outro (`rodada`, que `comecar` troca).
import { computed, ref, shallowRef } from 'vue';
import { ARQUIVO_GRANDE, chaveDaRecusa, codigoDaRecusa } from './recusas';
import { useLimiteDoPdf } from './useLimiteDoPdf';

const NAO_GUARDOU = 'RELACIONAMENTOS_CARTEIRA.PDF.NAO_GUARDOU';
const NAO_LEU = 'nao_deu_para_ler';
export const ETAPAS = { SOLTAR: 'soltar', LENDO: 'lendo', MUDOU: 'mudou' };

export const useAnexarPdf = fonte => {
  const cabe = useLimiteDoPdf();
  const seguro = ref(null);
  // A chave do catálogo da frase de erro; vazia quando não há erro.
  const erro = ref('');
  const guardando = ref(false);
  const etapa = ref(ETAPAS.SOLTAR);
  const leitura = ref(null);
  const escolhidos = ref([]);
  // O arquivo que não deu para ler, para guardar sem leitura se a pessoa quiser.
  const naoLido = shallowRef(null);
  // Muda toda vez que a tela passa para outro seguro: a resposta que chega de
  // uma rodada antiga é descartada.
  let rodada = 0;

  const comecar = alvo => {
    rodada += 1;
    seguro.value = alvo;
    erro.value = '';
    etapa.value = ETAPAS.SOLTAR;
    leitura.value = null;
    escolhidos.value = [];
    naoLido.value = null;
  };

  // O arquivo pode ser enviado? Quando não pode, a frase fica em `erro`.
  const conferir = arquivo => {
    const cabeAqui = cabe(arquivo);
    erro.value = cabeAqui ? '' : chaveDaRecusa(ARQUIVO_GRANDE, NAO_GUARDOU);
    return cabeAqui;
  };

  const tentar = async pedido => {
    guardando.value = true;
    try {
      return await pedido();
    } catch (falha) {
      erro.value = chaveDaRecusa(codigoDaRecusa(falha), NAO_GUARDOU);
      return null;
    } finally {
      guardando.value = false;
    }
  };

  // Devolve o seguro como ficou, ou null se não deu.
  const guardar = async arquivo => {
    if (!conferir(arquivo)) return null;
    naoLido.value = null;
    return tentar(() => fonte.guardarPdf(seguro.value.id, arquivo));
  };

  // Devolve o seguro como ficou, ou null: a frase do erro fica em `erro` e a
  // tela volta ao começo (a leitura já não vale).
  const guardarLido = async usar => {
    const guardado = await tentar(() =>
      fonte.guardarPdfLido(seguro.value.id, leitura.value.leituraId, usar)
    );
    if (!guardado) etapa.value = ETAPAS.SOLTAR;
    return guardado;
  };

  // Lê o PDF. Devolve o seguro quando nada mudou (o PDF já foi guardado); null
  // quando a tela mostra o que mudou ou a frase do que fazer.
  const ler = async arquivo => {
    if (!conferir(arquivo)) return null;
    etapa.value = ETAPAS.LENDO;
    naoLido.value = null;
    const minhaRodada = rodada;
    let lida;
    try {
      lida = await fonte.lerPdf(seguro.value.id, arquivo);
    } catch (falha) {
      if (minhaRodada !== rodada) return null;
      const codigo = codigoDaRecusa(falha);
      etapa.value = ETAPAS.SOLTAR;
      erro.value = chaveDaRecusa(codigo, NAO_GUARDOU);
      if (codigo === NAO_LEU) naoLido.value = arquivo;
      return null;
    }
    if (minhaRodada !== rodada) return null;
    leitura.value = lida;
    if (!leitura.value.mudancas.length) return guardarLido([]);
    escolhidos.value = leitura.value.mudancas
      .filter(mudanca => mudanca.usar)
      .map(mudanca => mudanca.campo);
    etapa.value = ETAPAS.MUDOU;
    return null;
  };

  const trocarEscolha = campo => {
    escolhidos.value = escolhidos.value.includes(campo)
      ? escolhidos.value.filter(escolhido => escolhido !== campo)
      : [...escolhidos.value, campo];
  };

  const mudancas = computed(() => leitura.value?.mudancas || []);
  const outraApolice = computed(() => Boolean(leitura.value?.outraApolice));

  return {
    seguro,
    erro,
    guardando,
    etapa,
    mudancas,
    outraApolice,
    escolhidos,
    naoLido,
    comecar,
    conferir,
    guardar,
    ler,
    guardarLido,
    trocarEscolha,
  };
};
