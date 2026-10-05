<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useCanManage } from 'dashboard/composables/useCanManage';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TrackedLinkQr from 'dashboard/components-next/Campaigns/TrackedLinks/TrackedLinkQr.vue';
import CreateTrackedLinkDialog from 'dashboard/components-next/Campaigns/TrackedLinks/CreateTrackedLinkDialog.vue';
import TrackedLinkWebsitePanel from 'dashboard/components-next/Campaigns/TrackedLinks/TrackedLinkWebsitePanel.vue';
import TrackedLinkCampaignTable from 'dashboard/components-next/Campaigns/TrackedLinks/TrackedLinkCampaignTable.vue';
import TrackedLinkReadyBadge from 'dashboard/components-next/Campaigns/TrackedLinks/TrackedLinkReadyBadge.vue';

const { t, locale } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const store = useStore();
const inboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const canManage = useCanManage('campaign_manage');
const request = useAbortableRequest();
const isLoading = request.isPending;
const links = ref([]);
const search = ref('');
const selectedId = ref(null);
const error = ref('');
const createError = ref('');
const isCreating = ref(false);
const isDeleting = ref(false);
const creator = ref(null);
const material = ref(null);
const deleteDialog = ref(null);
const selected = computed(() =>
  links.value.find(link => link.id === selectedId.value)
);
const isWebsite = link => link?.usage === 'website';
const usageIcon = link =>
  isWebsite(link) ? 'i-lucide-globe' : 'i-lucide-qr-code';
const filteredLinks = computed(() => {
  const language = locale.value.replace('_', '-');
  const query = search.value.trim().toLocaleLowerCase(language);
  return links.value.filter(link =>
    link.name.toLocaleLowerCase(language).includes(query)
  );
});
const format = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(value);
const totals = computed(() => [
  { key: 'ORIGINS', value: links.value.length },
  {
    key: 'CLICKS',
    value: links.value.reduce((sum, link) => sum + link.clicks_count, 0),
  },
  {
    key: 'CONVERSATIONS',
    value: links.value.reduce((sum, link) => sum + link.conversations_count, 0),
  },
]);
const inboxName = id =>
  inboxes.value.find(inbox => inbox.id === id)?.name || t(`${NS}.DESTINATION`);
const replaceLink = updated => {
  links.value = links.value.map(link =>
    link.id === updated.id ? updated : link
  );
};

const fetchLinks = async () => {
  error.value = '';
  try {
    const result = await request.run(async signal => {
      const loaded = await store.dispatch('inboxes/get');
      if (!loaded) throw new Error('Could not load WhatsApp inboxes');
      return CtwaTrackedLinksAPI.get({ signal });
    });
    if (!result) return;
    links.value = result.data.payload;
    if (!links.value.some(link => link.id === selectedId.value)) {
      selectedId.value = links.value[0]?.id ?? null;
    }
  } catch {
    error.value = t(`${NS}.LOAD_ERROR`);
  }
};
const createLink = async attributes => {
  isCreating.value = true;
  createError.value = '';
  try {
    const { data } = await CtwaTrackedLinksAPI.create(attributes);
    links.value.unshift(data.payload);
    selectedId.value = data.payload.id;
    search.value = '';
    creator.value.close();
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.CREATE_SUCCESS'));
  } catch {
    createError.value = t('CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR');
  } finally {
    isCreating.value = false;
  }
};
const copyLink = async () => {
  try {
    await navigator.clipboard.writeText(selected.value.short_url);
    useAlert(t('CRM_KANBAN.TRACKED_LINKS.COPIED'));
  } catch {
    useAlert(t(`${NS}.COPY_ERROR`));
  }
};
const downloadQr = async () => {
  try {
    const image = await QRCode.toDataURL(selected.value.short_url, {
      width: 512,
    });
    const anchor = document.createElement('a');
    anchor.href = image;
    anchor.download = `${selected.value.code}-qr.png`;
    anchor.click();
  } catch {
    useAlert(t(`${NS}.QR_ERROR`));
  }
};
const deleteLink = async () => {
  const id = selected.value.id;
  isDeleting.value = true;
  try {
    await CtwaTrackedLinksAPI.delete(id);
    links.value = links.value.filter(link => link.id !== id);
    selectedId.value = links.value[0]?.id ?? null;
    deleteDialog.value.close();
    useAlert(t(`${NS}.DELETE_SUCCESS`));
  } catch {
    useAlert(t(`${NS}.DELETE_ERROR`));
  } finally {
    isDeleting.value = false;
  }
};

