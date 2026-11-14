<script setup>
import { computed, nextTick, reactive, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  TIPOS_DE_SEGURO,
  chaveDoTipo,
} from '../../../../carteira/tiposDeSeguro';

// #2899 (E6.4) — um PDF do lote no Conferir. Diz o que aconteceu com ele (não
// é apólice, não deu para ler, deixado de fora, não entrou) e, no PDF lido, o
// que falta para o seguro entrar (a pessoa escreve) e o que foi achado sem
// certeza (o telefone, o e-mail, o valor): só vale se a pessoa disser que é do
// cliente. "Não, não é do cliente" tira o dado do seguro e da ficha.
// "Salvar o que escrevi" está sempre ligado: com campo faltando, marca o campo
// (aria-invalid), diz o que falta e leva o foco ao primeiro.
//   item: { id, posicao, estado, nome, seguradora, numero, faltam, confira }
const props = defineProps({
  item: { type: Object, required: true },
  ocupado: { type: Boolean, default: false },
});
const emit = defineEmits(['mudar']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PDFS.ITEM.${chave}`, valores);
const id = useId();
const escritos = reactive({ tipo: '', seguradora: '', termina: '', nome: '' });
const raiz = useTemplateRef('raiz');
// Os campos que a pessoa tentou salvar sem escrever.
const tentados = ref([]);

const lido = computed(() => props.item.estado === 'lido');
const opcoesDeTipo = computed(() =>
  TIPOS_DE_SEGURO.map(tipo => ({ value: tipo, label: t(chaveDoTipo(tipo)) }))
);
const titulo = computed(() =>
  [props.item.nome, props.item.seguradora, props.item.numero]
    .filter(Boolean)
    .join(' · ')
);
const vazio = campo => !String(escritos[campo] || '').trim();
// Some da lista no instante em que a pessoa escreve o campo.
const faltando = computed(() => tentados.value.filter(vazio));

const salvar = async () => {
  const vazios = props.item.faltam.filter(vazio);
  if (vazios.length) {
    tentados.value = vazios;
    await nextTick();
    raiz.value?.querySelector(`[id="${id}-${vazios[0]}"]`)?.focus();
    return;
  }
  tentados.value = [];
  const campos = Object.fromEntries(
    props.item.faltam.map(campo => [campo, String(escritos[campo]).trim()])
  );
  emit('mudar', { campos });
};
</script>

<template>
  <li
    ref="raiz"
    :data-item-do-pdf="item.posicao"
    class="flex flex-col gap-3 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
  >
    <p class="m-0 text-base font-semibold text-n-slate-12">
      {{ tp('TITULO', { posicao: item.posicao }) }}
      <span v-if="titulo" class="block font-normal text-n-slate-11">
        {{ titulo }}
      </span>
    </p>
    <p
      v-if="!lido"
      data-carteira="estado-do-pdf"
      class="m-0 text-base text-n-slate-11"
    >
      {{ tp(`ESTADO.${item.estado.toUpperCase()}`) }}
    </p>

    <form
      v-if="lido && item.faltam.length"
      class="flex flex-col gap-3"
      @submit.prevent="salvar"
    >
      <p class="m-0 text-sm text-n-slate-11">{{ tp('FALTAM') }}</p>
      <div
        v-for="campo in item.faltam"
        :key="campo"
        class="flex flex-col gap-1"
      >
        <label
          :for="`${id}-${campo}`"
          class="text-sm font-medium text-n-slate-12"
        >
          {{ tp(`CAMPOS.${campo.toUpperCase()}`) }}
        </label>
        <ChoiceSelect
          v-if="campo === 'tipo'"
          v-model="escritos.tipo"
          :options="opcoesDeTipo"
          :aria-label="tp(`CAMPOS.${campo.toUpperCase()}`)"
          :trigger-id="`${id}-${campo}`"
          :invalid="faltando.includes(campo)"
          :described-by="
            faltando.includes(campo) ? `${id}-${campo}-falta` : undefined
          "
        />
        <input
          v-else
          :id="`${id}-${campo}`"
          v-model="escritos[campo]"
          :type="campo === 'termina' ? 'date' : 'text'"
          maxlength="200"
          :aria-invalid="faltando.includes(campo)"
          :aria-describedby="
            faltando.includes(campo) ? `${id}-${campo}-falta` : undefined
          "
          class="px-3 text-base border rounded-xl min-h-11 bg-n-solid-2 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            faltando.includes(campo) ? 'border-n-ruby-9' : 'border-n-weak'
          "
        />
        <p
          v-if="faltando.includes(campo)"
          :id="`${id}-${campo}-falta`"
          role="alert"
          data-carteira="falta-campo"
          class="m-0 text-sm text-n-ruby-11"
        >
          {{ tp(`FALTA_CAMPO.${campo.toUpperCase()}`) }}
        </p>
      </div>
      <Button
        size="lg"
        type="submit"
        class="self-start"
        :disabled="ocupado"
        :label="tp('SALVAR')"
      />
    </form>

    <ul
      v-if="lido && item.confira.length"
      class="flex flex-col gap-3 p-0 m-0 list-none"
    >
      <li
        v-for="dado in item.confira"
        :key="dado.campo"
        :data-confira="dado.campo"
        class="flex flex-col gap-2"
      >
        <p class="m-0 text-base text-n-slate-12">
          {{ tp(`CONFIRA.${dado.campo.toUpperCase()}`, { valor: dado.valor }) }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            slate
            faded
            size="lg"
            type="button"
            :disabled="ocupado"
            :label="tp('CONFIRA.E_DO_CLIENTE')"
            @click="emit('mudar', { confirmar: [dado.campo] })"
          />
          <Button
            slate
            faded
            size="lg"
            type="button"
            :disabled="ocupado"
            :label="tp('CONFIRA.NAO_E_DO_CLIENTE')"
            @click="emit('mudar', { recusar: [dado.campo] })"
          />
        </div>
      </li>
    </ul>

    <button
      v-if="lido || item.estado === 'fora'"
      type="button"
      :data-carteira="lido ? 'deixar-de-fora' : 'trazer-de-volta'"
      :disabled="ocupado"
      class="self-start p-0 text-sm underline bg-transparent border-0 rounded-lg min-h-11 text-n-slate-11 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('mudar', { fora: lido })"
    >
      {{ tp(lido ? 'DEIXAR_DE_FORA' : 'TRAZER_DE_VOLTA') }}
    </button>
  </li>
</template>
