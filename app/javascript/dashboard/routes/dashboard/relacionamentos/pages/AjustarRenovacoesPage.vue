<script setup>
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  FALTAS,
  MENSAGENS,
  faltaNosAjustes,
  ondeFicam,
  quantosEntram,
  temMensagens,
} from '../carteira/ajustesDaRenovacao';
import { chaveDaRecusa } from '../carteira/recusas';
import { useAjustesDaRenovacao } from '../carteira/useAjustesDaRenovacao';
import { useContaDeSeguros } from '../carteira/useContaDeSeguros';
import { usePodeAjustarRenovacoes } from '../carteira/usePodeAjustarRenovacoes';
import { ESTADOS_DA_FICHA as ESTADOS } from '../ficha/useEstadoDaFicha';
import { ABA_SEGUROS } from '../fonte/gruposDeSeguros';
import { pecaPedida } from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';
import { renovacoesFonte } from '../fonte/renovacoesFonte';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import CartoesDeEscolha from '../components/trazer/CartoesDeEscolha.vue';
import CampoDeDias from '../components/carteira/renovacao/CampoDeDias.vue';
import CartaoDeAjuste from '../components/carteira/renovacao/CartaoDeAjuste.vue';
import OndeFicamAsRenovacoes from '../components/carteira/renovacao/OndeFicamAsRenovacoes.vue';

// #2898 — "Ajustar renovações": em que funil a renovação de cada seguro
// aparece, quantos dias antes do fim e se as mensagens antes de vencer saem. Um
// cartão por pergunta e uma ação só: Salvar, sempre ligado (sem mudança, ou
// faltando algo, o clique diz o que é e leva o foco até lá). Dias e mensagens
// já vêm respondidos; enquanto ninguém escolhe o funil, nenhuma renovação
// aparece. O cartão das mensagens só existe quando o servidor manda a escolha
// (a conta que tem as mensagens de renovação): sem ela, nada é mostrado no
// lugar. Quem não pode mudar (carteira/usePodeAjustarRenovacoes.js) lê a
// escolha de hoje e não vê Salvar. Conta sem a carteira de seguros não chama
// rota nenhuma e volta para a lista.
const { t } = useI18n();
const ta = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const id = useId();

const demo = usarDemo(route.query);
const temCarteira = useContaDeSeguros(demo);
const podeAjustar = usePodeAjustarRenovacoes();
const fonte = renovacoesFonte({ demo, peca: pecaPedida(route.query) });
const tela = useAjustesDaRenovacao(fonte);
const { conta, rascunho } = tela;

const raiz = useTemplateRef('raiz');
const onde = useTemplateRef('onde');
// O que o Salvar tem a dizer: { tipo: 'alerta' | 'feito', texto }.
const recado = ref({ tipo: '', texto: '' });
const falta = ref('');

const pronto = computed(() => tela.estado.value === ESTADOS.PRONTO);
// Na demonstração tudo aparece, como na lista e na ficha.
const podeMudar = computed(
  () => (fonte.usaDemo || podeAjustar.value) && !conta.value?.semPermissao
);
const temFunis = computed(() => Boolean(conta.value?.funis.length));
// O cartão das mensagens só é montado quando o servidor manda a escolha.
const comMensagens = computed(() => temMensagens(rascunho.value));

const opcoesDeMensagens = computed(() => [
  { id: MENSAGENS.MANDAR, rotulo: ta('MENSAGENS.MANDAR') },
  { id: MENSAGENS.NAO_MANDAR, rotulo: ta('MENSAGENS.NAO_MANDAR') },
]);

// "Com 60 dias, 12 seguros já entram em renovação."
const efeito = computed(() => {
  const { dias } = rascunho.value;
  if (!dias) return '';
  const entram = quantosEntram(conta.value.vencimentos, dias);
  return [
    ta('DIAS.COM_DIAS', { count: dias }, dias),
    ta('DIAS.ENTRAM', { count: entram }, entram),
  ].join(' ');
});

