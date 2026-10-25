<script setup>
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import CustomRoleCard from './component/CustomRoleCard.vue';
import CustomRolePaywall from './component/CustomRolePaywall.vue';
import DeleteRoleDialog from './component/DeleteRoleDialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { picoSearch } from '@chatwoot/pico-search';
import { usePeopleAccess } from 'dashboard/composables/usePeopleAccess';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const loading = ref({});
const showDeleteConfirmationPopup = ref(false);
const activeResponse = ref({});
const searchQuery = ref('');
const deleteRoleRef = ref(null);

const records = useMapGetter('customRole/getCustomRoles');
const agents = useMapGetter('agents/getAgents');

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name', 'description']);
});
const uiFlags = useMapGetter('customRole/getUIFlags');
// Fora do administrador (#1931): ninguém edita a própria função nem uma acima do seu alcance, e só
// duplica o que poderia criar.
const { roleLockReason, reachesRole } = usePeopleAccess();

const agentsOf = role =>
  agents.value.filter(agent => agent.custom_role_id === role.id);

const deleteConfirmText = computed(
  () => `${t('CUSTOM_ROLE.DELETE.CONFIRM.YES')} ${activeResponse.value.name}`
);

const deleteRejectText = computed(
  () => `${t('CUSTOM_ROLE.DELETE.CONFIRM.NO')} ${activeResponse.value.name}`
);

const deleteMessage = computed(() => {
  return ` ${activeResponse.value.name} ? `;
});

const isFeatureEnabledOnAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const currentAccountId = useMapGetter('getCurrentAccountId');

const isBehindAPaywall = computed(() => {
  return !isFeatureEnabledOnAccount.value(
    currentAccountId.value,
    'custom_roles'
  );
});

const fetchCustomRoles = async () => {
  try {
    await store.dispatch('customRole/getCustomRole');
  } catch (error) {
    // Ignore Error
  }
};

onMounted(() => {
  fetchCustomRoles();
  store.dispatch('agents/get');
});

const showAlertMessage = message => {
  loading.value[activeResponse.value.id] = false;
  activeResponse.value = {};
  useAlert(message);
};

const openNewRole = () => {
  if (isBehindAPaywall.value) return;
  router.push({ name: 'custom_roles_new' });
};

const openEditRole = role => {
  router.push({ name: 'custom_roles_edit', params: { roleId: role.id } });
};

const duplicateRole = role => {
  router.push({ name: 'custom_roles_new', query: { duplicate: role.id } });
};

// Com gente na função, pergunta antes para onde essas pessoas vão (#2185).
const openDeletePopup = response => {
  activeResponse.value = response;
  const people = agentsOf(response).length;
  if (people) {
    deleteRoleRef.value?.open(response, people);
    return;
  }
  showDeleteConfirmationPopup.value = true;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

// A lista de agentes chega depois da tela ou ficou velha, e o servidor achou gente na função: recarrega e faz a
// pergunta do destino em vez de só mostrar o aviso.
const askDestinationAfterRefusal = async (id, message) => {
  loading.value[id] = false;
  await store.dispatch('agents/get');
  const role = records.value.find(item => item.id === id);
  const people = role ? agentsOf(role).length : 0;
  if (!people) {
    showAlertMessage(message);
    return;
  }
  activeResponse.value = role;
  deleteRoleRef.value?.open(role, people);
};

const deleteCustomRole = async (id, destinationRoleId) => {
  try {
    await store.dispatch('customRole/deleteCustomRole', {
      id,
      destinationRoleId,
    });
    // As pessoas mudaram de função: a lista de agentes precisa refletir isso.
    if (destinationRoleId) store.dispatch('agents/get');
    showAlertMessage(t('CUSTOM_ROLE.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CUSTOM_ROLE.DELETE.API.ERROR_MESSAGE');
    if (error?.code === 'destination_required') {
      await askDestinationAfterRefusal(id, errorMessage);
      return;
    }
    showAlertMessage(errorMessage);
  }
};

const confirmDeletion = () => {
  loading.value[activeResponse.value.id] = true;
  closeDeletePopup();
  deleteCustomRole(activeResponse.value.id);
};

const confirmMoveAndDeletion = ({ role, destinationRoleId }) => {
  loading.value[role.id] = true;
  deleteCustomRole(role.id, destinationRoleId);
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="$t('CUSTOM_ROLE.LOADING')"
    :no-records-found="!records.length && !isBehindAPaywall"
    :no-records-message="$t('CUSTOM_ROLE.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('CUSTOM_ROLE.HEADER')"
        :description="$t('CUSTOM_ROLE.DESCRIPTION')"
        :link-text="$t('CUSTOM_ROLE.LEARN_MORE')"
        :search-placeholder="$t('CUSTOM_ROLE.SEARCH_PLACEHOLDER')"
        feature-name="canned_responses"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('CUSTOM_ROLE.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('CUSTOM_ROLE.HEADER_BTN_TXT')"
            icon="i-lucide-plus"
            size="sm"
            :disabled="isBehindAPaywall"
            @click="openNewRole"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <CustomRolePaywall v-if="isBehindAPaywall" />
      <template v-else>
        <p
          v-if="!filteredRecords.length"
          class="py-20 m-0 text-center text-base text-n-slate-11"
        >
          {{ $t('CUSTOM_ROLE.NO_RESULTS') }}
        </p>
        <div v-else class="grid gap-3 sm:grid-cols-2">
          <CustomRoleCard
            v-for="role in filteredRecords"
            :key="role.id"
            :role="role"
            :agents="agentsOf(role)"
            :is-deleting="!!loading[role.id]"
            :lock-reason="roleLockReason(role) || ''"
            :can-duplicate="reachesRole(role)"
            @edit="openEditRole"
            @duplicate="duplicateRole"
            @delete="openDeletePopup"
          />
        </div>
        <p
          class="flex items-center gap-1.5 mt-3 mb-0 text-label-small text-n-slate-10"
        >
          <span class="i-lucide-info size-3.5" />
          {{ $t('CUSTOM_ROLE.LIST.DEFAULT_ROLES_NOTE') }}
        </p>
      </template>
    </template>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CUSTOM_ROLE.DELETE.CONFIRM.TITLE')"
      :message="$t('CUSTOM_ROLE.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />
    <DeleteRoleDialog ref="deleteRoleRef" @confirm="confirmMoveAndDeletion" />
  </SettingsLayout>
</template>
