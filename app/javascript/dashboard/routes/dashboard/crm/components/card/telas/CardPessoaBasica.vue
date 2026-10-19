<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { formatClientPhone } from '../../../helpers/meetingDay';

// A pessoa do card para quem não pode ver contatos (#1849, decisão D7): nome, telefone e e-mail, que já vêm com o
// card. A ficha, a empresa e os campos ficam com quem tem "Ver contatos".
const props = defineProps({
  contato: { type: Object, default: null },
});
const { t } = useI18n();
const linhas = computed(() =>
  [
    {
      chave: 'telefone',
      icone: 'i-lucide-phone',
      rotulo: t('CRM_KANBAN.RELATIONSHIP.PHONE'),
      valor: formatClientPhone(props.contato?.phone_number),
      href: props.contato?.phone_number
        ? `tel:${props.contato.phone_number}`
        : '',
    },
    {
      chave: 'email',
      icone: 'i-lucide-mail',
      rotulo: t('CRM_KANBAN.RELATIONSHIP.EMAIL'),
      valor: props.contato?.email,
      href: props.contato?.email ? `mailto:${props.contato.email}` : '',
    },
  ].filter(linha => linha.valor)
);
</script>

<template>
  <div
    v-if="contato"
    class="flex flex-col gap-3 rounded-2xl border border-n-weak p-4"
    data-pessoa-basica
  >
    <div class="flex items-center gap-3">
      <Avatar :name="contato.name" :src="contato.thumbnail" :size="40" />
      <strong class="min-w-0 break-words text-base font-semibold">
        {{ contato.name }}
      </strong>
    </div>
    <dl class="m-0 grid gap-2">
      <div
        v-for="linha in linhas"
        :key="linha.chave"
        class="flex min-h-11 items-center gap-2"
      >
        <span
          :class="linha.icone"
          class="size-4 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <dt class="sr-only">{{ linha.rotulo }}</dt>
        <dd class="m-0 min-w-0 break-all text-n-slate-12">
          <a :href="linha.href" class="hover:underline">{{ linha.valor }}</a>
        </dd>
      </div>
    </dl>
  </div>
  <p v-else class="mb-0 text-n-slate-11">
    {{ t('CRM_CARD.RESUMO.SEM_CONTATO') }}
  </p>
</template>
