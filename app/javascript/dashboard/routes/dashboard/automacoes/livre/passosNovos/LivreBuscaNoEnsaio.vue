<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { P } from './passosNovos';
import { buscarNoEnsaio } from './dadosDaConta';
import { fonteEmFrase } from './frasesDosNovos';

// #2934 — no ensaio, o "Buscar em outro sistema" só busca com o OK explícito de
// quem ensaia: o botão, a frase que diz o que vai acontecer e a confirmação. O
// resultado só aparece aqui; nada é gravado na automação.
const props = defineProps({
  passo: { type: Object, required: true },
});

const { t } = useI18n();
const C = `${P}.CONSULTAR`;
// null: ainda não pediu; 'confirmando'; 'buscando'; 'pronto'.
const estado = ref(null);
const dados = ref([]);
const erro = ref('');
const fonte = computed(() => fonteEmFrase(props.passo.fonte, t));

const buscar = async () => {
  estado.value = 'buscando';
  const achou = await buscarNoEnsaio(props.passo);
  erro.value = achou.ok ? '' : achou.error || t(`${C}.TESTE_FALHOU`);
  dados.value = achou.ok ? achou.dados : [];
  estado.value = 'pronto';
};
</script>

<template>
  <div data-busca-no-ensaio class="flex flex-col gap-2">
    <Button
      v-if="!estado"
      data-busca-pedir
      type="button"
      :label="$t(`${C}.BUSCAR_DE_VERDADE`)"
      icon="i-lucide-search"
      slate
      faded
      class="self-start min-h-11"
      @click="estado = 'confirmando'"
    />

    <div
      v-else-if="estado === 'confirmando' || estado === 'buscando'"
      data-busca-confirmar
      role="group"
      :aria-label="$t(`${C}.BUSCAR_DE_VERDADE`)"
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-amber-2 text-n-amber-12"
    >
      <p class="mb-0 text-sm">{{ $t(`${C}.CONFIRMAR_BUSCA`, { fonte }) }}</p>
      <div class="flex flex-wrap gap-2">
        <Button
          data-busca-sim
          type="button"
          :label="$t(`${C}.BUSCAR_AGORA`)"
          icon="i-lucide-search"
          class="min-h-11"
          :is-loading="estado === 'buscando'"
          :disabled="estado === 'buscando'"
          @click="buscar"
        />
        <Button
          type="button"
          :label="$t(`${P}.PEDIDO.VOLTAR`)"
          slate
          link
          class="min-h-11"
          :disabled="estado === 'buscando'"
          @click="estado = null"
        />
      </div>
    </div>

    <p
      v-else-if="erro"
      data-busca-erro
      role="alert"
      class="mb-0 text-sm text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <div v-else data-busca-resultado role="status" class="flex flex-col gap-1">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ $t(`${C}.BUSCOU_NO_ENSAIO`, { fonte }) }}
      </p>
      <ul class="flex flex-col gap-1 m-0 text-sm ps-5 text-n-slate-12">
        <li v-for="dado in dados" :key="dado.nome">
          {{ $t(`${C}.DADO_E_VALOR`, { dado: dado.nome, valor: dado.valor }) }}
        </li>
      </ul>
    </div>
  </div>
</template>
