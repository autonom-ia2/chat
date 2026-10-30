<script setup>
// #2138 — "Time e prioridade", aberto pelo ⋯ do topo da conversa. Dois campos de
// escolha (o time só quando a conta tem time) e "Salvar", com as actions de hoje
// (assignTeam e assignPriority). Elas não devolvem erro, então o resultado é
// conferido na conversa guardada: o que não mudou lá não foi salvo.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

const props = defineProps({
  conversa: { type: Object, required: true },
  times: { type: Array, default: () => [] },
});

const { t } = useI18n();
const store = useStore();
const dialogo = ref(null);
const idTime = useId();
const idPrioridade = useId();

const SEM = '';
const PRIORIDADES = ['low', 'medium', 'high', 'urgent'];

const time = ref(SEM);
const prioridade = ref(SEM);
const salvando = ref(false);

const temTime = computed(() => props.times.length > 0);
const opcoesDeTime = computed(() => [
  { value: SEM, label: t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.SEM_TIME') },
  ...props.times.map(item => ({ value: item.id, label: item.name })),
]);
const NOMES = {
  low: () => t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.BAIXA'),
  medium: () => t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.MEDIA'),
  high: () => t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.ALTA'),
  urgent: () => t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.URGENTE'),
};
const opcoesDePrioridade = computed(() => [
  {
    value: SEM,
    label: t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.SEM_PRIORIDADE'),
  },
  ...PRIORIDADES.map(valor => ({ value: valor, label: NOMES[valor]() })),
]);

const timeAtual = () => props.conversa?.meta?.team?.id ?? SEM;
const prioridadeAtual = () => props.conversa?.priority || SEM;

const abrir = () => {
  time.value = timeAtual();
  prioridade.value = prioridadeAtual();
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

const guardada = () =>
  store.getters.getConversationById(props.conversa.id) || props.conversa;

const salvar = async () => {
  if (salvando.value) return;
  const id = props.conversa.id;
  const mudouTime = temTime.value && time.value !== timeAtual();
  const mudouPrioridade = prioridade.value !== prioridadeAtual();
  salvando.value = true;
  try {
    if (mudouTime)
      await store.dispatch('assignTeam', {
        conversationId: id,
        teamId: time.value === SEM ? 0 : time.value,
      });
    if (mudouPrioridade)
      await store.dispatch('assignPriority', {
        conversationId: id,
        priority: prioridade.value === SEM ? null : prioridade.value,
      });
  } finally {
    salvando.value = false;
  }
  const depois = guardada();
  const timeSalvo = !mudouTime || (depois.meta?.team?.id ?? SEM) === time.value;
  const prioridadeSalva =
    !mudouPrioridade || (depois.priority || SEM) === prioridade.value;
  if (!timeSalvo || !prioridadeSalva) {
    useAlert(t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.ERRO'));
    return;
  }
  useAlert(t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.PRONTO'));
  fechar();
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    data-dialogo-time-e-prioridade
    :title="
      temTime
        ? t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.TITULO')
        : t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.TITULO_SO_PRIORIDADE')
    "
    width="sm"
    @confirm="salvar"
  >
    <div class="flex flex-col gap-4">
      <div v-if="temTime" class="flex flex-col gap-1">
        <label :for="idTime" class="text-sm font-medium text-n-slate-12">
          {{ t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.TIME') }}
        </label>
        <ChoiceSelect
          v-model="time"
          :trigger-id="idTime"
          :options="opcoesDeTime"
          :aria-label="t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.TIME')"
          class="w-full"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label :for="idPrioridade" class="text-sm font-medium text-n-slate-12">
          {{ t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.PRIORIDADE') }}
        </label>
        <ChoiceSelect
          v-model="prioridade"
          :trigger-id="idPrioridade"
          :options="opcoesDePrioridade"
          :aria-label="t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.PRIORIDADE')"
          class="w-full"
        />
      </div>
    </div>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          :label="t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.CANCELAR')"
          slate
          faded
          class="!min-h-11"
          @click="fechar"
        />
        <Button
          type="submit"
          :label="t('PAINEL_DO_CONTATO.TIME_E_PRIORIDADE.SALVAR')"
          :is-loading="salvando"
          :disabled="salvando"
          class="!min-h-11"
        />
      </div>
    </template>
  </Dialog>
</template>
