import { nextTick } from 'vue';

// Uma mudança que tira do lugar (ou apaga) o elemento com o foco deixa o foco no body: quem usa teclado volta ao topo
// e o leitor de tela fica mudo (#2308, especificação 14). Depois da mudança, se o foco se perdeu, vai para o primeiro
// alvo que existir: o mesmo controle no lugar novo, um vizinho ou um ponto estável (o título).
const focoPerdido = () => {
  const ativo = document.activeElement;
  return !ativo || ativo === document.body || !ativo.isConnected;
};

export const devolverFoco = async (raiz, seletores) => {
  await nextTick();
  if (!focoPerdido()) return;
  const alvo = seletores
    .map(seletor => raiz?.querySelector(seletor))
    .find(Boolean);
  alvo?.focus();
};
