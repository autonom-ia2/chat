<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';

const props = defineProps({
  agentId: { type: [String, Number], required: true },
  agent: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['saved']);
const { t } = useI18n();

const name = ref('');
const voice = ref('feminina');
const avatarPreview = ref('');
const isSaving = ref(false);
const isAvatarSaving = ref(false);
const nameError = ref('');

const VOICE_OPTIONS = [
  { value: 'feminina', key: 'SHE' },
  { value: 'masculina', key: 'HE' },
];

const avatarSource = computed(
  () => avatarPreview.value || props.agent.avatar_url || ''
);

const sync = agent => {
  name.value = agent?.name || '';
  voice.value = ['feminina', 'masculina'].includes(agent?.voice)
    ? agent.voice
    : 'feminina';
  avatarPreview.value = '';
  nameError.value = '';
};

watch(
  [() => props.agentId, () => props.agent?.name, () => props.agent?.voice],
  () => sync(props.agent),
  { immediate: true }
);

const responseAgent = response =>
  response?.data?.payload || response?.data || response;

const save = async () => {
  if (!props.canManage || isSaving.value) return;
  const nextName = name.value.trim();
  if (!nextName) {
    nameError.value = t(
      'AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.NAME_REQUIRED'
    );
    return;
  }

  nameError.value = '';
  isSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.update(props.agentId, {
      agent: { name: nextName, voice: voice.value },
    });
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const uploadAvatar = async ({ file, url }) => {
  if (!props.canManage || !file || isAvatarSaving.value) return;
  avatarPreview.value = url || '';
  isAvatarSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.updateAvatar(props.agentId, file);
    avatarPreview.value = '';
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.AVATAR_SAVED'));
  } catch (error) {
    avatarPreview.value = '';
    useAlert(
      error?.message ||
        t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.AVATAR_SAVE_ERROR')
    );
  } finally {
    isAvatarSaving.value = false;
  }
};

const removeAvatar = async () => {
  if (!props.canManage || isAvatarSaving.value || !avatarSource.value) return;
  isAvatarSaving.value = true;
  try {
    const response = await AutonomiaAgentsAPI.deleteAvatar(props.agentId);
    emit('saved', responseAgent(response));
    useAlert(t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.AVATAR_REMOVED'));
  } catch (error) {
    useAlert(
      error?.message ||
        t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.AVATAR_REMOVE_ERROR')
    );
  } finally {
    isAvatarSaving.value = false;
  }
};
</script>

<template>
  <section
    data-test="settings-identity"
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <div>
      <h2 class="text-base font-semibold text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-wrap items-center gap-4">
      <Avatar
        :name="name"
        :src="avatarSource"
        :size="64"
        rounded-full
        :allow-upload="canManage && !isAvatarSaving"
        @upload="uploadAvatar"
      />
      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.PHOTO') }}
        </span>
        <Button
          v-if="avatarSource"
          outline
          sm
          :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.REMOVE_PHOTO')"
          :disabled="!canManage || isAvatarSaving"
          @click="removeAvatar"
        />
      </div>
    </div>

    <Input
      v-model="name"
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.NAME')"
      :message="nameError"
      message-type="error"
      :disabled="!canManage || isSaving"
      data-test="identity-name"
    />

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.VOICE_LABEL') }}
      </span>
      <div
        role="radiogroup"
        :aria-label="t('AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.VOICE_LABEL')"
        class="flex flex-wrap gap-2"
      >
        <button
          v-for="option in VOICE_OPTIONS"
          :key="option.value"
          type="button"
          role="radio"
          :aria-checked="voice === option.value"
          :disabled="!canManage || isSaving"
          class="min-h-11 px-4 text-sm border rounded-xl outline-none focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50"
          :class="
            voice === option.value
              ? 'border-n-blue-11 bg-n-blue-3 text-n-blue-12'
              : 'border-n-weak text-n-slate-11 hover:border-n-strong'
          "
          :data-test="`voice-${option.value}`"
          @click="voice = option.value"
        >
          {{ t(`AGENTS.PANEL.REDESIGN_SETTINGS.IDENTITY.VOICE.${option.key}`) }}
        </button>
      </div>
    </div>

    <Button
      solid
      sm
      :label="t('AGENTS.PANEL.REDESIGN_SETTINGS.SAVE')"
      :is-loading="isSaving"
      :disabled="!canManage || isSaving || isAvatarSaving"
      class="self-start !bg-n-blue-11 !text-white dark:!text-n-navy hover:enabled:!bg-n-blue-12 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:!outline-n-blue-11"
      data-test="identity-save"
      @click="save"
    />
  </section>
</template>
