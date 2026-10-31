<script setup>
import { computed, nextTick, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import AgenteBotao from '../../AgenteBotao.vue';
import AgenteConfirmacao from '../../AgenteConfirmacao.vue';
import AgenteErro from '../../AgenteErro.vue';
import FerramentaFaixa from './FerramentaFaixa.vue';
import PassoComoEntra from './PassoComoEntra.vue';
import PassoOQueFaz from './PassoOQueFaz.vue';
import PassoParaOnde from './PassoParaOnde.vue';
import PassoPreenche from './PassoPreenche.vue';
import {
  PASSOS,
  conteudoDoRascunho,
  paraRascunho,
  passosProvaveisDoErro,
  rascunhoDeExemplo,
  rascunhoVazio,
  segredosSemNome,
  validarPasso,
} from '../../../utils/ferramentas';

// #1301 (protótipos F03–F06, F09-editar e F10) — o assistente de 4 passos na própria gaveta. Novo:
// os dados ficam no rascunho até o passo 4, que salva a ferramenta DESLIGADA (POST enabled:false) e
// leva ao teste. Edição: abre só a parte escolhida e salva com PATCH; numa ferramenta ligada, a
// ação principal é "Desligar, salvar e testar" (a mudança valeria nas conversas sem teste).
const props = defineProps({
  modo: {
    type: String,
    default: 'novo',
    validator: v => ['novo', 'edicao'].includes(v),
  },
  passoInicial: { type: Number, default: 1 },
  ferramenta: { type: Object, default: null },
  rodape: { type: String, required: true },
  criar: { type: Function, required: true },
  alterar: { type: Function, required: true },
});

const emit = defineEmits(['salva', 'voltar', 'cancelar', 'anunciar']);

const NS = 'AGENTS.JORNADA.PAGINA.FERRAMENTAS';
const { t } = useI18n();
const base = `ferramenta-${useId()}`;
const SEPARADOR = '·';

const novo = computed(() => props.modo === 'novo');
const ligada = computed(
  () => !novo.value && Boolean(props.ferramenta?.enabled)
);
const rascunho = ref(
  props.ferramenta ? paraRascunho(props.ferramenta) : rascunhoVazio()
);
const inicial = conteudoDoRascunho(rascunho.value);
const passo = ref(props.passoInicial);
const erros = ref({});
const avisarQuando = ref(false);
const avisouQuando = ref(false);
const exemploAplicado = ref(false);
const salvando = ref(false);
// A última tentativa de salvar (com ou sem desligar), para o "Tentar de novo" repetir a mesma.
const ultimaTentativa = ref({});
const erroAoSalvar = ref(null);
const topo = ref(null);

// Sair com algo digitado pede confirmação (protótipo F03, "Sair sem salvar?").
// Vale para os 4 passos: qualquer campo diferente do começo (vazio, na criação) conta.
const sujo = computed(() => conteudoDoRascunho(rascunho.value) !== inicial);
defineExpose({ sujo });

const nomeDoPasso = numero => t(`${NS}.PASSOS.NOMES.${PASSOS[numero - 1]}`);

// Primeiro campo com erro, na ordem da tela.
const CAMPOS = {
  nome: () => `${base}-nome`,
  endereco: () => `${base}-endereco`,
  slug: () => `${base}-slug`,
};
const idDoErro = (chave, erro) => {
  if (CAMPOS[chave]) return CAMPOS[chave]();
  const indice = chave.slice(1);
  if (chave.startsWith('i')) return `${base}-info-${indice}-nome`;
  const campo = erro === 'CHAVE' ? 'chave' : 'valor';
  return `${base}-cab-${indice}-${campo}`;
};
const focar = async id => {
  await nextTick();
  document.getElementById(id)?.focus();
};

const focarPrimeiroErro = lista => {
  const primeiro = Object.keys(lista)[0];
  if (primeiro) focar(idDoErro(primeiro, lista[primeiro]));
  return Boolean(primeiro);
};

const irParaPasso = async numero => {
  passo.value = numero;
  erros.value = {};
  avisarQuando.value = false;
  avisouQuando.value = false;
  erroAoSalvar.value = null;
  await nextTick();
  topo.value?.focus();
};

// Valida o passo atual; devolve true quando pode seguir.
const conferir = () => {
  const resultado = validarPasso(
    passo.value,
    rascunho.value,
    avisouQuando.value
  );
  erros.value = resultado.erros;
  if (focarPrimeiroErro(resultado.erros)) return false;
  if (resultado.avisarQuando) {
    avisarQuando.value = true;
    avisouQuando.value = true;
    focar(`${base}-quando`);
    return false;
  }
  return true;
};

const continuar = () => {
  if (conferir()) irParaPasso(passo.value + 1);
};

const voltarPasso = () => irParaPasso(passo.value - 1);

const aplicarExemplo = () => {
  rascunho.value = rascunhoDeExemplo(t);
  exemploAplicado.value = true;
  erros.value = {};
  avisarQuando.value = false;
  focar(`${base}-nome`);
};

// Segredo guardado com o nome apagado: salvar apaga a chave, então pergunta antes (como Remover).
const confirmacaoDeRemover = ref(null);
const salvarDepois = ref(null);

const salvar = async ({ desligar = false } = {}) => {
  if (salvando.value) return;
  const resultado = validarPasso(passo.value, rascunho.value, true);
  erros.value = resultado.erros;
  if (focarPrimeiroErro(resultado.erros)) return;
  if (segredosSemNome(rascunho.value).length) {
    salvarDepois.value = { desligar };
    confirmacaoDeRemover.value?.abrir();
    return;
  }
  salvando.value = true;
  erroAoSalvar.value = null;
  ultimaTentativa.value = { desligar };
  try {
    const salva = novo.value
      ? await props.criar(rascunho.value)
      : await props.alterar(
          props.ferramenta.id,
          rascunho.value,
          desligar ? { enabled: false } : {}
        );
    emit('salva', { ferramenta: salva, desligou: desligar });
  } catch (erro) {
    erroAoSalvar.value = erro?.motivo || { tipo: 'REDE', mensagem: '' };
    await nextTick();
    topo.value?.focus();
  } finally {
    salvando.value = false;
  }
};

const confirmarRemover = () => {
  const opcoes = salvarDepois.value;
  confirmacaoDeRemover.value?.fechar();
  const apagados = segredosSemNome(rascunho.value);
  rascunho.value = {
    ...rascunho.value,
    cabecalhos: rascunho.value.cabecalhos.filter(c => !apagados.includes(c)),
  };
  salvarDepois.value = null;
  salvar(opcoes || {});
};

const garantia = computed(() =>
  novo.value ? t(`${NS}.PASSOS.NADA_SALVO`) : t(`${NS}.PASSOS.CONTINUA_VALENDO`)
);
const passosDoErro = computed(() =>
  passosProvaveisDoErro(erroAoSalvar.value?.mensagem)
);
</script>

<template>
  <div class="flex flex-col gap-5">
    <div ref="topo" tabindex="-1" class="flex flex-col gap-3 outline-none">
      <div v-if="novo" data-indicador class="flex flex-col gap-2">
        <p class="m-0 text-sm text-n-slate-11">
          <b class="font-semibold text-n-slate-12">
            {{ t(`${NS}.PASSOS.INDICADOR`, { n: passo }) }}
          </b>
          {{ SEPARADOR }} {{ nomeDoPasso(passo) }}
        </p>
        <div aria-hidden="true" class="grid grid-cols-4 gap-1.5">
          <span
            v-for="numero in 4"
            :key="numero"
            class="h-1.5 rounded-full"
            :class="numero <= passo ? 'bg-n-blue-11' : 'bg-n-alpha-3'"
          />
        </div>
      </div>
      <template v-else>
        <p data-editando class="m-0 text-sm text-n-slate-11">
          {{ t(`${NS}.PASSOS.EDITANDO`, { parte: nomeDoPasso(passo) }) }}
        </p>
        <FerramentaFaixa v-if="ligada" data-aviso-ligada tom="ambar">
          <p class="m-0">{{ t(`${NS}.PASSOS.LIGADA_AVISO`) }}</p>
          <p class="m-0">
            <button
              type="button"
              data-salvar-ligada
              class="px-1 -mx-1 text-sm font-semibold underline rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @click="salvar()"
            >
              {{ t(`${NS}.PASSOS.SALVAR_LIGADA`) }}
            </button>
          </p>
        </FerramentaFaixa>
      </template>

      <AgenteErro
        v-if="erroAoSalvar?.tipo === 'REDE'"
        data-erro-salvar
        :titulo="t(`${NS}.PASSOS.SEM_REDE`)"
        :garantia="garantia"
        :acao="t('AGENTS.JORNADA.COMUM.TENTAR_DE_NOVO')"
        :carregando="salvando"
        @acao="salvar(ultimaTentativa)"
      />
      <div
        v-else-if="erroAoSalvar"
        data-erro-salvar
        role="alert"
        class="flex items-start gap-3 p-4 rounded-2xl ring-1 ring-inset bg-n-ruby-2 ring-n-ruby-6"
      >
        <span
          aria-hidden="true"
          class="mt-0.5 size-5 shrink-0 i-lucide-circle-alert text-n-ruby-11"
        />
        <div class="flex flex-col min-w-0 gap-1">
          <p class="m-0 text-sm font-semibold text-n-slate-12">
            {{ t(`${NS}.PASSOS.ERRO_SALVAR`) }} {{ garantia }}
          </p>
          <p
            v-if="erroAoSalvar.mensagem"
            class="m-0 text-sm break-words text-n-slate-11"
          >
            {{
              t(`${NS}.PASSOS.SISTEMA_DISSE`, {
                mensagem: erroAoSalvar.mensagem,
              })
            }}
          </p>
          <div v-if="novo" class="flex flex-wrap gap-x-3">
            <button
              v-for="numero in passosDoErro"
              :key="numero"
              type="button"
              data-ir-para-passo
              class="px-1 -mx-1 text-sm font-semibold underline rounded-lg min-h-11 text-n-blue-11 underline-offset-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @click="irParaPasso(numero)"
            >
              {{
                t(`${NS}.PASSOS.IR_PARA_PASSO`, {
                  n: numero,
                  parte: nomeDoPasso(numero).toLowerCase(),
                })
              }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <PassoOQueFaz
      v-if="passo === 1"
      v-model:rascunho="rascunho"
      :base="base"
      :erros="erros"
      :avisar-quando="avisarQuando"
      :pode-usar-exemplo="novo && !exemploAplicado"
      :exemplo-aplicado="exemploAplicado"
      @exemplo="aplicarExemplo"
    />
    <PassoParaOnde
      v-else-if="passo === 2"
      v-model:rascunho="rascunho"
      :base="base"
      :erros="erros"
      :novo="novo"
    />
    <PassoPreenche
      v-else-if="passo === 3"
      v-model:rascunho="rascunho"
      :base="base"
      :erros="erros"
      @anunciar="emit('anunciar', $event)"
    />
    <PassoComoEntra
      v-else
      v-model:rascunho="rascunho"
      :base="base"
      :erros="erros"
      :novo="novo"
      @anunciar="emit('anunciar', $event)"
    />

    <Teleport defer :to="`#${rodape}`">
      <template v-if="novo">
        <AgenteBotao
          data-voltar
          variante="contorno"
          tamanho="lg"
          class="w-full sm:w-auto"
          @click="passo === 1 ? emit('cancelar') : voltarPasso()"
        >
          {{
            passo === 1
              ? t('AGENTS.JORNADA.COMUM.CANCELAR')
              : t(`${NS}.PASSOS.VOLTAR`)
          }}
        </AgenteBotao>
        <AgenteBotao
          v-if="passo < 4"
          data-continuar
          tamanho="lg"
          class="w-full sm:w-auto"
          @click="continuar"
        >
          {{ t(`${NS}.PASSOS.CONTINUAR`) }}
        </AgenteBotao>
        <AgenteBotao
          v-else
          data-salvar
          tamanho="lg"
          class="w-full sm:w-auto"
          :carregando="salvando"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar()"
        >
          {{ t(`${NS}.PASSOS.SALVAR_E_TESTAR`) }}
        </AgenteBotao>
      </template>
      <template v-else>
        <AgenteBotao
          data-voltar
          variante="contorno"
          tamanho="lg"
          class="w-full sm:w-auto"
          :desabilitado="salvando"
          @click="emit('voltar')"
        >
          {{ t(`${NS}.PASSOS.VOLTAR`) }}
        </AgenteBotao>
        <AgenteBotao
          data-salvar
          tamanho="lg"
          class="w-full sm:w-auto"
          :carregando="salvando"
          :rotulo-carregando="t(`${NS}.SALVANDO`)"
          @click="salvar({ desligar: ligada })"
        >
          {{
            ligada
              ? t(`${NS}.PASSOS.DESLIGAR_SALVAR_TESTAR`)
              : t(`${NS}.PASSOS.SALVAR`)
          }}
        </AgenteBotao>
      </template>
    </Teleport>
    <AgenteConfirmacao
      ref="confirmacaoDeRemover"
      :titulo="t(`${NS}.PASSOS.QUATRO.REMOVER_TITULO`)"
      :texto="t(`${NS}.PASSOS.QUATRO.REMOVER_TEXTO`)"
      :confirmar="t(`${NS}.REMOVER`)"
      @confirmar="confirmarRemover"
    />
  </div>
</template>
