<script setup>
// Painel lateral do público (#993, PRD §6.6, §7 "37rem", F1–F3, B8): channel badges, people,
// companies, other columns kept, who does not receive, campaigns that used it, "Usar em nova
// campanha", "Ver contatos e empresas" (contacts of the audience, paged — Contacts has no list
// filter) and "Excluir público". Reads GET campaign_imports/:id (show).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { audiencesAPI } from 'dashboard/api/campaignJourney';
import AudienceChannelBadges from './AudienceChannelBadges.vue';
import { audienceChannelBadges } from './audienceRows';
import { notReceiving } from './audienceReview';
import { CHANNEL_LABEL_KEYS } from './campaignChannels';

const props = defineProps({
  audienceId: { type: Number, required: true },
  canManage: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'use', 'delete']);

const NS = 'CAMPAIGN_JOURNEY.AUDIENCES.PANEL';
const { t, n } = useI18n();

const detail = ref(null);
const isLoading = ref(true);
const hasError = ref(false);
const contacts = ref([]);
const contactsMeta = ref({ count: 0, page: 0 });
const contactsOpen = ref(false);
const contactsError = ref(false);
const closeButton = ref(null);

const name = computed(
  () => detail.value?.name || detail.value?.campaign_name || ''
);
const badges = computed(() => audienceChannelBadges(detail.value?.channels));
const people = computed(() => Number(detail.value?.valid_rows) || 0);
const companies = computed(() => detail.value?.companies || null);
const blocked = computed(() => notReceiving(detail.value?.reachability));
const campaigns = computed(() => detail.value?.linked_campaigns || []);
const extras = computed(() => detail.value?.extra_columns || []);
const hasMoreContacts = computed(
  () => contacts.value.length < Number(contactsMeta.value.count || 0)
);

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  contacts.value = [];
  contactsMeta.value = { count: 0, page: 0 };
  contactsOpen.value = false;
  try {
    const { data } = await audiencesAPI.show(props.audienceId);
    detail.value = data.payload;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const loadContacts = async () => {
  contactsError.value = false;
  const page = Number(contactsMeta.value.page || 0) + 1;
  try {
    const { data } = await audiencesAPI.contacts(props.audienceId, page);
    contacts.value = [...contacts.value, ...(data?.payload || [])];
    contactsMeta.value = { count: data?.meta?.count || 0, page };
  } catch {
    contactsError.value = true;
  }
};

const toggleContacts = () => {
  contactsOpen.value = !contactsOpen.value;
  if (contactsOpen.value && !contactsMeta.value.page) loadContacts();
};

const campaignStatus = status =>
  status ? t(`${NS}.STATUS.${String(status).toUpperCase()}`) : '';
const channelLabel = channel =>
  CHANNEL_LABEL_KEYS[channel]
    ? t(`CAMPAIGN_JOURNEY.CHANNELS.${CHANNEL_LABEL_KEYS[channel]}`)
    : '';

const onKeydown = event => {
  if (event.key === 'Escape') emit('close');
};

watch(() => props.audienceId, load);
onMounted(() => {
  load();
  closeButton.value?.$el?.focus?.();
  document.addEventListener('keydown', onKeydown);
});
onBeforeUnmount(() => document.removeEventListener('keydown', onKeydown));
</script>

<template>
  <aside
    class="fixed inset-y-0 z-40 flex w-full max-w-full flex-col overflow-y-auto border-n-weak bg-n-solid-1 shadow-xl ltr:right-0 ltr:border-l rtl:left-0 rtl:border-r sm:w-[37rem]"
    :aria-label="name"
    data-test="audience-panel"
  >
    <header
      class="flex items-start justify-between gap-3 border-b border-n-weak px-5 py-4"
    >
      <div class="min-w-0">
        <h2 class="m-0 truncate text-lg font-semibold text-n-slate-12">
          {{ name }}
        </h2>
        <AudienceChannelBadges v-if="detail" :badges="badges" class="mt-2" />
      </div>
      <Button
        ref="closeButton"
        icon="i-lucide-x"
        :aria-label="t(`${NS}.CLOSE`)"
        variant="ghost"
        color="slate"
        size="sm"
        class="!min-h-11 !min-w-11"
        data-test="panel-close"
        @click="emit('close')"
      />
    </header>

    <div v-if="isLoading" class="flex justify-center p-10"><Spinner /></div>
    <p v-else-if="hasError" role="alert" class="m-5 text-sm text-n-ruby-11">
      {{ t(`${NS}.LOAD_ERROR`) }}
    </p>
    <div v-else class="flex flex-col gap-5 px-5 py-4">
      <p class="m-0 text-2xl font-semibold tabular-nums text-n-slate-12">
        {{ t(`${NS}.PEOPLE`, { count: n(people) }, people) }}
      </p>

      <section v-if="companies" data-test="panel-companies">
        <h3 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.COMPANIES`) }}
        </h3>
        <p class="m-0 mt-1 text-sm text-n-slate-12">
          {{
            t(`${NS}.COMPANIES_LINE`, {
              linked: n(Number(companies.contacts_linked) || 0),
              created: n(Number(companies.created) || 0),
              reused: n(Number(companies.reused) || 0),
            })
          }}
        </p>
      </section>

      <section data-test="panel-columns">
        <h3 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.OTHER_COLUMNS`) }}
        </h3>
        <ul v-if="extras.length" class="m-0 mt-2 flex list-none flex-wrap gap-1.5 p-0">
          <li
            v-for="extra in extras"
            :key="extra"
            class="rounded-lg bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
          >
            {{ extra }}
          </li>
        </ul>
        <p v-else class="m-0 mt-1 text-sm text-n-slate-11">
          {{ t(`${NS}.OTHER_NONE`) }}
        </p>
      </section>

      <section data-test="panel-not-receiving">
        <h3 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.NOT_RECEIVING`) }}
        </h3>
        <ul
          v-if="blocked && blocked.items.length"
          class="m-0 mt-1 list-none p-0 text-sm text-n-slate-12"
        >
          <li v-for="item in blocked.items" :key="item.key">
            {{
              t(`CAMPAIGN_JOURNEY.NEW_AUDIENCE.PEOPLE.${item.key}`, {
                count: n(item.count),
              })
            }}
          </li>
        </ul>
        <p v-else class="m-0 mt-1 text-sm text-n-slate-11">
          {{ t(`${NS}.NOT_RECEIVING_NONE`) }}
        </p>
      </section>

      <section data-test="panel-campaigns">
        <h3 class="m-0 text-xs font-semibold uppercase text-n-slate-11">
          {{ t(`${NS}.CAMPAIGNS`) }}
        </h3>
        <ul v-if="campaigns.length" class="m-0 mt-2 flex list-none flex-col gap-2 p-0">
          <li
            v-for="campaign in campaigns"
            :key="`${campaign.type}-${campaign.id}`"
            class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak px-3 py-2"
          >
            <span class="min-w-0 text-sm text-n-slate-12">
              <strong>{{ campaign.title }}</strong>
              <span class="text-xs text-n-slate-11">
                · {{ channelLabel(campaign.channel) }}
              </span>
            </span>
            <span class="text-xs text-n-slate-11">
              {{ campaignStatus(campaign.status) }}
            </span>
          </li>
        </ul>
        <p v-else class="m-0 mt-1 text-sm text-n-slate-11">
          {{ t(`${NS}.CAMPAIGNS_NONE`) }}
        </p>
      </section>

      <section data-test="panel-contacts">
        <Button
          :label="contactsOpen ? t(`${NS}.CONTACTS_HIDE`) : t(`${NS}.CONTACTS`)"
          icon="i-lucide-users"
          variant="outline"
          color="slate"
          class="!min-h-11 !rounded-xl"
          :aria-expanded="contactsOpen"
          data-test="panel-contacts-toggle"
          @click="toggleContacts"
        />
        <template v-if="contactsOpen">
          <p v-if="contactsError" role="alert" class="m-0 mt-2 text-sm text-n-ruby-11">
            {{ t(`${NS}.LOAD_ERROR`) }}
          </p>
          <p
            v-else-if="contactsMeta.page && !contacts.length"
            class="m-0 mt-2 text-sm text-n-slate-11"
          >
            {{ t(`${NS}.CONTACTS_EMPTY`) }}
          </p>
          <ul class="m-0 mt-2 flex list-none flex-col p-0">
            <li
              v-for="contact in contacts"
              :key="contact.id"
              class="border-b border-n-weak last:border-0"
              :data-contact="contact.id"
            >
              <router-link
                :to="{
                  name: 'contacts_edit',
                  params: { contactId: contact.id },
                }"
                class="flex min-h-11 flex-col justify-center rounded-lg px-2 py-1 hover:bg-n-alpha-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              >
                <span class="text-sm font-medium text-n-slate-12">
                  {{ contact.name }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{ [contact.company_name, contact.email, contact.phone_number].filter(Boolean).join(' · ') }}
                </span>
              </router-link>
            </li>
          </ul>
          <Button
            v-if="hasMoreContacts"
            :label="t(`${NS}.MORE`)"
            variant="ghost"
            size="sm"
            class="!min-h-11 mt-1"
            @click="loadContacts"
          />
        </template>
      </section>

      <footer
        v-if="canManage"
        class="flex flex-wrap justify-between gap-2 border-t border-n-weak pt-4"
      >
        <Button
          :label="t('CAMPAIGN_JOURNEY.AUDIENCES.DELETE')"
          icon="i-lucide-trash-2"
          variant="ghost"
          color="ruby"
          class="!min-h-11 !rounded-xl"
          :disabled="!detail?.can_delete"
          data-test="panel-delete"
          @click="emit('delete', { id: audienceId, name })"
        />
        <Button
          :label="t('CAMPAIGN_JOURNEY.AUDIENCES.USE_IN_CAMPAIGN')"
          class="!min-h-11 !rounded-xl"
          :disabled="!['completed', 'completed_with_failures'].includes(detail?.status)"
          data-test="panel-use"
          @click="emit('use', { id: audienceId })"
        />
      </footer>
    </div>
  </aside>
</template>
