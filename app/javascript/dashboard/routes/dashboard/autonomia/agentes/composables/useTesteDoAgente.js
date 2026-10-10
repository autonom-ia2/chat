import { computed, ref } from 'vue';
import { useStore } from 'dashboard/composables/store';

// #1181 PR3 — o teste do agente (T08 e a coluna do celular em T11). Pergunta como cliente pelo
// `autonomiaAgents/test` (nada vai para clientes nem para a base). Mostra a resposta em partes
// quando o backend manda `chunks`, o arquivo que o agente usou e se ele passaria para a equipe.
// Nunca guarda nem mostra confiança, nota ou percentual.
// Avisos: 'falha' (não respondeu), 'demora' (passou do tempo; a resposta atrasada é ignorada) e
// 'incompleto' (agente ainda sem instrução: nem chama a API).
export const AVISO_TESTE = {
  FALHA: 'falha',
  DEMORA: 'demora',
  INCOMPLETO: 'incompleto',
};

export const ESPERA_MAXIMA_MS = 60000;
const TEMPO_ESGOTADO = 'ai_request_timeout';
const FONTE_DE_IMAGEM = 'imagem da mensagem';

const arquivosUsados = usados => [
  ...new Set(
    (usados || [])
      .map(item => item?.source)
      .filter(fonte => fonte && fonte !== FONTE_DE_IMAGEM)
  ),
];

const partesDaResposta = dados => {
  if (dados?.humanized && Array.isArray(dados.chunks) && dados.chunks.length) {
    return dados.chunks.map(parte => parte.text).filter(Boolean);
  }
  return dados?.reply ? [dados.reply] : [];
};

export function useTesteDoAgente(agente) {
  const store = useStore();
  const mensagens = ref([]);
  const digitando = ref(false);
  const aviso = ref(null);
  const ultima = ref(null);
  const atualizado = ref(false);
  let sequencia = 0;
  let relogio = null;

  const pararRelogio = () => {
    if (relogio) clearTimeout(relogio);
    relogio = null;
  };

  const historico = () =>
    mensagens.value.map(mensagem => ({
      role: mensagem.de === 'cliente' ? 'user' : 'assistant',
      content: mensagem.texto,
    }));

  const responder = (dados, pergunta) => {
    const partes = partesDaResposta(dados);
    const usou = arquivosUsados(dados?.used_knowledge);
    const novas = partes.map((texto, indice) => ({
      de: 'agente',
      texto,
      usou: indice === partes.length - 1 ? usou : [],
    }));
    mensagens.value = [...mensagens.value, ...novas];
    ultima.value = {
      pergunta,
      resposta: partes.join(' '),
      passaria: dados?.handoff?.should === true,
    };
  };

  const enviar = async texto => {
    const pergunta = (texto || '').trim();
    if (!pergunta || digitando.value || !agente.value?.id) return;
    const anterior = historico();
    sequencia += 1;
    const minha = sequencia;
    atualizado.value = false;
    aviso.value = null;
    ultima.value = null;
    mensagens.value = [...mensagens.value, { de: 'cliente', texto: pergunta }];

    if (agente.value.has_instruction === false) {
      aviso.value = { tipo: AVISO_TESTE.INCOMPLETO, pergunta };
      return;
    }

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
      });
      if (minha !== sequencia) return;
      responder(dados, pergunta);
    } catch (error) {
      if (minha !== sequencia) return;
      aviso.value = {
        tipo:
          error?.code === TEMPO_ESGOTADO
            ? AVISO_TESTE.DEMORA
            : AVISO_TESTE.FALHA,
        pergunta,
      };
    } finally {
      if (minha === sequencia) {
        digitando.value = false;
        pararRelogio();
      }
    }
  };

  // Tenta de novo a mesma pergunta: tira a pergunta que ficou sem resposta antes de reenviar.
  const tentarDeNovo = () => {
    const pergunta = aviso.value?.pergunta;
    if (!pergunta) return;
    mensagens.value = mensagens.value.slice(0, -1);
    aviso.value = null;
    enviar(pergunta);
  };

  const limpar = () => {
    sequencia += 1;
    pararRelogio();
    mensagens.value = [];
    digitando.value = false;
    aviso.value = null;
    ultima.value = null;
    atualizado.value = false;
  };

  // Depois de mudar o agente (T11), o teste recomeça e avisa que dá para testar de novo.
  const marcarAtualizado = () => {
    limpar();
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

  return {
    mensagens,
    digitando,
    aviso,
    ultima,
    atualizado,
    vazio,
    enviar,
    tentarDeNovo,
    limpar,
    marcarAtualizado,
    mostrar,
    parar: () => {
      sequencia += 1;
      pararRelogio();
    },
  };
}