onMounted(fetchLinks);
</script>

<template>
  <div
    class="h-full w-full min-w-0 overflow-y-auto bg-n-background text-n-slate-12"
  >
    <div class="mx-auto max-w-[100rem] px-6 py-8 xl:px-10">
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="m-0 text-3xl font-semibold tracking-tight">
            {{ t(`${NS}.TITLE`) }}
          </h1>
          <p class="m-0 mt-2 text-sm text-n-slate-11">
            {{ t(`${NS}.SUBTITLE`) }}
          </p>
        </div>
        <Button
          v-if="canManage"
          :label="t(`${NS}.NEW`)"
          icon="i-lucide-plus"
          :disabled="isLoading || !!error || !inboxes.length"
          class="h-11"
          @click="creator.open()"
        />
      </header>
      <p
        v-if="!inboxes.length && !isLoading && !error"
        class="mt-4 text-sm text-n-amber-11"
      >
        {{ t(`${NS}.NO_INBOX`) }}
      </p>

      <div
        v-if="error"
        role="alert"
        class="flex items-center gap-4 mt-8 rounded-xl border border-n-weak p-6"
      >
        <p class="m-0 text-sm text-n-ruby-11">{{ error }}</p>
        <Button
          :label="t(`${NS}.RETRY`)"
          slate
          outline
          :disabled="isLoading"
          @click="fetchLinks"
        />
      </div>
      <div
        v-else-if="isLoading"
        role="status"
        class="flex items-center justify-center gap-3 py-16 text-n-slate-11"
      >
        <span class="i-lucide-loader-circle size-5 animate-spin" />
        {{ t(`${NS}.LOADING`) }}
      </div>
      <template v-else>
        <section
          :aria-label="t(`${NS}.RESULTS`)"
          class="mt-8 flex flex-wrap gap-x-10 gap-y-6 border-b border-n-weak pb-7"
        >
          <div
            v-for="(total, index) in totals"
            :key="total.key"
            :class="index ? 'border-s border-n-weak ps-10' : ''"
          >
            <p class="m-0 text-xs font-medium text-n-slate-11">
              {{ t(`${NS}.${total.key}`) }}
            </p>
            <p
              class="m-0 mt-2 text-3xl font-semibold tracking-tight tabular-nums"
              :class="total.key === 'CONVERSATIONS' ? 'text-n-teal-11' : ''"
            >
              {{ format(total.value) }}
            </p>
          </div>
          <p
            class="m-0 ms-auto self-end max-w-52 text-xs leading-relaxed text-n-slate-11"
          >
            {{ t(`${NS}.SAME_ORIGIN`) }}
          </p>
        </section>
        <div class="mt-7 grid gap-7 xl:grid-cols-[minmax(0,1fr)_21rem]">
          <section class="min-w-0">
            <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
              <h2 class="m-0 text-base font-semibold">
                {{ t(`${NS}.YOUR_CAMPAIGNS`) }}
                <span class="ms-2 rounded-full bg-n-alpha-2 px-2 py-1 text-xs">
                  {{ format(filteredLinks.length) }}
                </span>
              </h2>
              <Input
                v-model="search"
                :aria-label="t(`${NS}.SEARCH`)"
                :placeholder="t(`${NS}.SEARCH`)"
                size="sm"
                class="w-60 max-w-full"
              />
            </div>
            <div
              class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
            >
              <div
                v-if="links.length"
                class="grid grid-cols-[minmax(0,1fr)_3rem_4.5rem_1rem] gap-3 border-b border-n-weak bg-n-slate-2 px-5 py-3 text-xs text-n-slate-11 md:grid-cols-[minmax(0,1fr)_4rem_5rem_2rem] md:gap-4"
              >
                <span>{{ t(`${NS}.ORIGIN`) }}</span>
                <span class="text-end">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.CLICKS') }}
                </span>
                <span class="text-end">
                  {{ t('CRM_KANBAN.TRACKED_LINKS.CONVERSATIONS') }}
                </span>
                <span />
              </div>
              <button
                v-for="link in filteredLinks"
                :key="link.id"
                type="button"
                :aria-pressed="selectedId === link.id"
                class="grid w-full grid-cols-[minmax(0,1fr)_3rem_4.5rem_1rem] items-center gap-3 rounded-none border-solid border-b border-n-weak px-5 py-5 text-start hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand last:border-b-0 md:grid-cols-[minmax(0,1fr)_4rem_5rem_2rem] md:gap-4"
                :class="selectedId === link.id ? 'bg-n-blue-3' : 'bg-n-solid-1'"
                @click="selectedId = link.id"
              >
                <span class="flex min-w-0 items-center gap-3">
                  <span
                    class="hidden size-10 shrink-0 items-center justify-center rounded-lg bg-n-alpha-2 text-n-blue-11 md:flex"
                  >
                    <span class="size-5" :class="usageIcon(link)" />
                  </span>
                  <span class="min-w-0">
                    <span class="block truncate text-sm font-semibold">
                      {{ link.name }}
                    </span>
                    <span class="mt-1 block truncate text-xs text-n-slate-11">
                      {{
                        isWebsite(link)
                          ? `${t(`${NS}.USAGE_WEBSITE_SHORT`)} · ${inboxName(link.inbox_id)}`
                          : inboxName(link.inbox_id)
                      }}
                    </span>
                  </span>
                </span>
                <span class="text-end text-sm font-medium tabular-nums">
                  {{ format(link.clicks_count) }}
                </span>
                <span
                  class="text-end text-sm font-semibold tabular-nums text-n-teal-11"
                >
                  {{ format(link.conversations_count) }}
                </span>
                <span
                  class="i-lucide-arrow-right size-4 text-n-slate-10 rtl:rotate-180"
                />
              </button>
              <div v-if="!links.length" class="px-8 py-16 text-center">
                <span
                  class="i-lucide-qr-code inline-block size-9 text-n-blue-11"
                />
                <h3 class="m-0 mt-4 text-lg font-semibold">
                  {{ t(`${NS}.EMPTY_TITLE`) }}
                </h3>
                <p class="mx-auto mb-0 mt-2 max-w-sm text-sm text-n-slate-11">
                  {{ t(`${NS}.EMPTY_HINT`) }}
                </p>
                <Button
                  v-if="canManage"
                  :label="t(`${NS}.FIRST_CAMPAIGN`)"
                  class="mt-5"
                  :disabled="!inboxes.length"
                  @click="creator.open()"
                />
              </div>
              <p
                v-else-if="!filteredLinks.length"
                class="m-0 p-8 text-center text-sm text-n-slate-11"
              >
                {{ t(`${NS}.NO_RESULTS`) }}
              </p>
            </div>
            <p class="m-0 mt-4 text-xs text-n-slate-11">
              {{
                t(
                  `${NS}.LIST_COUNT`,
                  { count: format(filteredLinks.length) },
                  filteredLinks.length
                )
              }}
            </p>
            <div
              class="mt-8 flex items-start gap-4 rounded-xl bg-n-blue-2 px-5 py-5"
            >
              <span
                class="flex shrink-0 items-center justify-center rounded-lg bg-n-solid-1 p-2.5 text-n-blue-11"
              >
                <span class="i-lucide-route size-5" />
              </span>
              <div>
                <h3 class="m-0 text-sm font-semibold">
                  {{ t(`${NS}.ATTRIBUTION_TITLE`) }}
                </h3>
                <p class="m-0 mt-1 text-sm leading-relaxed text-n-slate-11">
                  {{ t(`${NS}.ATTRIBUTION_HINT`) }}
                </p>
              </div>
            </div>
          </section>

          <aside
            v-if="selected"
            :aria-label="t(`${NS}.DETAILS`)"
            class="self-start overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
          >
            <TrackedLinkReadyBadge :link="selected" class="px-6 pt-5" />
            <h2
              class="m-0 mt-3 break-words px-6 text-xl font-semibold tracking-tight"
            >
              {{ selected.name }}
            </h2>
            <p class="m-0 mt-1 px-6 text-xs text-n-slate-11">
              {{ inboxName(selected.inbox_id) }}
            </p>
            <TrackedLinkWebsitePanel
              v-if="isWebsite(selected)"
              :link="selected"
              :can-manage="canManage"
              @updated="replaceLink"
            />
            <TrackedLinkCampaignTable
              v-if="isWebsite(selected)"
              :campaigns="selected.campaigns || []"
              :origin-name="selected.name"
              class="px-6 pb-5"
            />
            <div
              v-else
              class="mx-6 mt-5 rounded-xl bg-n-slate-2 p-5 text-center"
            >
              <TrackedLinkQr
                :url="selected.short_url"
                class="mx-auto size-40 border border-n-weak"
              />
              <p class="m-0 mt-3 text-xs text-n-slate-11">
                {{ t(`${NS}.SCAN`) }}
              </p>
            </div>
            <div v-if="!isWebsite(selected)" class="px-6 py-5">
              <p class="mb-2 mt-0 text-xs font-medium text-n-slate-11">
                {{ t(`${NS}.LINK`) }}
              </p>
              <div
                :title="selected.short_url"
                class="truncate rounded-lg border border-n-weak p-3 font-mono text-xs"
              >
                {{ selected.short_url }}
              </div>
              <div class="mt-3 grid grid-cols-2 gap-2">
                <Button
                  :label="t('CRM_KANBAN.TRACKED_LINKS.COPY_LINK')"
                  icon="i-lucide-copy"
                  faded
                  class="h-11"
                  @click="copyLink"
                />
                <Button
                  :label="t(`${NS}.DOWNLOAD_QR`)"
                  icon="i-lucide-download"
                  slate
                  outline
                  class="h-11"
                  @click="downloadQr"
                />
              </div>
              <p class="mb-2 mt-6 text-xs font-medium text-n-slate-11">
                {{ t(`${NS}.INITIAL_MESSAGE`) }}
              </p>
              <p
                class="m-0 whitespace-pre-wrap break-words border-s-2 border-n-blue-6 ps-3 text-sm leading-relaxed text-n-slate-11"
              >
                {{ selected.prefilled_text || t(`${NS}.NO_MESSAGE`) }}
              </p>
              <Button
                :label="t(`${NS}.VIEW_MATERIAL`)"
                icon="i-lucide-expand"
                slate
                outline
                class="mt-6 h-11 w-full"
                @click="material.open()"
              />
            </div>
            <div v-if="canManage" class="px-6 pb-5">
              <Button
                :label="t('CRM_KANBAN.TRACKED_LINKS.DELETE')"
                icon="i-lucide-trash-2"
                ruby
                ghost
                class="h-11 w-full"
                @click="deleteDialog.open()"
              />
            </div>
          </aside>
        </div>
      </template>
    </div>
    <CreateTrackedLinkDialog
      v-if="canManage"
      ref="creator"
      :inboxes="inboxes"
      :is-saving="isCreating"
      :error="createError"
      @create="createLink"
      @open="createError = ''"
    />
    <Dialog
      ref="material"
      :title="t(`${NS}.VIEW_MATERIAL`)"
      :show-confirm-button="false"
      :cancel-button-label="t(`${NS}.CLOSE`)"
    >
      <div v-if="selected" class="text-center">
        <h2 class="m-0 text-3xl font-semibold tracking-tight text-n-slate-12">
          {{ t(`${NS}.POSTER_TITLE`) }}
        </h2>
        <p class="m-0 mt-3 text-sm text-n-slate-11">
          {{ t(`${NS}.POSTER_HINT`) }}
        </p>
        <TrackedLinkQr :url="selected.short_url" class="mx-auto my-7 size-56" />
        <p class="m-0 break-words font-semibold text-n-slate-12">
          {{ selected.name }}
        </p>
        <Button
          :label="t(`${NS}.DOWNLOAD_QR`)"
          icon="i-lucide-download"
          slate
          outline
          class="mt-5"
          @click="downloadQr"
        />
      </div>
    </Dialog>
    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t(`${NS}.DELETE_TITLE`)"
      :description="
        t(
          isWebsite(selected)
            ? `${NS}.DELETE_HINT_WEBSITE`
            : `${NS}.DELETE_HINT`,
          {
            name: selected?.name,
          }
        )
      "
      :confirm-button-label="t('CRM_KANBAN.TRACKED_LINKS.DELETE')"
      :is-loading="isDeleting"
      @confirm="deleteLink"
    />
  </div>
</template>
