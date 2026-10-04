<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useOnboardingTrail } from 'dashboard/composables/useOnboardingTrail';
import Button from 'dashboard/components-next/button/Button.vue';
import { idsVisiveis, refDoArtigo } from '../helpers/atalhos';

// O próximo passo da trilha de Primeiros passos, com o mesmo dado daquela tela. Some quando a trilha
// está completa, não carregou ou deu erro: a Central continua inteira sem ele.
const props = defineProps({
  capitulos: { type: Array, required: true },
});

const { t } = useI18n();
const router = useRouter();
const { isAdmin } = useAdmin();
const { carregando, erro, passos, resolvidos, total, percentual, carregar } =
  useOnboardingTrail();

// A trilha filtra os passos só pelo papel; a Central esconde também o artigo cujo recurso a conta não
// tem. Fica o primeiro passo pendente cujo artigo veio para a conta, senão o botão daria em "não
// encontrado".
const passo = computed(() => {
  const ids = idsVisiveis(props.capitulos);
  return (
    passos.value.find(
      item => item.status === 'pendente' && ids.has(item.artigo)
    ) || null
  );
});
const visivel = computed(
  () => !carregando.value && !erro.value && Boolean(passo.value)
);
const rotaDoArtigo = computed(() => ({
  name: 'central_de_ajuda_artigo',
  params: { ref: refDoArtigo(passo.value.artigo) },
}));
const poster = computed(() => passo.value?.video?.poster);

const abrirArtigo = () => router.push(rotaDoArtigo.value);

onMounted(carregar);
</script>

<template>
  <section
    v-if="visivel"
    class="flex min-w-0 flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm lg:flex-[3]"
    aria-labelledby="central-continue"
  >
    <h2
      id="central-continue"
      class="mb-0 self-start rounded-full bg-n-brand/10 px-2.5 py-1 text-xs font-semibold text-n-blue-11"
    >
      {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.TITULO') }}
    </h2>

    <div class="flex flex-col gap-5 sm:flex-row">
      <div class="flex min-w-0 flex-1 flex-col gap-3">
        <p class="mb-0 text-xl font-semibold text-n-slate-12">
          {{ passo.titulo }}
        </p>
        <p v-if="passo.por_que" class="mb-0 text-base text-n-slate-11">
          {{ passo.por_que }}
        </p>

        <div class="flex items-center gap-3">
          <!-- Barra em SVG: a largura vai no atributo, sem estilo inline nem classe montada na hora. -->
          <svg
            viewBox="0 0 100 4"
            preserveAspectRatio="none"
            class="h-2 min-w-0 flex-1 overflow-hidden rounded-full"
            role="progressbar"
            :aria-valuenow="resolvidos"
            aria-valuemin="0"
            :aria-valuemax="total"
            :aria-label="t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.PROGRESSO')"
          >
            <rect width="100" height="4" class="fill-n-alpha-2" />
            <rect :width="percentual" height="4" class="fill-n-brand" />
          </svg>
          <span class="shrink-0 text-sm text-n-slate-11">
            {{
              t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.X_DE_Y', {
                feitos: resolvidos,
                total,
              })
            }}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <Button
            v-if="passo.video"
            size="lg"
            color="blue"
            icon="i-lucide-play"
            class="min-h-11 max-sm:w-full"
            :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.ASSISTIR')"
            @click="abrirArtigo"
          />
          <Button
            size="lg"
            :color="passo.video ? 'slate' : 'blue'"
            :variant="passo.video ? 'outline' : null"
            icon="i-lucide-book-open"
            class="min-h-11 max-sm:w-full"
            :label="t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.LER')"
            @click="abrirArtigo"
          />
        </div>

        <router-link
          v-if="isAdmin"
          :to="{ name: 'first_steps' }"
          class="inline-flex min-h-11 items-center gap-1 self-start text-base font-medium text-n-blue-11 underline underline-offset-4 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.VER_TODOS') }}
          <span
            class="i-lucide-chevron-right size-4 rtl:rotate-180"
            aria-hidden="true"
          />
        </router-link>
      </div>

      <router-link
        v-if="poster"
        :to="rotaDoArtigo"
        class="group relative block shrink-0 self-start overflow-hidden rounded-xl border border-n-weak bg-n-slate-3 sm:w-56 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="
          t('HELP_CENTER.CENTRAL_DE_AJUDA.CONTINUE.ASSISTIR_VIDEO', {
            titulo: passo.titulo,
          })
        "
      >
        <img
          :src="poster"
          alt=""
          class="block aspect-video w-full object-cover"
        />
        <span
          class="absolute inset-0 grid place-items-center bg-n-alpha-black1 group-hover:bg-n-alpha-black2"
          aria-hidden="true"
        >
          <span
            class="grid size-12 place-items-center rounded-full bg-n-brand text-white shadow-sm"
          >
            <span class="i-lucide-play size-6" />
          </span>
        </span>
      </router-link>
    </div>
  </section>
</template>
