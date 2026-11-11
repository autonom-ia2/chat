<script setup>
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ALGO_MUDOU,
  COMO_ENVIA,
  DIAS_DAS_MENSAGENS,
  MENSAGENS,
  PALAVRAS,
  QUEM_COTA,
  QUEM_RESPONDE,
  faltaEmOndeFicam,
} from '../carteira/ajustesDaRenovacao';
import { useAjustesDaRenovacao } from '../carteira/useAjustesDaRenovacao';
import { useTextosDoSeguro } from '../carteira/useTextosDoSeguro';
import { ESTADOS_DA_FICHA as ESTADOS } from '../ficha/useEstadoDaFicha';
import {
  casoPedido,
  cotacaoDesligada,
  pecaPedida,
} from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';
import { renovacoesFonte } from '../fonte/renovacoesFonte';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import DialogoDaFicha from '../components/ficha/DialogoDaFicha.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import CartoesDeEscolha from '../components/trazer/CartoesDeEscolha.vue';
import CartaoDeAjuste from '../components/carteira/renovacao/CartaoDeAjuste.vue';
import OndeFicamAsRenovacoes from '../components/carteira/renovacao/OndeFicamAsRenovacoes.vue';
import PreviaDeMensagem from '../components/carteira/renovacao/PreviaDeMensagem.vue';

// #2897 — "Como as renovações andam" (Ajustar renovações): um cartão por
// pergunta, todos já respondidos com o padrão. Ninguém precisa responder nada
// para a renovação andar; quem quiser muda e salva. Salvar fica sempre ligado:
// sem mudança, ou faltando algo, o clique diz o que é. Se a pessoa escolhe que
// a proposta sai sozinha, ela sai sozinha: não há outra confirmação.
const { t } = useI18n();
const ta = (chave, valores, plural) =>
  t(`RELACIONAMENTOS_CARTEIRA.AJUSTES.${chave}`, valores, plural);
const route = useRoute();
const router = useRouter();
const textos = useTextosDoSeguro();
const { installationName } = useBranding();
const id = useId();

const tela = useAjustesDaRenovacao(
  renovacoesFonte({
    demo: usarDemo(route.query),
    peca: pecaPedida(route.query),
    caso: casoPedido(route.query),
    cotacaoDesligada: cotacaoDesligada(route.query),
  })
);
const { conta, rascunho } = tela;

const raiz = useTemplateRef('raiz');
const onde = useTemplateRef('onde');
const dialogoDeLigar = useTemplateRef('dialogoDeLigar');
// O que o Salvar tem a dizer: { tipo: 'alerta' | 'feito', texto }.
const recado = ref({ tipo: '', texto: '' });
const faltaEmOnde = ref('');

const escolha = (valor, chave, extras = {}) => ({
  id: valor,
  rotulo: ta(chave),
  ...extras,
});
const com = (chave, valores) => ({ descricao: ta(chave, valores) });

