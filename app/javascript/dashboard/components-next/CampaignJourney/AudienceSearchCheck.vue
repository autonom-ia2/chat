<script setup>
// Step "Confira" of the search by conversation (#2277). Either one question, when the request can be read two
// ways (radio cards + "Tanto faz"), or the plan: what was understood (with the period), how many conversations
// will be read, how long it takes and how much it costs on the account's own AI. Nothing is paid before
// "Começar a procurar", and the search never goes past the ceiling without asking.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatMoney, formatNumber } from './localeTag';

const props = defineProps({
  question: { type: Object, default: null },
  plan: { type: Object, default: null },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['answer', 'start', 'back']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const ANY = 'tanto-faz';
const PRIMARY = '!min-h-12 !rounded-xl !px-6 !text-base';
const { t, locale } = useI18n();
const choice = ref('');

const options = computed(() => [
  ...(props.question?.options || []),
  { id: ANY, label: t(`${NS}.QUESTION_ANY`) },
]);
const brl = value => formatMoney(value, 'BRL', locale.value);
const usd = value => formatMoney(value, 'USD', locale.value);
</script>

<template>
  <section
    class="flex flex-col gap-6 rounded-3xl border border-n-weak bg-n-solid-1 p-5 shadow-sm md:p-8"
    data-test="search-check"
  >
    <!-- Uma pergunta, quando o pedido dá para entender de dois jeitos -->
    <form
      v-if="question"
      class="flex flex-col gap-5"
      @submit.prevent="choice && emit('answer', choice)"
    >
      <fieldset class="m-0 flex flex-col gap-3 border-0 p-0">
        <legend class="mb-4 text-xl font-semibold text-n-slate-12">
          {{ question.text }}
        </legend>
        <label
          v-for="option in options"
          :key="option.id"
          class="flex min-h-14 cursor-pointer items-center gap-3 rounded-2xl border-2 px-4 py-3 transition focus-within:ring-2 focus-within:ring-n-brand"
          :class="
            choice === option.id
              ? 'border-n-blue-9 bg-n-blue-2'
              : 'border-n-weak hover:border-n-slate-7'
          "
        >
          <input
            v-model="choice"
            type="radio"
            name="audience-question"
            :value="option.id"
            class="size-5 shrink-0 accent-n-blue-9"
          />
          <span class="text-base font-medium text-n-slate-12">
            {{ option.label }}
          </span>
        </label>
      </fieldset>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-between">
        <Button
          type="button"
          :label="t(`${NS}.CHANGE_REQUEST`)"
          variant="outline"
          color="slate"
          :class="PRIMARY"
          @click="emit('back')"
        />
        <Button
          type="submit"
          :label="t(`${NS}.QUESTION_NEXT`)"
          :disabled="!choice"
          :is-loading="busy"
          :class="PRIMARY"
          data-test="answer"
        />
      </div>
    </form>

    <!-- O plano: o que entendemos, quanto vai ler, tempo e custo -->
    <template v-else-if="plan">
      <figure class="m-0 flex flex-col gap-2">
        <figcaption class="text-sm font-medium text-n-slate-11">
          {{ t(`${NS}.UNDERSTOOD`) }}
        </figcaption>
        <blockquote
          class="m-0 rounded-e-2xl border-s-4 border-n-iris-7 bg-n-iris-2 px-5 py-4 text-lg leading-relaxed text-n-slate-12"
          data-test="understood"
        >
          {{ plan.understood }}
        </blockquote>
      </figure>
      <dl
        class="m-0 grid grid-cols-3 divide-x divide-n-weak rounded-2xl bg-n-slate-2 p-3 sm:p-4 rtl:divide-x-reverse"
      >
        <div class="flex flex-col gap-1 px-2 first:ps-0 sm:px-4">
          <dt class="text-xs text-n-slate-11 sm:text-sm">
            {{ t(`${NS}.WILL_READ`) }}
          </dt>
          <dd
            class="m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:text-xl"
          >
            {{
              t(`${NS}.CONVERSATIONS`, {
                count: formatNumber(plan.conversations, locale),
              })
            }}
          </dd>
        </div>
        <div class="flex flex-col gap-1 px-2 first:ps-0 sm:px-4">
          <dt class="text-xs text-n-slate-11 sm:text-sm">
            {{ t(`${NS}.TIME`) }}
          </dt>
          <dd
            class="m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:text-xl"
          >
            {{ t(`${NS}.MINUTES`, { count: plan.minutes }) }}
          </dd>
        </div>
        <div class="flex flex-col gap-1 px-2 first:ps-0 sm:px-4">
          <dt class="text-xs text-n-slate-11 sm:text-sm">
            {{ t(`${NS}.COST`) }}
          </dt>
          <dd
            class="m-0 text-sm font-semibold tabular-nums text-n-slate-12 sm:text-xl"
          >
            {{ t(`${NS}.ABOUT`, { value: brl(plan.cost.brl) }) }}
            <span
              class="block text-xs font-normal text-n-slate-11 sm:inline sm:text-sm"
            >
              {{ t(`${NS}.IN_DOLLARS`, { value: usd(plan.cost.usd) }) }}
            </span>
          </dd>
        </div>
      </dl>
      <p
        class="m-0 flex items-start gap-2 rounded-2xl bg-n-teal-2 px-4 py-3 text-base leading-6 text-n-slate-12"
      >
        <span
          class="i-lucide-shield-check mt-0.5 size-5 shrink-0 text-n-teal-10"
          aria-hidden="true"
        />
        {{ t(`${NS}.COST_PROMISE`, { max: brl(plan.ceiling.brl) }) }}
      </p>
      <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-between">
        <Button
          :label="t(`${NS}.CHANGE_REQUEST`)"
          variant="outline"
          color="slate"
          :class="PRIMARY"
          @click="emit('back')"
        />
        <Button
          :label="t(`${NS}.START`)"
          icon="i-lucide-search"
          :is-loading="busy"
          :class="PRIMARY"
          data-test="start"
          @click="emit('start')"
        />
      </div>
    </template>
  </section>
</template>
