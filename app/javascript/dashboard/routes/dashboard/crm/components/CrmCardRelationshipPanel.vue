<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmRelationshipLinkForm from './CrmRelationshipLinkForm.vue';

const props = defineProps({
  card: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  editing: { type: Boolean, default: false },
});
const emit = defineEmits(['edit', 'linked', 'guard']);
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.RELATIONSHIP.${key}`);
const router = useRouter();
const { accountId, currentAccount, isCloudFeatureEnabled } = useAccount();
const companiesEnabled = computed(() =>
  Boolean(currentAccount.value?.id && isCloudFeatureEnabled('companies'))
);
const request = useAbortableRequest();
const person = ref(null);
const company = ref(null);
const failed = ref(false);
const companyFailed = ref(false);
const mode = ref(null);
const linkForm = ref(null);
const dirty = computed(() => Boolean(linkForm.value?.dirty));
const saving = computed(() => Boolean(linkForm.value?.saving));
const contactId = computed(
  () => props.card.contact_id || props.card.contact?.id
);
const identity = computed(
  () => `${accountId.value}:${props.card.id}:${contactId.value || ''}`
);

const reload = async () => {
  person.value = null;
  company.value = null;
  failed.value = false;
  companyFailed.value = false;
  request.abort();
  if (!contactId.value) return;
  const id = contactId.value;
  const withCompany = companiesEnabled.value;
  try {
    const result = await request.run(async () => {
      const { data } = await ContactAPI.show(id);
      const contact = data.payload;
      if (!withCompany || !contact.company_id)
        return { contact, company: null };
      try {
        const response = await CompanyAPI.show(contact.company_id);
        return { contact, company: response.data.payload };
      } catch {
        return { contact, company: null, companyFailed: true };
      }
    });
    if (!result) return;
    person.value = result.contact;
    company.value = result.company;
    companyFailed.value = Boolean(result.companyFailed);
  } catch {
    failed.value = true;
  }
};
const openProfile = entity => {
  const id = entity === 'contact' ? person.value?.id : company.value?.id;
  if (!id) return;
  // New tab preserves the current opportunity and any unsaved commercial draft.
  const target = router.resolve({
    name: entity === 'contact' ? 'contacts_edit' : 'companies_dashboard_show',
    params: {
      accountId: accountId.value,
      [entity === 'contact' ? 'contactId' : 'companyId']: id,
    },
  });
  window.open(target.href, '_blank', 'noopener,noreferrer');
};
const reset = () => {
  mode.value = null;
};
const guard = action => emit('guard', action);
const linked = card => {
  reset();
  emit('linked', card);
};
const details = computed(() => [
  { key: 'PHONE', value: person.value?.phone_number, icon: 'i-lucide-phone' },
  { key: 'EMAIL', value: person.value?.email, icon: 'i-lucide-mail' },
  {
    key: 'ROLE',
    value: person.value?.custom_attributes?.job_title,
    icon: 'i-lucide-briefcase-business',
  },
  {
    key: 'CITY',
    value: person.value?.additional_attributes?.city,
    icon: 'i-lucide-map-pin',
  },
]);
watch(
  [identity, companiesEnabled],
  () => {
    reset();
    reload();
  },
  { immediate: true }
);
defineExpose({ dirty, saving, reset, reload });
</script>

<template>
  <section class="grid min-w-0 gap-4" data-crm-relationship>
    <div class="flex items-center gap-2 text-xs leading-5 text-n-slate-11">
      <span
        class="i-lucide-link-2 size-4 shrink-0 text-n-blue-11"
        aria-hidden="true"
      />
      {{ label('SHARED') }}
    </div>
    <div
      v-if="request.isPending.value"
      role="status"
      class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-6 text-sm text-n-slate-11"
    >
      <span
        class="i-lucide-loader-2 size-5 animate-spin"
        aria-hidden="true"
      />{{ label('LOADING') }}
    </div>
    <div
      v-else-if="failed"
      role="alert"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-5"
    >
      <p class="mb-0 text-sm text-n-slate-11">{{ label('LOAD_ERROR') }}</p>
      <Button
        slate
        outline
        sm
        icon="i-lucide-refresh-cw"
        class="justify-self-start"
        :label="label('RETRY')"
        @click="reload"
      />
    </div>
    <template v-else>
      <div v-if="mode" class="rounded-xl border border-n-weak bg-n-solid-1 p-5">
        <CrmRelationshipLinkForm
          ref="linkForm"
          :key="`${identity}:${mode}`"
          :card-id="card.id"
          :mode="mode"
          @saved="linked"
          @cancel="guard(reset)"
        />
      </div>
      <section
        v-else-if="person"
        class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
        data-relationship-person
      >
        <header class="flex flex-wrap items-center gap-3 px-5 pt-5">
          <Avatar
            :name="person.name || ''"
            :src="person.thumbnail || ''"
            :size="44"
            rounded-full
          />
          <div class="min-w-[8rem] flex-1">
            <h3
              class="mb-1 break-words text-base font-semibold leading-6 text-n-slate-12"
            >
              {{ person.name }}
            </h3>
            <div class="flex items-center gap-2 text-xs text-n-slate-11">
              <span>{{ label('LINKED_CONTACT') }}</span>
              <Button
                v-if="canManage"
                link
                sm
                :label="label('CHANGE')"
                :disabled="editing"
                @click="guard(() => (mode = 'existing'))"
              />
            </div>
          </div>
          <div
            class="flex items-center gap-2 max-[470px]:ms-[3.5rem] max-[470px]:w-full"
          >
            <Button
              v-if="canManage"
              ghost
              sm
              icon="i-lucide-pencil"
              :label="label('EDIT')"
              :disabled="editing"
              @click="emit('edit', person)"
            />
            <Button
              outline
              slate
              sm
              icon="i-lucide-external-link"
              :label="label('OPEN')"
              :aria-label="label('OPEN_CONTACT')"
              @click="openProfile('contact')"
            />
          </div>
        </header>
        <dl
          v-if="!editing"
          class="m-0 grid min-w-0 grid-cols-1 gap-x-5 gap-y-5 p-5 min-[440px]:grid-cols-2"
        >
          <div v-for="item in details" :key="item.key" class="min-w-0">
            <dt
              class="mb-1.5 flex items-center gap-2 text-xs font-normal text-n-slate-11"
            >
              <span
                class="size-3.5 shrink-0"
                :class="[item.icon]"
                aria-hidden="true"
              />{{ label(item.key) }}
            </dt>
            <dd class="m-0 break-words text-sm leading-6 text-n-slate-12">
              {{ item.value || label('NOT_INFORMED') }}
            </dd>
          </div>
        </dl>
        <div v-else class="p-5"><slot name="editor" /></div>
      </section>
      <section
        v-else
        class="flex flex-col items-center rounded-xl border border-dashed border-n-strong bg-n-solid-1 px-6 py-9 text-center"
        data-relationship-empty
      >
        <div
          class="mb-4 flex size-12 items-center justify-center rounded-full bg-n-brand/10 text-n-blue-11"
        >
          <span class="i-lucide-user-round-plus size-6" aria-hidden="true" />
        </div>
        <h3 class="mb-2 text-base font-semibold text-n-slate-12">
          {{ label('EMPTY_TITLE') }}
        </h3>
        <p class="mb-6 max-w-sm text-sm leading-6 text-n-slate-11">
          {{ label('EMPTY_DESCRIPTION') }}
        </p>
        <div v-if="canManage" class="flex flex-wrap justify-center gap-3">
          <Button
            outline
            slate
            icon="i-lucide-link-2"
            :label="label('LINK_CONTACT')"
            @click="mode = 'existing'"
          />
          <Button
            icon="i-lucide-plus"
            :label="label('CREATE_CONTACT')"
            @click="mode = 'new'"
          />
        </div>
      </section>
      <section
        v-if="person && companiesEnabled && !mode"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-5"
        data-relationship-company
      >
        <header class="flex items-center gap-3">
          <div
            class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-brand/10 text-n-blue-11"
          >
            <span class="i-lucide-building-2 size-5" aria-hidden="true" />
          </div>
          <div class="min-w-0 flex-1">
            <h3
              class="mb-1 break-words text-base font-semibold text-n-slate-12"
            >
              {{
                company?.name ||
                label(companyFailed ? 'COMPANY_UNAVAILABLE' : 'NO_COMPANY')
              }}
            </h3>
            <p class="mb-0 text-xs leading-5 text-n-slate-11">
              {{ label(company ? 'LINKED_COMPANY' : 'COMPANY_OPTIONAL') }}
            </p>
          </div>
          <Button
            v-if="company"
            outline
            slate
            sm
            icon="i-lucide-external-link"
            :label="label('OPEN')"
            :aria-label="label('OPEN_COMPANY')"
            @click="openProfile('company')"
          />
        </header>
        <dl v-if="company" class="mb-0 mt-5 grid gap-3 text-sm">
          <div class="flex flex-wrap gap-x-7 gap-y-1">
            <dt class="text-n-slate-11">{{ label('DOMAIN') }}</dt>
            <dd class="m-0 break-all text-n-slate-12">
              {{ company.domain || label('NOT_INFORMED') }}
            </dd>
          </div>
          <div v-if="company.description">
            <dt class="mb-1 text-xs text-n-slate-11">
              {{ label('ABOUT_COMPANY') }}
            </dt>
            <dd class="m-0 text-sm leading-6 text-n-slate-12">
              {{ company.description }}
            </dd>
          </div>
        </dl>
        <p
          v-else-if="person.additional_attributes?.company_name"
          class="mb-0 mt-4 rounded-lg bg-n-amber-3 p-3 text-xs leading-5 text-n-amber-11"
        >
          {{ label('LEGACY_COMPANY') }}:
          {{ person.additional_attributes.company_name }}
        </p>
        <Button
          v-if="companyFailed"
          class="mt-4"
          ghost
          sm
          :label="label('RETRY')"
          @click="reload"
        />
        <Button
          v-else-if="!company && canManage"
          class="mt-4"
          link
          sm
          icon="i-lucide-external-link"
          :label="label('MANAGE_COMPANY')"
          @click="openProfile('contact')"
        />
      </section>
      <details
        v-if="person && !mode && !editing"
        class="group rounded-xl border border-n-weak bg-n-solid-1"
      >
        <summary
          class="flex cursor-pointer list-none items-center gap-2 p-4 text-sm font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-n-brand"
        >
          <span
            class="i-lucide-contact-round size-4 text-n-slate-11"
            aria-hidden="true"
          />{{ label('MORE_CONTACT')
          }}<span
            class="i-lucide-chevron-down ms-auto size-4 text-n-slate-11 group-open:rotate-180"
            aria-hidden="true"
          />
        </summary>
        <dl class="m-0 grid gap-4 border-t border-n-weak p-5">
          <div>
            <dt class="mb-1 text-xs text-n-slate-11">{{ label('ADDRESS') }}</dt>
            <dd class="m-0 text-sm text-n-slate-12">
              {{ person.custom_attributes?.address || label('NOT_INFORMED') }}
            </dd>
          </div>
          <div>
            <dt class="mb-1 text-xs text-n-slate-11">{{ label('COUNTRY') }}</dt>
            <dd class="m-0 text-sm text-n-slate-12">
              {{
                person.additional_attributes?.country || label('NOT_INFORMED')
              }}
            </dd>
          </div>
        </dl>
      </details>
    </template>
  </section>
</template>
