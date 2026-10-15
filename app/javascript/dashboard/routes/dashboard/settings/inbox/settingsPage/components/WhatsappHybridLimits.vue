<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import {
  timelockEndFor,
  limitDateTime,
  limitDate,
} from '../whatsappHybridState';

// chat#1480/#1481 — o que o WhatsApp está limitando neste número: a restrição temporária de conversas novas e o
// ciclo de conversas novas. Só avisos, no tom das caixas de situação (âmbar atenção, vermelho bloqueado).
const props = defineProps({
  state: { type: Object, required: true },
  now: { type: Number, required: true },
});

const { t, locale } = useI18n();
const { currentAccount } = useAccount();
// Fuso e idioma da conta, nunca os do navegador.
const dateOptions = computed(() => ({
  locale: locale.value,
  timeZone: fusoDaConta(currentAccount.value),
}));

const CAPPING_KEYS = {
  FIRST_WARNING: 'NEAR',
  SECOND_WARNING: 'NEAR',
  CAPPED: 'BLOCKED',
};

const capping = computed(() => props.state.capping || { status: 'NONE' });
const cappingKey = computed(() => CAPPING_KEYS[capping.value.status] || '');
const cappingEnd = computed(() =>
  capping.value.cycle_end
    ? limitDate(capping.value.cycle_end, dateOptions.value)
    : '—'
);
const cappingText = computed(() =>
  cappingKey.value
    ? // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      t(`INBOX_MGMT.WHATSAPP_HYBRID.CAPPING.${cappingKey.value}`, {
        used: capping.value.used ?? '—',
        total: capping.value.total ?? '—',
        end: cappingEnd.value,
      })
    : ''
);

// `now` anda a cada segundo, então o aviso some na hora certa. Com o bloqueio do ciclo, só ele aparece.
const timelockEnd = computed(() => timelockEndFor(props.state, props.now));
const timelockText = computed(() => {
  if (!timelockEnd.value || cappingKey.value === 'BLOCKED') return '';
  if (timelockEnd.value === true) {
    return t('INBOX_MGMT.WHATSAPP_HYBRID.TIMELOCK.NO_END');
  }
  return t('INBOX_MGMT.WHATSAPP_HYBRID.TIMELOCK.UNTIL', {
    end: limitDateTime(props.state.timelock.ends_at, dateOptions.value),
  });
});
</script>

<template>
  <section
    v-if="timelockText"
    data-hybrid-timelock
    role="status"
    class="flex items-start gap-3 p-4 text-sm leading-relaxed rounded-2xl ring-1 ring-inset bg-n-amber-2 ring-n-amber-6 text-n-slate-12"
  >
    <span
      class="i-lucide-hourglass size-5 mt-0.5 shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    <span>{{ timelockText }}</span>
  </section>
  <section
    v-if="cappingText"
    data-hybrid-capping
    role="status"
    class="flex items-start gap-3 p-4 text-sm leading-relaxed rounded-2xl ring-1 ring-inset text-n-slate-12"
    :class="
      cappingKey === 'BLOCKED'
        ? 'bg-n-ruby-2 ring-n-ruby-6'
        : 'bg-n-amber-2 ring-n-amber-6'
    "
  >
    <span
      class="i-lucide-gauge size-5 mt-0.5 shrink-0"
      :class="cappingKey === 'BLOCKED' ? 'text-n-ruby-11' : 'text-n-amber-11'"
      aria-hidden="true"
    />
    <span>{{ cappingText }}</span>
  </section>
</template>
