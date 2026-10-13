<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import NovaConversaCartao from './NovaConversaCartao.vue';
import { contatoLegivel, podeCriarContato } from './novaConversa';
import { SINAIS } from './modeloPronto';

// #1459 — "Para quem": um campo grande de busca e os achados como linhas
// clicáveis. Escolhido, vira uma frase com "Alterar".
const props = defineProps({
  contato: { type: Object, default: null },
  termo: { type: String, default: '' },
  resultados: { type: Array, default: () => [] },
  buscando: { type: Boolean, default: false },
  erroNaBusca: { type: Boolean, default: false },
  criando: { type: Boolean, default: false },
  erroAoCriar: { type: Boolean, default: false },
});

defineEmits(['buscar', 'escolher', 'criar', 'alterar']);

const P = 'NOVA_CONVERSA.PARA_QUEM';
const digitou = computed(() => props.termo.trim().length > 1);
const semAchados = computed(
  () => digitou.value && !props.buscando && !props.resultados.length
);
const podeCriar = computed(
  () => semAchados.value && !props.erroNaBusca && podeCriarContato(props.termo)
);
</script>

<template>
  <NovaConversaCartao
    v-if="contato"
    icone="i-lucide-user-round"
    :titulo="$t(`${P}.TITULO`)"
    @alterar="$emit('alterar')"
  >
    <strong class="font-semibold">{{ contato.name }}</strong>
    <template v-if="contatoLegivel(contato)">
      {{ SINAIS.ponto }} {{ contatoLegivel(contato) }}
    </template>
  </NovaConversaCartao>

  <section v-else class="flex flex-col gap-3">
    <label
      for="nova-conversa-busca"
      class="mb-0 text-base font-semibold text-n-slate-12"
    >
      {{ $t(`${P}.TITULO`) }}
    </label>
    <span class="relative flex items-center">
      <span
        class="i-lucide-search pointer-events-none absolute start-4 size-5 text-n-slate-10"
        aria-hidden="true"
      />
      <input
        id="nova-conversa-busca"
        data-foco
        type="search"
        autocomplete="off"
        :value="termo"
        :placeholder="$t(`${P}.CAMPO`)"
        aria-controls="nova-conversa-achados"
        class="reset-base !mb-0 min-h-12 w-full rounded-2xl border border-n-weak bg-n-solid-1 pe-4 ps-12 text-base text-n-slate-12 shadow-sm outline-none transition placeholder:text-n-slate-10 hover:border-n-slate-7 focus:border-n-blue-8 focus:shadow-md"
        @input="$emit('buscar', $event.target.value)"
      />
    </span>

    <div id="nova-conversa-achados" aria-live="polite" class="flex flex-col">
      <p v-if="buscando" class="mb-0 px-1 text-[0.9375rem] text-n-slate-11">
        {{ $t(`${P}.BUSCANDO`) }}
      </p>
      <p
        v-else-if="erroNaBusca"
        role="alert"
        class="mb-0 px-1 text-[0.9375rem] text-n-amber-11"
      >
        {{ $t(`${P}.ERRO`) }}
      </p>
      <ul
        v-else-if="resultados.length"
        class="m-0 flex list-none flex-col gap-2 p-0"
      >
        <li v-for="pessoa in resultados" :key="pessoa.id">
          <button
            type="button"
            data-nova-conversa-achado
            class="flex min-h-14 w-full items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-4 py-2 text-start transition hover:border-n-slate-7 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
            @click="$emit('escolher', pessoa)"
          >
            <Avatar
              :name="pessoa.name || ''"
              :src="pessoa.thumbnail || ''"
              :size="36"
              rounded-full
            />
            <span class="flex min-w-0 flex-1 flex-col">
              <span
                class="truncate text-[0.9375rem] font-semibold text-n-slate-12"
              >
                {{ pessoa.name }}
              </span>
              <span class="truncate text-sm text-n-slate-11">
                {{ contatoLegivel(pessoa) }}
              </span>
            </span>
            <span
              class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10 rtl:rotate-180"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
      <div v-else-if="semAchados" class="flex flex-col items-start gap-3 px-1">
        <p class="mb-0 text-[0.9375rem] text-n-slate-11">
          {{ $t(podeCriar ? `${P}.NADA_CRIAR` : `${P}.NADA`) }}
        </p>
        <Button
          v-if="podeCriar"
          :label="$t(`${P}.CRIAR`, { valor: termo.trim() })"
          icon="i-lucide-user-round-plus"
          slate
          faded
          class="!min-h-11 max-w-full"
          :is-loading="criando"
          :disabled="criando"
          @click="$emit('criar')"
        />
        <p
          v-if="erroAoCriar"
          role="alert"
          class="mb-0 text-[0.9375rem] text-n-amber-11"
        >
          {{ $t(`${P}.ERRO_CRIAR`) }}
        </p>
      </div>
    </div>
  </section>
</template>
