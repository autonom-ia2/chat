<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ProfilePicker from './component/ProfilePicker.vue';
import PermissionGroup from './component/PermissionGroup.vue';
import RoleSummary from './component/RoleSummary.vue';
import AssignAgentsDialog from './component/AssignAgentsDialog.vue';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';
import { LOCK_REASONS, holdsKey } from 'dashboard/helper/peopleAccess';
import {
  BLANK_PROFILE,
  LEVELS,
  MODULES,
  MODULE_GROUPS,
  SENSITIVE_EXTRAS,
  hasAccess,
  modulesWithKeys,
  profilePermissions,
  setLevel,
  toggleExtra,
  visibleExtras,
} from './permissionMatrix';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const roles = useMapGetter('customRole/getCustomRoles');
const uiFlags = useMapGetter('customRole/getUIFlags');
const agents = useMapGetter('agents/getAgents');

// Fora do administrador (#1931): só monta com as próprias chaves, sem chave de delegação (a menos que
// possa entregar acima do próprio acesso), e não abre a própria função nem uma acima do alcance.
const { canManagePeople, keyLockReason, roleLockReason } = usePeopleAccess();
const withinReach = keys => keys.filter(key => !keyLockReason(key));

const roleId = computed(() => Number(route.params.roleId) || null);
const isNewRole = computed(() => !roleId.value);

const step = ref('edit');
const name = ref('');
const description = ref('');
const permissions = ref([]);
const baseProfile = ref(null);
const search = ref('');
const openGroups = ref([]);
const openRows = ref([]);
const nameError = ref('');
// Chaves do modelo que a pessoa não pode entregar e que ficaram de fora ao aplicá-lo (#2115).
const leftOut = ref([]);

const confirmRef = ref(null);
const confirmation = ref({
  title: '',
  description: '',
  label: '',
  cancel: '',
});
let pendingAction = null;
const assignRef = ref(null);

const findRole = id => roles.value.find(role => role.id === id);

const load = role => {
  name.value = role.name;
  description.value = role.description || '';
  permissions.value = [...role.permissions];
};

const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const getAccount = useMapGetter('accounts/getAccount');
const currentAccountId = useMapGetter('getCurrentAccountId');

// On a fresh page load the account arrives after the editor mounts; until then its
// features read as off. Decide only once the account is there, or a direct link to
// the editor would always bounce to the list.
const isBehindAPaywall = computed(
  () =>
    !!getAccount.value(currentAccountId.value)?.id &&
    !isFeatureEnabledOnAccount.value(currentAccountId.value, 'custom_roles')
);
watch(
  isBehindAPaywall,
  behind => {
    if (behind) router.replace({ name: 'custom_roles_list' });
  },
  { immediate: true }
);

onMounted(async () => {
  // The watch above is already sending this page back to the list.
  if (isBehindAPaywall.value) return null;
  if (!roles.value.length) await store.dispatch('customRole/getCustomRole');
  store.dispatch('agents/get');
  if (roleId.value) {
    const role = findRole(roleId.value);
    if (!role || roleLockReason(role))
      return router.replace({ name: 'custom_roles_list' });
    return load(role);
  }
  const source = findRole(Number(route.query.duplicate));
  // Same rule as the list, which hides Duplicate on roles above the giver.
  if (source && roleLockReason(source) === LOCK_REASONS.ABOVE)
    return router.replace({ name: 'custom_roles_list' });
  if (source) {
    load(source);
    permissions.value = withinReach(permissions.value);
    name.value = t('CUSTOM_ROLE.EDITOR.COPY_NAME', { name: source.name });
    return null;
  }
  step.value = 'pick';
  return null;
});

const backToList = () => router.push({ name: 'custom_roles_list' });

// Step 1 -----------------------------------------------------------------
const applyProfile = key => {
  const full = profilePermissions(key);
  permissions.value = withinReach(full);
  leftOut.value = full.filter(item => !permissions.value.includes(item));
  baseProfile.value = key === BLANK_PROFILE ? null : key;
  openRows.value = [];
  openGroups.value = key === BLANK_PROFILE ? [MODULE_GROUPS[0].key] : [];
  if (isNewRole.value && !name.value && baseProfile.value) {
    name.value = t(`CUSTOM_ROLE.PROFILES.${key}.NAME`);
  }
  step.value = 'edit';
};

