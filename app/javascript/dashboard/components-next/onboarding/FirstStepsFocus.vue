<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import VideoDoTrajeto from 'dashboard/routes/dashboard/centralDeAjuda/components/VideoDoTrajeto.vue';

// Painel do passo em foco: uma coisa de cada vez, com um único botão forte.
// Ao lado, o vídeo curto do artigo da Central de Ajuda, para quem prefere ver a ler.
const props = defineProps({
  passo: { type: Object, required: true },
  total: { type: Number, required: true },
  ehProximo: { type: Boolean, default: true },
  guiaDisponivel: { type: Boolean, default: false },
  accountId: { type: [Number, String], required: true },
});

const emit = defineEmits(['fazer', 'pular', 'ajuda']);

const { t } = useI18n();

// Um desenho por passo ajuda quem lê pouco a reconhecer o assunto. Passo novo
// sem desenho próprio usa o genérico.
const ICONES = {
  perfil: 'i-lucide-bell-ring',
  chave_ia: 'i-lucide-key-round',
  canal: 'i-lucide-message-circle',
  primeira_resposta: 'i-lucide-reply',
  funil: 'i-lucide-kanban',
  equipe: 'i-lucide-users',
  agente_ia: 'i-lucide-bot',
  campanha: 'i-lucide-megaphone',
  configuracoes: 'i-lucide-sliders-horizontal',
};
const icone = computed(() => ICONES[props.passo.id] || 'i-lucide-footprints');
</script>

<template>
  <article
    class="grid overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm md:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]"
  >
    <div class="flex min-w-0 flex-col gap-4 p-6">
      <span
        class="self-start rounded-full bg-n-brand/10 px-2.5 py-1 text-xs font-semibold text-n-blue-11"
      >
        {{
          ehProximo
            ? t('ONBOARDING_TRAIL.NEXT_STEP')
            : t('ONBOARDING_TRAIL.CHOSEN_STEP')
        }}
        ·
        {{ t('ONBOARDING_TRAIL.STEP_OF', { numero: passo.numero, total }) }}
      </span>

      <div class="flex items-start gap-4">
        <span
          class="grid size-12 shrink-0 place-items-center rounded-xl bg-n-brand text-white"
        >
          <span class="size-6" :class="icone" />
        </span>
        <div class="min-w-0">
          <h2 class="mb-1 text-xl font-semibold text-n-slate-12">
            {{ passo.titulo }}
          </h2>
          <p class="mb-0 text-base text-n-slate-11">{{ passo.por_que }}</p>
        </div>
      </div>

      <p
        v-if="passo.depende_de?.pendente"
        class="mb-0 flex items-start gap-2 rounded-xl bg-n-amber-3 px-3 py-2 text-sm text-n-amber-12"
      >
        <span class="i-lucide-info mt-0.5 size-4 shrink-0" />
        {{
          t('ONBOARDING_TRAIL.WAITS_FOR', { titulo: passo.depende_de.titulo })
        }}
      </p>

      <div
        v-if="passo.pre_requisitos?.length"
        class="flex flex-col gap-1.5 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <p class="mb-0 text-sm font-semibold text-n-slate-12">
          {{ t('ONBOARDING_TRAIL.NEED') }}
        </p>
        <ul class="m-0 flex list-none flex-col gap-1 p-0">
          <li
            v-for="item in passo.pre_requisitos"
            :key="item"
            class="flex items-start gap-2 text-sm text-n-slate-11"
          >
            <span
              class="i-lucide-check mt-0.5 size-4 shrink-0 text-n-teal-11"
            />
            {{ item }}
          </li>
        </ul>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <Button
          lg
          color="blue"
          :label="passo.acao"
          class="max-sm:w-full"
          @click="emit('fazer', passo)"
        />
        <Button
          v-if="guiaDisponivel"
          lg
          color="slate"
          variant="outline"
          icon="i-lucide-life-buoy"
          :label="t('ONBOARDING_TRAIL.HELP')"
          class="max-sm:w-full"
          @click="emit('ajuda')"
        />
        <Button
          v-if="passo.pulavel"
          lg
          color="slate"
          variant="ghost"
          :label="t('ONBOARDING_TRAIL.SKIP')"
          @click="emit('pular', passo)"
        />
      </div>

      <span
        v-if="passo.minutos"
        class="inline-flex items-center gap-1.5 text-sm text-n-slate-10"
      >
        <span class="i-lucide-clock size-4" />
        {{ t('ONBOARDING_TRAIL.TIME', { minutos: passo.minutos }) }}
      </span>
    </div>

    <aside
      class="flex min-w-0 flex-col justify-center gap-3 border-t border-n-weak bg-n-alpha-1 p-6 md:border-l md:border-t-0"
    >
      <VideoDoTrajeto v-if="passo.video" :video="passo.video" />
      <p v-else class="mb-0 text-sm text-n-slate-11">
        {{ t('ONBOARDING_TRAIL.NO_VIDEO') }}
      </p>
      <router-link
        v-if="passo.artigo"
        :to="{
          name: 'central_de_ajuda_artigo',
          params: { accountId, ref: passo.artigo },
        }"
        class="text-sm font-medium text-n-blue-11 underline underline-offset-4"
      >
        {{
          passo.video
            ? t('ONBOARDING_TRAIL.READ_ARTICLE')
            : t('ONBOARDING_TRAIL.OPEN_ARTICLE')
        }}
      </router-link>
    </aside>
  </article>
</template>
