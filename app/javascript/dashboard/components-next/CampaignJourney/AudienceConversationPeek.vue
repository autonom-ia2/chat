<script setup>
// The conversation beside the list (#2277): the person sees the proof of why someone came in (the messages that
// count have an amber ring; the first one says "Por isso entrou", or "Isto conta" for who was left out), decides
// right there with the same "Vai receber" switch of the list and walks the list with "Anterior" / "Próxima"
// ("2 de 13"), kept at the bottom with "Abrir a conversa inteira". Dates separate the days, like in WhatsApp.
// Esc, the X or a tap outside closes it.
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AudienceListSwitch from './AudienceListSwitch.vue';

const props = defineProps({
  person: { type: Object, default: null },
  messages: { type: Array, default: () => [] },
  conversationUrl: { type: String, default: '' },
  included: { type: Boolean, default: false },
  position: { type: Number, default: 0 },
  total: { type: Number, default: 0 },
  isOutGroup: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'toggle', 'previous', 'next']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const { t } = useI18n();
const closeButton = ref(null);

const initials = computed(() =>
  (props.person?.name || '')
    .split(' ')
    .slice(0, 2)
    .map(part => part[0])
    .join('')
);

// Someone outside the rule that the person put in says so, instead of "Por que ficou de fora".
const whyTitle = computed(() => {
  if (!props.isOutGroup) return t(`${NS}.PEEK_WHY`);
  return props.included ? t(`${NS}.PEEK_WHY_ADDED`) : t(`${NS}.PEEK_WHY_OUT`);
});

// The date shows once per day, above the first message of that day; only the first message that counts
// carries the label.
const rows = computed(() => {
  const firstCounting = props.messages.findIndex(message => message.counts);
  return props.messages.map((message, index) => ({
    ...message,
    newDay:
      Boolean(message.date) &&
      props.messages.findIndex(other => other.date === message.date) === index,
    isFirstCounting: index === firstCounting,
  }));
});

watch(
  () => props.person,
  async value => {
    if (!value) return;
    await nextTick();
    closeButton.value?.focus();
  }
);

onKeyStroke('Escape', () => {
  if (props.person) emit('close');
});
</script>

<template>
  <TeleportWithDirection to="body">
    <div v-if="person" class="fixed inset-0 z-50 flex justify-end">
      <div
        class="absolute inset-0 bg-n-alpha-black1 backdrop-blur-[2px]"
        aria-hidden="true"
        @click="emit('close')"
      />
      <aside
        role="dialog"
        aria-modal="true"
        :aria-label="t(`${NS}.PEEK_TITLE`, { name: person.name })"
        class="relative flex h-full w-full max-w-md flex-col bg-n-solid-1 shadow-2xl"
        data-test="peek-panel"
      >
        <div class="flex flex-1 flex-col gap-5 overflow-y-auto p-5">
          <header class="flex items-center gap-3">
            <span
              class="grid size-10 shrink-0 place-items-center rounded-full bg-n-blue-3 text-sm font-semibold text-n-blue-11"
              aria-hidden="true"
            >
              {{ initials }}
            </span>
            <div class="flex min-w-0 flex-1 flex-col">
              <h3 class="m-0 truncate text-lg font-semibold text-n-slate-12">
                {{ person.name }}
              </h3>
              <span class="text-sm tabular-nums text-n-slate-11">
                {{ person.contact }}
              </span>
            </div>
            <span class="shrink-0 text-sm tabular-nums text-n-slate-11">
              {{ t(`${NS}.PEEK_POSITION`, { position, total }) }}
            </span>
            <button
              ref="closeButton"
              type="button"
              class="grid size-11 shrink-0 place-items-center rounded-xl text-n-slate-11 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
              :aria-label="t(`${NS}.PEEK_CLOSE`)"
              @click="emit('close')"
            >
              <span class="i-lucide-x size-5" aria-hidden="true" />
            </button>
          </header>
          <div
            class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak px-4 py-2"
          >
            <span class="text-base font-medium text-n-slate-12">
              {{ t(`${NS}.PEEK_IN_LIST`) }}
            </span>
            <AudienceListSwitch
              :on="included"
              :label="t(`${NS}.IN_LIST_NAMED`, { name: person.name })"
              @toggle="emit('toggle')"
            />
          </div>
          <section class="flex flex-col gap-1 rounded-2xl bg-n-iris-2 p-4">
            <h4 class="m-0 text-sm font-medium text-n-slate-11">
              {{ whyTitle }}
            </h4>
            <p class="m-0 text-base text-n-slate-12">{{ person.reason }}</p>
          </section>
          <ol class="m-0 flex list-none flex-col gap-3 p-0">
            <template v-for="(message, index) in rows" :key="index">
              <li
                v-if="message.newDay"
                class="self-center rounded-full bg-n-slate-3 px-3 py-0.5 text-xs font-medium text-n-slate-11"
              >
                {{ message.date }}
              </li>
              <li
                class="flex max-w-[85%] flex-col gap-1"
                :class="message.from === 'contato' ? 'self-start' : 'self-end'"
              >
                <span
                  v-if="message.isFirstCounting"
                  class="w-fit rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
                >
                  {{
                    isOutGroup
                      ? t(`${NS}.PEEK_COUNTS_OUT`)
                      : t(`${NS}.PEEK_COUNTS`)
                  }}
                </span>
                <span
                  class="rounded-2xl px-4 py-2 text-sm leading-6"
                  :class="
                    message.from === 'contato'
                      ? message.counts
                        ? 'bg-n-amber-2 text-n-slate-12 ring-2 ring-inset ring-n-amber-6'
                        : 'bg-n-slate-3 text-n-slate-12'
                      : 'bg-n-blue-9 text-white'
                  "
                >
                  {{ message.text }}
                </span>
              </li>
            </template>
          </ol>
        </div>
        <footer
          class="flex flex-col gap-2 border-t border-n-weak bg-n-solid-1 px-5 py-4"
        >
          <div class="grid grid-cols-2 gap-2">
            <Button
              :label="t(`${NS}.PEEK_PREVIOUS`)"
              icon="i-lucide-arrow-left"
              variant="outline"
              color="slate"
              :disabled="position <= 1"
              class="!min-h-12 !rounded-xl !text-base"
              @click="emit('previous')"
            />
            <Button
              :label="t(`${NS}.PEEK_NEXT`)"
              icon="i-lucide-arrow-right"
              trailing-icon
              :disabled="position >= total"
              class="!min-h-12 !rounded-xl !text-base"
              data-test="peek-next"
              @click="emit('next')"
            />
          </div>
          <a
            v-if="conversationUrl"
            :href="conversationUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl px-4 text-sm font-medium text-n-blue-11 hover:bg-n-blue-2"
          >
            {{ t(`${NS}.PEEK_OPEN`) }}
            <span class="i-lucide-external-link size-4" aria-hidden="true" />
          </a>
        </footer>
      </aside>
    </div>
  </TeleportWithDirection>
</template>
