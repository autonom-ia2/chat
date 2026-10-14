<script setup>
import { computed, ref, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import FunilSugestao from './FunilSugestao.vue';
import FunilEtapaAcoes from './FunilEtapaAcoes.vue';
import { CORES } from './funil';

// #1384 — uma etapa aberta: o nome, a frase de quando o cliente está nela e a
// cor. Um estado por vez na frase: escrever (ou, vazia, o cartão âmbar com um
// botão), esperar a sugestão, comparar "Como está" e "Como fica". As ações
// automáticas de uma etapa salva são um cartão com "Alterar"; tirar a etapa
// fica no rodapé.
const props = defineProps({
  etapa: { type: Object, required: true },
  ia: { type: Boolean, default: false },
  pronta: { type: Boolean, default: true },
  melhorando: { type: Boolean, default: false },
  sugestao: { type: Object, default: null },
  erro: { type: Boolean, default: false },
  nomesFaltando: { type: Boolean, default: false },
  editando: { type: Boolean, default: false },
});

const emit = defineEmits(['melhorar', 'usar', 'manter', 'mudar', 'acoes']);

// Quem guarda a etapa é a gaveta: aqui só se pede a mudança.
const campo = chave =>
  computed({
    get: () => props.etapa[chave] ?? '',
    set: valor => emit('mudar', { [chave]: valor }),
  });
const nome = campo('name');
const cor = campo('color');
const corLivre = computed(
  () => !CORES.some(opcao => opcao.valor === cor.value)
);

const frase = defineModel('frase', { type: String, default: '' });

const temFrase = computed(() => frase.value.trim() !== '');
// Vazia, mostra o cartão âmbar; "Prefiro escrever" abre o campo.
const escrevendo = ref(false);
watch(
  () => props.etapa,
  () => {
    escrevendo.value = false;
  }
);
const mostraCampo = computed(() => temFrase.value || escrevendo.value);
</script>

<template>
  <div data-funil-etapa class="flex flex-col gap-7">
    <Input
      v-model="nome"
      :label="$t('CRM_FUNIL.ETAPA.NOME')"
      :placeholder="$t('CRM_KANBAN.PIPELINE_DRAWER.STAGE_NAME_PLACEHOLDER')"
      :message="!etapa.name.trim() ? $t('CRM_FUNIL.ETAPA.NOME_FALTA') : ''"
      :message-type="!etapa.name.trim() ? 'error' : 'info'"
      custom-input-class="!h-12 !rounded-xl !bg-n-solid-1 !px-4 !text-base shadow-sm"
    />

    <section v-if="ia" class="flex flex-col gap-3">
      <label for="stage-ai-criteria" class="flex flex-col gap-1">
        <span class="text-lg font-semibold text-n-slate-12">
          {{ $t('CRM_FUNIL.ETAPA.PERGUNTA') }}
        </span>
        <span class="text-[0.9375rem] leading-relaxed text-n-slate-11">
          {{ $t('CRM_FUNIL.ETAPA.PERGUNTA_AJUDA') }}
        </span>
      </label>

      <FunilSugestao
        v-if="sugestao"
        :antes="frase"
        :depois="sugestao.description"
        :nota="sugestao.note || ''"
        @usar="emit('usar')"
        @manter="emit('manter')"
      />

      <template v-else>
        <textarea
          v-show="mostraCampo"
          id="stage-ai-criteria"
          v-model="frase"
          rows="4"
          maxlength="4000"
          :disabled="!pronta || melhorando"
          :placeholder="$t('CRM_FUNIL.ETAPA.EXEMPLO')"
          class="reset-base !mb-0 !h-auto min-h-[7.5rem] w-full rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-3 text-base leading-7 text-n-slate-12 shadow-sm placeholder:text-n-slate-10 focus:outline focus:outline-2 focus:outline-n-brand"
        />
        <div
          v-if="!mostraCampo"
          data-etapa-falta
          class="flex flex-col gap-3 rounded-2xl border border-dashed border-n-amber-8 bg-n-amber-2 p-5"
        >
          <p class="mb-0 flex items-start gap-2 text-base text-n-slate-12">
            <span
              class="i-lucide-triangle-alert mt-1 size-4 shrink-0 text-n-amber-11"
              aria-hidden="true"
            />
            {{ $t('CRM_FUNIL.ETAPAS.FALTA') }}
          </p>
          <div class="flex flex-wrap items-center gap-2">
            <Button
              :label="$t('CRM_FUNIL.ETAPAS.CRIAR_IA')"
              icon="i-lucide-sparkles"
              amber
              faded
              class="!min-h-11"
              :is-loading="melhorando"
              :disabled="!pronta || melhorando || nomesFaltando"
              @click="emit('melhorar')"
            />
            <Button
              :label="$t('CRM_FUNIL.ETAPA.ESCREVER')"
              slate
              ghost
              class="!min-h-11"
              @click="escrevendo = true"
            />
          </div>
        </div>
        <div v-else class="flex flex-wrap items-center gap-3">
          <Button
            :label="$t('CRM_FUNIL.ETAPA.MELHORAR')"
            icon="i-lucide-sparkles"
            blue
            faded
            class="!min-h-11"
            :is-loading="melhorando"
            :disabled="!pronta || melhorando || nomesFaltando || !temFrase"
            @click="emit('melhorar')"
          />
          <span class="text-sm text-n-slate-11">
            {{ $t('CRM_FUNIL.ETAPA.VE_ANTES') }}
          </span>
        </div>
        <p v-if="nomesFaltando" class="mb-0 text-sm text-n-amber-11">
          {{ $t('CRM_FUNIL.ETAPA.NOMES_FALTAM') }}
        </p>
      </template>
      <p v-if="erro" role="alert" class="mb-0 text-sm text-n-ruby-11">
        {{ $t('CRM_KANBAN.PIPELINE_EDITOR.IMPROVE_ERROR') }}
      </p>
    </section>

    <div
      class="flex flex-col gap-3"
      role="group"
      aria-labelledby="stage-color-title"
    >
      <h4
        id="stage-color-title"
        class="mb-0 text-base font-semibold text-n-slate-12"
      >
        {{ $t('CRM_FUNIL.ETAPA.COR') }}
      </h4>
      <div class="flex flex-wrap items-center gap-1 sm:gap-2">
        <button
          v-for="opcaoCor in CORES"
          :key="opcaoCor.valor"
          type="button"
          :aria-pressed="cor === opcaoCor.valor"
          :aria-label="$t(`CRM_KANBAN.PIPELINE_EDITOR.COLORS.${opcaoCor.nome}`)"
          :title="$t(`CRM_KANBAN.PIPELINE_EDITOR.COLORS.${opcaoCor.nome}`)"
          class="grid size-11 shrink-0 place-items-center rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="
            cor === opcaoCor.valor
              ? 'outline outline-2 -outline-offset-2 outline-n-slate-12'
              : ''
          "
          @click="cor = opcaoCor.valor"
        >
          <span
            class="grid size-8 place-items-center rounded-full text-white"
            :class="opcaoCor.amostra"
            aria-hidden="true"
          >
            <span v-if="cor === opcaoCor.valor" class="i-lucide-check size-4" />
          </span>
        </button>
        <!-- Outra cor: mesmo círculo das outras, com o seletor do sistema
             por baixo. Escolhida, a bolinha mostra a cor e o visto. -->
        <label
          data-outra-cor
          :title="$t('CRM_FUNIL.ETAPA.OUTRA_COR')"
          class="relative grid size-11 shrink-0 cursor-pointer place-items-center rounded-full focus-within:outline focus-within:outline-2 focus-within:outline-n-brand"
          :class="
            corLivre
              ? 'outline outline-2 -outline-offset-2 outline-n-slate-12'
              : ''
          "
        >
          <input
            v-model="cor"
            type="color"
            :aria-label="$t('CRM_FUNIL.ETAPA.OUTRA_COR')"
            class="absolute inset-0 size-full cursor-pointer opacity-0"
          />
          <span
            class="pointer-events-none grid size-8 place-items-center rounded-full"
            :class="
              corLivre
                ? 'text-white'
                : 'bg-n-slate-3 text-n-slate-12 ring-1 ring-inset ring-n-slate-7'
            "
            :style="corLivre ? { backgroundColor: cor } : undefined"
            aria-hidden="true"
          >
            <span
              class="size-4"
              :class="corLivre ? 'i-lucide-check' : 'i-lucide-palette'"
            />
          </span>
        </label>
      </div>
    </div>

    <FunilEtapaAcoes
      v-if="editando && etapa.id"
      :etapa-id="etapa.id"
      @alterar="emit('acoes')"
    />
  </div>
</template>
