<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useRelationships } from 'dashboard/composables/useRelationships';
import Policy from 'dashboard/components/policy.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
const { navigationEnabled, accountId, mediaEnabled, attributesEnabled } =
  useRelationships();
const { isCloudFeatureEnabled } = useAccount();
const capabilityIcons = title =>
  title === 'ATTRIBUTES'
    ? {
        PROFILE: 'i-lucide-settings',
        MEDIA: 'i-lucide-layers',
        FIELDS: 'i-lucide-file-text',
      }
    : {
        PROFILE: 'i-lucide-users-round',
        MEDIA: 'i-lucide-image',
        FIELDS: 'i-lucide-tag',
      };
const capabilities = title =>
  Object.entries(capabilityIcons(title)).filter(([key]) => {
    if (title === 'COMPANIES' && key === 'MEDIA') return mediaEnabled.value;
    if (title === 'ATTRIBUTES' && key === 'MEDIA')
      return attributesEnabled.value;
    if (title !== 'ATTRIBUTES' && key === 'FIELDS')
      return isCloudFeatureEnabled('custom_attributes');
    return true;
  });
const description = title => {
  const customized =
    attributesEnabled.value && isCloudFeatureEnabled('custom_attributes');
  const complete = customized && (title !== 'COMPANIES' || mediaEnabled.value);
  return `RELATIONSHIPS.CARD_DETAILS.${title}.${complete ? 'DESCRIPTION' : 'BASIC_DESCRIPTION'}`;
};
const cards = computed(() =>
  [
    {
      title: 'CONTACTS',
      route: 'contacts_dashboard_index',
      flag: 'crm',
      permissions: ['administrator', 'agent', 'contact_view', 'contact_manage'],
      icon: 'i-lucide-user-round',
      color: 'bg-n-blue-3 text-n-blue-11',
      action: 'OPEN_CONTACTS',
    },
    {
      title: 'COMPANIES',
      route: 'companies_dashboard_index',
      flag: 'companies',
      permissions: ['administrator', 'agent'],
      icon: 'i-lucide-building-2',
      color: 'bg-n-violet-3 text-n-violet-11',
      action: 'OPEN_COMPANIES',
      installationTypes: ['cloud', 'enterprise'],
    },
    {
      title: 'ATTRIBUTES',
      route: 'attributes_list',
      flag: 'custom_attributes',
      permissions: ['administrator', 'attribute_manage'],
      icon: 'i-lucide-tag',
      color: 'bg-n-teal-3 text-n-teal-11',
      action: 'OPEN_ATTRIBUTES',
    },
  ].filter(card => isCloudFeatureEnabled(card.flag))
);
</script>

<template>
  <main
    v-if="navigationEnabled"
    class="flex-1 min-w-0 overflow-auto bg-n-surface-1"
  >
    <div
      class="mx-auto flex w-full max-w-7xl flex-col gap-8 px-5 py-8 md:px-8 md:py-12"
    >
      <header class="flex flex-col gap-5 sm:flex-row sm:items-center">
        <div
          class="flex size-20 shrink-0 items-center justify-center rounded-2xl bg-n-blue-4 text-n-blue-11"
        >
          <Icon icon="i-lucide-users-round" class="size-10" />
        </div>
        <div class="min-w-0">
          <h1
            class="text-3xl font-semibold leading-tight tracking-tight text-n-slate-12 md:text-4xl"
          >
            {{ $t('RELATIONSHIPS.TITLE') }}
          </h1>
          <p
            class="mt-3 max-w-4xl text-base leading-relaxed text-n-slate-11 md:text-lg"
          >
            {{ $t('RELATIONSHIPS.SUBTITLE') }}
          </p>
        </div>
      </header>
      <div
        class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,18rem),1fr))] gap-5"
      >
        <Policy
          v-for="card in cards"
          :key="card.route"
          :feature-flag="card.flag"
          :permissions="card.permissions"
          :installation-types="card.installationTypes"
        >
          <article
            class="flex h-full min-w-0 flex-col gap-6 rounded-xl border border-n-weak bg-n-solid-2 p-6 shadow-sm md:p-7"
          >
            <div class="flex items-center gap-4">
              <div
                :class="card.color"
                class="flex size-14 shrink-0 items-center justify-center rounded-xl"
              >
                <Icon :icon="card.icon" class="size-7" />
              </div>
              <div class="min-w-0">
                <h2 class="text-xl font-semibold leading-snug text-n-slate-12">
                  {{ $t(`RELATIONSHIPS.${card.title}`) }}
                </h2>
                <p class="mt-1 text-sm text-n-slate-11">
                  {{ $t(`RELATIONSHIPS.CARD_DETAILS.${card.title}.SUBTITLE`) }}
                </p>
              </div>
            </div>
            <p class="text-base leading-relaxed text-n-slate-11">
              {{ $t(description(card.title)) }}
            </p>
            <ul
              class="mt-auto flex flex-col gap-3 border-t border-n-weak pt-5 text-sm text-n-slate-11"
            >
              <li
                v-for="[key, icon] in capabilities(card.title)"
                :key="key"
                class="flex items-center gap-3"
              >
                <div
                  class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-n-slate-3 text-n-slate-12"
                >
                  <Icon :icon="icon" class="size-4" />
                </div>
                {{ $t(`RELATIONSHIPS.CARD_DETAILS.${card.title}.${key}`) }}
              </li>
            </ul>
            <RouterLink
              :to="{ name: card.route, params: { accountId } }"
              class="flex min-h-12 items-center justify-center gap-3 rounded-lg bg-n-brand px-4 py-3 text-center text-sm font-medium text-white transition-colors hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-n-blue-9"
            >
              {{ $t(`RELATIONSHIPS.${card.action}`) }}
              <Icon
                icon="i-lucide-arrow-right"
                class="size-4 shrink-0 rtl:rotate-180"
              />
            </RouterLink>
          </article>
        </Policy>
      </div>
      <aside
        class="flex items-start gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-5 md:items-center"
      >
        <div
          class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-n-blue-4 text-n-blue-11"
        >
          <Icon icon="i-lucide-lightbulb" class="size-6" />
        </div>
        <div>
          <h2 class="text-base font-medium text-n-slate-12">
            {{ $t('RELATIONSHIPS.HOME_SUPPORT_TITLE') }}
          </h2>
          <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
            {{ $t('RELATIONSHIPS.HOME_SUPPORT_DESCRIPTION') }}
          </p>
        </div>
      </aside>
    </div>
  </main>
  <template v-else />
</template>
