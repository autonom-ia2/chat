import { onMounted, onUnmounted, watch } from 'vue';

// Enquanto houver modelo "Em análise", a tela pergunta à Meta sozinha a cada
// 60 s (#1394, aprovado pelo Rodrigo). Só com a aba visível: a aba volta a ficar
// visível, confere na hora. Para quando nada mais está em análise, e no máximo
// 30 conferências seguidas (30 min de aba aberta). `conferir` que falha não para
// nada: a tela fica como estava e tenta na rodada seguinte.
export const INTERVALO_MS = 60 * 1000;
export const MAXIMO_DE_RODADAS = 30;

export function useConferenciaAutomatica(emAnalise, conferir) {
  let timer = null;
  let rodadas = 0;
  let conferindo = false;

  const visivel = () => document.visibilityState === 'visible';
  const pode = () =>
    emAnalise.value && visivel() && rodadas < MAXIMO_DE_RODADAS;

  const parar = () => {
    clearTimeout(timer);
    timer = null;
  };

  const agendar = () => {
    parar();
    // eslint-disable-next-line no-use-before-define
    if (pode()) timer = setTimeout(rodada, INTERVALO_MS);
  };

  const rodada = async () => {
    parar();
    if (conferindo || !pode()) return;
    conferindo = true;
    rodadas += 1;
    try {
      await conferir();
    } catch {
      // Mantém a tela; a próxima rodada tenta de novo.
    } finally {
      conferindo = false;
    }
    agendar();
  };

  const mudouAVisibilidade = () => {
    if (visivel()) rodada();
    else parar();
  };

  // Um modelo voltou a ficar em análise (alterado, corrigido): começa a contar de novo.
  watch(
    () => Boolean(emAnalise.value),
    agora => {
      if (!agora) {
        parar();
        return;
      }
      if (!timer && !conferindo) {
        rodadas = 0;
        agendar();
      }
    }
  );

  onMounted(() => {
    document.addEventListener('visibilitychange', mudouAVisibilidade);
    agendar();
  });

  onUnmounted(() => {
    document.removeEventListener('visibilitychange', mudouAVisibilidade);
    parar();
  });

  return { parar };
}

// O que mudou de "Em análise" para pronto ou recusado, para o aviso da tela.
const MUDANCAS_AVISADAS = ['pronto', 'recusado'];
export const mudancasDeSituacao = (antes, depois) =>
  antes
    .filter(modelo => modelo.situacao === 'em_analise')
    .map(modelo => {
      const agora = depois.find(item => item.id === modelo.id);
      return agora && MUDANCAS_AVISADAS.includes(agora.situacao)
        ? { nome: agora.nome, situacao: agora.situacao }
        : null;
    })
    .filter(Boolean);
