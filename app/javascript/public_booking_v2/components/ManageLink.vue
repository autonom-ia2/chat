<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ActionButton from './ActionButton.vue';

// Link de gestão da reserva (`manage_url`): sem avisos ligados, o cliente não recebe nada depois, então a página
// entrega o link para guardar, com "Copiar" e "Abrir". Sem a área de transferência (navegador de dentro de app), o
// texto fica selecionado para a pessoa copiar. Quem usa passa só link http/https já conferido (helpers/url.js).
const props = defineProps({
  url: { type: String, required: true },
});

const { t } = useI18n();
const field = ref(null);
const isCopied = ref(false);

const selectText = () => {
  field.value?.focus();
  field.value?.select();
};

const copy = async () => {
  try {
    await navigator.clipboard.writeText(props.url);
    isCopied.value = true;
  } catch (error) {
    // Sem permissão para a área de transferência: o texto selecionado deixa a pessoa copiar pelo menu do celular.
    selectText();
  }
};
</script>

<template>
  <div
    data-testid="manage-link"
    class="flex flex-col gap-3 rounded-2xl border-2 border-slate-200 bg-white p-4"
  >
    <label for="manage-link" class="text-base font-semibold text-slate-900">
      {{ t('BOOKING_V2.DONE.MANAGE_TITLE') }}
    </label>
    <input
      id="manage-link"
      ref="field"
      :value="url"
      type="text"
      readonly
      class="min-h-12 w-full rounded-xl border-2 border-slate-300 bg-slate-50 px-4 py-3 text-base text-slate-900 focus:border-[var(--brand)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--brand)]"
      @focus="$event.target.select()"
    />
    <ActionButton variant="secondary" @click="copy">
      {{ t('BOOKING_V2.DONE.COPY') }}
    </ActionButton>
    <ActionButton :href="url" variant="ghost" external>
      {{ t('BOOKING_V2.DONE.OPEN') }}
    </ActionButton>
    <p role="status" class="text-base text-slate-700">
      {{ isCopied ? t('BOOKING_V2.DONE.COPIED') : '' }}
    </p>
  </div>
</template>
