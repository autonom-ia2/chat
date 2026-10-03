// Guia da Plataforma — LOCAL message store for the global guide widget.
//
// Self-contained reactive store (NOT a Vuex module → no store/index.js change, update-safe). The
// thread is global (not conversation-scoped) and ephemeral. Records mirror the components-next
// copilot bubble shape; assistant records also carry `navigation` (the screen the guide suggests)
// and `acao` (the action the guide proposes, which only runs after an explicit confirmation).
import { reactive, readonly, markRaw } from 'vue';

const state = reactive({
  messages: [],
  // #857 — arquivos anexados nesta conversa: { id, nome, estado, signedId }.
  // Valem para a conversa inteira: o Guia lê todos a cada pergunta.
  // #895 — e também { tipo, previa, turno }: `previa` é a miniatura da foto
  // (endereço local do navegador) e `turno` é a mensagem que levou o arquivo —
  // `null` enquanto ele espera no campo de digitar.
  arquivos: [],
});

let nextArquivoId = 1;

// O Guia lê no máximo 5 arquivos por conversa
// (`Autonomia::Guide::Arquivos::MAX_POR_TURNO`): a tela recusa o sexto com
// aviso, em vez de o servidor ignorá-lo em silêncio.
export const MAX_ANEXOS_POR_CONVERSA = 5;

let nextId = 1;

// Acima disso não é recado para quem usa: é dump, stack trace ou corpo de resposta.
const MOTIVO_MAX_CARACTERES = 160;

// Procura uma sequência de EXATAMENTE 3 dígitos cujo valor caia em 100–599, o
// formato de um status HTTP. Varredura caractere a caractere porque regex é
// proibido neste repositório.
const temStatusHttp = texto => {
  let inicio = -1;

  for (let i = 0; i <= texto.length; i += 1) {
    const ehDigito = i < texto.length && texto[i] >= '0' && texto[i] <= '9';

    if (ehDigito) {
      if (inicio === -1) inicio = i;
    } else if (inicio !== -1) {
      const bloco = texto.slice(inicio, i);
      const numero = Number(bloco);
      if (bloco.length === 3 && numero >= 100 && numero <= 599) return true;
      inicio = -1;
    }
  }

  return false;
};

// O erro cru da plataforma às vezes é um recado ("Este funil não existe mais"),
// e às vezes é a tradução de um status para quem nunca vai olhar um log ("A
// plataforma respondeu 422."). Só o primeiro tipo ajuda. Devolve '' quando o
// motivo não serve, e aí quem chama mostra o texto genérico.
export const motivoUtilizavel = motivo => {
  if (typeof motivo !== 'string') return '';

  const texto = motivo.trim();
  if (!texto || texto.length > MOTIVO_MAX_CARACTERES) return '';

  return temStatusHttp(texto) ? '' : texto;
};

// #895 — o que ainda está no campo de digitar, esperando o próximo envio.
const arquivosPendentes = () => state.arquivos.filter(item => !item.turno);

// Mensagem de quem usa. `content` é o que vai para o histórico do Guia; `texto`
// é o que o balão mostra — numa mensagem só com anexos o histórico leva a frase
// padrão e o balão mostra só os anexos. Os anexos já prontos que esperavam no
// campo passam a ser desta mensagem (como no WhatsApp) e continuam na lista da
// conversa: o Guia segue lendo todos a cada pergunta.
//
// `voz` (#895): { audio, url, duracao }. O texto chega depois, pela
// transcrição; até lá a mensagem fica fora do histórico (conteúdo vazio).
const addUserMessage = (content, { texto = content, voz = null } = {}) => {
  const id = nextId;
  nextId += 1;
  const anexos = arquivosPendentes()
    .filter(item => item.estado === 'pronto')
    .map(item => {
      item.turno = id;
      return {
        id: item.id,
        nome: item.nome,
        tipo: item.tipo,
        previa: item.previa,
      };
    });
  const record = {
    id,
    message_type: 'user',
    message: { content: voz ? '' : content },
    texto: voz ? '' : texto,
    anexos,
    voz: voz
      ? {
          audio: markRaw(voz.audio),
          url: voz.url,
          duracao: voz.duracao || 0,
          estado: 'transcrevendo',
          texto: '',
          erro: '',
        }
      : null,
  };
  state.messages.push(record);
  return state.messages[state.messages.length - 1];
};

