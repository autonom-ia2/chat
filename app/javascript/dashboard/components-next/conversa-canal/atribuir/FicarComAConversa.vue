<script setup>
// #2067: o ícone "ficar com a conversa ao enviar", ao lado do Enviar. Clicar alterna, só
// para a próxima mensagem. Pessoa com check (verde) = fica com a conversa; pessoa cinza =
// não fica. A frase inteira vai na dica e no nome acessível. Alvo de toque de 44 px.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  ficar: { type: Object, required: true },
});

const { t } = useI18n();

const dica = computed(() => {
  const clique = props.ficar.ligada
    ? t('CONVERSA_CANAL.FICAR.DICA_LIGADA')
    : t('CONVERSA_CANAL.FICAR.DICA_DESLIGADA');
  return `${props.ficar.frase}. ${clique}`;
});
</script>

<template>
  <button
    v-tooltip.top-end="dica"
    type="button"
    role="switch"
    :aria-checked="ficar.ligada"
    :aria-label="dica"
    data-ficar-com-a-conversa
    class="grid flex-shrink-0 self-center rounded-full outline-none group size-11 place-content-center focus-visible:ring-2 focus-visible:ring-n-teal-8"
    @click="ficar.alternar"
  >
    <span
      class="grid transition-colors rounded-full size-9 place-content-center"
      :class="
        ficar.ligada
          ? 'bg-n-teal-3 text-n-teal-11 group-hover:bg-n-teal-4'
          : 'text-n-slate-10 group-hover:bg-n-alpha-2'
      "
    >
      <span
        :class="
          ficar.ligada ? 'i-lucide-user-round-check' : 'i-lucide-user-round'
        "
        class="size-5"
        aria-hidden="true"
      />
    </span>
  </button>
</template>