const opcoes = computed(() => {
  const { agente } = conta.value;
  const doAgente = agente
    ? [
        {
          id: QUEM_COTA.AGENTE,
          rotulo: agente,
          ...com('QUEM_COTA.AGENTE_APOIO', { agente }),
        },
      ]
    : [];
  return {
    mensagens: [
      escolha(MENSAGENS.MANDAR, 'MENSAGENS.MANDAR'),
      escolha(MENSAGENS.NAO_MANDAR, 'MENSAGENS.NAO_MANDAR'),
    ],
    algoMudou: [
      escolha(ALGO_MUDOU.PERGUNTAR, 'ALGO_MUDOU.PERGUNTAR'),
      escolha(ALGO_MUDOU.NAO, 'ALGO_MUDOU.NAO_PERGUNTAR'),
    ],
    quemCota: [
      escolha(QUEM_COTA.ROBO, 'QUEM_COTA.ROBO', com('QUEM_COTA.ROBO_APOIO')),
      ...doAgente,
      escolha(
        QUEM_COTA.NINGUEM,
        'QUEM_COTA.NINGUEM',
        com('QUEM_COTA.NINGUEM_APOIO')
      ),
    ],
    comoEnvia: [
      escolha(COMO_ENVIA.CONFERE, 'COMO_ENVIA.CONFERE', {
        atributos: { 'data-carteira': 'envia-conferindo' },
      }),
      escolha(COMO_ENVIA.SOZINHA, 'COMO_ENVIA.SOZINHA', {
        atributos: { 'data-carteira': 'envia-sozinha' },
      }),
    ],
    quemResponde: [
      ...(agente ? [{ id: QUEM_RESPONDE.AGENTE, rotulo: agente }] : []),
      escolha(QUEM_RESPONDE.EQUIPE, 'QUEM_RESPONDE.EQUIPE'),
    ],
    palavras: [
      escolha(PALAVRAS.CONFIRO, 'PALAVRAS.CONFIRO'),
      escolha(PALAVRAS.SOZINHO, 'PALAVRAS.SOZINHO'),
      escolha(PALAVRAS.NAO_MANDAR, 'PALAVRAS.NAO_MANDAR'),
    ],
  };
});

// As prévias usam um seguro da própria conta como exemplo.
const doExemplo = computed(() => {
  const { nome, tipo, termina } = conta.value.exemplo;
  return {
    nome,
    tipo: textos.tipo({ tipo }),
    data: textos.diaMes(termina),
  };
});
const previasDasMensagens = computed(() =>
  DIAS_DAS_MENSAGENS.map(dias => ({
    dias,
    legenda: ta('MENSAGENS.AOS', { count: dias }),
    texto: ta(`MENSAGENS.TEXTO_${dias}`, doExemplo.value),
  }))
);

const mudar = (chave, valor) => {
  rascunho.value = { ...rascunho.value, [chave]: valor };
  recado.value = { tipo: '', texto: '' };
  faltaEmOnde.value = '';
};
const mudarOnde = nova => {
  rascunho.value = nova;
  recado.value = { tipo: '', texto: '' };
  faltaEmOnde.value = '';
};

const alertar = texto => {
  recado.value = { tipo: 'alerta', texto };
};
const salvar = async () => {
  faltaEmOnde.value = conta.value.semPermissao
    ? ''
    : faltaEmOndeFicam(rascunho.value);
  if (faltaEmOnde.value) {
    alertar(ta(`ONDE.FALTA.${faltaEmOnde.value}`));
    onde.value?.focar(faltaEmOnde.value);
    return;
  }
  if (!tela.mudou.value) {
    alertar(ta('NADA_MUDOU'));
    raiz.value?.querySelector('[role="radio"][tabindex="0"]')?.focus();
    return;
  }
  const salvou = await tela.salvar();
  if (salvou) recado.value = { tipo: 'feito', texto: ta('SALVO') };
  else alertar(ta('ERRO_SALVAR'));
};

const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: 'seguros' } });
const ligarAgger = () =>
  router.push({ name: 'relacionamentos_trazer', query: { como: 'agger' } });