// #895 — o andamento da transcrição de uma mensagem de voz. Pronta, o texto
// falado vira o conteúdo da mensagem (é ele que o Guia lê no histórico).
// Devolve `false` quando a mensagem não existe mais ("Nova conversa").
const marcarVoz = (id, estado, { texto = '', erro = '' } = {}) => {
  const registro = state.messages.find(m => m.id === id);
  if (!registro?.voz) return false;
  registro.voz.estado = estado;
  registro.voz.erro = erro;
  if (estado === 'pronta') {
    registro.voz.texto = texto;
    registro.message.content = texto;
  }
  return true;
};

// O backend manda `navigations`/`artigos` (listas, #636). Durante o deploy blue/green, um pedido
// pode ser respondido por uma instância que ainda só manda o campo singular antigo (`navigation`/
// `artigo`) — a tela recebe as duas formas e nunca perde o botão por causa disso. Sem regex: é
// só "a lista veio e tem item" ou "sobrou o singular".
const paraLista = (lista, unico) => {
  if (Array.isArray(lista) && lista.length) return lista;
  return unico ? [unico] : [];
};

const addAssistantMessage = ({
  content,
  navigation = null,
  navigations = null,
  acao = null,
  artigo = null,
  artigos = null,
  execucao = null,
} = {}) => {
  const record = {
    id: nextId,
    message_type: 'assistant',
    message: { content },
    // As telas que o Guia escolheu, na ordem em que escolheu (#590, #636).
    navigations: paraLista(navigations, navigation),
    // Ação proposta: fica aguardando confirmação e guarda o desfecho depois.
    acao,
    acaoEstado: acao ? 'aguardando' : null,
    acaoResultado: null,
    // Os artigos da Central que o Guia leu, na ordem de leitura (#617, #636):
    // o link "Ler" de cada um abre o artigo completo dele.
    artigos: paraLista(artigos, artigo),
    // O que o Guia FEZ neste turno (#855), com o desfazer.
    execucao,
  };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const revogar = url => {
  if (url) URL.revokeObjectURL(url);
};

// O áudio e as miniaturas vivem na memória do navegador até alguém soltar.
const reset = () => {
  const enderecos = new Set([
    ...state.messages.map(m => m.voz?.url),
    ...state.arquivos.map(item => item.previa),
  ]);
  enderecos.forEach(revogar);
  state.messages.splice(0, state.messages.length);
  state.arquivos.splice(0, state.arquivos.length);
};

const addArquivo = (nome, { tipo = 'documento', previa = null } = {}) => {
  const arquivo = {
    id: nextArquivoId,
    nome,
    estado: 'subindo',
    signedId: null,
    tipo,
    previa,
    turno: null,
  };
  nextArquivoId += 1;
  state.arquivos.push(arquivo);
  return arquivo.id;
};

// Devolve `false` quando o arquivo saiu da lista no meio do envio (removido ou
// "Nova conversa"): quem chama não deve tratar o envio como parte da conversa.
const marcarArquivo = (id, estado, signedId = null) => {
  const arquivo = state.arquivos.find(item => item.id === id);
  if (!arquivo) return false;
  arquivo.estado = estado;
  arquivo.signedId = signedId;
  return true;
};

const removeArquivo = id => {
  const indice = state.arquivos.findIndex(item => item.id === id);
  if (indice < 0) return;
  revogar(state.arquivos[indice].previa);
  state.arquivos.splice(indice, 1);
};

// O que vai com a pergunta: só os arquivos que já subiram.
const arquivosProntos = () =>
  state.arquivos
    .filter(item => item.estado === 'pronto')
    .map(item => item.signedId);

// History for the backend chat call: [{ role: 'user' | 'assistant', content }].
const toHistory = () =>
  state.messages
    .filter(m => m.message?.content)
    .map(m => ({
      role: m.message_type === 'assistant' ? 'assistant' : 'user',
      content: m.message.content,
    }));

// Devolve `false` quando o registro não existe mais — troca de conta ou "Nova
// conversa" durante os segundos da execução. Quem chama precisa saber disso:
// a ação já rodou no servidor, e sem esse retorno o desfecho sumia em silêncio.
const marcarAcao = (id, estado, resultado = null) => {
  const registro = state.messages.find(m => m.id === id);
  if (!registro) return false;
  registro.acaoEstado = estado;
  registro.acaoResultado = resultado;
  return true;
};

export const useAutonomiaGuideStore = () => ({
  messages: readonly(state).messages,
  arquivos: readonly(state).arquivos,
  addArquivo,
  marcarArquivo,
  removeArquivo,
  arquivosProntos,
  arquivosPendentes,
  addUserMessage,
  marcarVoz,
  addAssistantMessage,
  marcarAcao,
  reset,
  toHistory,
});

export default useAutonomiaGuideStore;