// A escolha de hoje, para quem só lê.
const escolhaDeHoje = computed(() => {
  const escolha = ondeFicam(conta.value.funis, rascunho.value);
  const { dias } = rascunho.value;
  return escolha
    ? ta('HOJE', { ...escolha, count: dias }, dias)
    : ta('HOJE_SEM_FUNIL');
});

const semRecado = () => {
  recado.value = { tipo: '', texto: '' };
  falta.value = '';
};
const mudar = novo => {
  rascunho.value = novo;
  semRecado();
};
const alertar = texto => {
  recado.value = { tipo: 'alerta', texto };
};

const focarOQueFalta = async () => {
  await nextTick();
  if (falta.value === FALTAS.DIAS) {
    document.getElementById(`${id}-dias`)?.focus();
    return;
  }
  onde.value?.focar(falta.value);
};

// O funil ou a etapa que o servidor recusou já não existe: a tela relê os
// funis da conta, e o aviso continua dizendo o que fazer.
const FUNIS_MUDARAM = ['funil_desconhecido', 'etapa_de_outro_funil'];

const salvar = async () => {
  falta.value = faltaNosAjustes(rascunho.value);
  if (falta.value) {
    alertar(ta(`FALTA.${falta.value}`));
    focarOQueFalta();
    return;
  }
  if (!tela.mudou.value) {
    alertar(ta('NADA_MUDOU'));
    return;
  }
  if (await tela.salvar()) {
    recado.value = { tipo: 'feito', texto: ta('SALVO') };
    return;
  }
  const codigo = tela.recusa.value;
  alertar(
    t(chaveDaRecusa(codigo, 'RELACIONAMENTOS_CARTEIRA.AJUSTES.ERRO_SALVAR'))
  );
  if (FUNIS_MUDARAM.includes(codigo)) tela.carregar();
};

const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: ABA_SEGUROS } });
const abrirCrm = () => router.push({ name: 'crm_kanban_index' });

onMounted(async () => {
  if (!temCarteira.value) {
    router.replace({ name: 'relationships_home' });
    return;
  }
  tela.carregar();
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
});
</script>

