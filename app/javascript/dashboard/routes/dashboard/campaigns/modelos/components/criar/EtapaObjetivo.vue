<script setup>
import { computed } from 'vue';
import { FORMATOS, OBJETIVO_EM_BRANCO, OBJETIVOS } from '../../constants';
import { useCanUseIA } from '../../helpers/useCanUseIA';
import FormatoMiniatura from './FormatoMiniatura.vue';

// Começar pronto: as sugestões com texto livre e o "começar do zero".
const emit = defineEmits(['escolher', 'formato', 'ia']);

const grupos = computed(() => [
  { chave: 'SUGESTOES', itens: [...OBJETIVOS, OBJETIVO_EM_BRANCO] },
]);

// Formatos sem backend (catálogo, formulário) ficam fora: nenhum botão sem funcionar.
const formatos = FORMATOS.filter(formato => formato.disponivel !== false);

// "Criar com IA" (#1333): só para quem cria modelo.
const podeUsarIA = useCanUseIA();
</script>

<template>
  <div data-etapa-objetivo class="flex flex-col gap-10">
    <button
      v-if="podeUsarIA"
      type="button"
      data-criar-com-ia-entrada
      class="flex flex-col items-start gap-4 p-6 text-start transition rounded-2xl ring-1 ring-inset ring-n-iris-6 bg-n-iris-2 sm:flex-row sm:items-center hover:ring-n-iris-8 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      @click="emit('ia')"
    >
      <span
        class="grid place-items-center size-12 shrink-0 rounded-2xl bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-sparkles size-6" aria-hidden="true" />
      </span>
      <span class="flex flex-col flex-1 gap-1">
        <span class="text-lg font-semibold text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.IA.CRIAR_COM_IA') }}
        </span>
        <span class="text-[0.9375rem] text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.IA.CRIAR_COM_IA_TEXTO') }}
        </span>
      </span>
      <span
        class="inline-flex items-center gap-1.5 text-sm font-semibold text-n-iris-11"
      >
        {{ $t('MODELOS_WHATSAPP.IA.COMECAR') }}
        <span
          class="i-lucide-arrow-right size-4 rtl:rotate-180"
          aria-hidden="true"
        />
      </span>
    </button>
    <section
      v-for="grupo in grupos"
      :key="grupo.chave"
      class="flex flex-col gap-4"
    >
      <div>
        <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ $t(`MODELOS_WHATSAPP.OBJETIVO.${grupo.chave}.TITULO`) }}
        </h2>
        <p class="mb-0 mt-1 text-base text-n-slate-11">
          {{ $t(`MODELOS_WHATSAPP.OBJETIVO.${grupo.chave}.TEXTO`) }}
        </p>
      </div>
      <ul
        class="grid list-none gap-4 p-0 m-0 grid-cols-[repeat(auto-fill,minmax(min(100%,17rem),1fr))]"
      >
        <li v-for="objetivo in grupo.itens" :key="objetivo.chave" class="flex">
          <button
            type="button"
            :data-objetivo="objetivo.chave"
            class="flex flex-col w-full gap-4 p-5 transition shadow-sm group text-start rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-lg hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="emit('escolher', objetivo.chave)"
          >
            <span class="flex items-center justify-between w-full gap-3">
              <span
                class="grid place-items-center size-12 rounded-2xl"
                :class="objetivo.tom"
              >
                <span
                  class="size-6"
                  :class="objetivo.icone"
                  aria-hidden="true"
                />
              </span>
            </span>
            <span class="flex flex-col gap-1">
              <span class="text-lg font-semibold leading-snug text-n-slate-12">
                {{ $t(`MODELOS_WHATSAPP.OBJETIVOS.${objetivo.chave}.TITULO`) }}
              </span>
              <span class="text-[0.9375rem] leading-relaxed text-n-slate-11">
                {{ $t(`MODELOS_WHATSAPP.OBJETIVOS.${objetivo.chave}.PARA`) }}
              </span>
            </span>
            <span
              class="inline-flex items-center gap-1.5 mt-auto text-sm font-medium text-n-blue-11 opacity-80 group-hover:opacity-100"
            >
              {{
                objetivo.chave === 'em_branco'
                  ? $t('MODELOS_WHATSAPP.OBJETIVO.ESCREVER')
                  : $t('MODELOS_WHATSAPP.OBJETIVO.ESCOLHER')
              }}
              <span
                class="i-lucide-arrow-right size-4 rtl:rotate-180"
                aria-hidden="true"
              />
            </span>
          </button>
        </li>
      </ul>
    </section>
    <section data-formatos class="flex flex-col gap-4">
      <div>
        <h2 class="m-0 text-xl font-semibold tracking-tight text-n-slate-12">
          {{ $t('MODELOS_WHATSAPP.OBJETIVO.FORMATOS.TITULO') }}
        </h2>
        <p class="mb-0 mt-1 text-base text-n-slate-11">
          {{ $t('MODELOS_WHATSAPP.OBJETIVO.FORMATOS.TEXTO') }}
        </p>
      </div>
      <ul
        class="grid list-none gap-4 p-0 m-0 grid-cols-[repeat(auto-fill,minmax(min(100%,13.5rem),1fr))]"
      >
        <li v-for="formato in formatos" :key="formato.chave" class="flex">
          <button
            type="button"
            :data-formato="formato.chave"
            class="flex flex-col w-full gap-3 p-4 transition shadow-sm group text-start rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1 hover:-translate-y-0.5 hover:shadow-lg hover:ring-n-blue-7 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="emit('formato', formato.chave)"
          >
            <FormatoMiniatura :formato="formato.chave" />
            <span class="flex flex-col gap-1">
              <span
                class="flex items-center gap-2 text-base font-semibold text-n-slate-12"
              >
                <span
                  class="size-4"
                  :class="formato.icone"
                  aria-hidden="true"
                />
                {{ $t(`MODELOS_WHATSAPP.FORMATOS.${formato.chave}.TITULO`) }}
              </span>
              <span class="text-sm leading-relaxed text-n-slate-11">
                {{ $t(`MODELOS_WHATSAPP.FORMATOS.${formato.chave}.PARA`) }}
              </span>
            </span>
            <span class="flex flex-wrap gap-1.5 mt-auto">
              <span
                v-if="formato.soDivulgacao"
                class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-amber-3 text-n-amber-11"
              >
                {{ $t('MODELOS_WHATSAPP.OBJETIVO.SO_DIVULGACAO') }}
              </span>
              <!-- #1334: só o código de verificação não vai em campanha. -->
              <span
                v-if="formato.chave === 'codigo'"
                data-nao-vai-em-campanha
                class="px-2 py-0.5 text-xs font-medium rounded-lg bg-n-slate-3 text-n-slate-11"
              >
                {{ $t('MODELOS_WHATSAPP.OBJETIVO.NAO_VAI_EM_CAMPANHA') }}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </section>
  </div>
</template>
