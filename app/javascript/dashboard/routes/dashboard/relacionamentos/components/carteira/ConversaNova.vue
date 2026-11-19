<script setup>
import { nextTick, ref, useTemplateRef } from 'vue';
import { useStore } from 'vuex';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';

// #3057 (2ª rodada) — "Conversar" com quem ainda não tem conversa: abre a
// "Nova conversa" da casa já com a pessoa escolhida. É o mesmo caminho do
// "Enviar mensagem" da página do contato (Relationships/ContactDetailActions):
// a ponte NovaConversaEntrada com `contact-id` (ela escolhe entre a gaveta nova
// e o popover antigo pela flag da conta). As duas abrem pelo clique no gatilho
// e leem o contato do store: `abrir` busca o contato (contacts/show, a mesma
// leitura da página do contato) e aciona o gatilho, um botão escondido.
// Devolve `false` quando não abriu: quem olha só lê conversas (#1800), ou o
// contato não veio. As duas telas alternam no clique (abrem e fecham): o
// gatilho guarda o `isOpen` que elas mandam, `abrir` só clica se ainda está
// fechada e devolve o que ficou de verdade.
const store = useStore();
const podeComecar = usePodeComecarConversa();
const contatoId = ref(null);
const gatilho = useTemplateRef('gatilho');

const estaAberta = () => gatilho.value?.dataset.aberta === 'true';

const abrir = async pessoaId => {
  if (!podeComecar.value) return false;
  try {
    await store.dispatch('contacts/show', { id: pessoaId });
  } catch {
    return false;
  }
  contatoId.value = String(pessoaId);
  await nextTick();
  if (!gatilho.value) return false;
  if (!estaAberta()) gatilho.value.click();
  await nextTick();
  return estaAberta();
};

defineExpose({ abrir });
</script>

<template>
  <NovaConversaEntrada v-if="contatoId" :contact-id="contatoId">
    <template #trigger="{ isOpen }">
      <button
        ref="gatilho"
        :data-aberta="String(Boolean(isOpen))"
        type="button"
        tabindex="-1"
        aria-hidden="true"
        data-carteira="abrir-conversa-nova"
        class="sr-only"
      />
    </template>
  </NovaConversaEntrada>
</template>
