<script setup>
// "Redes e rodapé" of an identity (#1076): its name, the networks and the identity line of the
// footer (company · address · site). The rest of the footer — why the person got the e-mail and
// the unsubscribe link — is the system's and never changes here.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  NETWORKS,
  NETWORK_LABELS,
  NETWORK_MARKS,
  withScheme,
} from './brandKitData';

const props = defineProps({
  form: { type: Object, required: true },
  isFirst: { type: Boolean, default: false },
});

const emit = defineEmits(['update:form']);

const NS = 'BRAND_KITS.FOOTER';
const { t } = useI18n();
const editing = ref('');
const editUrl = ref('');
const adding = ref(false);
const newNetwork = ref('');
const newUrl = ref('');

const appearance = computed(() => props.form.appearance);
const links = computed(() => appearance.value.social_links || []);
const footer = computed(() => appearance.value.footer || {});
const freeNetworks = computed(() =>
  NETWORKS.filter(
    network => !links.value.some(link => link.network === network)
  )
);
const networkOptions = computed(() =>
  freeNetworks.value.map(network => ({
    value: network,
    label: NETWORK_LABELS[network],
  }))
);

const update = patch => emit('update:form', { ...props.form, ...patch });
const updateAppearance = patch =>
  update({ appearance: { ...appearance.value, ...patch } });
const setLinks = socialLinks => updateAppearance({ social_links: socialLinks });
const setFooter = (key, value) =>
  updateAppearance({ footer: { ...footer.value, [key]: value } });

const startEdit = link => {
  editing.value = link.network;
  editUrl.value = link.url;
};
const saveEdit = () => {
  setLinks(
    links.value.map(link =>
      link.network === editing.value
        ? { ...link, url: withScheme(editUrl.value) }
        : link
    )
  );
  editing.value = '';
};
const remove = network =>
  setLinks(links.value.filter(link => link.network !== network));
const startAdd = () => {
  adding.value = true;
  newNetwork.value = freeNetworks.value[0] || '';
  newUrl.value = '';
};
const add = () => {
  if (!newNetwork.value || !newUrl.value.trim()) return;
  setLinks([
    ...links.value,
    { network: newNetwork.value, url: withScheme(newUrl.value) },
  ]);
  adding.value = false;
};
</script>

<template>
  <div class="flex flex-col">
    <section class="flex flex-col gap-3 border-b border-n-weak p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.NAME_TITLE`) }}
      </h3>
      <Input
        :model-value="form.name"
        :label="t(`${NS}.NAME_LABEL`)"
        custom-input-class="!h-11"
        data-test="kit-name"
        @update:model-value="name => update({ name })"
      />
      <p v-if="isFirst" class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.FIRST_IS_DEFAULT`) }}
      </p>
    </section>

    <section class="flex flex-col gap-3 border-b border-n-weak p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.SOCIAL_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.SOCIAL_HINT`) }}</p>
      <p v-if="!links.length" class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.SOCIAL_EMPTY`) }}
      </p>
      <ul v-else class="m-0 list-none p-0">
        <li
          v-for="link in links"
          :key="link.network"
          class="flex flex-col gap-2 border-b border-n-weak py-3 last:border-0"
          :data-network="link.network"
        >
          <div class="flex items-center gap-3">
            <span
              class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-n-blue-3 text-xs font-bold text-n-blue-11"
              aria-hidden="true"
            >
              {{ NETWORK_MARKS[link.network] }}
            </span>
            <div class="min-w-0 flex-1">
              <p class="m-0 text-sm font-semibold text-n-slate-12">
                {{ NETWORK_LABELS[link.network] }}
              </p>
              <p class="m-0 truncate text-xs text-n-slate-11">{{ link.url }}</p>
            </div>
            <Button
              :label="t(`${NS}.CHANGE`)"
              variant="outline"
              color="slate"
              size="sm"
              class="!min-h-11 !rounded-xl"
              @click="startEdit(link)"
            />
            <Button
              :label="t(`${NS}.REMOVE`)"
              variant="ghost"
              color="slate"
              size="sm"
              class="!min-h-11 !rounded-xl"
              @click="remove(link.network)"
            />
          </div>
          <div
            v-if="editing === link.network"
            class="flex flex-wrap items-end gap-2"
          >
            <Input
              v-model="editUrl"
              class="min-w-0 flex-1"
              :label="t(`${NS}.LINK_LABEL`)"
              custom-input-class="!h-11"
              @enter="saveEdit"
            />
            <Button
              :label="t(`${NS}.DONE`)"
              size="sm"
              class="!min-h-11 !rounded-xl"
              @click="saveEdit"
            />
          </div>
        </li>
      </ul>
      <div
        v-if="adding"
        class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-3"
      >
        <ChoiceSelect
          v-model="newNetwork"
          :options="networkOptions"
          :aria-label="t(`${NS}.NETWORK_LABEL`)"
        />
        <Input
          v-model="newUrl"
          :label="t(`${NS}.LINK_LABEL`)"
          :placeholder="t(`${NS}.LINK_PLACEHOLDER`)"
          custom-input-class="!h-11"
          @enter="add"
        />
        <div class="flex gap-2">
          <Button
            :label="t(`${NS}.ADD_CONFIRM`)"
            size="sm"
            class="!min-h-11 !rounded-xl"
            data-test="network-add-confirm"
            @click="add"
          />
          <Button
            :label="t(`${NS}.CANCEL`)"
            variant="ghost"
            color="slate"
            size="sm"
            class="!min-h-11 !rounded-xl"
            @click="adding = false"
          />
        </div>
      </div>
      <div v-else-if="freeNetworks.length">
        <Button
          :label="t(`${NS}.ADD`)"
          icon="i-lucide-plus"
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11 !rounded-xl"
          data-test="network-add"
          @click="startAdd"
        />
      </div>
    </section>

    <section class="flex flex-col gap-3 p-5">
      <h3 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.FOOTER_TITLE`) }}
      </h3>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.FOOTER_HINT`) }}</p>
      <Input
        :model-value="footer.company_name || ''"
        :label="t(`${NS}.COMPANY`)"
        custom-input-class="!h-11"
        @update:model-value="value => setFooter('company_name', value)"
      />
      <Input
        :model-value="footer.website || ''"
        :label="t(`${NS}.SITE`)"
        custom-input-class="!h-11"
        @update:model-value="value => setFooter('website', value)"
      />
      <Input
        :model-value="footer.address || ''"
        :label="t(`${NS}.ADDRESS`)"
        :placeholder="t(`${NS}.ADDRESS_PLACEHOLDER`)"
        :message="footer.address ? '' : t(`${NS}.ADDRESS_MISSING`)"
        custom-input-class="!h-11"
        data-test="kit-address"
        @update:model-value="value => setFooter('address', value)"
      />
    </section>
  </div>
</template>
