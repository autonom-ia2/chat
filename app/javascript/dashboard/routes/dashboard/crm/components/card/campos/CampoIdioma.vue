<script setup>
import { computed, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import {
  IDIOMAS_MAIS_USADOS,
  IDIOMAS_WHATSAPP,
  nomeDoIdioma,
  paraBcp47,
} from './idiomasWhatsApp';

// #1423 (RT-10) — o idioma da mensagem pronta. A lista traz todos os idiomas
// que o WhatsApp aceita, pelo nome ("Português (Brasil)"); o valor guardado é
// o código (pt_BR). "Outro idioma" abre um campo para qualquer código, como a
// gaveta antiga deixava. Um valor que não está na lista já abre nesse campo:
// o valor atual sempre aparece.
defineProps({
  rotulo: { type: String, required: true },
});
const idioma = defineModel({ type: String, default: 'pt_BR' });

const OUTRO = '__outro__';
const { t, locale } = useI18n();
const campoId = useId();
const N = 'CRM_CARD.RETORNO.IDIOMA';

const naLista = codigo => IDIOMAS_WHATSAPP.includes(codigo);
const outro = ref(Boolean(idioma.value) && !naLista(idioma.value));
// Quem preenche de fora (a mensagem pronta da caixa oficial) volta para a lista.
watch(idioma, codigo => {
  if (codigo && !naLista(codigo)) outro.value = true;
});

const opcao = codigo => ({
  value: codigo,
  label: nomeDoIdioma(codigo, locale.value) || codigo,
});
const grupos = computed(() => {
  const todos = IDIOMAS_WHATSAPP.filter(
    codigo => !IDIOMAS_MAIS_USADOS.includes(codigo)
  )
    .map(opcao)
    .sort((a, b) => a.label.localeCompare(b.label, paraBcp47(locale.value)));
  return [
    { label: t(`${N}.MAIS_USADOS`), options: IDIOMAS_MAIS_USADOS.map(opcao) },
    { label: t(`${N}.TODOS`), options: todos },
    {
      label: t(`${N}.NAO_ACHOU`),
      options: [{ value: OUTRO, label: t(`${N}.OUTRO`) }],
    },
  ];
});

const escolha = computed({
  get: () => (outro.value ? OUTRO : idioma.value),
  set: valor => {
    if (valor === OUTRO) {
      outro.value = true;
      return;
    }
    outro.value = false;
    idioma.value = valor;
  },
});

// No campo livre, o nome confirma o código digitado.
const nomeDigitado = computed(() => nomeDoIdioma(idioma.value, locale.value));
</script>

<template>
  <div class="flex flex-col gap-3" data-campo-idioma>
    <div class="flex flex-col gap-1">
      <label :for="campoId" class="mb-0 text-sm font-medium text-n-slate-12">
        {{ rotulo }}
      </label>
      <ChoiceSelect
        v-model="escolha"
        :trigger-id="campoId"
        :groups="grupos"
        :aria-label="rotulo"
        class="w-full"
      />
    </div>
    <Input
      v-if="outro"
      v-model="idioma"
      data-campo-idioma-outro
      :label="t(`${N}.CODIGO`)"
      :placeholder="t(`${N}.CODIGO_EXEMPLO`)"
      :message="
        nomeDigitado
          ? t(`${N}.CODIGO_NOME`, { nome: nomeDigitado })
          : t(`${N}.CODIGO_DICA`)
      "
    />
  </div>
</template>
