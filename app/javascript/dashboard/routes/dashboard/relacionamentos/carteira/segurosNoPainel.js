// #2897 — o painel da conversa só ganha o bloco Seguros na demonstração da
// carteira (`?demo=<estado>`, só no ambiente de desenvolvimento). Fora dela
// devolve `null` e o painel fica como é. A peça chega por import dinâmico: não
// entra no pacote de produção. O endereço é lido da janela porque o painel
// também é montado onde não há roteador.
import { defineAsyncComponent } from 'vue';
import { contaDeSeguros } from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';

const PAINEL = import.meta.env.DEV
  ? defineAsyncComponent(
      () => import('../components/carteira/PainelDeSeguros.vue')
    )
  : null;

export const segurosNoPainel = (endereco = window.location.search) => {
  if (!PAINEL) return null;
  usarDemo(Object.fromEntries(new URLSearchParams(endereco)));
  return contaDeSeguros() ? PAINEL : null;
};
