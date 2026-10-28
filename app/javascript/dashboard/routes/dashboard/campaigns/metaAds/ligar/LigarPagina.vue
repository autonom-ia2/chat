<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Passo 3 (#2338): a Página que anuncia e o Instagram ligado a ela, vindos do mesmo login do Facebook. Uma Página:
// a pessoa só confere. Várias: escolhe uma. Nenhuma: entra de novo e marca a Página na janela da Meta.
const props = defineProps({
  pages: { type: Array, required: true },
  escolhida: { type: Object, default: null },
});
const emit = defineEmits(['escolher', 'entrarDeNovo']);

const KEY = 'CRM_KANBAN.META_ADS_HUB.LIGAR.PAGINA';
const escolhaId = ref(props.escolhida?.id || props.pages[0]?.id || null);
const confirmar = () =>
  emit(
    'escolher',
    props.pages.find(page => page.id === escolhaId.value)
  );
</script>

<template>
  <div data-ligar-pagina class="flex flex-col gap-5">
    <template v-if="!pages.length">
      <span class="i-lucide-flag size-8 text-n-amber-11" aria-hidden="true" />
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${KEY}.NONE_TITLE`) }}
      </h3>
      <p class="m-0 text-sm leading-6 text-n-slate-11">
        {{ $t(`${KEY}.NONE_TEXT`) }}
      </p>
      <Button
        data-ligar-pagina-de-novo
        class="self-start !min-h-11"
        icon="i-lucide-facebook"
        :label="$t(`${KEY}.SIGN_IN_AGAIN`)"
        @click="emit('entrarDeNovo')"
      />
    </template>

    <template v-else>
      <div class="flex flex-col gap-2">
        <h3 class="m-0 text-lg font-semibold text-n-slate-12">
          {{
            pages.length > 1 ? $t(`${KEY}.CHOOSE_TITLE`) : $t(`${KEY}.TITLE`)
          }}
        </h3>
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{ pages.length > 1 ? $t(`${KEY}.CHOOSE_TEXT`) : $t(`${KEY}.TEXT`) }}
        </p>
      </div>

      <div
        role="radiogroup"
        :aria-label="$t(`${KEY}.CHOOSE_TITLE`)"
        class="flex flex-col gap-3"
      >
        <button
          v-for="page in pages"
          :key="page.id"
          type="button"
          role="radio"
          :aria-checked="escolhaId === page.id"
          :data-ligar-pagina-opcao="page.id"
          class="flex flex-col gap-3 p-4 text-left border border-solid rounded-xl min-h-11 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            escolhaId === page.id
              ? 'border-n-blue-9 bg-n-blue-2'
              : 'border-n-weak bg-n-solid-1 hover:bg-n-alpha-1'
          "
          @click="escolhaId = page.id"
        >
          <span class="flex items-center gap-3">
            <span
              class="i-ri-facebook-circle-fill size-6 text-[#1877F2]"
              aria-hidden="true"
            />
            <span class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ $t(`${KEY}.PAGE_LABEL`) }}
              </span>
              <span class="text-sm font-semibold text-n-slate-12">
                {{ page.name }}
              </span>
            </span>
          </span>
          <span class="flex items-center gap-3">
            <span
              class="i-ri-instagram-line size-6 text-n-slate-11"
              aria-hidden="true"
            />
            <span class="flex flex-col">
              <span class="text-xs text-n-slate-11">
                {{ $t(`${KEY}.INSTAGRAM_LABEL`) }}
              </span>
              <span
                class="text-sm"
                :class="
                  page.instagram
                    ? 'font-semibold text-n-slate-12'
                    : 'text-n-amber-11'
                "
              >
                {{
                  page.instagram
                    ? `@${page.instagram.username}`
                    : $t(`${KEY}.NO_INSTAGRAM`)
                }}
              </span>
            </span>
          </span>
        </button>
      </div>

      <Button
        data-ligar-pagina-confirmar
        class="self-start !min-h-11"
        :label="$t(`${KEY}.CONFIRM`)"
        @click="confirmar"
      />
      <button
        type="button"
        data-ligar-pagina-de-novo
        class="self-start p-0 text-sm font-medium bg-transparent border-0 rounded-lg min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        @click="emit('entrarDeNovo')"
      >
        {{ $t(`${KEY}.NOT_THIS`) }}
      </button>
    </template>
  </div>
</template>
