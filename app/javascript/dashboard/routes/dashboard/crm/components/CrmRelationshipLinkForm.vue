<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';

const props = defineProps({
  cardId: { type: Number, required: true },
  readOnly: { type: Boolean, default: false },
  mode: { type: String, required: true },
});
const emit = defineEmits(['saved', 'cancel']);
const { t } = useI18n();
const label = key => t(`CRM_KANBAN.RELATIONSHIP.${key}`);
const query = ref('');
const results = ref([]);
const selected = ref(null);
const searched = ref(false);
const error = ref('');
const saving = ref(false);
const form = reactive({ name: '', email: '', phone_number: '' });
const request = useAbortableRequest();
let requestKey = crypto.randomUUID();
let submittedPayload = '';
const dirty = computed(() =>
  Boolean(selected.value || Object.values(form).some(Boolean))
);
const canSave = computed(
  () =>
    !props.readOnly &&
    (props.mode === 'new'
      ? form.name.trim().length > 0
      : Boolean(selected.value))
);

const search = async () => {
  if (query.value.trim().length < 2) return;
  error.value = '';
  selected.value = null;
  try {
    const response = await request.run(signal =>
      ContactAPI.search(query.value.trim(), 1, 'name', '', { signal })
    );
    if (!response) return;
    results.value = response.data.payload;
    searched.value = true;
  } catch {
    error.value = label('SEARCH_ERROR');
  }
};
const save = async () => {
  if (saving.value || !canSave.value) return;
  saving.value = true;
  error.value = '';
  try {
    let response;
    if (props.mode === 'new') {
      const payload = Object.fromEntries(
        Object.entries(form).map(([key, value]) => [key, (value ?? '').trim()])
      );
      const fingerprint = JSON.stringify(payload);
      if (submittedPayload && fingerprint !== submittedPayload)
        requestKey = crypto.randomUUID();
      submittedPayload = fingerprint;
      response = await CrmKanbanAPI.createCardContact(
        props.cardId,
        payload,
        requestKey
      );
    } else {
      response = await CrmKanbanAPI.linkCardContact(
        props.cardId,
        selected.value.id
      );
    }
    selected.value = null;
    Object.assign(form, { name: '', email: '', phone_number: '' });
    emit('saved', response.data.payload);
  } catch (failure) {
    const status = failure.response?.status;
    error.value = [409, 422].includes(status)
      ? label('SAVE_CONFLICT')
      : label('SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};
defineExpose({ dirty, saving });
</script>

<template>
  <form class="grid gap-5" data-relationship-link-form @submit.prevent="save">
    <div>
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ label(mode === 'new' ? 'CREATE_CONTACT' : 'LINK_CONTACT') }}
      </h3>
      <p class="mt-1 mb-0 text-sm leading-6 text-n-slate-11">
        {{ label('SAME_OPPORTUNITY') }}
      </p>
    </div>
    <p
      v-if="error"
      role="alert"
      class="mb-0 rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <div v-if="mode === 'new'" class="grid gap-4">
      <Input
        v-model="form.name"
        :label="label('NAME')"
        :placeholder="label('NAME_PLACEHOLDER')"
        required
        :disabled="saving"
      />
      <Input
        v-model="form.email"
        type="email"
        :label="label('EMAIL')"
        :disabled="saving"
      />
      <label class="grid gap-2 text-sm text-n-slate-12">
        <span>{{ label('PHONE') }}</span>
        <PhoneNumberInput v-model="form.phone_number" :disabled="saving" />
      </label>
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ label('OPTIONAL_CHANNELS') }}
      </p>
    </div>
    <div v-else class="grid gap-3">
      <div class="flex items-end gap-3">
        <Input
          v-model="query"
          class="min-w-0 flex-1"
          :label="label('SEARCH_CONTACT')"
          :placeholder="label('SEARCH_PLACEHOLDER')"
          :disabled="saving"
          @enter="search"
        />
        <Button
          type="button"
          icon="i-lucide-search"
          slate
          faded
          :label="label('SEARCH')"
          :disabled="saving || query.trim().length < 2"
          :is-loading="request.isPending.value"
          @click="search"
        />
      </div>
      <div
        v-if="results.length"
        class="overflow-hidden rounded-lg border border-n-weak"
        role="group"
        :aria-label="label('SEARCH_CONTACT')"
      >
        <button
          v-for="contact in results"
          :key="contact.id"
          type="button"
          :disabled="saving"
          :aria-pressed="selected?.id === contact.id"
          class="flex w-full items-center gap-3 border-b border-n-weak p-3 text-start last:border-0 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-n-brand"
          :class="
            selected?.id === contact.id ? 'bg-n-brand/10' : 'bg-n-solid-1'
          "
          @click="selected = contact"
        >
          <Avatar :name="contact.name || ''" :size="36" rounded-full />
          <span class="min-w-0 flex-1">
            <!-- Keep the name and channel on separate visual lines. -->
            <strong class="block truncate text-sm font-medium text-n-slate-12">
              {{ contact.name }}
            </strong>
            <span class="block truncate text-xs text-n-slate-11">
              {{ contact.email || contact.phone_number || label('NO_CHANNEL') }}
            </span>
          </span>
          <span
            v-if="selected?.id === contact.id"
            class="i-lucide-circle-check size-5 text-n-blue-11"
            aria-hidden="true"
          />
        </button>
      </div>
      <p v-else-if="searched" class="mb-0 text-sm text-n-slate-11">
        {{ label('SEARCH_EMPTY') }}
      </p>
    </div>
    <div class="flex flex-wrap justify-end gap-3">
      <Button
        type="button"
        slate
        faded
        :label="label('CANCEL')"
        :disabled="saving"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        icon="i-lucide-check"
        :label="label(mode === 'new' ? 'SAVE_AND_LINK' : 'CONFIRM_LINK')"
        :is-loading="saving"
        :disabled="saving || !canSave"
      />
    </div>
  </form>
</template>
