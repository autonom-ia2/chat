<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import api from '../api/modelosWhatsapp';

// Depois de enviar: o que acontece agora, em três passos, e um botão só. Vindo
// da campanha (?from=campaign&caixa=), o botão volta para ela com o modelo novo
// já escolhido.
const route = useRoute();
const router = useRouter();

const MODOS = ['novo', 'duplicar', 'alterar', 'corrigir'];
const modo = computed(() =>
  MODOS.includes(route.query.modo) ? route.query.modo : 'novo'
);
const ids = computed(() =>
  String(route.query.ids || '')
    .split(',')
    .filter(Boolean)
);
const daCampanha = computed(() => route.query.from === 'campaign');
const semCampanha = computed(() => route.query.semCampanha === '1');

// O que o passo diz: o da campanha, o de formato que ainda não vai em campanha
// ou o de sempre.
const textoDoPasso = chave => {
  if (chave === 'ENVIADO') return 'TEXTO';
  if (chave === 'PRONTO' && semCampanha.value) return 'SEM_CAMPANHA';
  return daCampanha.value ? 'CAMPANHA' : 'TEXTO';
};
const modeloDaCaixa = ref('');

const PASSOS = [
  { chave: 'ENVIADO', icone: 'i-lucide-check', tom: 'bg-n-teal-9 text-white' },
  {
    chave: 'ANALISE',
    icone: 'i-lucide-clock-3',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    chave: 'PRONTO',
    icone: 'i-lucide-circle-check',
    tom: 'bg-n-slate-3 text-n-slate-11',
  },
];

// Com contas diferentes há um modelo por conta: volta com o da conta da caixa.
onMounted(async () => {
  if (!daCampanha.value || !ids.value.length) return;
  const caixa = Number(route.query.caixa);
  try {
    const modelos = await Promise.all(ids.value.map(id => api.obterModelo(id)));
    modeloDaCaixa.value = (
      modelos.find(modelo => modelo.numeros.includes(caixa)) || modelos[0]
    ).id;
  } catch {
    [modeloDaCaixa.value] = ids.value;
  }
});

const seguir = () => {
  if (daCampanha.value) {
    router.push({
      name: 'campaigns_journey_new',
      query: {
        returned: '1',
        modelo: modeloDaCaixa.value || ids.value[0],
        caixa: route.query.caixa,
      },
    });
    return;
  }
  router.push({ name: 'modelos_whatsapp_lista' });
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        data-enviado
        class="flex flex-col items-center w-full gap-8 px-5 pt-12 pb-24 mx-auto text-center max-w-2xl md:py-16"
      >
        <span
          class="grid rounded-full place-items-center size-20 bg-n-teal-3 text-n-teal-11"
        >
          <span class="i-lucide-send size-10" aria-hidden="true" />
        </span>
        <div class="flex flex-col gap-3">
          <h1
            class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
          >
            {{ $t(`MODELOS_WHATSAPP.ENVIADO.TITULO.${modo}`) }}
          </h1>
          <p class="mb-0 text-lg text-n-slate-11">
            {{ $t('MODELOS_WHATSAPP.ENVIADO.SITUACAO') }}
          </p>
          <p v-if="ids.length > 1" class="mb-0 text-base text-n-slate-11">
            {{ $t('MODELOS_WHATSAPP.ENVIADO.POR_CONTA', { n: ids.length }) }}
          </p>
        </div>
        <ol
          class="flex flex-col w-full gap-0 p-0 m-0 list-none text-start rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
        >
          <li
            v-for="passo in PASSOS"
            :key="passo.chave"
            class="flex items-start gap-4 px-5 py-4 border-b border-n-weak last:border-b-0"
          >
            <span
              class="grid rounded-full place-items-center size-9 shrink-0"
              :class="passo.tom"
            >
              <span class="size-5" :class="passo.icone" aria-hidden="true" />
            </span>
            <span class="flex flex-col gap-0.5">
              <span class="text-base font-semibold text-n-slate-12">
                {{
                  $t(`MODELOS_WHATSAPP.ENVIADO.PASSOS.${passo.chave}.TITULO`)
                }}
              </span>
              <span class="text-[0.9375rem] text-n-slate-11">
                {{
                  $t(
                    `MODELOS_WHATSAPP.ENVIADO.PASSOS.${passo.chave}.${textoDoPasso(passo.chave)}`
                  )
                }}
              </span>
            </span>
          </li>
        </ol>
        <Button
          data-ver-modelos
          :label="
            daCampanha
              ? $t('MODELOS_WHATSAPP.ENVIADO.VOLTAR_PARA_CAMPANHA')
              : $t('MODELOS_WHATSAPP.ENVIADO.VER_MODELOS')
          "
          :icon="daCampanha ? 'i-lucide-arrow-left' : ''"
          size="lg"
          class="!min-h-12 !rounded-xl"
          @click="seguir"
        />
      </div>
    </main>
  </section>
</template>
