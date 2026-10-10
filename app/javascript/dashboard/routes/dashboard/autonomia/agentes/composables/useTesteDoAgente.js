import { computed, getCurrentInstance, onBeforeUnmount, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';

// #1181 — o celular de teste do agente, o mesmo na criação (Confira, T04) e na página do agente
// (T08 e a coluna do celular em T11). Pergunta como cliente pelo `autonomiaAgents/test` (sandbox:
// ninguém recebe e nada vai para a base) e toca a resposta em partes, com a espera de cada uma,
// como o canal de verdade entrega. Embaixo da última parte, "usou: <arquivo>" quando o agente se
// apoiou na base; a última parte também diz se ele passaria a conversa para a equipe. Nunca guarda
// nem mostra confiança, nota ou percentual. Fotos vão como data-url só neste turno e aparecem no
// balão do cliente; foto sem texto vai com `textoSoFoto` (a API exige uma mensagem).
// A primeira parte sai assim que a resposta chega; entre as outras, a espera do canal com teto
// (ESPERA_ENTRE_PARTES_MAX_MS), e nenhuma espera para quem prefere menos movimento.
//
// `agente` é uma ref para `{ id, has_instruction? }`. Quando `has_instruction` é `false`, nem
// chama a API ("ainda não sabe o suficiente"); quando não vem (rascunho da criação, que o
// Construtor ainda está escrevendo), quem diz é o 422 da API.
// Avisos: 'falha' (não respondeu), 'demora' (passou do tempo; a resposta atrasada é ignorada),
// 'incompleto' (ainda sem instrução) e 'offline' (sem internet). A tela decide o texto.
export const AVISO_TESTE = {
  FALHA: 'falha',
  DEMORA: 'demora',
  INCOMPLETO: 'incompleto',
  OFFLINE: 'offline',
};

export const ESPERA_MAXIMA_MS = 60000;
export const ESPERA_ENTRE_PARTES_MAX_MS = 2000;

const TEMPO_ESGOTADO = 'ai_request_timeout';
const SEM_REDE = 'ERR_NETWORK';
const FONTE_DE_IMAGEM = 'imagem da mensagem';

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const movimentoReduzido = () =>
  typeof window !== 'undefined' &&
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches === true;

const lerComoDataUrl = arquivo =>
  new Promise((resolve, reject) => {
    const leitor = new FileReader();
    leitor.onload = () => resolve(leitor.result);
    leitor.onerror = reject;
    leitor.readAsDataURL(arquivo);
  });

const semInternet = erro =>
  (typeof navigator !== 'undefined' && navigator.onLine === false) ||
  erro?.code === SEM_REDE;

const avisoDoErro = erro => {
  if (semInternet(erro)) return AVISO_TESTE.OFFLINE;
  if (erro?.code === TEMPO_ESGOTADO) return AVISO_TESTE.DEMORA;
  if (erro?.response?.status === 422) return AVISO_TESTE.INCOMPLETO;
  return AVISO_TESTE.FALHA;
};

// used_knowledge chega como [{ source, content }]; só o nome do arquivo aparece, uma vez cada. A
// foto enviada no próprio teste não é arquivo da base.
const arquivosUsados = usados => [
  ...new Set(
    (usados || [])
      .map(item => (typeof item === 'string' ? item : item?.source))
      .filter(fonte => fonte && fonte !== FONTE_DE_IMAGEM)
  ),
];

const partesDaResposta = dados => {
  if (dados?.humanized && Array.isArray(dados.chunks) && dados.chunks.length) {
    return dados.chunks
      .filter(parte => parte?.text)
      .map(parte => ({
        texto: parte.text,
        espera: Math.max(0, Number(parte.delay_ms) || 0),
      }));
  }
  return dados?.reply ? [{ texto: dados.reply, espera: 0 }] : [];
};

export function useTesteDoAgente(agente, { textoSoFoto = '' } = {}) {
  const store = useStore();
  const mensagens = ref([]);
  const digitando = ref(false);
  const aviso = ref(null);
  const ultima = ref(null);
  const respondidas = ref(0);
  const atualizado = ref(false);
  let sequencia = 0;
  let relogio = null;
  let pendente = null;

  const pararRelogio = () => {
    if (relogio) clearTimeout(relogio);
    relogio = null;
  };

  const acrescentar = mensagem => {
    mensagens.value = [...mensagens.value, mensagem];
  };

  const historico = () =>
    mensagens.value.map(mensagem => ({
      role: mensagem.de === 'cliente' ? 'user' : 'assistant',
      content: mensagem.texto,
    }));

  const tocar = async (dados, minha, pergunta) => {
    const partes = partesDaResposta(dados);
    const usou = arquivosUsados(dados?.used_knowledge);
    const passaria = dados?.handoff?.should === true;
    const semEspera = movimentoReduzido();
    for (let i = 0; i < partes.length; i += 1) {
      const espera =
        i === 0 || semEspera
          ? 0
          : Math.min(partes[i].espera, ESPERA_ENTRE_PARTES_MAX_MS);
      // eslint-disable-next-line no-await-in-loop
      if (espera) await esperar(espera);
      if (minha !== sequencia) return;
      const ehUltima = i === partes.length - 1;
      acrescentar({
        de: 'agente',
        texto: partes[i].texto,
        ...(ehUltima && usou.length ? { usou } : {}),
        ...(ehUltima && passaria ? { passaria } : {}),
      });
    }
    respondidas.value += 1;
    ultima.value = {
      pergunta,
      resposta: partes.map(parte => parte.texto).join(' '),
      passaria,
    };
  };

  const executar = async ({ pergunta, fotos, anterior }) => {
    sequencia += 1;
    const minha = sequencia;
    aviso.value = null;
    ultima.value = null;
    digitando.value = true;
    pararRelogio();
    relogio = setTimeout(() => {
      if (minha !== sequencia) return;
      sequencia += 1;
      digitando.value = false;
      aviso.value = { tipo: AVISO_TESTE.DEMORA, pergunta };
    }, ESPERA_MAXIMA_MS);

    try {
      const dados = await store.dispatch('autonomiaAgents/test', {
        agentId: agente.value.id,
        message: pergunta,
        history: anterior,
        ...(fotos.length ? { images: fotos } : {}),
      });
      if (minha !== sequencia) return;
      pararRelogio();
      await tocar(dados, minha, pergunta);
    } catch (erro) {
      if (minha === sequencia) {
        aviso.value = { tipo: avisoDoErro(erro), pergunta };
      }
    } finally {
      if (minha === sequencia) {
        digitando.value = false;
        pararRelogio();
      }
    }
  };

  // Lê as fotos antes de mostrar o balão (ele leva a foto). Enquanto lê, o teste já está ocupado:
  // nada de segunda pergunta. null = não entra (limpou/saiu no meio, ou a foto não pôde ser lida).
  const lerFotos = async (pergunta, imagens) => {
    digitando.value = true;
    const vez = sequencia;
    try {
      const fotos = await Promise.all(imagens.map(lerComoDataUrl));
      if (vez !== sequencia) return null;
      digitando.value = false;
      return fotos;
    } catch {
      if (vez === sequencia) {
        digitando.value = false;
        aviso.value = { tipo: AVISO_TESTE.FALHA, pergunta };
      }
      return null;
    }
  };

  const enviar = async (texto, imagens = []) => {
    const pergunta =
      (texto || '').trim() || (imagens.length ? textoSoFoto : '');
    if (!pergunta || digitando.value || !agente.value?.id) return;
    atualizado.value = false;
    const fotos = imagens.length ? await lerFotos(pergunta, imagens) : [];
    if (!fotos) return;
    pendente = { pergunta, fotos, anterior: historico() };
    acrescentar({
      de: 'cliente',
      texto: pergunta,
      ...(fotos.length ? { fotos } : {}),
    });

    if (agente.value.has_instruction === false) {
      sequencia += 1;
      ultima.value = null;
      aviso.value = { tipo: AVISO_TESTE.INCOMPLETO, pergunta };
      return;
    }
    await executar(pendente);
  };

  // Tenta de novo a mesma pergunta (com as mesmas fotos), sem repetir o balão do cliente.
  const tentarDeNovo = async () => {
    if (!pendente || digitando.value) return;
    await executar(pendente);
  };

  const parar = () => {
    sequencia += 1;
    pararRelogio();
  };

  const limpar = () => {
    parar();
    mensagens.value = [];
    digitando.value = false;
    aviso.value = null;
    ultima.value = null;
    atualizado.value = false;
    pendente = null;
  };

  // O agente mudou depois de um teste (Construtor na criação, T11 na página): as respostas antigas
  // já não valem; o teste recomeça e avisa que dá para testar de novo.
  // Também esquece as respostas vistas: começar a atender espera uma resposta da versão nova.
  const marcarAtualizado = () => {
    limpar();
    respondidas.value = 0;
    atualizado.value = true;
  };

  // Mostra a pergunta e a resposta que estão sendo corrigidas (t11-teste).
  const mostrar = ({ pergunta, resposta }) => {
    limpar();
    mensagens.value = [
      { de: 'cliente', texto: pergunta },
      { de: 'agente', texto: resposta },
    ];
  };

  const vazio = computed(() => !mensagens.value.length);

  if (getCurrentInstance()) onBeforeUnmount(parar);

  return {
    mensagens,
    digitando,
    aviso,
    ultima,
    respondidas,
    atualizado,
    vazio,
    enviar,
    tentarDeNovo,
    limpar,
    marcarAtualizado,
    mostrar,
    parar,
  };
}
