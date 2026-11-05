<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import Button from 'dashboard/components-next/button/Button.vue';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import { fraseDoPasso } from '../frases';
import { acharPasso } from '../receita';
import { abaixoDoMinimo, dolares } from '../custoDaIa';

// #2498 — "O que aconteceu": cada vez que a automação rodou, com os passos em
// frases e o porquê de cada pulo e falha. A frase sai da receita da versão em
// que a execução entrou; o motivo já vem traduzido da API. Conversa numa caixa
// que a pessoa não vê aparece sem nome e sem link.
const props = defineProps({
  automacaoId: { type: Number, required: true },
  catalogo: { type: Object, required: true },
  accountId: { type: Number, required: true },
});

const { t, locale } = useI18n();
const estado = ref('carregando');
const execucoes = ref([]);
const versoes = ref({});
const pagina = ref(1);
const mais = ref(false);
const aberta = ref(null);

const ESTADO = {
  andando: 'bg-n-blue-3 text-n-blue-11',
  esperando: 'bg-n-blue-3 text-n-blue-11',
  concluida: 'bg-n-teal-3 text-n-teal-11',
  parada: 'bg-n-amber-3 text-n-amber-11',
  interrompida: 'bg-n-amber-3 text-n-amber-11',
  falhou: 'bg-n-ruby-3 text-n-ruby-11',
};

const RESULTADO = {
  ok: { icone: 'i-lucide-check', tom: 'text-n-teal-11', chave: '' },
  pulado: {
    icone: 'i-lucide-skip-forward',
    tom: 'text-n-amber-11',
    chave: 'PULOU',
  },
  falhou: {
    icone: 'i-lucide-circle-x',
    tom: 'text-n-ruby-11',
    chave: 'NAO_FEZ',
  },
};

const RAMO = {
  entao: 'ENTAO',
  senao: 'SENAO',
  se_vencer: 'SE_VENCER',
  nenhum: 'NENHUM',
};

const hora = iso =>
  new Date(iso).toLocaleString(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  });

const custoDaIa = valor =>
  t(
    abaixoDoMinimo(valor)
      ? 'AUTOMACAO_LIVRE.HISTORICO.IA_MENOS_DE'
      : 'AUTOMACAO_LIVRE.HISTORICO.IA',
    { valor: dolares(valor, locale.value) }
  );

const fraseDe = (execucao, passo) => {
  if (passo.passo === 'inicio') return t('AUTOMACAO_LIVRE.HISTORICO.INICIO');
  const receita = versoes.value[execucao.versao_id]?.receita;
  const achado = acharPasso(receita?.passos || [], passo.passo);
  const frase = achado
    ? fraseDoPasso(achado, props.catalogo, t)
    : t('AUTOMACAO_LIVRE.HISTORICO.PASSO_SUMIU');
  const { chave } = RESULTADO[passo.resultado];
  return chave ? t(`AUTOMACAO_LIVRE.HISTORICO.${chave}`, { frase }) : frase;
};

// O caminho do "decidir" pelo nome que tinha na versão que rodou (a pessoa
// pode ter renomeado depois); sem achar, a chave.
const nomeDoCaminho = (execucao, passo) => {
  const receita = versoes.value[execucao.versao_id]?.receita;
  const decidir = acharPasso(receita?.passos || [], passo.passo);
  return (decidir?.caminhos || []).find(
    caminho => caminho.chave === passo.dados.ramo
  )?.nome;
};
const ramoDe = (execucao, passo) => {
  const { ramo } = passo.dados;
  if (RAMO[ramo]) return t(`AUTOMACAO_LIVRE.RAMOS.${RAMO[ramo]}`);
  return nomeDoCaminho(execucao, passo) || ramo;
};

const linkDa = (execucao, mensagemId) => {
  const url = frontendURL(
    conversationUrl({
      accountId: props.accountId,
      id: execucao.alvo.conversa_id,
    })
  );
  return mensagemId ? `${url}?messageId=${mensagemId}` : url;
};