const askConfirmation = (texts, action) => {
  confirmation.value = texts;
  pendingAction = action;
  confirmRef.value?.open();
};

const onConfirm = () => {
  confirmRef.value?.close();
  pendingAction?.();
  pendingAction = null;
};

const chooseProfile = key => {
  if (isNewRole.value) return applyProfile(key);
  const profileName = t(`CUSTOM_ROLE.PROFILES.${key}.NAME`);
  return askConfirmation(
    {
      title: t('CUSTOM_ROLE.EDITOR.APPLY_CONFIRM.TITLE', { name: profileName }),
      description: t('CUSTOM_ROLE.EDITOR.APPLY_CONFIRM.DESCRIPTION'),
      label: t('CUSTOM_ROLE.EDITOR.APPLY_CONFIRM.CONFIRM'),
    },
    () => {
      applyProfile(key);
      useAlert(
        t('CUSTOM_ROLE.EDITOR.APPLY_CONFIRM.DONE', { name: profileName })
      );
    }
  );
};

// Step 2 -----------------------------------------------------------------
const query = computed(() => search.value.trim().toLowerCase());
const matches = module => {
  if (!query.value) return true;
  const texts = [
    t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`),
    t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.HINT`),
    ...(module.extras || []).map(key =>
      t(`CUSTOM_ROLE.PERMISSIONS.${key.toUpperCase()}`)
    ),
  ];
  return texts.join(' ').toLowerCase().includes(query.value);
};

const visibleGroups = computed(() =>
  MODULE_GROUPS.map(group => ({
    group,
    modules: group.modules.filter(matches),
  })).filter(item => item.modules.length)
);

const isGroupOpen = key => !!query.value || openGroups.value.includes(key);
const allOpen = computed(() =>
  MODULE_GROUPS.every(group => openGroups.value.includes(group.key))
);
const toggleItem = (list, key) =>
  list.includes(key) ? list.filter(item => item !== key) : [...list, key];

const toggleGroup = key => {
  openGroups.value = toggleItem(openGroups.value, key);
};
const toggleAll = () => {
  openGroups.value = allOpen.value ? [] : MODULE_GROUPS.map(group => group.key);
};
const toggleRow = key => {
  openRows.value = toggleItem(openRows.value, key);
};

const selectLevel = (module, level) => {
  const wasOff = !hasAccess(module, permissions.value);
  permissions.value = setLevel(module, level, permissions.value);
  const opensExtras =
    wasOff && level !== LEVELS.NONE && visibleExtras(module, permissions.value);
  if (opensExtras?.length && !openRows.value.includes(module.key)) {
    openRows.value = [...openRows.value, module.key];
  }
};

const changeExtra = (module, key) => {
  const turningOn = !permissions.value.includes(key);
  const apply = () => {
    permissions.value = toggleExtra(module, key, permissions.value);
  };
  if (!turningOn || !SENSITIVE_EXTRAS.includes(key)) return apply();
  return askConfirmation(
    {
      title: t('CUSTOM_ROLE.EDITOR.SENSITIVE_CONFIRM.TITLE', {
        name: t(`CUSTOM_ROLE.PERMISSIONS.${key.toUpperCase()}`),
      }),
      description: t('CUSTOM_ROLE.EDITOR.SENSITIVE_CONFIRM.DESCRIPTION'),
      label: t('CUSTOM_ROLE.EDITOR.SENSITIVE_CONFIRM.CONFIRM'),
    },
    apply
  );
};

const grantSuggested = (target, level = LEVELS.MANAGE) => {
  permissions.value = setLevel(target, level, permissions.value);
  const group = MODULE_GROUPS.find(item => item.modules.includes(target));
  if (!openGroups.value.includes(group.key)) {
    openGroups.value = [...openGroups.value, group.key];
  }
};

const clearGroup = group => {
  permissions.value = group.modules.reduce(
    (current, module) => setLevel(module, LEVELS.NONE, current),
    permissions.value
  );
};

