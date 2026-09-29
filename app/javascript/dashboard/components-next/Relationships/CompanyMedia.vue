<script setup>
import { computed, ref, watch, onBeforeUnmount, useId } from 'vue';
import axios from 'dashboard/api/relationships';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import MediaThumbnail from './MediaThumbnail.vue';

const props = defineProps({
  companyId: { type: Number, required: true },
  expanded: { type: Boolean, default: false },
});
const { accountId } = useAccount();
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const rows = ref([]);
const inputId = useId();
let actionGeneration = 0;
const contactQuery = ref('');
const contactOptions = ref([]);
let contactGeneration = 0;
const total = ref(0);
const loading = ref(false);
const error = ref(false);
const filters = ref({
  q: '',
  contact_id: '',
  type: '',
  from: '',
  to: '',
  group: '',
  page: 1,
});
let generation = 0;
const base = computed(
  () => `/api/v1/accounts/${accountId.value}/companies/${props.companyId}/media`
);
const options = computed(() => [
  { value: '', label: t('RELATIONSHIPS.MEDIA.ALL_TYPES') },
  ...['image', 'video', 'audio', 'file'].map(value => ({
    value,
    label: t(`RELATIONSHIPS.MEDIA.${value}`),
  })),
]);
const findContacts = async () => {
  contactGeneration += 1;
  const current = contactGeneration;
  try {
    const { data } = await axios.get(`${base.value}/contacts`, {
      params: { q: contactQuery.value },
    });
    if (current === contactGeneration)
      contactOptions.value = data.map(contact => ({
        value: String(contact.id),
        label: contact.name,
      }));
  } catch {
    if (current === contactGeneration) error.value = true;
  }
};
const load = async () => {
  generation += 1;
  const current = generation;
  loading.value = true;
  error.value = false;
  rows.value = [];
  total.value = 0;
  try {
    const { data } = await axios.get(base.value, {
      params: {
        ...Object.fromEntries(
          Object.entries(filters.value).filter(([, value]) => value !== '')
        ),
        per_page: props.expanded ? 25 : 5,
        page: props.expanded ? filters.value.page : 1,
      },
    });
    if (current !== generation) return;
    rows.value = data.payload;
    total.value = data.meta.total;
  } catch {
    if (current === generation) error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
const apply = () => {
  filters.value.page = 1;
  router.replace({
    query: { ...route.query, media: JSON.stringify(filters.value) },
  });
  load();
};
const changePage = amount => {
  filters.value.page += amount;
  router.replace({
    query: { ...route.query, media: JSON.stringify(filters.value) },
  });
  load();
};
const openAll = () =>
  router.push({
    name: 'relationships_company_media',
    params: { accountId: accountId.value, companyId: props.companyId },
    query: { media: JSON.stringify(filters.value) },
  });
const openOrigin = row =>
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: row.conversation_id,
    },
    query: { messageId: row.message_id },
  });
const download = async (row, inline = false) => {
  const current = actionGeneration;
  const context = base.value;
  try {
    const { data } = await axios.get(`${base.value}/${row.id}`, {
      params: { inline },
    });
    if (current !== actionGeneration || context !== base.value) return;
    const url = new URL(data.url);
    if (!['http:', 'https:'].includes(url.protocol)) return;
    const link = document.createElement('a');
    link.href = data.url;
    link.target = '_blank';
    link.rel = 'noopener noreferrer';
    link.click();
  } catch {
    if (current === actionGeneration) error.value = true;
  }
};

watch(
  () => [accountId.value, props.companyId],
  () => {
    actionGeneration += 1;
    contactGeneration += 1;
    contactOptions.value = [];
    contactQuery.value = '';
    findContacts();
    filters.value = {
      q: '',
      contact_id: '',
      type: '',
      from: '',
      to: '',
      group: '',
      page: 1,
    };
    if (typeof route.query.media === 'string') {
      try {
        const parsed = JSON.parse(route.query.media);
        Object.keys(filters.value).forEach(key => {
          if (typeof parsed[key] === typeof filters.value[key])
            filters.value[key] = parsed[key];
        });
      } catch {
        /* Invalid bookmark uses clean filters. */
      }
    }
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  actionGeneration += 1;
  generation += 1;
  contactGeneration += 1;
});
</script>

