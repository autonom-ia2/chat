<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { parsePhoneNumberFromString } from 'libphonenumber-js';
import ContactAPI from 'dashboard/api/contacts';
import CompanyAPI from 'dashboard/api/companies';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useRelationships } from 'dashboard/composables/useRelationships';
import { selectDefinitions } from 'dashboard/components-next/Relationships/presentation';
import AttributeDraftFields from 'dashboard/components-next/Relationships/AttributeDraftFields.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import countries from 'shared/constants/countries';
import CrmOpportunityCompanyPicker from './CrmOpportunityCompanyPicker.vue';
import { companyDomain } from './opportunityRegistration';

const props = defineProps({ disabled: { type: Boolean, default: false } });
const emit = defineEmits(['useContact']);
const draft = defineModel({ type: Object, required: true });
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.OPPORTUNITY.REGISTRATION.${key}`);
const { attributesEnabled, companiesEnabled, state, load } = useRelationships();
const root = ref(null);
const phone = ref(null);
const contactMore = ref(false);
const companyMore = ref(false);
const serverError = ref(null);
const lookupError = ref(false);
const contactMatches = ref([]);
const companyMatches = ref([]);
const contactRequest = useAbortableRequest();
const companyRequest = useAbortableRequest();
const reuseRequest = useAbortableRequest();
const definitions = entity =>
  selectDefinitions(
    state.value.definitions.filter(
      item => item.attribute_model === `${entity}_attribute`
    ),
    state.value.configuration,
    `${entity}_details`
  );
const nativeTextDetail = key => {
  const definition = state.value.definitions.find(
    item =>
      item.attribute_model === 'contact_attribute' && item.attribute_key === key
  );
  return (
    !definition ||
    (definition.attribute_display_type === 'text' && !definition.regex_pattern)
  );
};
const availableDefinitions = entity =>
  definitions(entity).filter(
    item =>
      !item.regex_pattern &&
      !(
        entity === 'contact' &&
        ['job_title', 'address'].includes(item.attribute_key) &&
        nativeTextDetail(item.attribute_key)
      )
  );
const contactDefinitions = computed(() => availableDefinitions('contact'));
const companyDefinitions = computed(() => availableDefinitions('company'));
const hasLegacy = computed(() =>
  definitions('contact')
    .concat(definitions('company'))
    .some(item => item.regex_pattern)
);
const countryChoices = computed(() => [
  { value: '', label: t('RELATIONSHIPS.EMPTY') },
  ...countries.map(country => ({ value: country.id, label: country.name })),
]);
const contactErrors = computed(() =>
  serverError.value?.section === 'contact' ? serverError.value.fields || {} : {}
);
const companyErrors = computed(() =>
  serverError.value?.section === 'company' ? serverError.value.fields || {} : {}
);
const busy = computed(
  () =>
    contactRequest.isPending.value ||
    companyRequest.isPending.value ||
    reuseRequest.isPending.value
);
const companyExact = computed(() =>
  companyMatches.value.find(
    item =>
      item.domain &&
      companyDomain(item.domain) === companyDomain(draft.value.companyDomain)
  )
);
const canSave = computed(() =>
  Boolean(
    !props.disabled &&
      !busy.value &&
      draft.value.name.trim() &&
      (draft.value.companyMode === 'none' ||
        (companiesEnabled.value &&
          (draft.value.companyMode === 'existing'
            ? draft.value.company?.id
            : draft.value.companyName.trim())))
  )
);
const errorLabel = computed(() => {
  const code = serverError.value?.code?.split('.').at(-1);
  return label(
    {
      contact_exists: 'CONTACT_EXISTS',
      identity_conflict: 'IDENTITY_CONFLICT',
      company_exists: 'DOMAIN_EXISTS',
      concurrent_conflict: 'CONCURRENT_CONFLICT',
    }[code] || 'CHECK_FIELDS'
  );
});
const setCompanyMode = next => {
  if (props.disabled) return;
  draft.value.companyMode = next;
  draft.value.company = null;
  companyMatches.value = [];
  serverError.value = null;
};
watch(
  () => [draft.value.email, draft.value.phoneNumber],
  () => {
    contactRequest.abort();
    contactMatches.value = [];
    if (serverError.value?.section === 'contact') serverError.value = null;
  },
  { flush: 'sync' }
);
watch(
  () => [
    draft.value.companyName,
    draft.value.companyDomain,
    draft.value.companyMode,
  ],
  () => {
    companyRequest.abort();
    companyMatches.value = [];
    if (serverError.value?.section === 'company') serverError.value = null;
  },
  { flush: 'sync' }
);
const lookupContact = async () => {
  if (props.disabled) return;
  const email = draft.value.email.trim().toLowerCase();
  const rawPhone = draft.value.phoneNumber;
  const normalizedPhone =
    parsePhoneNumberFromString(rawPhone)?.number || rawPhone;
  const terms = [email, normalizedPhone].filter(term => term.length >= 2);
  if (!terms.length) return;
  lookupError.value = false;
  try {
    const responses = await contactRequest.run(signal =>
      Promise.all(
        terms.map(term =>
          ContactAPI.search(term, 1, 'name', '', {
            signal,
            includeCompany: companiesEnabled.value,
          })
        )
      )
    );
    if (!responses) return;
    const candidates = responses
      .flatMap(response => response.data.payload)
      .filter(
        item =>
          (email && item.email?.toLowerCase() === email) ||
          (normalizedPhone && item.phone_number === normalizedPhone)
      );
    contactMatches.value = [
      ...new Map(candidates.map(item => [item.id, item])).values(),
    ];
  } catch {
    lookupError.value = true;
  }
};
const lookupCompany = async () => {
  if (
    props.disabled ||
    draft.value.companyMode !== 'new' ||
    !companiesEnabled.value
  )
    return;
  const name = draft.value.companyName.trim().toLowerCase();
  const domain = companyDomain(draft.value.companyDomain);
  const terms = [...new Set([domain, name].filter(term => term.length >= 2))];
  if (!terms.length) return;
  lookupError.value = false;
  try {
    const responses = await companyRequest.run(() =>
      Promise.all(terms.map(term => CompanyAPI.search(term, 1, 'name')))
    );
    if (!responses) return;
    const candidates = responses
      .flatMap(response => response.data.payload)
      .filter(
        item =>
          (domain && item.domain?.toLowerCase() === domain) ||
          (name && item.name.toLowerCase() === name)
      );
    companyMatches.value = [
      ...new Map(candidates.map(item => [item.id, item])).values(),
    ];
  } catch {
    lookupError.value = true;
  }
};
const useCompany = item => {
  if (props.disabled) return;
  setCompanyMode('existing');
  draft.value.company = item;
};
const useContact = async item => {
  if (props.disabled || reuseRequest.isPending.value) return;
  lookupError.value = false;
  try {
    const response = await reuseRequest.run(async () => {
      const person = (await ContactAPI.show(item.id)).data.payload;
      if (companiesEnabled.value && person.company_id)
        person.company = (
          await CompanyAPI.show(person.company_id)
        ).data.payload;
      return person;
    });
    if (response) emit('useContact', response);
  } catch {
    lookupError.value = true;
  }
};
const showError = async error => {
  serverError.value = error;
  if (error.section === 'company') {
    companyMore.value = true;
    companyMatches.value = error.matches || [];
  } else {
    contactMore.value = true;
    contactMatches.value = error.matches || [];
  }
  await nextTick();
  root.value
    ?.querySelector('[data-registration-error]')
    ?.scrollIntoView({ block: 'nearest' });
};
const validate = async () => {
  const validPhone = await phone.value.validate();
  if (!validPhone) {
    serverError.value = {
      section: 'contact',
      fields: { phone_number: 'invalid' },
    };
    return false;
  }
  const invalid = root.value?.querySelector(':invalid');
  if (invalid) {
    if (invalid.closest('[data-registration-company]'))
      companyMore.value = true;
    else contactMore.value = true;
    await nextTick();
    root.value.querySelector(':invalid')?.reportValidity();
    return false;
  }
  return true;
};
defineExpose({ canSave, validate, showError });
</script>

<template>
  <div ref="root" class="grid min-w-0 gap-4" data-opportunity-registration>
    <div
      v-if="serverError"
      role="alert"
      class="rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-4 text-sm leading-6 text-n-ruby-11"
      data-registration-error
    >
      {{ errorLabel }}
    </div>
    <Input
      v-model="draft.name"
      custom-input-class="!text-base"
      :label="label('NAME')"
      :placeholder="label('NAME_HINT')"
      required
      :disabled="disabled"
      :message="contactErrors.name ? label('INVALID_FIELD') : ''"
      :message-type="contactErrors.name ? 'error' : 'info'"
    />
    <div class="grid min-w-0 gap-4 min-[440px]:grid-cols-2">
      <Input
        v-model="draft.email"
        type="email"
        custom-input-class="!text-base"
        :label="label('EMAIL')"
        :placeholder="label('EMAIL_HINT')"
        :disabled="disabled"
        :message="contactErrors.email ? label('INVALID_FIELD') : ''"
        :message-type="contactErrors.email ? 'error' : 'info'"
        @focusout="lookupContact"
      />
      <div class="grid content-start gap-2" @focusout="lookupContact">
        <div class="text-heading-3 text-n-slate-12">{{ label('PHONE') }}</div>
        <PhoneNumberInput
          ref="phone"
          v-model="draft.phoneNumber"
          :compact="false"
          :aria-label="label('PHONE')"
          :placeholder="label('PHONE_HINT')"
          :disabled="disabled"
        />
        <p
          v-if="contactErrors.phone_number"
          role="alert"
          class="m-0 text-xs text-n-ruby-11"
        >
          {{ label('INVALID_FIELD') }}
        </p>
      </div>
    </div>
    <div
      v-if="contactMatches.length"
      class="grid gap-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-4"
      data-registration-contact-duplicates
    >
      <p class="m-0 text-sm font-medium text-n-slate-12">
        {{
          label(
            contactMatches.length > 1 ? 'IDENTITY_CONFLICT' : 'CONTACT_EXISTS'
          )
        }}
      </p>
      <div
        v-for="item in contactMatches"
        :key="item.id"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <div class="min-w-0 text-sm text-n-slate-12">
          <p class="m-0 break-words font-semibold">{{ item.name }}</p>
          <p class="m-0 break-all text-xs text-n-slate-11">
            {{ item.email || item.phone_number }}
          </p>
        </div>
        <Button
          type="button"
          sm
          faded
          :label="label('USE_CONTACT')"
          :disabled="disabled || reuseRequest.isPending.value"
          @click="useContact(item)"
        />
      </div>
    </div>
    <section
      v-if="companiesEnabled || draft.companyMode !== 'none'"
      class="grid min-w-0 gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      data-registration-company
    >
      <h4
        class="m-0 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-building-2 size-4 text-n-blue-11"
          aria-hidden="true"
        />{{ label('COMPANY_OPTIONAL') }}
      </h4>
      <div
        class="flex flex-wrap gap-2"
        :aria-label="label('COMPANY_OPTIONAL')"
        role="group"
      >
        <button
          v-for="option in [
            { value: 'none', key: 'NO_COMPANY' },
            { value: 'existing', key: 'EXISTING_COMPANY' },
            { value: 'new', key: 'NEW_COMPANY' },
          ]"
          :key="option.value"
          type="button"
          class="min-h-11 rounded-lg border px-3 py-2 text-xs font-medium focus-visible:outline focus-visible:outline-n-brand"
          :class="
            draft.companyMode === option.value
              ? 'border-n-brand/30 bg-n-brand/10 text-n-blue-11'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-2'
          "
          :aria-pressed="draft.companyMode === option.value"
          :disabled="disabled || (!companiesEnabled && option.value !== 'none')"
          @click="setCompanyMode(option.value)"
        >
          <span
            v-if="draft.companyMode === option.value"
            class="i-lucide-check me-1 inline-block size-3 align-middle"
            aria-hidden="true"
          />
          {{ label(option.key) }}
        </button>
      </div>
      <p
        v-if="!companiesEnabled"
        role="alert"
        class="m-0 text-xs text-n-ruby-11"
      >
        {{ label('COMPANY_UNAVAILABLE') }}
      </p>
      <CrmOpportunityCompanyPicker
        v-if="draft.companyMode === 'existing'"
        v-model="draft.company"
        :disabled="disabled"
      />
      <template v-else-if="draft.companyMode === 'new'">
        <div class="grid min-w-0 gap-4 min-[440px]:grid-cols-2">
          <Input
            v-model="draft.companyName"
            custom-input-class="!text-base"
            :label="label('COMPANY_NAME')"
            required
            :maxlength="100"
            :disabled="disabled"
            :message="companyErrors.name ? label('INVALID_FIELD') : ''"
            :message-type="companyErrors.name ? 'error' : 'info'"
            @focusout="lookupCompany"
          />
          <Input
            v-model="draft.companyDomain"
            :label="label('DOMAIN')"
            :placeholder="label('DOMAIN_HINT')"
            :disabled="disabled"
            :message="companyErrors.domain ? label('INVALID_FIELD') : ''"
            :message-type="companyErrors.domain ? 'error' : 'info'"
            @focusout="lookupCompany"
          />
        </div>
        <div
          v-if="companyMatches.length"
          class="grid gap-3 rounded-lg bg-n-amber-2 p-3"
          data-registration-company-duplicates
        >
          <p class="m-0 text-sm text-n-slate-12">
            {{
              label(
                companyExact ||
                  serverError?.code === 'crm.opportunity.company_exists'
                  ? 'DOMAIN_EXISTS'
                  : 'COMPANY_SAME_NAME'
              )
            }}
          </p>
          <div
            v-for="item in companyMatches"
            :key="item.id"
            class="flex flex-wrap items-center justify-between gap-2"
          >
            <div class="min-w-0">
              <p class="m-0 break-words text-sm font-medium text-n-slate-12">
                {{ item.name }}
              </p>
              <p class="m-0 break-all text-xs text-n-slate-11">
                {{ item.domain || label('NO_DOMAIN') }}
              </p>
            </div>
            <Button
              type="button"
              sm
              faded
              :label="label('USE_COMPANY')"
              :disabled="disabled"
              @click="useCompany(item)"
            />
          </div>
        </div>
        <button
          type="button"
          class="flex min-h-11 items-center gap-2 text-start text-sm text-n-slate-11 focus-visible:outline focus-visible:outline-n-brand"
          :aria-expanded="companyMore"
          :disabled="disabled"
          @click="companyMore = !companyMore"
        >
          <span
            class="i-lucide-chevron-down size-4"
            :class="{ 'rotate-180': companyMore }"
            aria-hidden="true"
          />{{ label('MORE_COMPANY') }}
        </button>
        <div
          v-show="companyMore"
          class="grid min-w-0 gap-4 min-[440px]:grid-cols-2"
        >
          <Input
            v-model="draft.companyCity"
            :label="label('COMPANY_CITY')"
            :disabled="disabled"
          />
          <AttributeDraftFields
            v-if="attributesEnabled"
            v-model="draft.companyAttributes"
            :definitions="companyDefinitions"
            :errors="companyErrors"
            :disabled="disabled"
          />
        </div>
      </template>
      <p v-else class="m-0 text-xs leading-5 text-n-slate-11">
        {{ label('NO_COMPANY_HELP') }}
      </p>
    </section>
    <section class="rounded-xl border border-n-weak">
      <button
        type="button"
        class="flex min-h-12 w-full items-center gap-2 p-4 text-start text-sm font-medium text-n-slate-12 focus-visible:outline focus-visible:outline-n-brand"
        :aria-expanded="contactMore"
        :disabled="disabled"
        @click="contactMore = !contactMore"
      >
        <span
          class="i-lucide-contact-round size-4 text-n-slate-11"
          aria-hidden="true"
        />
        <!-- Caption and trailing state indicator stay separate. -->
        <span>{{ label('MORE_CONTACT') }}</span>
        <span
          class="i-lucide-chevron-down ms-auto size-4"
          :class="{ 'rotate-180': contactMore }"
          aria-hidden="true"
        />
      </button>
      <div
        v-show="contactMore"
        class="grid min-w-0 gap-4 border-t border-n-weak p-4 min-[440px]:grid-cols-2"
      >
        <Input
          v-if="nativeTextDetail('job_title')"
          v-model="draft.jobTitle"
          :label="label('JOB_TITLE')"
          :disabled="disabled"
        />
        <Input
          v-model="draft.city"
          :label="label('CITY')"
          :disabled="disabled"
        />
        <label class="grid min-w-0 gap-2 text-sm text-n-slate-12">
          <!-- The native choice component owns its accessible input label. -->
          <span>{{ label('COUNTRY') }}</span>
          <ChoiceSelect
            v-model="draft.country"
            :options="countryChoices"
            :aria-label="label('COUNTRY')"
            :disabled="disabled"
          />
        </label>
        <Input
          v-if="nativeTextDetail('address')"
          v-model="draft.address"
          :label="label('ADDRESS')"
          :disabled="disabled"
        />
        <AttributeDraftFields
          v-if="attributesEnabled"
          v-model="draft.contactAttributes"
          :definitions="contactDefinitions"
          :errors="contactErrors"
          :disabled="disabled"
        />
        <p
          v-if="hasLegacy"
          class="m-0 text-xs leading-5 text-n-slate-11 min-[440px]:col-span-2"
        >
          {{ label('LEGACY_FIELDS') }}
        </p>
      </div>
    </section>
    <div
      v-if="attributesEnabled && state.error"
      class="flex flex-wrap items-center gap-2 text-xs text-n-ruby-11"
      role="alert"
    >
      <p class="m-0">{{ label('ATTRIBUTE_LOAD_ERROR') }}</p>
      <Button
        type="button"
        sm
        ghost
        :label="t('CRM_KANBAN.OPPORTUNITY.RETRY')"
        :disabled="disabled"
        @click="load"
      />
    </div>
    <p v-if="busy" role="status" class="m-0 text-xs text-n-slate-11">
      {{ label('LOOKING_UP') }}
    </p>
    <p v-if="lookupError" role="alert" class="m-0 text-xs text-n-ruby-11">
      {{ label('LOOKUP_ERROR') }}
    </p>
  </div>
</template>
