<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BookingLinkActions from './BookingLinkActions.vue';

// O link para divulgar. Página com um responsável: um link só. Página com um
// link por pessoa: o endereço da página não marca nada (o cliente só marca
// pelo link de cada pessoa), então aparece uma linha por pessoa, cada uma com
// Copiar link, QR code e Abrir.
const props = defineProps({
  page: { type: Object, required: true },
});

const { t } = useI18n();
const links = computed(() => props.page.links || []);
</script>

<template>
  <BookingLinkActions v-if="page.public_url" :url="page.public_url" />
  <div v-else-if="links.length" data-person-links class="flex flex-col gap-3">
    <div class="flex flex-col gap-1">
      <p class="m-0 text-base font-semibold text-n-slate-12">
        {{ t('BOOKING.LINK.PER_PERSON_TITLE') }}
      </p>
      <p class="m-0 text-base text-n-slate-11">
        {{ t('BOOKING.LINK.PER_PERSON_HINT') }}
      </p>
    </div>
    <ul class="flex flex-col gap-3 p-0 m-0 list-none">
      <li
        v-for="link in links"
        :key="link.agent_id"
        :data-person-link="link.agent_id"
        class="flex flex-col gap-2 p-4 rounded-xl ring-1 ring-inset ring-n-weak"
      >
        <p class="m-0 text-base font-semibold text-n-slate-12 break-words">
          {{ link.agent_name }}
        </p>
        <div
          role="group"
          :aria-label="
            t('BOOKING.LINK.PERSON_LABEL', { name: link.agent_name })
          "
        >
          <BookingLinkActions :url="link.url" />
        </div>
      </li>
    </ul>
  </div>
</template>
