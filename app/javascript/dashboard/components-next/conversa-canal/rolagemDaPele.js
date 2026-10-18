// Rolagem da conversa com a pele (#1702), como no app: abre na 1ª não lida com a faixa
// "N mensagens não lidas" perto do topo; quem está lendo mais acima não é puxado para
// o fim quando o cliente escreve (o botão de descer conta as novas); a citação busca a
// mensagem antiga que ainda não veio. Sem a pele, a tela segue o Chatwoot.
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { MESSAGE_TYPES } from '../message/constants';
import { ocultaNaPele } from './marcasDaMensagem';
import { eMarcadorDeAlbum } from './album/agruparAlbuns';

// A partir de quanto rolado para cima a pessoa "está lendo lá em cima".
export const DISTANCIA_DO_FIM = 300;
// Páginas anteriores que a conversa busca atrás da não lida ou da citada (20 por página).
export const TETO_DE_PAGINAS = 10;
// Espaço acima da faixa ao abrir: a etiqueta do dia presa no topo não a cobre.
export const MARGEM_DA_FAIXA = 56;

export const distanciaDoFim = painel =>
  painel ? painel.scrollHeight - painel.scrollTop - painel.clientHeight : 0;

export const pertoDoFim = (painel, limite = DISTANCIA_DO_FIM) =>
  distanciaDoFim(painel) <= limite;

export const topoDaFaixa = (deslocamento, margem = MARGEM_DA_FAIXA) =>
  Math.max(0, deslocamento - margem);

const NOSSAS = [MESSAGE_TYPES.OUTGOING, MESSAGE_TYPES.TEMPLATE];
const tipoDa = mensagem => mensagem?.messageType ?? mensagem?.message_type;

// Chegou mensagem (ou a conversa mudou): desce só quem já estava no fim, ou quando a
// última é nossa e acabou de sair (o atendente enviou). Cliente escrevendo com a
// pessoa lendo lá em cima não a tira do lugar.
export const deveDescer = ({ estavaNoFim, ultimaAntes, ultima }) => {
  if (estavaNoFim) return true;
  if (!ultima || ultima.id === ultimaAntes) return false;
  return NOSSAS.includes(tipoDa(ultima));
};

// A faixa de não lidas some depois de lida (pedido do Rodrigo, 18/10): 5 s com a aba
// visível, ou quando o atendente envia uma mensagem. Ao reabrir, a leitura já foi marcada
// e a faixa não volta. Dispensada, guarda que abriu na faixa (a rolagem não desce sozinha).
export const TEMPO_DA_FAIXA_EM_MS = 5000;

export const faixaDispensada = marco =>
  marco ? { ...marco, primeiraNaoLida: null, dispensada: true } : marco;

// Conta só o tempo com a aba visível: sair da aba pausa, voltar continua de onde parou.
// Devolve a função que cancela.
export const agendarFimDaFaixa = (aoFim, tempo = TEMPO_DA_FAIXA_EM_MS) => {
  let restante = tempo;
  let relogio = null;
  let inicio = 0;
  const pausar = () => {
    if (!relogio) return;
    clearTimeout(relogio);
    relogio = null;
    restante -= Date.now() - inicio;
  };
  const aoMudar = () => {
    if (document.visibilityState !== 'visible') {
      pausar();
      return;
    }
    if (relogio) return;
    inicio = Date.now();
    relogio = setTimeout(
      () => {
        relogio = null;
        document.removeEventListener('visibilitychange', aoMudar);
        aoFim();
      },
      Math.max(0, restante)
    );
  };
  document.addEventListener('visibilitychange', aoMudar);
  aoMudar();
  return () => {
    document.removeEventListener('visibilitychange', aoMudar);
    clearTimeout(relogio);
    relogio = null;
  };
};

// Carrega páginas anteriores até `achou()` ou o teto; diz se achou.
export const buscarAteAchar = async ({
  achou,
  temMais,
  carregarMais,
  teto = TETO_DE_PAGINAS,
}) => {
  let paginas = 0;
  while (!achou() && paginas < teto && temMais()) {
    // Uma página por vez: a seguinte começa antes da 1ª que acabou de chegar.
    // eslint-disable-next-line no-await-in-loop
    await carregarMais();
    paginas += 1;
  }
  return achou();
};

// As mensagens da loja vêm em snake_case; a regra de esconder lê camelCase. O "pai" do
// álbum que a Cloud entrega (marcador) não tem balão: some da lista e não conta.
const visivelNaPele = mensagem => {
  const camel = useCamelCase(mensagem, { deep: true });
  return !ocultaNaPele(camel) && !eMarcadorDeAlbum(camel);
};

const naoLida = (mensagem, vistoEm) =>
  !vistoEm || mensagem.created_at > vistoEm;

// Já veio tudo o que está depois da última leitura? (a mais antiga carregada já tinha
// sido lida). Sem leitura nenhuma não há marco a alcançar: não busca páginas antigas,
// a faixa conta o que veio.
export const naoLidasCarregadas = (mensagens, vistoEm) => {
  if (!vistoEm) return true;
  const [maisAntiga] = mensagens;
  return Boolean(maisAntiga && !naoLida(maisAntiga, vistoEm));
};

// A faixa fica na 1ª mensagem do cliente depois da última leitura e conta todas as
// do cliente dali em diante (o número exato, sem "9+"). Resposta da equipe ou do robô
// depois da leitura não abre faixa, como no app. Ler (que zera a contagem no servidor)
// não muda o número; a faixa some sozinha depois de lida (agendarFimDaFaixa).
// Conversa que nenhum atendente abriu (só o robô atendeu): não há marco de leitura, então
// não há faixa e a conversa abre no fim. Um número aqui seria só o da página carregada.
export const marcoDeNaoLidas = (conversaId, mensagens, vistoEm) => {
  if (!vistoEm) {
    return { conversaId, pronta: true, primeiraNaoLida: null, quantidade: 0 };
  }
  const doCliente = mensagens.filter(
    mensagem =>
      tipoDa(mensagem) === MESSAGE_TYPES.INCOMING &&
      naoLida(mensagem, vistoEm) &&
      visivelNaPele(mensagem)
  );
  return {
    conversaId,
    pronta: true,
    primeiraNaoLida: doCliente[0]?.id ?? null,
    quantidade: doCliente.length,
  };
};

// Botão de descer: quantas do cliente chegaram a partir de `desde` (id).
export const novasDoCliente = (mensagens, desde) => {
  if (!desde) return 0;
  return mensagens.filter(
    mensagem =>
      tipoDa(mensagem) === MESSAGE_TYPES.INCOMING &&
      typeof mensagem.id === 'number' &&
      mensagem.id >= desde &&
      visivelNaPele(mensagem)
  ).length;
};

// De onde a contagem começa: na não lida da faixa, ou logo depois da última.
export const inicioDaContagem = (mensagens, primeiraNaoLida) => {
  if (primeiraNaoLida) return primeiraNaoLida;
  const ultima = [...mensagens]
    .reverse()
    .find(mensagem => typeof mensagem.id === 'number');
  return ultima ? ultima.id + 1 : null;
};
