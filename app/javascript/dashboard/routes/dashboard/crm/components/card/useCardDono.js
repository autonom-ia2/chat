import { computed, ref, watch } from 'vue';

// #1423 — quem cuida (DN-02/OB-07): a troca do dono na própria gaveta. A
// escolha começa no dono atual a cada vez que a tela abre; salvar manda só o
// `owner_id` e, quando a página confirma, volta ao resumo.
export const useCardDono = ({
  card,
  agentes,
  tela,
  podeGerenciar,
  emit,
  voltarSemGuarda,
}) => {
  const escolhido = ref('');
  const atual = () => card.value.owner?.id || '';
  const sujo = computed(
    () =>
      tela.value === 'dono' && String(escolhido.value || '') !== String(atual())
  );
  const nome = computed(
    () =>
      agentes.value.find(agente => agente.id === escolhido.value)?.name ||
      card.value.owner?.name ||
      ''
  );
  watch(tela, destino => {
    if (destino === 'dono') escolhido.value = atual();
  });
  const desfazer = () => {
    escolhido.value = atual();
  };
  const salvar = () => {
    if (!podeGerenciar.value || !sujo.value) return;
    emit('save', { owner_id: escolhido.value }, undefined, () => {
      if (tela.value === 'dono') voltarSemGuarda();
    });
  };
  return { escolhido, sujo, nome, desfazer, salvar };
};
