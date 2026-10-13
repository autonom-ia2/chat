<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import AgenteErro from '../../AgenteErro.vue';
import EscolhaRadio from '../../EscolhaRadio.vue';
import FerramentaCampo from './FerramentaCampo.vue';
import FerramentaEntrada from './FerramentaEntrada.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import {
  PASSOS,
  hostDoEndereco,
  paraRascunho,
} from '../../../utils/ferramentas';
import {
  lerResposta,
  montarChamada,
  passoDaCorrecao,
  traduzirErroDoTeste,
  valorParaTeste,
} from '../../../utils/testeDaFerramenta';
import TesteChamada from './TesteChamada.vue';
import TesteResposta from './TesteResposta.vue';

// #1301 (protótipos F07, F07-ok e F07-falha) — chamada de teste de verdade (POST /tools/:id/test)
// com os valores digitados. A prévia mostra o que o backend monta (Liquid sem codificar). Deu
// certo: "O que o agente recebe" e, se a ferramenta está desligada, "Ligar ferramenta" (PATCH
// enabled:true). Falhou: o erro traduzido, com o texto original em "Detalhe", e o caminho para
// corrigir. Status e tempo da chamada exigem backend e não aparecem.
const props = defineProps({
  ferramenta: { type: Object, required: true },
  precisaTestar: { type: Boolean, default: false },
  rodape: { type: String, required: true },
  testar: { type: Function, required: true },
  ligar: { type: Function, required: true },
});

