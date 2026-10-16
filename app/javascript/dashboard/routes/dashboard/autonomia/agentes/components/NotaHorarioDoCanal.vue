<script setup>
import { computed, getCurrentInstance, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useEventListener } from '@vueuse/core';
import { useHorarioUnicoCaixa } from 'dashboard/composables/useHorarioUnicoCaixa';
import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';

// #1619 (flag `horario_unico_caixa`) — abaixo de "Quando atende": o horário mostrado é o do canal, o
// mesmo que o agente obedece, no fuso da conta. Com horário: a linha do fuso e "Mudar o horário do
// canal"; sem horário: "Definir o horário do canal". O link abre a tela do canal em outra aba; ao
// voltar para esta, as caixas são relidas e o horário novo já aparece aqui.
// `horario`: texto (tem horário), null (sem horário) ou undefined (caixa fora do mapa: nada).
const props = defineProps({
  inboxId: { type: Number, default: null },
  horario: { type: String, default: undefined },
});

const { t } = useI18n();
const router = useRouter();
// A store da instância (como no useStore), só para reler as caixas ao voltar da outra aba.
const instancia = getCurrentInstance();
const { ligado, fuso } = useHorarioUnicoCaixa();
// Mesmas permissões de quem conecta canal: administrador ou inbox_manage, que editam o horário.
const { podeConectarCanal } = usePermissoesDaJornada();
const NS = 'HORARIO_DO_CANAL.AGENTE';

const temHorario = computed(() => typeof props.horario === 'string');
const semHorario = computed(() => props.horario === null);
const mostrar = computed(
  () => ligado.value && props.inboxId && (temHorario.value || semHorario.value)
);

const link = computed(
  () =>
    router.resolve({
      name: 'settings_inbox_show',
      params: { inboxId: props.inboxId, tab: 'business-hours' },
    }).href
);

const aguardando = ref(false);
useEventListener(document, 'visibilitychange', () => {
  if (!aguardando.value || document.visibilityState !== 'visible') return;
  aguardando.value = false;
  instancia.proxy.$store.dispatch('inboxes/get');
});
</script>

<template>
  <!-- contents: a raiz não cria caixa, então não abre espaço no gap da seção quando não há nota. -->
  <div class="contents">
    <div v-if="mostrar" data-horario-do-canal class="flex flex-col">
      <p v-if="temHorario" data-fuso class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.FUSO`, { fuso }) }}
      </p>
      <a
        v-if="podeConectarCanal"
        data-link-horario
        :href="link"
        target="_blank"
        rel="noopener noreferrer"
        class="relative inline-flex items-center gap-1 text-sm font-medium underline min-h-11 w-fit text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="aguardando = true"
      >
        {{ temHorario ? t(`${NS}.MUDAR`) : t(`${NS}.DEFINIR`) }}
        <span class="i-lucide-external-link size-4" aria-hidden="true" />
        <span class="sr-only">{{ t(`${NS}.NOVA_ABA`) }}</span>
      </a>
    </div>
  </div>
</template>
