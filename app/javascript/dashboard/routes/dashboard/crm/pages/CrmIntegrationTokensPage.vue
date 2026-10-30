<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import CrmIntegrationTokensAPI from 'dashboard/api/crmIntegrationTokens';
import { useCrmPermissions } from '../composables/useCrmPermissions';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { TOKEN_MANAGE_PERMISSION } from 'dashboard/constants/permissions';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConfirmModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';

const { t } = useI18n();
const router = useRouter();
// Tokens são segredos que a plataforma gera (#2027): administrador ou token_manage. Um token nunca leva mais do que
// a pessoa tem: só aparecem os escopos que a própria função já tem (o servidor confere de novo).
const canManageTokens = usePermissionGranted(TOKEN_MANAGE_PERMISSION);
const { hasCrmPermission } = useCrmPermissions();

const goBack = () => router.back();
// The snippet keeps its line breaks; in one constant the <pre> fits a line and the formatter leaves its text alone.
const SNIPPET_CLASS =
  'overflow-x-auto whitespace-pre-wrap rounded-lg bg-n-alpha-black2 px-3 py-2 font-mono text-xs text-n-slate-11';

// The native CRM scope keys (CustomRole::PERMISSIONS crm_* whitelist, D9; arquivar desde o #1874).
// Order matters for display only; the backend filters to ASSIGNABLE_SCOPES.
const SCOPE_KEYS = [
  'crm_view',
  'crm_manage_cards',
  'crm_move_cards',
  'crm_delete_cards',
  'crm_manage_pipelines',
  'crm_manage_ai',
  'crm_view_reports',
  'crm_admin',
  // #2075: sem ela, o token lê o CRM sem os valores de venda em R$.
  'sales_value_view',
];

const grantableScopes = computed(() =>
  SCOPE_KEYS.filter(scope => hasCrmPermission(scope))
);

const tokens = ref([]);
const isLoading = ref(true);
const loadError = ref(false);

const newTokenName = ref('');
const selectedScopes = ref([]);
const isCreating = ref(false);

// Reveal-once secret box: populated only by create/rotate, cleared on dismiss.
const revealedToken = ref('');
const revealedFor = ref('');

const confirmModal = ref(null);
const confirmConfig = ref({ title: '', description: '', confirmLabel: '' });

const canCreate = computed(
  () => newTokenName.value.trim().length > 0 && selectedScopes.value.length > 0
);

const n8nSnippet = computed(() => {
  const secret = revealedToken.value || '<your-token>';
  return `Header name: api_access_token\nHeader value: ${secret}`;
});

// Human-friendly name shown as the primary scope label.
const scopeName = key =>
  t(`CRM_INTEGRATION_TOKENS.SCOPE_NAMES.${key.toUpperCase()}`);

// Longer description shown as supporting copy under the name.
const scopeLabel = key =>
  t(`CRM_INTEGRATION_TOKENS.SCOPES.${key.toUpperCase()}`);

const statusLabel = status =>
  status === 'revoked'
    ? t('CRM_INTEGRATION_TOKENS.STATUS.REVOKED')
    : t('CRM_INTEGRATION_TOKENS.STATUS.ACTIVE');

