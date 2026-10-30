import { getCurrentScope, onScopeDispose, ref, toValue, watch } from 'vue';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';

// Comentários que viram cliente (#2212): o cuidado de um post (Seus posts, B1) ou de um anúncio (B2). Recebe o alvo
// { kind: 'post' | 'ad', id, perfil } (valor, ref ou getter; null não lê nada) e guarda o Painel do servidor. As escritas devolvem true
// quando valeram e false quando falharam: a tela decide o aviso. Contrato: docs/audit/2026-10-30-2212-contrato-api.md.
const ERRO_POR_STATUS = { 403: 'acesso', 404: 'sumiu' };

export const erroDaResposta = error =>
  ERRO_POR_STATUS[error?.response?.status] || 'rede';

// O "para quem" do dono vai inteiro ao classificador: até 500 letras (o servidor recusa mais).
export const FOR_WHOM_LIMIT = 500;

// Por que uma escrita falhou, para a tela dizer o certo: 'acesso' (403), 'invalid_message' ou 'invalid_para_quem' (422
// do servidor, o texto não serve) ou 'rede' (o resto).
const ESCRITA_INVALIDA = ['invalid_message', 'invalid_para_quem'];
export const falhaDaEscrita = error => {
  if (error?.response?.status === 403) return 'acesso';
  const codigo = error?.response?.data?.error;
  return ESCRITA_INVALIDA.includes(codigo) ? codigo : 'rede';
};

// O mesmo alvo, comparado pelo que ele é (kind, id, perfil), não pela referência do objeto.
const chaveDo = alvo => (alvo ? `${alvo.kind}:${alvo.id}:${alvo.perfil}` : '');

export function useCuidado(alvo) {
  const painel = ref(null);
  const carregando = ref(false);
  // 'acesso' (403), 'sumiu' (404: sem a flag ou o post saiu do perfil) ou 'rede'.
  const erro = ref(null);
  const salvando = ref(false);
  // Por que a última escrita falhou (ver falhaDaEscrita); null quando valeu.
  const falhaAoSalvar = ref(null);

  const target = () => toValue(alvo);

  // Trocar de alvo no meio de uma leitura: só a resposta da leitura mais nova vale, e o Painel do alvo anterior sai na
  // hora (a tela não mostra o post A enquanto lê o B, e nada do A é gravado no B). Ler de novo o mesmo alvo mantém o
  // Painel na tela. Sem alvo (a flag desligada, por exemplo), nada é lido.
  let leitura = 0;
  let lido = '';
  const carregar = async () => {
    if (!target()) return;
    leitura += 1;
    const minha = leitura;
    if (chaveDo(target()) !== lido) {
      lido = chaveDo(target());
      painel.value = null;
    }
    carregando.value = true;
    erro.value = null;
    try {
      const { data } = await ComentariosIaAPI.getCuidado(target());
      if (minha === leitura) painel.value = data;
    } catch (error) {
      if (minha === leitura) erro.value = erroDaResposta(error);
    } finally {
      if (minha === leitura) carregando.value = false;
    }
  };

  // A resposta de uma escrita só entra no Painel se o alvo ainda é o mesmo.
  const escrever = async chamada => {
    const deQuem = chaveDo(target());
    salvando.value = true;
    falhaAoSalvar.value = null;
    try {
      const { data } = await chamada();
      if (data && deQuem === lido) painel.value = data;
      return true;
    } catch (error) {
      falhaAoSalvar.value = falhaDaEscrita(error);
      return false;
    } finally {
      salvando.value = false;
    }
  };

  // Grava a mensagem, o "para quem" e as frases; `status` liga ('on') ou mantém o atual.
  const salvar = ({ message, paraQuem, phrases, status }) =>
    escrever(() =>
      ComentariosIaAPI.saveCuidado(target(), {
        message,
        paraQuem,
        phrases,
        status: status || painel.value?.care,
      })
    );

  // Pausar e voltar a cuidar regravam o que já está guardado, só com outro status.
  const mudarStatus = status =>
    escrever(() =>
      ComentariosIaAPI.saveCuidado(target(), {
        message: painel.value?.message,
        paraQuem: painel.value?.para_quem,
        phrases: painel.value?.phrases,
        status,
      })
    );
  const pausar = () => mudarStatus('paused');
  const voltar = () => mudarStatus('on');

  // Passo 3 do jeito do dono: dois comentários do post, um que é o caso e um que não é. Falha: null.
  const previa = async paraQuem => {
    try {
      const { data } = await ComentariosIaAPI.previa(target(), { paraQuem });
      return data;
    } catch {
      return null;
    }
  };

  // "Ler e mandar" os comentários que chegaram antes de ligar: o servidor põe na fila e o Painel é lido de novo.
  const lerAntigos = async () => {
    const valeu = await escrever(async () => {
      await ComentariosIaAPI.lerAntigos(target());
      return { data: null };
    });
    if (valeu) await carregar();
    return valeu;
  };

  watch(target, carregar, { immediate: true, deep: true });

  return {
    painel,
    carregando,
    erro,
    salvando,
    falhaAoSalvar,
    carregar,
    salvar,
    pausar,
    voltar,
    previa,
    lerAntigos,
  };
}

// O resumo "O que tem nos comentários" (A2) do mesmo alvo: { status, questions, questions_old, complaints, read, more }.
// Na primeira visita o servidor conta num job e responde `reading`: a tela segue "carregando" e pergunta de novo a cada
// ESPERA_LENDO_MS, até MAX_LEITURAS; passou disso, `falhou`, e a tela oferece tentar de novo. Falha de rede ou do
// servidor também é `falhou`. `ai_unavailable` (a IA fora) e `meta_unavailable` vêm no `resumo`, e a tela diz que não
// deu. Trocar de alvo ou sair da tela para as perguntas. Sem alvo, nada é lido.
export const ESPERA_LENDO_MS = 3000;
export const MAX_LEITURAS = 10;

export function useResumo(alvo) {
  const resumo = ref(null);
  const carregando = ref(false);
  const falhou = ref(false);

  const target = () => toValue(alvo);

  let leitura = 0;
  let lido = '';
  let espera = null;
  const parar = () => {
    clearTimeout(espera);
    espera = null;
  };

  const ler = async (minha, tentativa) => {
    let data;
    try {
      ({ data } = await ComentariosIaAPI.getResumo(target()));
    } catch {
      if (minha !== leitura) return;
      falhou.value = true;
      carregando.value = false;
      return;
    }
    if (minha !== leitura) return;
    if (data?.status !== 'reading') {
      resumo.value = data;
      carregando.value = false;
      return;
    }
    if (tentativa >= MAX_LEITURAS) {
      falhou.value = true;
      carregando.value = false;
      return;
    }
    espera = setTimeout(() => ler(minha, tentativa + 1), ESPERA_LENDO_MS);
  };

  const carregar = async () => {
    parar();
    if (!target()) return;
    leitura += 1;
    // Outro alvo, ou um resumo que não ficou pronto: some, e a tela mostra "carregando" de novo. O mesmo alvo pronto
    // fica na tela enquanto é relido (depois de responder um comentário, por exemplo).
    if (chaveDo(target()) !== lido || resumo.value?.status !== 'ready') {
      lido = chaveDo(target());
      resumo.value = null;
    }
    carregando.value = true;
    falhou.value = false;
    await ler(leitura, 1);
  };

  watch(target, carregar, { immediate: true, deep: true });
  if (getCurrentScope()) {
    onScopeDispose(() => {
      leitura += 1;
      parar();
    });
  }

  return { resumo, carregando, falhou, carregar };
}
