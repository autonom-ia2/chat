// Pedido de "Escrever" vindo do balão do menu recolhido (#1809). O balão some quando
// fecha, e a gaveta dentro dele sumiria junto; então o botão só faz o pedido, e o
// EscreverDoEmail (montado no ícone do menu, que continua na tela) abre a gaveta.
import { ref } from 'vue';

export const pedidoDeEscrever = ref(null);

export const pedirEscrever = caixaId => {
  pedidoDeEscrever.value = { caixaId, quando: Date.now() };
};
