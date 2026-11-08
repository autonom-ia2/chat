<script setup>
// One person found in the conversations (#2277): name and how it is reached (phone, or e-mail when there is
// no phone) on top, why the person came in below (never cut on the phone: it is what gives trust), a button that opens the conversation beside the list and the switch
// that keeps the person in or out. Who is out stays readable, only faded.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AudienceListSwitch from './AudienceListSwitch.vue';

const props = defineProps({
  person: { type: Object, required: true },
  included: { type: Boolean, default: true },
});
const emit = defineEmits(['toggle', 'peek']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const { t } = useI18n();

const initials = computed(() =>
  props.person.name
    .split(' ')
    .slice(0, 2)
    .map(part => part[0])
    .join('')
);
</script>

<template>
  <li
    class="grid grid-cols-[auto_1fr_auto_auto] items-center gap-x-3 py-3"
    data-test="found-person"
  >
    <span
      class="row-span-2 grid size-10 place-items-center self-start rounded-full text-sm font-semibold transition sm:row-span-1 sm:self-center"
      :class="
        included ? 'bg-n-blue-3 text-n-blue-11' : 'bg-n-slate-3 text-n-slate-10'
      "
      aria-hidden="true"
    >
      {{ initials }}
    </span>
    <div class="flex min-w-0 flex-col">
      <div class="flex min-w-0 flex-wrap items-baseline gap-x-2">
        <strong
          class="truncate text-sm transition"
          :class="included ? 'text-n-slate-12' : 'text-n-slate-11'"
        >
          {{ person.name }}
        </strong>
        <span class="text-xs tabular-nums text-n-slate-11">
          {{ person.contact }}
        </span>
      </div>
      <p
        class="m-0 hidden truncate text-sm text-n-slate-11 sm:block"
        :title="person.reason"
      >
        {{ person.reason }}
      </p>
    </div>
    <button
      type="button"
      class="grid size-11 place-items-center rounded-xl text-n-slate-11 transition hover:bg-n-slate-3 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :aria-label="t(`${NS}.SEE_CONVERSATION_NAMED`, { name: person.name })"
      :title="t(`${NS}.SEE_CONVERSATION`)"
      data-test="peek"
      @click="emit('peek')"
    >
      <span class="i-lucide-message-circle size-5" aria-hidden="true" />
    </button>
    <AudienceListSwitch
      :on="included"
      :label="t(`${NS}.IN_LIST_NAMED`, { name: person.name })"
      @toggle="emit('toggle')"
    />
    <p class="col-span-3 m-0 mt-1 text-sm leading-5 text-n-slate-11 sm:hidden">
      {{ person.reason }}
    </p>
  </li>
</template>
