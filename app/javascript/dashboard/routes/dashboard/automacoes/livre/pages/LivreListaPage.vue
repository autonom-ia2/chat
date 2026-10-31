<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import Button from 'dashboard/components-next/button/Button.vue';
import LivreLinha from '../components/LivreLinha.vue';
import LivreConfirmaLigar from '../components/LivreConfirmaLigar.vue';
import { useAutomacoesLivre } from '../prototipo/useAutomacoesLivre';

// #2414 F0 — a lista única de Automações: as novas, as do funil e as do jeito
// antigo, cada uma em frase. Sem nenhuma: uma frase e um botão.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const podeMudar = useCanManage('automation_manage');
const { automacoes, alternar } = useAutomacoesLivre();
const confirma = ref(null);

// `?vazio=1` mostra a lista como numa conta que ainda não tem nenhuma.
const linhas = computed(() =>
  route.query.vazio === '1' ? [] : automacoes.value
);
const ligadas = computed(
  () => linhas.value.filter(automacao => automacao.ativa).length
);
const antigas = computed(
  () => linhas.value.filter(automacao => automacao.jeitoAntigo).length
);

const ir = (name, extra = {}) =>
  router.push({
    name,
    params: { accountId: route.params.accountId },
    ...extra,
  });

const abrir = automacao =>
  ir('automacoes_livre_editar', {
    params: { accountId: route.params.accountId, id: automacao.id },
  });

const aoLigar = automacao => {
  alternar(automacao.id, true);
  useAlert(t('AUTOMACAO_LIVRE.LIGOU'));
};

const aoAlternar = automacao => {
  if (!podeMudar.value) return;
  if (automacao.ativa) {
    alternar(automacao.id, false);
    useAlert(t('AUTOMACAO_LIVRE.DESLIGOU'));
    return;
  }
  confirma.value?.pedir(automacao.versao.receita, automacao);
};
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-surface-1">
    <div
      class="flex flex-col w-full max-w-6xl gap-8 px-5 py-8 pb-40 mx-auto md:px-8 md:py-10"
    >
      <div
        v-if="!linhas.length"
        data-vazio
        class="flex flex-col items-center gap-5 px-6 py-16 text-center border rounded-3xl border-n-weak bg-n-solid-1"
      >
        <span
          class="grid text-white place-items-center size-16 rounded-2xl bg-n-heroi dark:bg-n-heroi-escuro"
        >
          <span class="i-lucide-zap size-8" aria-hidden="true" />
        </span>
        <p class="max-w-md mb-0 text-xl font-semibold text-n-slate-12">
          {{ $t('AUTOMACAO_LIVRE.LISTA.VAZIO') }}
        </p>
        <Button
          data-comecar
          :label="$t('AUTOMACAO_LIVRE.LISTA.COMECAR')"
          icon="i-lucide-plus"
          size="lg"
          class="!min-h-12 !rounded-xl"
          :disabled="!podeMudar"
          @click="ir('automacoes_livre_comecar')"
        />
      </div>

      <template v-else>
        <header class="flex flex-wrap items-end justify-between gap-5">
          <div class="min-w-0">
            <h1
              class="text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
            >
              {{ $t('AUTOMACAO_LIVRE.LISTA.TITULO') }}
            </h1>
            <p class="mt-2 mb-0 text-base md:text-lg text-n-slate-11">
              {{ $t('AUTOMACAO_LIVRE.LISTA.SUBTITULO') }}
            </p>
          </div>
          <Button
            v-if="podeMudar"
            data-nova
            :label="$t('AUTOMACAO_LIVRE.LISTA.NOVA')"
            icon="i-lucide-plus"
            size="lg"
            class="!min-h-12 !rounded-xl"
            @click="ir('automacoes_livre_comecar')"
          />
        </header>

        <div class="flex flex-wrap gap-3">
          <span
            class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <span
              class="rounded-full size-2.5 bg-n-teal-9"
              aria-hidden="true"
            />
            {{ $t('AUTOMACAO_LIVRE.LISTA.LIGADAS', { n: ligadas }, ligadas) }}
          </span>
          <span
            v-if="antigas"
            class="inline-flex items-center gap-2.5 px-4 py-2.5 text-[0.9375rem] border rounded-xl border-n-amber-6 bg-n-amber-2 text-n-slate-12"
          >
            <span
              class="i-lucide-history size-4 text-n-amber-11"
              aria-hidden="true"
            />
            {{ $t('AUTOMACAO_LIVRE.LISTA.ANTIGAS', { n: antigas }, antigas) }}
          </span>
        </div>

        <ul class="flex flex-col gap-3.5 p-0 m-0 list-none">
          <LivreLinha
            v-for="automacao in linhas"
            :key="automacao.id"
            :automacao="automacao"
            :pode-mudar="podeMudar"
            @abrir="abrir(automacao)"
            @alternar="aoAlternar(automacao)"
          />
        </ul>
      </template>
    </div>
    <LivreConfirmaLigar ref="confirma" @ligar="aoLigar" />
  </main>
</template>
