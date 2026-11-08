// #2202 — um relógio só para a lista inteira: 300 cards, 1 timer. Cada card que usa
// soma um; quando o último sai, o timer para. `agora` em segundos.
import { onBeforeUnmount, ref } from 'vue';

export const PASSO_DO_RELOGIO_MS = 30000;

const agora = ref(Math.floor(Date.now() / 1000));
let usuarios = 0;
let timer = null;

const bater = () => {
  agora.value = Math.floor(Date.now() / 1000);
};

export const timersAtivos = () => (timer ? 1 : 0);

export function useRelogioDaLista() {
  usuarios += 1;
  if (!timer) {
    bater();
    timer = setInterval(bater, PASSO_DO_RELOGIO_MS);
  }
  onBeforeUnmount(() => {
    usuarios -= 1;
    if (usuarios > 0 || !timer) return;
    clearInterval(timer);
    timer = null;
  });
  return agora;
}