onMounted(async () => {
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
    <main class="flex flex-col flex-1 overflow-y-auto">
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
          <p class="m-0 text-base text-n-slate-11">{{ ta('APOIO') }}</p>
        </div>

        <EsqueletoDeLista
          v-if="tela.estado.value === ESTADOS.CARREGANDO"
          :linhas="6"
          data-carteira="carregando"
        />
        <div
          v-else-if="tela.estado.value !== ESTADOS.PRONTO"
          data-carteira="erro"
        >
          <ErroComTentarDeNovo :mensagem="ta('ERRO')" @tentar="tela.carregar" />
        </div>
        <template v-else>
          <CartaoDeAjuste
            v-slot="{ rotuloId }"
            marca="ajuste-onde"
            :titulo="ta('ONDE.TITULO')"
          >
            <OndeFicamAsRenovacoes
              ref="onde"
              :model-value="rascunho"
              :funis="conta.funis"
              :vencimentos="conta.vencimentos"
              :sem-permissao="conta.semPermissao"
              :falta="faltaEmOnde"
              :id-do-aviso="`${id}-recado`"
              :rotulo-id="rotuloId"
              @update:model-value="mudarOnde"
            />
          </CartaoDeAjuste>

          <CartaoDeAjuste
            v-slot="{ rotuloId }"
            marca="ajuste-mensagens"
            :titulo="ta('MENSAGENS.TITULO')"
          >
            <CartoesDeEscolha
              :opcoes="opcoes.mensagens"
              :model-value="rascunho.mensagens"
              :rotulo-id="rotuloId"
              @update:model-value="mudar('mensagens', $event)"
            />
            <div
              v-if="rascunho.mensagens === MENSAGENS.MANDAR"
              data-carteira="previa-das-mensagens"
              class="flex flex-col gap-3"
            >
              <p class="m-0 text-sm font-medium text-n-slate-11">
                {{ ta('MENSAGENS.PREVIA') }}
              </p>
              <PreviaDeMensagem
                v-for="previa in previasDasMensagens"
                :key="previa.dias"
                :legenda="previa.legenda"
                :texto="previa.texto"
              />
            </div>
            <p class="m-0 text-sm text-n-slate-11">
              {{ ta('MENSAGENS.APOIO') }}
            </p>
          </CartaoDeAjuste>

          <CartaoDeAjuste
            v-slot="{ rotuloId }"
            marca="ajuste-algo-mudou"
            :titulo="ta('ALGO_MUDOU.TITULO')"
          >
            <p class="m-0 text-base text-n-slate-12">
              {{ ta('ALGO_MUDOU.PERGUNTA') }}
            </p>
            <CartoesDeEscolha
              :opcoes="opcoes.algoMudou"
              :model-value="rascunho.algoMudou"
              :rotulo-id="rotuloId"
              @update:model-value="mudar('algoMudou', $event)"
            />
            <div
              v-if="rascunho.algoMudou === ALGO_MUDOU.PERGUNTAR"
              class="flex flex-col gap-3"
            >
              <PreviaDeMensagem
                :legenda="ta('ALGO_MUDOU.PREVIA')"
                :texto="ta('ALGO_MUDOU.TEXTO', doExemplo)"
                :botoes="[
                  ta('ALGO_MUDOU.NADA_MUDOU'),
                  ta('ALGO_MUDOU.MUDOU_ALGO'),
                ]"
              />
              <PreviaDeMensagem
                :legenda="ta('ALGO_MUDOU.DEPOIS')"
                :texto="ta('ALGO_MUDOU.O_QUE_MUDOU')"
                :botoes="[
                  ta('ALGO_MUDOU.CARRO'),
                  ta('ALGO_MUDOU.ENDERECO'),
                  ta('ALGO_MUDOU.OUTRA'),
                ]"
              />
            </div>
          </CartaoDeAjuste>

          <template v-if="conta.cotaSozinha">
            <CartaoDeAjuste
              v-slot="{ rotuloId }"
              marca="ajuste-quem-cota"
              :titulo="ta('QUEM_COTA.TITULO')"
            >
              <CartoesDeEscolha
                :opcoes="opcoes.quemCota"
                :model-value="rascunho.quemCota"
                :rotulo-id="rotuloId"
                @update:model-value="mudar('quemCota', $event)"
              />
            </CartaoDeAjuste>
            <CartaoDeAjuste
              v-slot="{ rotuloId }"
              marca="ajuste-como-envia"
              :titulo="ta('COMO_ENVIA.TITULO')"
            >
              <CartoesDeEscolha
                :opcoes="opcoes.comoEnvia"
                :model-value="rascunho.comoEnvia"
                :rotulo-id="rotuloId"
                @update:model-value="mudar('comoEnvia', $event)"
              />
              <p
                v-if="rascunho.comoEnvia === COMO_ENVIA.SOZINHA"
                data-carteira="sai-sozinha"
                aria-live="polite"
                class="m-0 text-base text-n-slate-12"
              >
                {{ ta('COMO_ENVIA.SOZINHA_APOIO') }}
              </p>
            </CartaoDeAjuste>
            <CartaoDeAjuste
              v-slot="{ rotuloId }"
              marca="ajuste-quem-responde"
              :titulo="ta('QUEM_RESPONDE.TITULO')"
            >
              <CartoesDeEscolha
                :opcoes="opcoes.quemResponde"
                :model-value="
                  conta.agente ? rascunho.quemResponde : QUEM_RESPONDE.EQUIPE
                "
                :rotulo-id="rotuloId"
                @update:model-value="mudar('quemResponde', $event)"
              />
              <p v-if="!conta.agente" class="m-0 text-sm text-n-slate-11">
                {{ ta('QUEM_RESPONDE.SEM_AGENTE') }}
              </p>
            </CartaoDeAjuste>
          </template>
          <CartaoDeAjuste
            v-else
            marca="ajuste-cotacao"
            :titulo="ta('COTAR_SOZINHO.TITULO')"
          >
            <template v-if="conta.aggerLigado">
              <p class="m-0 text-base text-n-slate-12">
                {{ ta('COTAR_SOZINHO.DESLIGADA') }}
              </p>
              <div>
                <Button
                  slate
                  faded
                  size="lg"
                  data-carteira="quero-ligar"
                  aria-haspopup="dialog"
                  :label="ta('COTAR_SOZINHO.QUERO_LIGAR')"
                  @click="dialogoDeLigar?.open()"
                />
              </div>
            </template>
            <template v-else>
              <p class="m-0 text-base text-n-slate-12">
                {{ ta('COTAR_SOZINHO.SEM_AGGER') }}
              </p>
              <div>
                <Button
                  slate
                  faded
                  size="lg"
                  data-carteira="ligar-agger"
                  :label="ta('COTAR_SOZINHO.LIGAR_AGGER')"
                  @click="ligarAgger"
                />
              </div>
            </template>
          </CartaoDeAjuste>

          <CartaoDeAjuste
            v-slot="{ rotuloId }"
            marca="ajuste-palavras-simples"
            :titulo="ta('PALAVRAS.TITULO')"
          >
            <p class="m-0 text-base text-n-slate-12">
              {{ ta('PALAVRAS.PERGUNTA') }}
            </p>
            <CartoesDeEscolha
              :opcoes="opcoes.palavras"
              :model-value="rascunho.palavras"
              :rotulo-id="rotuloId"
              @update:model-value="mudar('palavras', $event)"
            />
          </CartaoDeAjuste>
        </template>
      </div>

      <footer
        v-if="tela.estado.value === ESTADOS.PRONTO"
        class="sticky bottom-0 z-10 border-t border-n-weak bg-n-solid-1"
      >
        <div
          class="flex flex-wrap items-center w-full max-w-3xl gap-3 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))] mx-auto md:px-8"
        >
          <!-- O "Salvo." mora numa região viva fixa (nasce vazia); o alerta
               nasce com o texto, que é como o leitor de tela o anuncia. -->
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
            :disabled="tela.salvando.value"
            :aria-describedby="
              recado.tipo === 'alerta' ? `${id}-recado` : undefined
            "
            :label="ta('SALVAR')"
            @click="salvar"
          />
        </div>
      </footer>
    </main>

    <DialogoDaFicha
      ref="dialogoDeLigar"
      so-entendi
      :titulo="ta('COTAR_SOZINHO.DIALOGO_TITULO')"
      :texto="
        ta('COTAR_SOZINHO.DIALOGO_TEXTO', { instalacao: installationName })
      "
      :entendi="t('RELACIONAMENTOS.COMUM.ENTENDI')"
    />
  </section>
</template>
