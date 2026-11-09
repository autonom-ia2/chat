import { onMounted, onBeforeUnmount, ref } from 'vue';

// #2207 — o botão flutuante do menu some enquanto a página rola, para não cobrir o começo das linhas, e volta
// quando a rolagem para. O painel rola numa div interna (o <main> do Dashboard é overflow-hidden), por isso a
// escuta fica no document em captura: pega a rolagem de qualquer elemento, inclusive a da página inteira.
export const ATRASO_PARA_VOLTAR_MS = 600;
// Rolagem sem fim (arrastar longo, rolagem feita por código) não esconde o botão para sempre: passado este
// tempo, ele volta mesmo com a rolagem andando.
export const TEMPO_MAXIMO_ESCONDIDO_MS = 4000;

const OPCOES = { capture: true, passive: true };

export const useEscondeAoRolar = alvo => {
  const rolando = ref(false);
  let espera = null;
  let inicio = null;

  const voltar = () => {
    rolando.value = false;
    espera = null;
    inicio = null;
  };

  const aoRolar = () => {
    // Com o foco no botão (teclado), ele fica visível.
    if (alvo.value?.contains(document.activeElement)) return;
    inicio ??= Date.now();
    rolando.value = Date.now() - inicio < TEMPO_MAXIMO_ESCONDIDO_MS;
    clearTimeout(espera);
    espera = setTimeout(voltar, ATRASO_PARA_VOLTAR_MS);
  };

  onMounted(() => document.addEventListener('scroll', aoRolar, OPCOES));
  onBeforeUnmount(() => {
    document.removeEventListener('scroll', aoRolar, { capture: true });
    clearTimeout(espera);
  });

  return { rolando };
};