<template>
  <section class="p-4 flex flex-col gap-3 min-w-0">
    <p class="text-xs text-n-slate-11">{{ t('RELATIONSHIPS.MEDIA.SCOPE') }}</p>
    <form class="flex flex-wrap gap-2" @submit.prevent="apply">
      <Input
        v-model="filters.q"
        type="search"
        :aria-label="t('RELATIONSHIPS.MEDIA.SEARCH')"
        :placeholder="t('RELATIONSHIPS.MEDIA.SEARCH')"
      />
      <ChoiceSelect
        v-model="filters.type"
        :options="options"
        :aria-label="t('RELATIONSHIPS.TYPE')"
        compact
      />
      <label :for="`${inputId}-contact`" class="text-xs">
        <span>{{ t('RELATIONSHIPS.MEDIA.CONTACT_SEARCH') }}</span>
        <Input
          :id="`${inputId}-contact`"
          v-model="contactQuery"
          type="search"
        />
      </label>
      <Button
        type="button"
        :label="t('RELATIONSHIPS.MEDIA.CONTACT_SEARCH')"
        @click="findContacts"
      />
      <ChoiceSelect
        v-model="filters.contact_id"
        :options="[
          { value: '', label: t('RELATIONSHIPS.MEDIA.ALL_CONTACTS') },
          ...contactOptions,
        ]"
        :aria-label="t('RELATIONSHIPS.CONTACTS')"
        compact
      />
      <label :for="`${inputId}-from`" class="text-xs">
        <span>{{ t('RELATIONSHIPS.MEDIA.FROM') }}</span>
        <Input :id="`${inputId}-from`" v-model="filters.from" type="date" />
      </label>
      <label :for="`${inputId}-to`" class="text-xs">
        <span>{{ t('RELATIONSHIPS.MEDIA.TO') }}</span>
        <Input :id="`${inputId}-to`" v-model="filters.to" type="date" />
      </label>
      <label v-if="expanded" class="flex items-center gap-2 text-sm">
        <input
          v-model="filters.group"
          type="checkbox"
          true-value="contact"
          false-value=""
        />
        <span>{{ t('RELATIONSHIPS.MEDIA.GROUP') }}</span>
      </label>
      <Button type="submit" :label="t('RELATIONSHIPS.MEDIA.FILTER')" />
    </form>
    <p v-if="loading" role="status">{{ t('RELATIONSHIPS.LOADING') }}</p>
    <Button v-if="error" :label="t('RELATIONSHIPS.RETRY')" @click="load" />
    <div v-if="expanded" class="overflow-x-auto">
      <table class="w-full text-sm text-start">
        <thead>
          <tr>
            <th>{{ t('RELATIONSHIPS.NAME') }}</th>
            <th>{{ t('RELATIONSHIPS.TYPE') }}</th>
            <th>{{ t('RELATIONSHIPS.MEDIA.SIZE') }}</th>
            <th>{{ t('RELATIONSHIPS.CONTACTS') }}</th>
            <th>{{ t('RELATIONSHIPS.MEDIA.SENDER') }}</th>
            <th>{{ t('RELATIONSHIPS.MEDIA.DATE') }}</th>
            <th>{{ t('RELATIONSHIPS.MEDIA.ACTIONS') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.id" class="border-t border-n-weak">
            <td class="p-2">
              <div class="flex items-center gap-2">
                <MediaThumbnail
                  :url="`${base}/${row.id}/preview`"
                  :name="row.filename"
                  :type="row.file_type"
                />{{ row.filename }}
              </div>
            </td>
            <td class="p-2">{{ row.content_type }}</td>
            <td class="p-2">
              {{
                t('RELATIONSHIPS.MEDIA.BYTES', {
                  size: row.byte_size.toLocaleString(),
                })
              }}
            </td>
            <td class="p-2">
              <RouterLink
                :to="{
                  name: 'contacts_edit',
                  params: { accountId, contactId: row.contact.id },
                }"
              >
                {{ row.contact.name }}
              </RouterLink>
            </td>
            <td class="p-2">
              {{ row.sender?.name || t('RELATIONSHIPS.EMPTY') }}
            </td>
            <td class="p-2">{{ new Date(row.created_at).toLocaleString() }}</td>
            <td class="p-2">
              <Button
                xs
                ghost
                :label="t('RELATIONSHIPS.MEDIA.PREVIEW')"
                @click="download(row, true)"
              /><Button
                xs
                ghost
                :label="t('RELATIONSHIPS.MEDIA.DOWNLOAD')"
                @click="download(row)"
              /><Button
                xs
                ghost
                :label="t('RELATIONSHIPS.MEDIA.ORIGIN')"
                @click="openOrigin(row)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <ul v-else class="flex flex-col gap-3">
      <li v-for="row in rows" :key="row.id" class="flex gap-2 items-start">
        <MediaThumbnail
          :url="`${base}/${row.id}/preview`"
          :name="row.filename"
          :type="row.file_type"
        />
        <div class="min-w-0">
          <p class="text-sm break-all">{{ row.filename }}</p>
          <p class="text-xs text-n-slate-11">
            {{
              t('RELATIONSHIPS.MEDIA.FILE_METADATA', {
                type: row.content_type,
                size: row.byte_size.toLocaleString(),
              })
            }}
          </p>
          <RouterLink
            class="text-xs"
            :to="{
              name: 'contacts_edit',
              params: { accountId, contactId: row.contact.id },
            }"
          >
            {{ row.contact.name }}
          </RouterLink>
          <div class="flex gap-1">
            <Button
              xs
              ghost
              :label="t('RELATIONSHIPS.MEDIA.PREVIEW')"
              @click="download(row, true)"
            /><Button
              xs
              ghost
              :label="t('RELATIONSHIPS.MEDIA.DOWNLOAD')"
              @click="download(row)"
            /><Button
              xs
              ghost
              :label="t('RELATIONSHIPS.MEDIA.ORIGIN')"
              @click="openOrigin(row)"
            />
          </div>
        </div>
      </li>
    </ul>
    <p v-if="!loading && !error && !rows.length">
      {{ t('RELATIONSHIPS.MEDIA.EMPTY') }}
    </p>
    <div v-if="expanded" class="flex items-center gap-2">
      <Button
        xs
        faded
        :disabled="filters.page <= 1 || loading"
        :label="t('RELATIONSHIPS.BACK')"
        @click="changePage(-1)"
      />
      <span>{{ filters.page }}</span>
      <Button
        xs
        faded
        :disabled="filters.page * 25 >= total || loading"
        :label="t('RELATIONSHIPS.NEXT')"
        @click="changePage(1)"
      />
    </div>
    <Button
      v-if="!expanded"
      :label="t('RELATIONSHIPS.MEDIA.ALL')"
      @click="openAll"
    />
  </section>
</template>
