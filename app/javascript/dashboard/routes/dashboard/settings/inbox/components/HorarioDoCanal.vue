<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import DiaDoHorario from './DiaDoHorario.vue';
import { diaValido, diasDaCaixa, paraWorkingHours } from './horarioDoCanal';

// #1619 (flag `horario_unico_caixa`) — o horário do canal, única fonte do horário da caixa: o agente
// de IA que atende "só no horário", o SLA e a mensagem de fora do horário seguem este horário, no
// fuso da conta. No lugar do WeeklyAvailability do Chatwoot (que continua sem a flag): sem o campo
// de fuso, horas em 24 h pelo ChoiceSelect. Salva pela mesma API, sem mandar `timezone`.
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useStore();
const NS = 'HORARIO_DO_CANAL.CANAL';

const canManage = useCanManage('inbox_manage');
const papel = useMapGetter('getCurrentRole');
const uiFlags = useMapGetter('inboxes/getUIFlags');
// O fuso que o servidor devolve na caixa: com a flag, já é o efetivo (o da conta, ou o padrão do CRM).
const fuso = computed(() => rotuloDoFuso(props.inbox?.timezone));

// A tela de Configurações da conta (onde fica o fuso) é só do administrador.
const podeMudarFuso = computed(() => papel.value === 'administrator');

const ligado = ref(false);
const mensagem = ref('');
const dias = ref(diasDaCaixa(null));

const carregar = () => {
  ligado.value = Boolean(props.inbox?.working_hours_enabled);
  mensagem.value = props.inbox?.out_of_office_message || '';
  dias.value = diasDaCaixa(props.inbox);
};
watch(() => props.inbox, carregar, { immediate: true });

// Como no WeeklyAvailability: Twilio, X e Facebook não aceitam texto formatado.
const SEM_FORMATACAO = [
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.TWITTER,
  INBOX_TYPES.FB,
];
const editorRico = computed(
  () => !SEM_FORMATACAO.includes(props.inbox?.channel_type)
);

const temErro = computed(
  () => ligado.value && dias.value.some(dia => !diaValido(dia))
);

const mudarDia = (indice, dia) => {
  dias.value = dias.value.map((item, i) => (i === indice ? dia : item));
};

const salvar = async () => {
  if (temErro.value) return;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      working_hours_enabled: ligado.value,
      out_of_office_message: mensagem.value,
      working_hours: paraWorkingHours(dias.value),
      channel: {},
    });
    useAlert(t(`${NS}.SALVO`));
  } catch (error) {
    useAlert(error?.message || t(`${NS}.ERRO_SALVAR`));
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 mx-6">
    <SettingsToggleSection
      v-model="ligado"
      :header="t(`${NS}.LIGAR`)"
      :description="t(`${NS}.LIGAR_AJUDA`)"
    >
      <template v-if="ligado" #editor>
        <p class="mt-1 mb-1.5 text-body-main font-medium text-n-slate-12">
          {{ t(`${NS}.MENSAGEM`) }}
        </p>
        <WootMessageEditor
          v-if="editorRico"
          v-model="mensagem"
          enable-variables
          is-format-mode
          :placeholder="t(`${NS}.MENSAGEM`)"
          :min-height="4"
          class="[&_.message-editor]:border-0"
        />
        <textarea
          v-else
          v-model="mensagem"
          :aria-label="t(`${NS}.MENSAGEM`)"
          class="min-h-16 mt-1.5"
        />
      </template>
    </SettingsToggleSection>

    <div
      v-if="ligado"
      data-aviso
      class="flex items-start gap-2 p-3 rounded-xl bg-n-blue-2 ring-1 ring-inset ring-n-blue-6 text-body-main text-n-slate-12"
    >
      <span
        class="i-lucide-info size-4 mt-0.5 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      <div class="flex flex-col gap-1.5 min-w-0">
        <p class="m-0">
          <strong class="font-semibold">{{ t(`${NS}.AVISO_TITULO`) }}</strong>
          {{ t(`${NS}.AVISO`) }}
        </p>
        <p class="m-0">
          {{ fuso ? t(`${NS}.FUSO`, { fuso }) : t(`${NS}.FUSO_SEM_NOME`) }}
          <router-link
            v-if="podeMudarFuso"
            data-mudar-fuso
            :to="{ name: 'general_settings_index' }"
            class="inline-flex items-center font-medium underline min-h-11 md:min-h-0 text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          >
            {{ t(`${NS}.MUDAR_FUSO`) }}
          </router-link>
        </p>
      </div>
    </div>
    <div
      v-else
      data-sem-horario
      class="flex items-start gap-2 p-3 rounded-xl bg-n-slate-2 ring-1 ring-inset ring-n-weak text-body-main text-n-slate-12"
    >
      <span
        class="i-lucide-info size-4 mt-0.5 shrink-0 text-n-slate-11"
        aria-hidden="true"
      />
      <p class="m-0">{{ t(`${NS}.SEM_HORARIO`) }}</p>
    </div>

    <form class="flex flex-col" @submit.prevent="salvar">
      <template v-if="ligado">
        <div class="flex items-center py-1 my-4">
          <div class="flex-1 h-px bg-n-weak" />
          <span class="px-2 text-body-main text-n-slate-11">
            {{ t(`${NS}.DIAS_E_HORAS`) }}
          </span>
          <div class="flex-1 h-px bg-n-weak" />
        </div>
        <div
          class="flex flex-col divide-y divide-n-weak rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <div
            aria-hidden="true"
            class="hidden md:grid md:grid-cols-[11rem_minmax(0,1fr)_4rem] gap-x-4 px-4 py-3 text-heading-3 text-n-slate-12"
          >
            <span>{{ t(`${NS}.COLUNA_DIA`) }}</span>
            <span>{{ t(`${NS}.COLUNA_HORARIO`) }}</span>
            <span class="text-end">{{ t(`${NS}.COLUNA_TOTAL`) }}</span>
          </div>
          <DiaDoHorario
            v-for="(dia, indice) in dias"
            :key="dia.dia"
            :model-value="dia"
            :desabilitado="!canManage"
            @update:model-value="mudarDia(indice, $event)"
          />
        </div>
      </template>
      <div v-if="canManage" class="flex justify-end w-full py-4 mt-2">
        <NextButton
          type="submit"
          :label="t(`${NS}.SALVAR`)"
          :is-loading="uiFlags.isUpdating"
          :disabled="temErro"
        />
      </div>
    </form>
  </div>
</template>
