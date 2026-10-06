<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomationAPI from 'dashboard/api/automation';
import { descreverAutomacao } from 'dashboard/helper/automacaoEmPortugues';
import { useNomesDaConta } from 'dashboard/routes/dashboard/automacoes/composables/useNomesDaConta';

// O cartão de confirmação de criar ou mudar automação mostra como ela vai
// ficar, na mesma língua do resumo da tela (Quando → Só se → Faz), com o que
// muda marcado. Antes saía a estrutura crua — `{"values" => [3], ...}` (conta
// 16, 05/10/2026). Nada é gravado aqui: só lê a automação atual para comparar.
const props = defineProps({
  // { nome: 'PATCH automation_rules/:id', dados: { caminho, corpo } }
  acao: { type: Object, required: true },
});

const { t } = useI18n();
const { nomes, carregarNomes } = useNomesDaConta();

const id = computed(() => props.acao.dados?.caminho?.id);
const atual = ref(null);
const carregando = ref(Boolean(id.value));

onMounted(async () => {
  carregarNomes();
  if (!id.value) return;
  try {
    const { data } = await AutomationAPI.show(id.value);
    atual.value = data?.payload || null;
  } catch {
    // Sem a atual, a prévia mostra só como vai ficar, sem marcar o que muda.
    atual.value = null;
  } finally {
    carregando.value = false;
  }
});

const corpo = computed(() => {
  const dados = props.acao.dados?.corpo || {};
  return dados.automation_rule || dados;
});

const descrever = regra => descreverAutomacao(regra, { t, nomes: nomes.value });
const antes = computed(() => (atual.value ? descrever(atual.value) : null));
const depois = computed(() =>
  descrever({ ...(atual.value || {}), ...corpo.value })
);

// Cada bloco com as linhas novas e as que saem. Linha igual nos dois lados é
// só lida; a que mudou aparece marcada, e a que sumiu, riscada.
const bloco = (titulo, novas, velhas) => ({
  titulo,
  linhas: novas.map(texto => ({
    texto,
    nova: Boolean(antes.value) && !velhas.includes(texto),
  })),
  saem: velhas.filter(texto => !novas.includes(texto)),
});

const blocos = computed(() => {
  const textos = descricao => ({
    quando: descricao ? [descricao.quando] : [],
    se: descricao ? descricao.se.map(item => item.texto) : [],
    entao: descricao ? descricao.entao : [],
  });
  const novo = textos(depois.value);
  const velho = textos(antes.value);
  return [
    bloco(t('AUTOMACOES.RESUMO.QUANDO'), novo.quando, velho.quando),
    bloco(t('AUTOMACOES.RESUMO.SE'), novo.se, velho.se),
    bloco(t('AUTOMACOES.RESUMO.ENTAO'), novo.entao, velho.entao),
  ].filter(item => item.linhas.length || item.saem.length);
});
</script>

<template>
  <div
    data-previa-automacao
    class="flex flex-col gap-3 p-3 rounded-lg bg-n-solid-1 border border-n-weak"
  >
    <p
      class="mb-0 text-xs font-semibold tracking-wide uppercase text-n-slate-10"
    >
      {{ $t('AUTONOMIA_GUIDE.ACTION.PREVIEW_TITLE') }}
    </p>
    <p v-if="carregando" class="mb-0 text-sm text-n-slate-11">
      {{ $t('AUTONOMIA_GUIDE.ACTION.PREVIEW_LOADING') }}
    </p>
    <template v-else>
      <div
        v-for="item in blocos"
        :key="item.titulo"
        class="flex flex-col gap-1"
      >
        <p class="mb-0 text-xs font-medium text-n-slate-11">
          {{ item.titulo }}
        </p>
        <ul class="flex flex-col gap-1 list-none m-0 p-0">
          <li
            v-for="linha in item.linhas"
            :key="linha.texto"
            class="text-sm break-words text-n-slate-12"
            :class="linha.nova ? 'font-semibold' : ''"
          >
            <span
              v-if="linha.nova"
              data-muda
              class="inline-block me-1.5 px-1.5 rounded text-xs font-medium bg-n-teal-3 text-n-teal-11"
            >
              {{ $t('AUTONOMIA_GUIDE.ACTION.PREVIEW_CHANGES') }}
            </span>
            {{ linha.texto }}
          </li>
          <li
            v-for="texto in item.saem"
            :key="`sai-${texto}`"
            data-sai
            class="text-sm break-words line-through text-n-slate-10"
          >
            {{ texto }}
          </li>
        </ul>
      </div>
    </template>
  </div>
</template>