const leftOutModules = computed(() => modulesWithKeys(leftOut.value));

const areaCount = computed(
  () => MODULES.filter(module => hasAccess(module, permissions.value)).length
);
const isSaving = computed(
  () => uiFlags.value.creatingItem || uiFlags.value.updatingItem
);

// Um nome por conta, sem diferenciar maiúsculas nem espaços (#2185). O servidor confere de novo, e o banco tem
// índice único.
const isNameTaken = value =>
  value !== findRole(roleId.value)?.name &&
  roles.value.some(
    role =>
      role.id !== roleId.value &&
      role.name.trim().toLowerCase() === value.toLowerCase()
  );

// Quem tem a função e as áreas em que ela perde chaves ao salvar (#2185): o administrador confirma antes.
// Passar de ver para editar não é perda: editar inclui ver, como no servidor (holdsKey).
const lostAccess = () => {
  const saved = findRole(roleId.value)?.permissions || [];
  const next = { permissions: permissions.value };
  const removed = saved.filter(key => !holdsKey(next, key));
  return {
    people: agents.value.filter(agent => agent.custom_role_id === roleId.value)
      .length,
    areas: modulesWithKeys(removed),
  };
};

const persist = async payload => {
  try {
    if (isNewRole.value) {
      const role = await store.dispatch('customRole/createCustomRole', payload);
      if (canManagePeople.value) {
        assignRef.value?.open(role);
      } else {
        useAlert(t('CUSTOM_ROLE.ADD.API.SUCCESS_MESSAGE'));
        backToList();
      }
      return;
    }
    await store.dispatch('customRole/updateCustomRole', {
      id: roleId.value,
      ...payload,
    });
    useAlert(t('CUSTOM_ROLE.EDIT.API.SUCCESS_MESSAGE'));
    backToList();
  } catch (error) {
    // O nome é a única recusa de campo que chega aqui: o tamanho é conferido em save, antes de chegar aqui.
    if (error?.attributes?.includes('name')) {
      nameError.value = t('CUSTOM_ROLE.FORM.NAME.TAKEN');
      return;
    }
    useAlert(error?.message || t('CUSTOM_ROLE.FORM.API.ERROR_MESSAGE'));
  }
};