const fetchTokens = async () => {
  isLoading.value = true;
  loadError.value = false;
  try {
    const { data } = await CrmIntegrationTokensAPI.get();
    // index.json.jbuilder nests as { payload: { integration_tokens: [...] } }
    tokens.value = data.payload?.integration_tokens || [];
  } catch (error) {
    loadError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const toggleScope = key => {
  const index = selectedScopes.value.indexOf(key);
  if (index === -1) {
    selectedScopes.value.push(key);
  } else {
    selectedScopes.value.splice(index, 1);
  }
};

const resetForm = () => {
  newTokenName.value = '';
  selectedScopes.value = [];
};

const createToken = async () => {
  if (!canCreate.value || isCreating.value) return;
  isCreating.value = true;
  try {
    const { data } = await CrmIntegrationTokensAPI.create({
      name: newTokenName.value.trim(),
      scopes: selectedScopes.value,
    });
    revealedToken.value = data.token || '';
    revealedFor.value = data.name || newTokenName.value.trim();
    resetForm();
    await fetchTokens();
    useAlert(t('CRM_INTEGRATION_TOKENS.CREATE.SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_INTEGRATION_TOKENS.CREATE.ERROR'));
  } finally {
    isCreating.value = false;
  }
};

const copyToken = async () => {
  await copyTextToClipboard(revealedToken.value);
  useAlert(t('CRM_INTEGRATION_TOKENS.REVEAL.COPIED'));
};

const copySnippet = async () => {
  await copyTextToClipboard(n8nSnippet.value);
  useAlert(t('CRM_INTEGRATION_TOKENS.REVEAL.SNIPPET_COPIED'));
};

const dismissRevealedToken = () => {
  revealedToken.value = '';
  revealedFor.value = '';
};

const runRevoke = async token => {
  try {
    await CrmIntegrationTokensAPI.revoke(token.id);
    if (revealedFor.value === token.name) dismissRevealedToken();
    await fetchTokens();
    useAlert(t('CRM_INTEGRATION_TOKENS.REVOKE.SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_INTEGRATION_TOKENS.REVOKE.ERROR'));
  }
};

const runRotate = async token => {
  try {
    const { data } = await CrmIntegrationTokensAPI.rotate(token.id);
    revealedToken.value = data.token || '';
    revealedFor.value = data.name || token.name;
    await fetchTokens();
    useAlert(t('CRM_INTEGRATION_TOKENS.ROTATE.SUCCESS'));
  } catch (error) {
    useAlert(t('CRM_INTEGRATION_TOKENS.ROTATE.ERROR'));
  }
};

const confirmRevoke = async token => {
  confirmConfig.value = {
    title: t('CRM_INTEGRATION_TOKENS.REVOKE.TITLE'),
    description: t('CRM_INTEGRATION_TOKENS.REVOKE.DESCRIPTION', {
      name: token.name,
    }),
    confirmLabel: t('CRM_INTEGRATION_TOKENS.REVOKE.CONFIRM'),
  };
  const ok = await confirmModal.value?.showConfirmation();
  if (ok) await runRevoke(token);
};

const confirmRotate = async token => {
  confirmConfig.value = {
    title: t('CRM_INTEGRATION_TOKENS.ROTATE.TITLE'),
    description: t('CRM_INTEGRATION_TOKENS.ROTATE.DESCRIPTION', {
      name: token.name,
    }),
    confirmLabel: t('CRM_INTEGRATION_TOKENS.ROTATE.CONFIRM'),
  };
  const ok = await confirmModal.value?.showConfirmation();
  if (ok) await runRotate(token);
};

onMounted(fetchTokens);
</script>

<template>
  <main class="flex h-full min-w-0 flex-col overflow-y-auto bg-n-background">
    <header class="flex flex-col gap-3 border-b border-n-weak px-8 py-6">
      <Button
        :label="t('CRM_INTEGRATION_TOKENS.BACK')"
        icon="i-lucide-arrow-left"
        slate
        ghost
        sm
        type="button"
        class="-ml-2 self-start"
        @click="goBack"
      />
      <div class="flex flex-col gap-1">
        <h1 class="mb-0 text-2xl font-medium text-n-slate-12">
          {{ t('CRM_INTEGRATION_TOKENS.TITLE') }}
        </h1>
        <p class="mb-0 max-w-3xl text-sm leading-5 text-n-slate-11">
          {{ t('CRM_INTEGRATION_TOKENS.SUBTITLE') }}
        </p>
      </div>
    </header>

    <div
      v-if="!canManageTokens"
      class="m-8 rounded-xl border border-n-weak bg-n-alpha-black1 px-6 py-8 text-center text-sm text-n-slate-11"
    >
      {{ t('CRM_INTEGRATION_TOKENS.NO_PERMISSION') }}
    </div>

    <div v-else class="flex flex-col gap-6 px-8 py-6">
      <!-- Reveal-once secret box -->
      <section
        v-if="revealedToken"
        class="flex flex-col gap-4 rounded-xl border border-n-teal-6 bg-n-teal-2 px-6 py-5"
      >
        <div class="flex flex-col gap-1">
          <h2 class="mb-0 text-base font-medium text-n-slate-12">
            {{
              t('CRM_INTEGRATION_TOKENS.REVEAL.TITLE', { name: revealedFor })
            }}
          </h2>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('CRM_INTEGRATION_TOKENS.REVEAL.WARNING') }}
          </p>
        </div>
        <div class="flex flex-row items-center gap-3">
          <code
            class="flex-1 select-all break-all rounded-lg bg-n-alpha-black2 px-3 py-2 font-mono text-sm text-n-slate-12"
          >
            {{ revealedToken }}
          </code>
          <Button
            :label="t('CRM_INTEGRATION_TOKENS.REVEAL.COPY')"
            icon="i-lucide-copy"
            slate
            outline
            type="button"
            @click="copyToken"
          />
        </div>
        <div class="flex flex-col gap-2">
          <span class="text-xs font-medium uppercase text-n-slate-10">
            {{ t('CRM_INTEGRATION_TOKENS.REVEAL.SNIPPET_LABEL') }}
          </span>
          <pre :class="SNIPPET_CLASS">{{ n8nSnippet }}</pre>
          <div class="flex flex-row gap-2">
            <Button
              :label="t('CRM_INTEGRATION_TOKENS.REVEAL.SNIPPET_COPY')"
              icon="i-lucide-clipboard"
              slate
              outline
              sm
              type="button"
              @click="copySnippet"
            />
            <Button
              :label="t('CRM_INTEGRATION_TOKENS.REVEAL.DISMISS')"
              ruby
              ghost
              sm
              type="button"
              @click="dismissRevealedToken"
            />
          </div>
        </div>
      </section>

      <!-- Create form -->
      <section
        class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-alpha-black1 px-6 py-5"
      >
        <h2 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CRM_INTEGRATION_TOKENS.CREATE.TITLE') }}
        </h2>
        <Input
          v-model="newTokenName"
          :label="t('CRM_INTEGRATION_TOKENS.CREATE.NAME_LABEL')"
          :placeholder="t('CRM_INTEGRATION_TOKENS.CREATE.NAME_PLACEHOLDER')"
        />
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CRM_INTEGRATION_TOKENS.CREATE.SCOPES_LABEL') }}
          </span>
          <p
            v-if="!grantableScopes.length"
            class="mb-0 text-sm text-n-slate-11"
          >
            {{ t('CRM_INTEGRATION_TOKENS.CREATE.NO_SCOPES') }}
          </p>
          <div v-else class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label
              v-for="scope in grantableScopes"
              :key="scope"
              class="flex cursor-pointer items-start gap-2 rounded-lg border border-n-weak px-3 py-2 hover:bg-n-alpha-2"
            >
              <input
                type="checkbox"
                class="mt-0.5"
                :checked="selectedScopes.includes(scope)"
                @change="toggleScope(scope)"
              />
              <span class="flex min-w-0 flex-col gap-1">
                <span class="flex flex-wrap items-center gap-2">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ scopeName(scope) }}
                  </span>
                  <span
                    class="rounded bg-n-alpha-black2 px-1.5 py-0.5 font-mono text-xs text-n-slate-10"
                  >
                    {{ scope }}
                  </span>
                </span>
                <span class="text-xs text-n-slate-11">
                  {{ scopeLabel(scope) }}
                </span>
              </span>
            </label>
          </div>
        </div>
        <div class="flex flex-row justify-end gap-2">
          <Button
            :label="t('CRM_INTEGRATION_TOKENS.CREATE.CANCEL')"
            slate
            faded
            type="button"
            :disabled="(!newTokenName && !selectedScopes.length) || isCreating"
            @click="resetForm"
          />
          <Button
            :label="t('CRM_INTEGRATION_TOKENS.CREATE.SUBMIT')"
            icon="i-lucide-plus"
            :disabled="!canCreate || isCreating"
            :is-loading="isCreating"
            @click="createToken"
          />
        </div>
      </section>

      <!-- Token list -->
      <section class="flex flex-col gap-3">
        <h2 class="mb-0 text-base font-medium text-n-slate-12">
          {{ t('CRM_INTEGRATION_TOKENS.LIST.TITLE') }}
        </h2>

        <div v-if="isLoading" class="flex justify-center py-10">
          <Spinner />
        </div>

        <div
          v-else-if="loadError"
          class="rounded-xl border border-n-ruby-6 bg-n-ruby-2 px-6 py-4 text-sm text-n-ruby-11"
        >
          {{ t('CRM_INTEGRATION_TOKENS.LIST.ERROR') }}
        </div>

        <div
          v-else-if="tokens.length === 0"
          class="rounded-xl border border-n-weak bg-n-alpha-black1 px-6 py-8 text-center text-sm text-n-slate-11"
        >
          {{ t('CRM_INTEGRATION_TOKENS.LIST.EMPTY') }}
        </div>

        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="token in tokens"
            :key="token.id"
            class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-black1 px-6 py-4 lg:flex-row lg:items-center lg:justify-between"
          >
            <div class="flex min-w-0 flex-col gap-1">
              <div class="flex items-center gap-2">
                <span class="truncate text-sm font-medium text-n-slate-12">
                  {{ token.name }}
                </span>
                <span
                  class="rounded-full px-2 py-0.5 text-xs font-medium"
                  :class="
                    token.status === 'revoked'
                      ? 'bg-n-ruby-3 text-n-ruby-11'
                      : 'bg-n-teal-3 text-n-teal-11'
                  "
                >
                  {{ statusLabel(token.status) }}
                </span>
              </div>
              <div class="flex flex-wrap gap-1">
                <span
                  v-for="scope in token.scopes || []"
                  :key="scope"
                  class="rounded bg-n-alpha-black2 px-1.5 py-0.5 font-mono text-xs text-n-slate-11"
                >
                  {{ scope }}
                </span>
              </div>
            </div>
            <div
              v-if="token.status !== 'revoked'"
              class="flex shrink-0 flex-row gap-2"
            >
              <Button
                v-if="(token.scopes || []).every(hasCrmPermission)"
                :label="t('CRM_INTEGRATION_TOKENS.LIST.ROTATE')"
                icon="i-lucide-refresh-cw"
                slate
                outline
                sm
                @click="confirmRotate(token)"
              />
              <Button
                :label="t('CRM_INTEGRATION_TOKENS.LIST.REVOKE')"
                icon="i-lucide-trash-2"
                ruby
                outline
                sm
                @click="confirmRevoke(token)"
              />
            </div>
          </li>
        </ul>
      </section>
    </div>

    <ConfirmModal
      ref="confirmModal"
      :title="confirmConfig.title"
      :description="confirmConfig.description"
      :confirm-label="confirmConfig.confirmLabel"
      :cancel-label="t('CRM_INTEGRATION_TOKENS.CONFIRM.CANCEL')"
    />
  </main>
</template>
