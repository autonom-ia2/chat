<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SourcesAPI from 'dashboard/api/autonomia/sources';
import { openSignedFile } from 'shared/helpers/openSignedFile';

const props = defineProps({ fonte: { type: Object, required: true } });
const { t } = useI18n();
const opening = ref(false);

const open = async () => {
  if (opening.value) return;
  opening.value = true;
  const error = await openSignedFile(async () => {
    const { data } = await SourcesAPI.getFile(
      props.fonte.autonomia_agent_id,
      props.fonte.id
    );
    return data.url;
  });
  opening.value = false;
  if (error) {
    useAlert(
      error.response?.status === 404
        ? t('AGENTS.JORNADA.PAGINA.SABE.ORIGINAL_UNAVAILABLE')
        : t('AGENTS.JORNADA.PAGINA.SABE.ORIGINAL_ERROR')
    );
  }
};
</script>

<template>
  <button
    v-tooltip.top="
      t('AGENTS.JORNADA.PAGINA.SABE.OPEN_ORIGINAL', { nome: fonte.reference })
    "
    type="button"
    data-open-original
    :aria-label="
      t('AGENTS.JORNADA.PAGINA.SABE.OPEN_ORIGINAL', { nome: fonte.reference })
    "
    :aria-busy="opening ? 'true' : 'false'"
    :aria-disabled="opening ? 'true' : undefined"
    class="grid shrink-0 rounded-lg place-items-center size-11 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
    @click="open"
  >
    <span
      aria-hidden="true"
      class="size-5"
      :class="
        opening
          ? 'i-lucide-loader-circle motion-safe:animate-spin'
          : 'i-lucide-external-link'
      "
    />
  </button>
</template>
