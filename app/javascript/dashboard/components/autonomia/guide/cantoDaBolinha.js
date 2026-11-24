import { computed, onBeforeUnmount, ref, watch } from 'vue';

// #3192 — telas cujo botão de enviar mora no canto de baixo à direita, o mesmo
// da bolinha do Guia no celular. A tela avisa enquanto o canto é dela, e a
// bolinha some. Só a tela sabe: a criação de agente (rota /agents/new) mostra
// primeiro a escolha do modelo, sem caixa de envio, onde a bolinha fica.
// Cada tela solta só o próprio aviso: uma que sai depois de outra entrar não
// devolve o canto que a outra pegou.
const donas = ref(new Set());

export const cantoOcupadoPelaTela = computed(() => donas.value.size > 0);

export const useOcuparCantoDaBolinha = ocupado => {
  const dona = Symbol('tela');
  const marcar = valor => {
    const novas = new Set(donas.value);
    if (valor) novas.add(dona);
    else novas.delete(dona);
    donas.value = novas;
  };
  watch(ocupado, marcar, { immediate: true });
  onBeforeUnmount(() => marcar(false));
};