const nomeDa = ({ alvo }) => {
  if (!alvo.visivel) return t('AUTOMACAO_LIVRE.HISTORICO.OCULTA');
  return alvo.nome
    ? t('AUTOMACAO_LIVRE.HISTORICO.CONVERSA_DE', { nome: alvo.nome })
    : t('AUTOMACAO_LIVRE.HISTORICO.CONVERSA_N', { n: alvo.conversa_id });
};

const carregar = async (proxima = 1) => {
  if (proxima === 1) estado.value = 'carregando';
  try {
    const { data } = await AutomacoesAPI.historico(props.automacaoId, proxima);
    // Uma execução que começou entre duas páginas empurra a lista: a que já
    // está na tela não aparece de novo.
    const vistas = new Set(proxima === 1 ? [] : execucoes.value.map(e => e.id));
    execucoes.value = [
      ...(proxima === 1 ? [] : execucoes.value),
      ...data.execucoes.filter(execucao => !vistas.has(execucao.id)),
    ];
    versoes.value = {
      ...(proxima === 1 ? {} : versoes.value),
      ...data.versoes,
    };
    pagina.value = data.pagina;
    mais.value = data.mais;
    if (proxima === 1) aberta.value = data.execucoes[0]?.id ?? null;
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
};

const alternar = id => {
  aberta.value = aberta.value === id ? null : id;
};

watch(
  () => props.automacaoId,
  () => carregar()
);
onMounted(() => carregar());
</script>

<template>
  <section
    data-historico
    class="flex flex-col gap-4 p-6 border rounded-3xl border-n-weak bg-n-solid-1"
    aria-labelledby="titulo-historico"
  >
    <div class="flex flex-col gap-1">
      <h2
        id="titulo-historico"
        class="mb-0 text-lg font-semibold text-n-slate-12"
      >
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.TITULO') }}
      </h2>
      <p class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.SUBTITULO') }}
      </p>
    </div>

    <div
      v-if="estado === 'carregando'"
      data-carregando
      aria-busy="true"
      :aria-label="$t('AUTOMACAO_LIVRE.HISTORICO.CARREGANDO')"
      class="h-24 rounded-2xl bg-n-alpha-2 animate-pulse"
    />

    <div
      v-else-if="estado === 'erro'"
      data-erro
      role="alert"
      class="flex flex-col items-start gap-3"
    >
      <p class="mb-0 text-[0.9375rem] text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.HISTORICO.ERRO') }}
      </p>
      <Button
        :label="$t('AUTOMACAO_LIVRE.LISTA.TENTAR_DE_NOVO')"
        icon="i-lucide-refresh-cw"
        slate
        faded
        class="min-h-11"
        @click="carregar()"
      />
    </div>

    <p
      v-else-if="!execucoes.length"
      data-vazio
      class="mb-0 text-[0.9375rem] text-n-slate-11"
    >
      {{ $t('AUTOMACAO_LIVRE.HISTORICO.VAZIO') }}
    </p>

    <template v-else>
      <ul class="flex flex-col p-0 m-0 list-none divide-y divide-n-weak">
        <li v-for="execucao in execucoes" :key="execucao.id" class="py-1">
          <button
            type="button"
            data-execucao
            :aria-expanded="aberta === execucao.id"
            class="flex flex-wrap items-center w-full py-2 gap-x-3 gap-y-1 text-start min-h-11"
            @click="alternar(execucao.id)"
          >
            <span
              class="transition size-4 text-n-slate-10 i-lucide-chevron-right rtl:rotate-180"
              :class="[aberta === execucao.id ? '!rotate-90' : '']"
              aria-hidden="true"
            />
            <span
              :data-oculta="!execucao.alvo.visivel || undefined"
              :title="
                execucao.alvo.visivel
                  ? undefined
                  : $t('AUTOMACAO_LIVRE.HISTORICO.OCULTA_DICA')
              "
              class="text-[0.9375rem] font-medium"
              :class="
                execucao.alvo.visivel ? 'text-n-slate-12' : 'text-n-slate-11'
              "
            >
              {{ nomeDa(execucao) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ relativeTimeFromISO(execucao.criada_em, locale) }}
            </span>
            <span
              data-estado
              class="px-2.5 py-0.5 text-xs font-semibold rounded-full"
              :class="ESTADO[execucao.estado]"
            >
              {{
                execucao.esperando_ate
                  ? $t('AUTOMACAO_LIVRE.HISTORICO.ESPERANDO_ATE', {
                      quando: hora(execucao.esperando_ate),
                    })
                  : $t(
                      `AUTOMACAO_LIVRE.HISTORICO.ESTADOS.${execucao.estado.toUpperCase()}`
                    )
              }}
            </span>
          </button>
          <div
            v-if="aberta === execucao.id"
            class="flex flex-col gap-3 pb-3 ps-7"
          >
            <ol class="flex flex-col gap-2 p-0 m-0 list-none">
              <li
                v-for="(passo, indice) in execucao.passos"
                :key="indice"
                data-passo
                class="flex items-start gap-2.5"
              >
                <span
                  class="mt-0.5 size-4 shrink-0"
                  :class="[
                    RESULTADO[passo.resultado].icone,
                    RESULTADO[passo.resultado].tom,
                  ]"
                  aria-hidden="true"
                />
                <span class="flex flex-col gap-0.5">
                  <span class="text-[0.9375rem] text-n-slate-12">
                    {{ fraseDe(execucao, passo) }}
                  </span>
                  <span
                    v-if="passo.dados.ramo"
                    data-ramo
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.SEGUIU_POR', {
                        ramo: ramoDe(execucao, passo),
                      })
                    }}
                  </span>
                  <span v-if="passo.dados.ate" class="text-sm text-n-slate-11">
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.ESPERA_ATE', {
                        quando: hora(passo.dados.ate),
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.motivo"
                    data-motivo
                    class="text-sm text-n-slate-11"
                  >
                    {{ passo.motivo }}
                  </span>
                  <span
                    v-if="passo.dados.tentativa"
                    class="text-sm text-n-slate-11"
                  >
                    {{
                      $t('AUTOMACAO_LIVRE.HISTORICO.TENTATIVA', {
                        n: passo.dados.tentativa,
                      })
                    }}
                  </span>
                  <span
                    v-if="passo.dados.ia?.custo_usd != null"
                    data-ia
                    class="text-xs text-n-slate-10"
                  >
                    {{ custoDaIa(passo.dados.ia.custo_usd) }}
                  </span>
                  <a
                    v-if="
                      execucao.alvo.visivel &&
                      (passo.dados.mensagem_id || passo.dados.nota_id)
                    "
                    data-ver-mensagem
                    :href="
                      linkDa(
                        execucao,
                        passo.dados.mensagem_id || passo.dados.nota_id
                      )
                    "
                    class="text-sm font-medium text-n-blue-11 hover:underline"
                  >
                    {{ $t('AUTOMACAO_LIVRE.HISTORICO.VER_MENSAGEM') }}
                  </a>
                </span>
              </li>
            </ol>
            <a
              v-if="execucao.alvo.visivel"
              data-abrir-conversa
              :href="linkDa(execucao)"
              class="self-start text-sm font-medium text-n-blue-11 hover:underline"
            >
              {{ $t('AUTOMACAO_LIVRE.HISTORICO.ABRIR_CONVERSA') }}
            </a>
          </div>
        </li>
      </ul>
      <Button
        v-if="mais"
        data-ver-mais
        :label="$t('AUTOMACAO_LIVRE.HISTORICO.VER_MAIS')"
        slate
        faded
        class="self-start min-h-11"
        @click="carregar(pagina + 1)"
      />
    </template>
  </section>
</template>
