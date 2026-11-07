<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SeloDaFonte from './SeloDaFonte.vue';
import logoChatgpt from 'dashboard/assets/images/ia-da-conta/chatgpt-logo-white.svg';

// #2472: o login ChatGPT. Botão e textos seguem as diretrizes da OpenAI
// (developers.openai.com/siwc/ui-ux-guidelines): "Continuar com ChatGPT",
// logo branco e "Ver meu uso" levando para as configurações do ChatGPT.
const props = defineProps({
  fonte: { type: Object, default: null },
  disponivel: { type: Boolean, default: true },
});

const emit = defineEmits(['entrar', 'desconectar']);

const USO_DO_CHATGPT = 'https://chatgpt.com/settings/usage';

const desconectado = computed(() => props.fonte?.status === 'desconectado');
</script>

<template>
  <article
    data-cartao-chatgpt
    class="flex flex-col gap-5 p-6 rounded-3xl bg-n-solid-1 ring-1 ring-inset ring-n-weak md:p-8"
  >
    <div class="flex items-start gap-4">
      <span
        class="grid rounded-2xl place-items-center size-12 shrink-0 bg-n-slate-12"
      >
        <img :src="logoChatgpt" alt="" class="size-6 dark:invert" />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <h2 class="text-xl font-semibold text-n-slate-12">
          {{ $t('IA_DA_CONTA.CHATGPT.TITULO') }}
        </h2>
        <p class="mb-0 text-base text-n-slate-11">
          {{ $t('IA_DA_CONTA.CHATGPT.TEXTO') }}
        </p>
      </div>
    </div>

    <template v-if="fonte">
      <div class="flex flex-wrap items-center gap-3">
        <SeloDaFonte :status="fonte.status" />
        <span v-if="!desconectado" class="text-sm text-n-slate-11">
          {{ $t('IA_DA_CONTA.CHATGPT.CONECTADO_COMO', { email: fonte.email }) }}
        </span>
      </div>
      <div class="flex flex-wrap gap-3 mt-auto">
        <Button
          v-if="desconectado"
          data-entrar-de-novo
          :label="$t('IA_DA_CONTA.CHATGPT.ENTRAR_DE_NOVO')"
          size="lg"
          @click="emit('entrar')"
        />
        <a
          v-else
          data-ver-uso
          :href="USO_DO_CHATGPT"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-2 px-4 text-sm font-medium rounded-xl min-h-11 bg-n-slate-12 text-n-slate-1 hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ $t('IA_DA_CONTA.CHATGPT.VER_USO') }}
          <span class="i-lucide-external-link size-4" aria-hidden="true" />
        </a>
        <Button
          v-if="!desconectado"
          data-desconectar
          :label="$t('IA_DA_CONTA.CHATGPT.DESCONECTAR')"
          variant="ghost"
          color="slate"
          size="lg"
          @click="emit('desconectar')"
        />
      </div>
    </template>

    <template v-else>
      <button
        type="button"
        data-oai-siwc-button
        data-continuar-chatgpt
        :disabled="!disponivel"
        class="inline-flex items-center justify-center gap-3 px-5 mt-auto text-base font-semibold text-white bg-[#000000] rounded-full min-h-12 hover:bg-[#2f2f2f] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-40"
        @click="emit('entrar')"
      >
        <img :src="logoChatgpt" alt="" class="size-5" />
        {{ $t('IA_DA_CONTA.CHATGPT.BOTAO') }}
      </button>
      <p v-if="disponivel" class="mb-0 text-sm text-n-slate-11">
        {{ $t('IA_DA_CONTA.CHATGPT.AVISO_DADOS') }}
      </p>
      <p v-else data-em-breve class="mb-0 text-sm font-medium text-n-slate-11">
        {{ $t('IA_DA_CONTA.CHATGPT.EM_BREVE') }}
      </p>
    </template>
  </article>
</template>
