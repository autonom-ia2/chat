<script setup>
import { ref, computed } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Auth from '../../../../api/auth';
import wootConstants from 'dashboard/constants/globals';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CrmScheduleEditor from 'dashboard/routes/dashboard/crm/components/sla/CrmScheduleEditor.vue';
import CrmServiceSchedulesAPI from 'dashboard/api/crmServiceSchedules';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    default: '',
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const { t } = useI18n();

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const selectedRoleId = ref(props.customRoleId || props.type);
const agentCredentials = ref({ email: props.email });

const rules = {
  agentName: { required, minLength: minLength(1) },
  selectedRoleId: { required },
  agentAvailability: { required },
};

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// SLA service-hours calendar (CRM SLA v2): visible only when the CRM fork is
// enabled AND the account has the enterprise `sla` feature.
const showSlaSchedule = computed(
  () =>
    window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
    isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.SLA)
);

const showScheduleEditor = ref(false);
const agentSchedule = ref(null);
const scheduleLoaded = ref(false);
const isLoadingSchedule = ref(false);

const openScheduleEditor = async () => {
  if (!scheduleLoaded.value) {
    isLoadingSchedule.value = true;
    try {
      const response = await CrmServiceSchedulesAPI.get();
      agentSchedule.value =
        (response.data.payload || []).find(
          schedule =>
            schedule.owner_type === 'User' && schedule.owner_id === props.id
        ) ?? null;
      scheduleLoaded.value = true;
    } catch (error) {
      agentSchedule.value = null;
    } finally {
      isLoadingSchedule.value = false;
    }
  }
  showScheduleEditor.value = true;
};

const onScheduleSaved = saved => {
  agentSchedule.value = saved;
  showScheduleEditor.value = false;
};

const roles = computed(() => {
  const defaultRoles = [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
    },
  ];

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const roleChoices = computed(() =>
  roles.value.map(role => ({ value: role.id, label: role.label }))
);

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

// O status atual continua escolhível, como antes (nada desabilitava a opção).
const availabilityChoices = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
  }))
);

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      id: props.id,
      name: agentName.value,
      availability: agentAvailability.value,
    };

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
      payload.custom_role_id = null;
    }

    await store.dispatch('agents/update', payload);
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  try {
    await Auth.resetPassword(agentCredentials.value);
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <ChoiceSelect
            v-model="selectedRoleId"
            :options="roleChoices"
            :aria-label="$t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL')"
            :invalid="v$.selectedRoleId.$error"
            class="w-full"
            :class="v$.selectedRoleId.$error ? 'mb-1' : 'mb-4'"
            @change="v$.selectedRoleId.$touch"
          />
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <ChoiceSelect
            v-model="agentAvailability"
            :options="availabilityChoices"
            :aria-label="$t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL')"
            :invalid="v$.agentAvailability.$error"
            class="w-full"
            :class="v$.agentAvailability.$error ? 'mb-1' : 'mb-4'"
            @change="v$.agentAvailability.$touch"
          />
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
        </label>
      </div>

      <div v-if="showSlaSchedule" class="flex flex-col w-full gap-1 py-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('CRM_SLA.AGENT.SECTION_TITLE') }}
        </span>
        <p class="mb-1 text-xs text-n-slate-11">
          {{ $t('CRM_SLA.AGENT.SECTION_NOTE') }}
        </p>
        <Button
          outline
          slate
          type="button"
          icon="i-lucide-calendar-clock"
          class="w-fit"
          :label="$t('CRM_SLA.AGENT.EDIT_BUTTON')"
          :is-loading="isLoadingSchedule"
          @click.prevent="openScheduleEditor"
        />
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right">
          <Button
            v-if="provider !== 'saml'"
            ghost
            type="button"
            icon="i-lucide-lock-keyhole"
            class="!px-2"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_RESET_BUTTON')"
            @click.prevent="resetPassword"
          />
        </div>
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="v$.$invalid || uiFlags.isUpdating"
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>

    <CrmScheduleEditor
      v-if="showScheduleEditor"
      owner-type="User"
      :owner-id="id"
      :owner-name="name"
      :schedule="agentSchedule"
      @saved="onScheduleSaved"
      @close="showScheduleEditor = false"
    />
  </div>
</template>
