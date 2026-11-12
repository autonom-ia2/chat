<script setup>
import { ref, computed, watch, provide } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import MacroForm from './MacroForm.vue';
import { MACRO_ACTION_TYPES } from './constants';
import { useAlert } from 'dashboard/composables';
import actionQueryGenerator from 'dashboard/helper/actionQueryGenerator.js';
import { getActionIcon } from 'dashboard/helper/automationHelper';
import { useMacros } from 'dashboard/composables/useMacros';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  useHasCustomRolePermission,
  usePermissionGranted,
} from 'dashboard/composables/useCanManage';
import { acoesOferecidas, webhookTravado } from './macroWebhook';

const store = useStore();
const getters = useStoreGetters();

const route = useRoute();
const router = useRouter();

const { t } = useI18n();

const { getMacroDropdownValues } = useMacros();
const { isAdmin: isAccountAdmin } = useAdmin();
const hasMacroManage = useHasCustomRolePermission('macro_manage');
// Custom roles with macro_manage (#452) manage team-wide macros like admins.
const isAdmin = computed(() => isAccountAdmin.value || hasMacroManage.value);

const macro = ref(null);
const mode = ref('CREATE');
// #2451: o webhook pede integration_manage. As ações com que a macro chegou: tirar o webhook também é mexer.
const podeIntegrar = usePermissionGranted('integration_manage');
const acoesAoAbrir = ref([]);
const salvarTravado = computed(() =>
  webhookTravado(podeIntegrar.value, macro.value?.actions, acoesAoAbrir.value)
);

const macroActionTypes = computed(() => {
  return acoesOferecidas(
    MACRO_ACTION_TYPES,
    podeIntegrar.value,
    macro.value?.actions
  ).map(type => ({
    ...type,
    label: t(`MACROS.ACTIONS.${type.label}`),
    icon: getActionIcon(type.key),
  }));
});

provide('macroActionTypes', macroActionTypes);

const uiFlags = computed(() => getters['macros/getUIFlags'].value);
const macroId = computed(() => route.params.macroId);
const isPublicMacroReadOnly = computed(
  () => macro.value?.visibility === 'global' && !isAdmin.value
);

const fetchDropdownData = () =>
  Promise.all([
    store.dispatch('agents/get'),
    store.dispatch('teams/get'),
    store.dispatch('labels/get'),
  ]);

const formatMacro = macroData => {
  const formattedActions = macroData.actions.map(action => {
    let actionParams = [];
    if (action.action_params.length) {
      const inputType = MACRO_ACTION_TYPES.find(
        item => item.key === action.action_name
      ).inputType;
      if (inputType === 'multi_select' || inputType === 'search_select') {
        actionParams = getMacroDropdownValues(action.action_name).filter(item =>
          [...action.action_params].includes(item.id)
        );
      } else actionParams = [...action.action_params];
    }
    return {
      ...action,
      action_params: actionParams,
    };
  });
  return {
    ...macroData,
    actions: formattedActions,
  };
};

const manifestMacro = async () => {
  await Promise.all([
    fetchDropdownData(),
    store.dispatch('macros/getSingleMacro', macroId.value),
  ]);
  const singleMacro = store.getters['macros/getMacro'](macroId.value);
  acoesAoAbrir.value = singleMacro.actions.map(({ action_name }) => ({
    action_name,
  }));
  macro.value = formatMacro(singleMacro);
};

const fetchMacro = () => {
  mode.value = 'EDIT';
  manifestMacro();
};

const initNewMacro = () => {
  mode.value = 'CREATE';
  acoesAoAbrir.value = [];
  macro.value = {
    name: '',
    actions: [
      {
        action_name: 'assign_team',
        action_params: [],
      },
    ],
    visibility: isAdmin.value ? 'global' : 'personal',
  };
};

watch(
  () => route,
  () => {
    if (route.params.macroId) {
      fetchMacro();
    } else {
      fetchDropdownData();
      initNewMacro();
    }
  },
  { immediate: true, deep: true }
);

const saveMacro = async macroData => {
  if (isPublicMacroReadOnly.value || salvarTravado.value) return;

  try {
    const action = mode.value === 'EDIT' ? 'macros/update' : 'macros/create';
    const successMessage =
      mode.value === 'EDIT'
        ? t('MACROS.EDIT.API.SUCCESS_MESSAGE')
        : t('MACROS.ADD.API.SUCCESS_MESSAGE');
    let serializedMacro = JSON.parse(JSON.stringify(macroData));
    serializedMacro.actions = actionQueryGenerator(serializedMacro.actions);
    await store.dispatch(action, serializedMacro);
    useAlert(successMessage);
    router.push({ name: 'macros_wrapper' });
  } catch (error) {
    useAlert(t('MACROS.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-6 mb-8 max-w-7xl mx-auto h-full w-full !px-6">
    <woot-loading-state
      v-if="uiFlags.isFetchingItem"
      :message="t('MACROS.EDITOR.LOADING')"
    />
    <MacroForm
      v-if="macro && !uiFlags.isFetchingItem"
      :macro-data="macro"
      :can-manage-public-macros="isAdmin"
      :read-only="isPublicMacroReadOnly"
      :locked-reason="salvarTravado ? t('MACROS.WEBHOOK_LOCKED') : ''"
      @update:macro-data="macro = $event"
      @submit="saveMacro"
    />
  </div>
</template>