const emit = defineEmits(['ligada', 'agoraNao', 'corrigir', 'voltar']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS.TESTE';
const { t } = useI18n();
const base = `teste-${useId()}`;

const rascunho = computed(() => paraRascunho(props.ferramenta));
const informacoes = computed(() => rascunho.value.informacoes);
const valores = ref({});
const errosValores = ref({});
const testando = ref(false);
const resultado = ref(null);
const ligando = ref(false);
const erroAoLigar = ref(false);
const cartaoFalha = ref(null);

const chamada = computed(() => montarChamada(rascunho.value, valores.value));
const feito = computed(() => Boolean(resultado.value) && !testando.value);
const falha = computed(() =>
  resultado.value?.ok ? null : resultado.value?.erro
);
const passoDaFalha = computed(() =>
  falha.value?.corrigir ? passoDaCorrecao(falha.value.corrigir) : null
);
const nomeDaParte = passo =>
  t(`AGENTS.JORNADA.PAGINA.FERRAMENTAS.PASSOS.NOMES.${PASSOS[passo - 1]}`);

const opcoesSimNao = computed(() => [
  { valor: 'true', titulo: t(`${NS}.SIM`) },
  { valor: 'false', titulo: t(`${NS}.NAO`) },
]);
const MODO_DO_TECLADO = { integer: 'numeric', number: 'decimal' };

const mudarValor = (nome, valor) => {
  valores.value = { ...valores.value, [nome]: valor };
};

const preenchido = valor => String(valor ?? '').trim() !== '';

const conferirValores = () => {
  const erros = Object.fromEntries(
    informacoes.value
      .filter(i => !i.podeFaltar && !preenchido(valores.value[i.nome]))
      .map(i => [i.nome, 'PREENCHA'])
  );
  errosValores.value = erros;
  const primeiro = informacoes.value.findIndex(i => erros[i.nome]);
  if (primeiro >= 0) {
    // Sim/não é um grupo de rádio: o foco vai para a primeira opção.
    nextTick(() => {
      const campo = document.getElementById(`${base}-valor-${primeiro}`);
      const alvo = campo?.querySelector('[role="radio"]') || campo;
      alvo?.focus();
    });
    return false;
  }
  return true;
};

// Vazio que pode faltar vai como null, como o agente manda no atendimento; vírgula vira ponto.
const parametros = () =>
  Object.fromEntries(
    informacoes.value.map(i => [
      i.nome,
      valorParaTeste(i.tipo, valores.value[i.nome]),
    ])
  );

const rodar = async () => {
  if (testando.value || !conferirValores()) return;
  testando.value = true;
  resultado.value = null;
  erroAoLigar.value = false;
  try {
    const dados = await props.testar(props.ferramenta.id, parametros());
    resultado.value = {
      ok: true,
      resposta: lerResposta(dados?.body, dados?.cortada),
    };
  } catch (erro) {
    // Só o texto da API vira "Detalhe" (o que o agente recebe, #1425); sem rede não há detalhe real.
    const mensagem = erro?.motivo?.mensagem || '';
    const agenteRecebe = erro?.motivo?.agenteRecebe || '';
    resultado.value = {
      ok: false,
      erro: traduzirErroDoTeste(mensagem, agenteRecebe),
    };
  } finally {
    testando.value = false;
  }
  await nextTick();
  if (resultado.value && !resultado.value.ok) cartaoFalha.value?.focus();
};

const outrosValores = async () => {
  resultado.value = null;
  await nextTick();
  document.getElementById(`${base}-valor-0`)?.focus();
};

const ligarAgora = async () => {
  if (ligando.value) return;
  ligando.value = true;
  erroAoLigar.value = false;
  try {
    const ligada = await props.ligar(props.ferramenta.id);
    emit('ligada', ligada);
  } catch {
    erroAoLigar.value = true;
  } finally {
    ligando.value = false;
  }
};

const garantia = computed(() =>
  props.ferramenta.enabled
    ? t(`${NS}.CONTINUA_LIGADA`)
    : t(`${NS}.CONTINUA_DESLIGADA`)
);
const textoDaFalha = computed(() => {
  if (!falha.value) return '';
  const partes = [
    falha.value.chave === 'URL_INVALIDA'
      ? t(`${NS}.ERROS.URL_INVALIDA_POR_QUE`)
      : '',
    garantia.value,
    passoDaFalha.value
      ? t(`${NS}.CORRIJA_EM`, { parte: nomeDaParte(passoDaFalha.value) })
      : '',
  ];
  return partes.filter(Boolean).join(' ');
});
const avisoDeEspaco = computed(() =>
  chamada.value.ruim
    ? t(`${NS}.ESPACO`, {
        codificada: `{{ ${chamada.value.ruim} | url_encode }}`,
      })
    : ''
);
const resumoDaChamada = computed(
  () =>
    `${chamada.value.metodo} ${hostDoEndereco(props.ferramenta.endpoint_url)}`
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <FerramentaFaixa
      v-if="precisaTestar && !feito"
      data-precisa-testar
      tom="azul"
    >
      <p class="m-0">{{ t(`${NS}.PRECISA`) }}</p>
    </FerramentaFaixa>
    <FerramentaFaixa v-if="!feito" data-chamada-real tom="ambar">
      <p class="m-0">{{ t(`${NS}.REAL`) }}</p>
    </FerramentaFaixa>

    <div v-if="informacoes.length" class="flex flex-col gap-4">
      <template
        v-for="(informacao, indice) in informacoes"
        :key="informacao.nome"
      >
        <div v-if="informacao.tipo === 'boolean'" class="flex flex-col gap-1.5">
          <p class="m-0 font-mono text-sm font-semibold text-n-slate-12">
            {{ informacao.nome }}
          </p>
          <p v-if="informacao.descricao" class="m-0 text-sm text-n-slate-11">
            {{ informacao.descricao }}
          </p>
          <EscolhaRadio
            :id="`${base}-valor-${indice}`"
            :rotulo="informacao.nome"
            :opcoes="opcoesSimNao"
            :model-value="valores[informacao.nome] ?? null"
            :aria-describedby="
              errosValores[informacao.nome]
                ? `${base}-valor-${indice}-erro`
                : undefined
            "
            @update:model-value="mudarValor(informacao.nome, $event)"
          />
          <p
            v-if="errosValores[informacao.nome]"
            :id="`${base}-valor-${indice}-erro`"
            class="m-0 text-sm font-medium text-n-ruby-11"
          >
            {{ t(`${NS}.PREENCHA`) }}
          </p>
        </div>
        <FerramentaCampo
          v-else
          :id="`${base}-valor-${indice}`"
          :rotulo="informacao.nome"
          :opcional="informacao.podeFaltar"
          :erro="errosValores[informacao.nome] ? t(`${NS}.PREENCHA`) : ''"
          :ajuda="informacao.descricao"
        >
          <template #default="{ descricao, invalido }">
            <FerramentaEntrada
              :id="`${base}-valor-${indice}`"
              data-valor-teste
              :model-value="valores[informacao.nome] || ''"
              :inputmode="MODO_DO_TECLADO[informacao.tipo]"
              :descricao="descricao"
              :invalido="invalido"
              @update:model-value="mudarValor(informacao.nome, $event)"
            />
          </template>
        </FerramentaCampo>
      </template>
    </div>
    <p v-else data-sem-informacao class="m-0 text-sm text-n-slate-11">
      {{ t(`${NS}.SEM_INFORMACAO`) }}
    </p>

    <details
      v-if="feito"
      data-chamada
      class="group rounded-xl ring-1 ring-inset ring-n-weak"
    >
      <summary
        class="flex items-center gap-2 px-3 text-sm list-none cursor-pointer rounded-xl min-h-11 text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      >
        <span
          aria-hidden="true"
          class="transition i-lucide-chevron-right size-4 group-open:rotate-90 shrink-0"
        />
        <span class="font-mono break-all grow">{{ resumoDaChamada }}</span>
        <span class="font-semibold text-n-blue-11 shrink-0">
          {{ t(`${NS}.VER_CHAMADA`) }}
        </span>
      </summary>
      <div class="px-3 pb-3">
        <TesteChamada :chamada="chamada" />
      </div>
    </details>
    <section
      v-else
      data-chamada
      :aria-labelledby="`${base}-chamada`"
      class="flex flex-col gap-2 p-4 rounded-2xl bg-n-alpha-1"
    >
      <p
        :id="`${base}-chamada`"
        class="m-0 text-sm font-semibold text-n-slate-12"
      >
        {{ t(`${NS}.CHAMADA`) }}
      </p>
      <TesteChamada :chamada="chamada" />
    </section>
    <FerramentaFaixa v-if="avisoDeEspaco" data-aviso-espaco tom="ambar" solta>
      <p class="m-0 break-words">{{ avisoDeEspaco }}</p>
    </FerramentaFaixa>

    <div aria-live="polite" class="relative flex flex-col gap-3">
      <p
        v-if="testando"
        data-chamando
        class="flex items-center gap-2 m-0 text-sm text-n-slate-12"
      >
        <span
          aria-hidden="true"
          class="i-lucide-loader-circle size-4 animate-spin"
        />
        {{ t(`${NS}.CHAMANDO_LONGO`) }}
      </p>
      <template v-else-if="resultado?.ok">
        <AgenteErro
          v-if="erroAoLigar"
          data-erro-ligar
          :titulo="t(`${NS}.ERRO_LIGAR`)"
          :garantia="t(`${NS}.ERRO_LIGAR_TEXTO`)"
        />
        <AgenteErro
          v-if="resultado.resposta.vazia"
          data-resposta-vazia
          tom="ambar"
          :titulo="t(`${NS}.VAZIA`)"
          :garantia="t(`${NS}.VAZIA_TEXTO`)"
        />
        <TesteResposta
          v-else
          :resposta="resultado.resposta"
          :mapeada="Boolean(rascunho.mapeamento)"
        />
        <p class="m-0">
          <button
            type="button"
            data-outros-valores
            class="px-1 -mx-1 text-sm font-semibold underline rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
            @click="outrosValores"
          >
            {{ t(`${NS}.OUTROS_VALORES`) }}
          </button>
        </p>
        <p v-if="!ferramenta.enabled" class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.AGORA_NAO_NOTA`) }}
        </p>
      </template>
      <div
        v-else-if="falha"
        ref="cartaoFalha"
        data-falha
        role="alert"
        tabindex="-1"
        class="flex items-start gap-3 p-4 outline-none rounded-2xl ring-1 ring-inset"
        :class="
          falha.ambar
            ? 'bg-n-amber-2 ring-n-amber-6'
            : 'bg-n-ruby-2 ring-n-ruby-6'
        "
      >
        <span
          aria-hidden="true"
          class="mt-0.5 size-5 shrink-0"
          :class="
            falha.ambar
              ? 'i-lucide-clock text-n-amber-11'
              : 'i-lucide-circle-alert text-n-ruby-11'
          "
        />
        <div class="flex flex-col min-w-0 gap-1">
          <p class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.ERROS.${falha.chave}`) }}
          </p>
          <p class="m-0 text-sm text-n-slate-11">{{ textoDaFalha }}</p>
          <p
            v-if="falha.detalhe"
            class="flex flex-wrap gap-x-2 m-0 text-xs text-n-slate-11"
          >
            <span class="font-semibold">{{ t(`${NS}.DETALHE`) }}</span>
            <code class="font-mono break-all">{{ falha.detalhe }}</code>
          </p>
        </div>
      </div>
    </div>

    <Teleport defer :to="`#${rodape}`">
      <template v-if="resultado?.ok && !testando">
        <AgenteBotao
          v-if="ferramenta.enabled"
          data-voltar-ferramenta
          variante="contorno"
          tamanho="lg"
          icone="i-lucide-arrow-left"
          class="w-full sm:w-auto"
          @click="emit('voltar')"
        >
          {{ t(`${NS}.VOLTAR_FERRAMENTA`) }}
        </AgenteBotao>
        <template v-else>
          <AgenteBotao
            data-agora-nao
            variante="contorno"
            tamanho="lg"
            class="w-full sm:w-auto"
            :desabilitado="ligando"
            @click="emit('agoraNao')"
          >
            {{ t(`${NS}.AGORA_NAO`) }}
          </AgenteBotao>
          <AgenteBotao
            data-ligar
            tamanho="lg"
            icone="i-lucide-power"
            class="w-full sm:w-auto"
            :carregando="ligando"
            :rotulo-carregando="t(`${NS}.LIGANDO`)"
            @click="ligarAgora"
          >
            {{ t(`${NS}.LIGAR`) }}
          </AgenteBotao>
        </template>
      </template>
      <template v-else-if="falha && !testando">
        <AgenteBotao
          data-testar-de-novo
          :variante="passoDaFalha ? 'contorno' : 'primario'"
          tamanho="lg"
          icone="i-lucide-refresh-cw"
          class="w-full sm:w-auto"
          @click="rodar"
        >
          {{ t(`${NS}.TESTAR_DE_NOVO`) }}
        </AgenteBotao>
        <AgenteBotao
          v-if="passoDaFalha"
          data-corrigir
          tamanho="lg"
          icone="i-lucide-pencil"
          class="w-full sm:w-auto"
          @click="emit('corrigir', passoDaFalha)"
        >
          {{ t(`${NS}.CORRIGIR.${falha.corrigir}`) }}
        </AgenteBotao>
      </template>
      <AgenteBotao
        v-else
        data-fazer-chamada
        tamanho="lg"
        icone="i-lucide-send"
        class="w-full sm:w-auto"
        :carregando="testando"
        :rotulo-carregando="t(`${NS}.CHAMANDO`)"
        @click="rodar"
      >
        {{ t(`${NS}.FAZER`) }}
      </AgenteBotao>
    </Teleport>
  </div>
</template>
