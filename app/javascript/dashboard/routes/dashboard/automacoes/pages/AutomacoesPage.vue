<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import AutomationAPI from 'dashboard/api/automation';
import Button from 'dashboard/components-next/button/Button.vue';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import AutomacaoLinha from '../components/AutomacaoLinha.vue';
import AutomacaoModelos from '../components/AutomacaoModelos.vue';
import { useNomesDaConta } from '../composables/useNomesDaConta';
import { useCriadasPeloGuia } from '../composables/useCriadasPeloGuia';

// #859 — Automações no menu principal. Cada automação aparece como frase em
// português, com o interruptor de ligar e o selo de quem criou. Criar é com o
// Guia (tela "nova"); o formulário antigo continua como modo manual.
const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const podeMudar = useCanManage('automation_manage');
const { nomes, carregarNomes } = useNomesDaConta();
const { criadas, carregarCriadas } = useCriadasPeloGuia();

const estado = ref('carregando');
const automacoes = ref([]);
const mudando = ref(null);

const carregar = async () => {
  estado.value = 'carregando';
  try {
    const { data } = await AutomationAPI.get();
    automacoes.value = [...(data?.payload || [])].sort((a, b) => b.id - a.id);
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

onMounted(() => {
  carregarNomes();
  carregarCriadas();
  carregar();
});

const linhas = computed(() =>
  automacoes.value.map(automacao => ({
    automacao,
    frase: descreverAutomacao(automacao, { t, nomes: nomes.value }).frase,
    criadaPeloGuia: criadas.value.has(automacao.id),
  }))
);

const abrir = automacao =>
  router.push({
    name: 'automacoes_editar',
    params: { accountId: accountId.value, id: automacao.id },
  });

const nova = modelo =>
  router.push({
    name: 'automacoes_nova',
    params: { accountId: accountId.value },
    query: modelo ? { modelo } : {},
  });

const alternar = async automacao => {
  if (!podeMudar.value || mudando.value) return;
  const ligar = !automacao.active;
  mudando.value = automacao.id;
  try {
    await AutomationAPI.update(automacao.id, { active: ligar });
    automacoes.value = automacoes.value.map(item =>
      item.id === automacao.id ? { ...item, active: ligar } : item
    );
    useAlert(
      ligar ? t('AUTOMACOES.LISTA.LIGOU') : t('AUTOMACOES.LISTA.DESLIGOU')
    );
  } catch {
    useAlert(t('AUTOMACOES.LISTA.FALHA_TROCA'));
  } finally {
    mudando.value = null;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="shrink-0 flex flex-wrap items-start justify-between gap-4 px-6 pt-6 pb-4 border-b border-n-weak"
    >
      <div class="min-w-0">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ $t('AUTOMACOES.LISTA.TITULO') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11 max-w-2xl">
          {{ $t('AUTOMACOES.LISTA.SUBTITULO') }}
        </p>
      </div>
      <Button
        v-if="podeMudar"
        data-nova
        :label="$t('AUTOMACOES.LISTA.NOVA')"
        icon="i-lucide-plus"
        class="min-h-11"
        @click="nova()"
      />
    </header>

    <main class="flex-1 overflow-y-auto px-6 py-6">
      <div class="w-full max-w-4xl mx-auto">
        <div
          v-if="estado === 'carregando'"
          data-carregando
          aria-busy="true"
          class="flex flex-col gap-3"
        >
          <span class="sr-only">{{ $t('AUTOMACOES.LISTA.CARREGANDO') }}</span>
          <div
            v-for="indice in 3"
            :key="indice"
            class="h-20 rounded-xl bg-n-alpha-2 animate-pulse"
          />
        </div>

        <div
          v-else-if="estado === 'erro'"
          data-erro
          role="alert"
          class="flex flex-col items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-6"
        >
          <p class="text-sm text-n-slate-12">
            {{ $t('AUTOMACOES.LISTA.ERRO') }}
          </p>
          <Button
            :label="$t('AUTOMACOES.LISTA.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            slate
            faded
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <div
          v-else-if="!linhas.length"
          data-vazio
          class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-6"
        >
          <div>
            <h2 class="text-base font-medium text-n-slate-12">
              {{ $t('AUTOMACOES.LISTA.VAZIO_TITULO') }}
            </h2>
            <p class="mt-1 text-sm text-n-slate-11">
              {{ $t('AUTOMACOES.LISTA.VAZIO_TEXTO') }}
            </p>
          </div>
          <AutomacaoModelos :desabilitado="!podeMudar" @escolher="nova" />
        </div>

        <ul v-else class="flex flex-col gap-3">
          <AutomacaoLinha
            v-for="linha in linhas"
            :key="linha.automacao.id"
            :automacao="linha.automacao"
            :frase="linha.frase"
            :criada-pelo-guia="linha.criadaPeloGuia"
            :pode-mudar="podeMudar"
            :mudando="mudando === linha.automacao.id"
            @abrir="abrir(linha.automacao)"
            @alternar="alternar(linha.automacao)"
          />
        </ul>
      </div>
    </main>
  </section>
</template>
