// Mensagem que acabou de ser alcançada pela citação (#1702): pisca por um instante,
// como no app. Uma conversa aberta por vez no painel, então o estado é um só.
import { readonly, ref } from 'vue';

export const DESTAQUE_EM_MS = 1500;

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
