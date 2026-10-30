import { ref, toValue, watch } from 'vue';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';

// Comentários que viram cliente (#2212): o cuidado de um post (Seus posts, B1) ou de um anúncio (B2). Recebe o alvo
// { kind: 'post' | 'ad', id, perfil } (valor, ref ou getter; null não lê nada) e guarda o Painel do servidor. As escritas devolvem true
// quando valeram e false quando falharam: a tela decide o aviso. Contrato: docs/audit/2026-10-30-2212-contrato-api.md.
const ERRO_POR_STATUS = { 403: 'acesso', 404: 'sumiu' };

export const erroDaResposta = error =>
  ERRO_POR_STATUS[error?.response?.status] || 'rede';

export function useCuidado(alvo) {
  const painel = ref(null);
  const carregando = ref(false);
  // 'acesso' (403), 'sumiu' (404: sem a flag ou o post saiu do perfil) ou 'rede'.
  const erro = ref(null);
  const salvando = ref(false);

  const target = () => toValue(alvo);

  // Trocar de alvo no meio de uma leitura: só a resposta da leitura mais nova vale.
  // Sem alvo (a flag desligada, por exemplo), nada é lido.
  let leitura = 0;
  const carregar = async () => {
    if (!target()) return;
    leitura += 1;
    const minha = leitura;
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

  const escrever = async chamada => {
    salvando.value = true;
    try {
      const { data } = await chamada();
      if (data) painel.value = data;
      return true;
    } catch {
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
    carregar,
    salvar,
    pausar,
    voltar,
    previa,
    lerAntigos,
  };
}

// O resumo "O que tem nos comentários" (A2) do mesmo alvo: { status, questions, questions_old, complaints, read, more }.
// Falha de rede ou do servidor: `falhou`, e a tela oferece tentar de novo. Sem alvo, nada é lido.
export function useResumo(alvo) {
  const resumo = ref(null);
  const carregando = ref(false);
  const falhou = ref(false);

  const target = () => toValue(alvo);

  let leitura = 0;
  const carregar = async () => {
    if (!target()) return;
    leitura += 1;
    const minha = leitura;
    carregando.value = true;
    falhou.value = false;
    try {
      const { data } = await ComentariosIaAPI.getResumo(target());
      if (minha === leitura) resumo.value = data;
    } catch {
      if (minha === leitura) falhou.value = true;
    } finally {
      if (minha === leitura) carregando.value = false;
    }
  };

  watch(target, carregar, { immediate: true, deep: true });

  return { resumo, carregando, falhou, carregar };
}