const save = async () => {
  const typedName = name.value.trim();
  if (typedName.length < 2) {
    nameError.value = t('CUSTOM_ROLE.FORM.NAME.ERROR');
    return null;
  }
  if (isNameTaken(typedName)) {
    nameError.value = t('CUSTOM_ROLE.FORM.NAME.TAKEN');
    return null;
  }
  if (!permissions.value.length) {
    useAlert(t('CUSTOM_ROLE.FORM.PERMISSIONS.ERROR'));
    return null;
  }
  const payload = {
    name: typedName,
    description: description.value.trim(),
    permissions: permissions.value,
  };
  if (isNewRole.value) return persist(payload);
  // Conta sobre a lista de agentes de agora: velha ou vazia, ela esconderia quem perde acesso.
  try {
    await store.dispatch('agents/get');
  } catch {
    useAlert(t('CUSTOM_ROLE.FORM.API.ERROR_MESSAGE'));
    return null;
  }
  const { people, areas } = lostAccess();
  if (!people || !areas.length) return persist(payload);
  return askConfirmation(
    {
      title: t('CUSTOM_ROLE.EDITOR.LOST_ACCESS.TITLE', people),
      description: t('CUSTOM_ROLE.EDITOR.LOST_ACCESS.DESCRIPTION', {
        areas: areas
          .map(module => t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`))
          .join(', '),
      }),
      label: t('CUSTOM_ROLE.EDITOR.LOST_ACCESS.CONFIRM'),
      cancel: t('CUSTOM_ROLE.EDITOR.LOST_ACCESS.BACK'),
    },
    () => persist(payload)
  );
};
</script>

<template>
  <div class="w-full">
    <ProfilePicker
      v-if="step === 'pick'"
      :is-new-role="isNewRole"
      :initial-profile="baseProfile || 'AGENT'"
      :reach="withinReach"
      @choose="chooseProfile"
      @back="isNewRole ? backToList() : (step = 'edit')"
    />

    <div v-else class="flex flex-col w-full gap-4 font-inter">
      <div class="flex flex-col items-start w-full">
        <button
          type="button"
          class="inline-flex items-center h-6 gap-1 my-1 text-sm text-n-slate-11 hover:text-n-slate-12"
          @click="backToList"
        >
          <span class="i-lucide-chevron-left size-4" />
          {{ $t('CUSTOM_ROLE.HEADER') }}
        </button>
        <div
          v-if="isNewRole && !route.query.duplicate"
          class="flex items-center gap-2 mt-2 mb-3"
        >
          <span class="w-8 h-1 rounded-full bg-n-brand" />
          <span class="w-8 h-1 rounded-full bg-n-brand" />
          <span class="ms-1 text-label-small text-n-slate-10">
            {{ $t('CUSTOM_ROLE.PICKER.STEP', { step: 2 }) }}
          </span>
        </div>
        <div class="flex items-center justify-between w-full gap-3">
          <h1 class="m-0 text-heading-1 text-n-slate-12">
            {{
              isNewRole
                ? $t('CUSTOM_ROLE.EDITOR.NEW_TITLE')
                : $t('CUSTOM_ROLE.EDIT.TITLE')
            }}
          </h1>
          <Button
            v-if="!isNewRole"
            :label="$t('CUSTOM_ROLE.EDITOR.APPLY_PROFILE')"
            icon="i-lucide-layout-template"
            slate
            faded
            sm
            @click="step = 'pick'"
          />
        </div>
      </div>

      <div
        v-if="isNewRole && baseProfile"
        class="flex items-center gap-3 px-4 py-3 text-sm rounded-xl bg-n-brand/10"
      >
        <span class="i-lucide-sparkles size-4 shrink-0 text-n-blue-11" />
        <span class="flex-1 text-n-slate-12">
          {{
            $t('CUSTOM_ROLE.EDITOR.BASED_ON', {
              name: $t(`CUSTOM_ROLE.PROFILES.${baseProfile}.NAME`),
            })
          }}
        </span>
        <Button
          :label="$t('CUSTOM_ROLE.EDITOR.CHANGE_PROFILE')"
          link
          xs
          class="shrink-0"
          @click="step = 'pick'"
        />
      </div>

      <div
        v-if="leftOutModules.length"
        role="status"
        class="flex items-start gap-3 px-4 py-3 text-sm rounded-xl bg-n-amber-3"
      >
        <span class="i-lucide-lock size-4 mt-0.5 shrink-0 text-n-amber-11" />
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <span class="font-medium text-n-slate-12">
            {{ $t('CUSTOM_ROLE.EDITOR.LEFT_OUT.TITLE') }}
          </span>
          <span class="text-n-slate-11">
            {{ $t('CUSTOM_ROLE.EDITOR.LEFT_OUT.DESCRIPTION') }}
          </span>
          <ul class="flex flex-wrap p-0 m-0 list-none gap-x-3 gap-y-1">
            <li
              v-for="module in leftOutModules"
              :key="module.key"
              class="font-medium text-n-amber-12"
            >
              {{ $t(`CUSTOM_ROLE.MATRIX.MODULES.${module.key}.NAME`) }}
            </li>
          </ul>
        </div>
      </div>

      <section
        class="grid gap-4 p-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-1 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)]"
      >
        <Input
          v-model="name"
          :label="$t('CUSTOM_ROLE.FORM.NAME.LABEL')"
          :placeholder="$t('CUSTOM_ROLE.FORM.NAME.PLACEHOLDER')"
          :message="nameError"
          :message-type="nameError ? 'error' : 'info'"
          autocomplete="off"
          @input="nameError = ''"
        />
        <Input
          v-model="description"
          :label="$t('CUSTOM_ROLE.FORM.DESCRIPTION.LABEL')"
          :placeholder="$t('CUSTOM_ROLE.FORM.DESCRIPTION.PLACEHOLDER')"
        />
      </section>

      <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_17rem]">
        <div class="flex flex-col min-w-0 gap-3">
          <div class="flex items-center gap-2">
            <Input
              v-model="search"
              :placeholder="$t('CUSTOM_ROLE.EDITOR.SEARCH_PLACEHOLDER')"
              type="search"
              size="sm"
              class="flex-1 [&>input]:!pl-8 [&>input]:!rounded-[0.625rem]"
            >
              <template #prefix>
                <span
                  class="absolute -translate-y-1/2 i-lucide-search size-3.5 top-1/2 left-2.5 text-n-slate-11"
                />
              </template>
            </Input>
            <Button
              :label="
                allOpen
                  ? $t('CUSTOM_ROLE.EDITOR.COLLAPSE_ALL')
                  : $t('CUSTOM_ROLE.EDITOR.EXPAND_ALL')
              "
              slate
              faded
              sm
              @click="toggleAll"
            />
          </div>

          <PermissionGroup
            v-for="item in visibleGroups"
            :key="item.group.key"
            :group="item.group"
            :modules="item.modules"
            :permissions="permissions"
            :is-open="isGroupOpen(item.group.key)"
            :open-rows="openRows"
            :key-lock="keyLockReason"
            @toggle="toggleGroup(item.group.key)"
            @clear="clearGroup(item.group)"
            @select-level="selectLevel"
            @toggle-extra="changeExtra"
            @toggle-row="toggleRow"
            @grant-suggested="grantSuggested"
          />
          <p
            v-if="!visibleGroups.length"
            class="p-8 m-0 text-center rounded-xl text-body-main text-n-slate-11 bg-n-solid-1 outline outline-1 outline-n-container"
          >
            {{ $t('CUSTOM_ROLE.EDITOR.NO_MATCH', { query: search }) }}
          </p>

          <section
            class="overflow-hidden rounded-xl outline outline-1 outline-n-container bg-n-solid-1"
          >
            <div
              class="flex items-center gap-2 px-4 py-3 border-b border-n-weak"
            >
              <span class="i-lucide-lock size-3.5 text-n-slate-11" />
              <h3 class="m-0 text-heading-3 text-n-slate-12">
                {{ $t('CUSTOM_ROLE.EDITOR.ADMIN_ONLY.TITLE') }}
              </h3>
            </div>
            <p class="px-4 py-3 m-0 text-sm text-n-slate-11">
              {{ $t('CUSTOM_ROLE.EDITOR.ADMIN_ONLY.ITEMS') }}
            </p>
            <div
              class="flex items-start gap-2 px-4 py-3 border-t border-n-weak bg-n-alpha-1 dark:bg-n-solid-2/50 text-label-small text-n-slate-11"
            >
              <span class="i-lucide-circle-help size-3.5 mt-px shrink-0" />
              {{ $t('CUSTOM_ROLE.EDITOR.ADMIN_ONLY.GUIDE') }}
            </div>
          </section>
        </div>
        <RoleSummary :permissions="permissions" class="lg:sticky lg:top-4" />
      </div>

      <div
        class="sticky bottom-0 z-10 flex items-center justify-between gap-3 py-3 -mx-1 px-1 border-t border-n-weak bg-n-surface-1/95 backdrop-blur"
      >
        <span class="truncate text-body-main text-n-slate-11">
          {{ $t('CUSTOM_ROLE.EDITOR.FOOTER_COUNT', areaCount) }}
        </span>
        <div class="flex gap-2 shrink-0">
          <Button
            :label="$t('CUSTOM_ROLE.FORM.CANCEL_BUTTON_TEXT')"
            slate
            faded
            @click="backToList"
          />
          <Button
            :label="
              isNewRole
                ? $t('CUSTOM_ROLE.ADD.SUBMIT')
                : $t('CUSTOM_ROLE.EDIT.SUBMIT')
            "
            :is-loading="isSaving"
            :disabled="isSaving"
            @click="save"
          />
        </div>
      </div>
    </div>

    <Dialog
      ref="confirmRef"
      :title="confirmation.title"
      :description="confirmation.description"
      :confirm-button-label="confirmation.label"
      :cancel-button-label="confirmation.cancel || ''"
      @confirm="onConfirm"
    />
    <AssignAgentsDialog ref="assignRef" @done="backToList" />
  </div>
</template>