<template>
  <section
    ref="raiz"
    data-carteira="ajustes"
    class="flex flex-col w-full h-full bg-n-surface-1"
  >
    <main v-if="temCarteira" class="flex flex-col flex-1 overflow-y-auto">
      <div
        class="flex flex-col flex-1 w-full max-w-3xl gap-6 px-5 pt-8 pb-10 mx-auto md:px-8 md:pt-10"
      >
        <LinkDeVolta
          :texto="ta('VOLTAR')"
          :rotulo="ta('VOLTAR_ROTULO')"
          @voltar="voltar"
        />
        <div class="flex flex-col gap-2">
          <h1
            data-titulo-da-tela
            tabindex="-1"
            class="m-0 text-3xl font-bold tracking-tight outline-none md:text-4xl text-n-slate-12"
          >
            {{ ta('TITULO') }}
          </h1>
          <p v-if="pronto" class="m-0 text-base text-n-slate-11">
            {{ ta(tela.jaEscolheu.value ? 'APOIO' : 'APOIO_SEM_FUNIL') }}
          </p>
        </div>

        <EsqueletoDeLista
          v-if="tela.estado.value === ESTADOS.CARREGANDO"
          :linhas="6"
          data-carteira="carregando"
        />
        <div v-else-if="!pronto" data-carteira="erro">
          <ErroComTentarDeNovo :mensagem="ta('ERRO')" @tentar="tela.carregar" />
        </div>
        <div
          v-else-if="!podeMudar"
          data-carteira="ajustes-so-leitura"
          class="flex flex-col gap-4"
        >
          <p
            data-carteira="escolha-de-hoje"
            class="m-0 text-lg text-n-slate-12"
          >
            {{ escolhaDeHoje }}
          </p>
          <Banner color="amber" data-carteira="sem-permissao">
            {{ ta('SEM_PERMISSAO') }}
          </Banner>
        </div>
        <template v-else>
          <CartaoDeAjuste marca="ajuste-onde" :titulo="ta('ONDE.TITULO')">
            <OndeFicamAsRenovacoes
              ref="onde"
              :model-value="rascunho"
              :funis="conta.funis"
              :falta="falta"
              :id-do-aviso="`${id}-recado`"
              @update:model-value="mudar"
              @abrir-crm="abrirCrm"
            />
          </CartaoDeAjuste>

          <template v-if="temFunis">
            <CartaoDeAjuste marca="ajuste-dias" :titulo="ta('DIAS.TITULO')">
              <div class="flex flex-col gap-2">
                <label :for="`${id}-dias`" class="text-base text-n-slate-12">
                  {{ ta('DIAS.ROTULO') }}
                </label>
                <div data-carteira="dias-antes">
                  <CampoDeDias
                    :id="`${id}-dias`"
                    :model-value="rascunho.dias"
                    :invalido="falta === FALTAS.DIAS"
                    :descrito-por="
                      falta === FALTAS.DIAS ? `${id}-recado` : undefined
                    "
                    @update:model-value="mudar({ ...rascunho, dias: $event })"
                  />
                </div>
                <p
                  data-carteira="efeito-dias"
                  aria-live="polite"
                  class="m-0 text-sm text-n-slate-11"
                >
                  {{ efeito }}
                </p>
              </div>
            </CartaoDeAjuste>

            <CartaoDeAjuste
              v-if="comMensagens"
              v-slot="{ rotuloId }"
              marca="ajuste-mensagens"
              :titulo="ta('MENSAGENS.TITULO')"
            >
              <CartoesDeEscolha
                :opcoes="opcoesDeMensagens"
                :model-value="rascunho.mensagens"
                :rotulo-id="rotuloId"
                @update:model-value="mudar({ ...rascunho, mensagens: $event })"
              />
              <p class="m-0 text-sm text-n-slate-11">
                {{ ta('MENSAGENS.APOIO') }}
              </p>
            </CartaoDeAjuste>
          </template>
        </template>
      </div>

      <footer
        v-if="pronto && podeMudar && temFunis"
        class="sticky bottom-0 z-10 border-t border-n-weak bg-n-solid-1"
      >
        <div
          class="flex flex-wrap items-center w-full max-w-3xl gap-3 ps-20 pe-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))] mx-auto md:ps-8 md:pe-8"
        >
          <!-- Abaixo de `md` o conteúdo começa depois do canto do botão ☰ do
               app (fixo embaixo, no início da linha): `ps-20`, como a barra
               de ação da lista. O "Salvo." mora numa região viva fixa (nasce
               vazia); o alerta nasce com o texto, que é como o leitor de tela
               o anuncia. -->
          <p
            data-carteira="ajustes-salvos"
            role="status"
            class="m-0 text-base font-medium basis-full text-n-teal-11"
          >
            {{ recado.tipo === 'feito' ? recado.texto : '' }}
          </p>
          <p
            v-if="recado.tipo === 'alerta'"
            :id="`${id}-recado`"
            data-carteira="alerta-dos-ajustes"
            role="alert"
            class="m-0 text-base font-medium basis-full text-n-ruby-11"
          >
            {{ recado.texto }}
          </p>
          <Button
            size="lg"
            class="flex-1 sm:flex-none"
            data-carteira="salvar-ajustes"
            :is-loading="tela.salvando.value"
            :aria-describedby="
              recado.tipo === 'alerta' ? `${id}-recado` : undefined
            "
            :label="ta('SALVAR')"
            @click="salvar"
          />
        </div>
      </footer>
    </main>
  </section>
</template>
