<script setup>
// #2211 — uma pessoa sem conversa. Ao tocar, a área da direita abre "Começar conversa com Fulana".
// O telefone aparece como se lê ("+55 41 96666-5555"); o "Escrever" diz o que o toque faz.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import { nomeNoAvatar } from './buscaDaLista';
import {
  nomeOuTelefone,
  telefoneLegivel,
} from 'dashboard/components-next/conversa-canal/mais/telefoneDoPais';

const props = defineProps({
  pessoa: { type: Object, required: true },
  // Quem só lê conversas (#1800) vê a pessoa, sem o "Escrever".
  podeEscrever: { type: Boolean, default: true },
});
const emit = defineEmits(['comecar']);

const { t } = useI18n();
const nome = computed(() =>
  nomeOuTelefone(props.pessoa.name, props.pessoa.phone_number)
);
const contato = computed(
  () =>
    telefoneLegivel(props.pessoa.phone_number) ||
    props.pessoa.email ||
    t('LISTA_DE_CONVERSAS.BUSCA.SEM_DADOS')
);
</script>

<template>
  <component
    :is="podeEscrever ? 'button' : 'div'"
    :type="podeEscrever ? 'button' : undefined"
    data-pessoa-achada
    class="flex items-center w-full gap-3 px-4 py-3 bg-transparent border-0 border-b text-start border-n-weak"
    :class="
      podeEscrever &&
      'hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand'
    "
    @click="podeEscrever && emit('comecar', pessoa)"
  >
    <Avatar
      :name="nomeNoAvatar(nome)"
      :src="pessoa.thumbnail || ''"
      :size="36"
      rounded-full
      class="flex-shrink-0"
    />
    <span class="flex flex-col flex-1 min-w-0">
      <span class="text-sm font-medium truncate text-n-slate-12">
        {{ nome }}
      </span>
      <span class="text-xs truncate text-n-slate-11">{{ contato }}</span>
    </span>
    <span
      v-if="podeEscrever"
      class="inline-flex items-center flex-shrink-0 px-3 text-sm font-medium rounded-lg min-h-11 bg-n-alpha-2 text-n-blue-11"
      data-escrever
    >
      {{ t('LISTA_DE_CONVERSAS.BUSCA.ESCREVER') }}
    </span>
  </component>
</template>
