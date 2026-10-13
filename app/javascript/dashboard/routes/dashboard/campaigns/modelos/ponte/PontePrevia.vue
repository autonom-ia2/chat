<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ModeloCelular from '../components/ModeloCelular.vue';
import { paraTemplateDaMeta } from '../helpers/paraMeta';

// "Como o cliente vê" na campanha: o mesmo celular da tela de Modelos (com
// topo, rodapé e botões), com o que cada variável vai receber.
const props = defineProps({
  modelo: { type: Object, required: true },
  bindings: { type: Object, default: () => ({}) },
  sample: { type: Object, default: null },
  remetente: { type: String, default: '' },
});

const { t } = useI18n();

const valorDe = ligacao => {
  if (!ligacao?.value) return '';
  if (ligacao.source === 'fixed') return ligacao.value;
  if (ligacao.source === 'column') {
    return props.sample?.extra_values?.[ligacao.value] || `[${ligacao.value}]`;
  }
  if (ligacao.value === 'first_name') {
    return (
      props.sample?.first_name ||
      (props.sample?.name || '').split(' ')[0] ||
      t('MODELOS_WHATSAPP.PONTE.PRIMEIRO_NOME')
    );
  }
  return props.sample?.name || t('MODELOS_WHATSAPP.PONTE.NOME_DO_CONTATO');
};

const conteudo = computed(() => {
  const { campos } = paraTemplateDaMeta(props.modelo);
  const exemplos = Object.fromEntries(
    Object.entries(campos).map(([chave, campo]) => [
      campo,
      valorDe(props.bindings[chave]) ||
        t(`MODELOS_WHATSAPP.CAMPOS.${campo}.ROTULO`),
    ])
  );
  return { ...props.modelo.conteudo, exemplos };
});
</script>

<template>
  <aside data-ponte-previa class="flex flex-col gap-2 lg:sticky lg:top-4">
    <p class="mb-0 text-sm font-medium text-center text-n-slate-11">
      {{ $t('MODELOS_WHATSAPP.CELULAR.TITULO') }}
    </p>
    <ModeloCelular :conteudo="conteudo" :remetente="remetente" compacto />
  </aside>
</template>
