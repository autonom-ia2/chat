// Mensagem que acabou de ser alcançada pela citação (#1702) ou pelo link com
// ?messageId= (busca, #2211): fica destacada uns 3 s, tempo de o olho achar. Uma conversa
// aberta por vez no painel, então o estado é um só.
import { readonly, ref } from 'vue';

export const DESTAQUE_EM_MS = 3000;

const destacada = ref(null);
let relogio = null;

export const mensagemDestacada = readonly(destacada);

export const destacarMensagem = id => {
  destacada.value = Number(id);
  clearTimeout(relogio);
  relogio = setTimeout(() => {
    destacada.value = null;
  }, DESTAQUE_EM_MS);
};
