<script setup>
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
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
import {
  FUNIL_INCOMPLETO,
  useCriarFunilDeRenovacoes,
} from '../carteira/useCriarFunilDeRenovacoes';
import { usePodeAjustarRenovacoes } from '../carteira/usePodeAjustarRenovacoes';
import { ESTADOS_DA_FICHA as ESTADOS } from '../ficha/useEstadoDaFicha';
import { ABA_SEGUROS } from '../fonte/gruposDeSeguros';
import { pecaPedida } from '../fonte/modoCarteira';
import { usarDemo } from '../fonte/modoDemo';
import { renovacoesFonte } from '../fonte/renovacoesFonte';
import ErroComTentarDeNovo from '../components/comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../components/comum/EsqueletoDeLista.vue';
import VazioComUmBotao from '../components/comum/VazioComUmBotao.vue';
import AvisoVivo from '../components/ficha/AvisoVivo.vue';
import LinkDeVolta from '../components/ficha/LinkDeVolta.vue';
import CartoesDeEscolha from '../components/trazer/CartoesDeEscolha.vue';
import CampoDeDias from '../components/carteira/renovacao/CampoDeDias.vue';
import CartaoDeAjuste from '../components/carteira/renovacao/CartaoDeAjuste.vue';
import CotacaoDaRenovacao from '../components/carteira/renovacao/CotacaoDaRenovacao.vue';
import DialogoDeConfirmacao from '../components/carteira/DialogoDeConfirmacao.vue';
import OndeFicamAsRenovacoes from '../components/carteira/renovacao/OndeFicamAsRenovacoes.vue';

// #2898 — "Ajustar renovações": em que funil a renovação de cada seguro
// aparece, quantos dias antes do fim e se as mensagens antes de vencer saem. Um
// cartão por pergunta e uma ação só: Salvar, sempre ligado (sem mudança, ou
// faltando algo, o clique diz o que é e leva o foco até lá). Dias e mensagens
// já vêm respondidos; enquanto ninguém escolhe o funil, nenhuma renovação
// aparece. O cartão das mensagens só existe quando o servidor manda a escolha
// (a conta que tem as mensagens de renovação): sem ela, nada é mostrado no
// lugar. Quem não pode mudar (carteira/usePodeAjustarRenovacoes.js) lê a
// escolha de hoje e não vê Salvar. Quem o servidor não deixa nem ler (401 ou
// 403) lê que não tem acesso e ganha o "Voltar": "tente de novo" nunca
// resolveria. Conta sem a carteira de seguros não chama rota nenhuma e volta
// para a lista.
// O funil escolhido que foi arquivado ou apagado (carteira/funilDasRenovacoes.js)
// para as renovações: o aviso no topo do cartão do funil diz isso e pede outro
// funil; o Salvar pede o funil enquanto a pessoa não escolhe.
// #2901 (E8) — com a cotação da renovação ligada na conta (`cotacaoLiberada`),
// soma-se o cartão "Cotação da renovação" (CotacaoDaRenovacao.vue), que entra
// no mesmo Salvar. Sem a chave, a tela é a da E5.
// #3057 — a conta sem funil não manda mais a pessoa ao CRM para voltar depois:
// quem pode criar funil no CRM ganha "Criar o funil de renovações para mim"
// (carteira/useCriarFunilDeRenovacoes.js, o mesmo caminho do CRM com o modelo
// Renovação). Criado, o funil e a primeira etapa já ficam escolhidos, e o
// recado no cartão pede só o Salvar. A tela não salva sozinha: a regra dela é
// uma ação só, Salvar, e a pessoa ainda vê os dias e as mensagens antes de
// guardar. Na demonstração a conta sempre tem funis, e o botão não existe.
// Se o funil nasceu mas uma etapa falhou (carteira/useCriarFunilDeRenovacoes.js,
// FUNIL_INCOMPLETO), "tente de novo" criaria outro funil: o recado manda
// conferir o funil no CRM, e o que nasceu fica escolhido. "Tente de novo" é só
// para a falha antes de o funil existir.
// Sair da tela com algo não salvo pergunta antes ("Sair sem salvar?"), com
// "Salvar ajustes" e "Sair sem salvar". A tela nunca salva sozinha: salvar,
// aqui, é o toque da pessoa. Esc só fecha a pergunta.
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
const funilNovo = useCriarFunilDeRenovacoes();

const raiz = useTemplateRef('raiz');
const onde = useTemplateRef('onde');
const cotacao = useTemplateRef('cotacao');
// O que o Salvar tem a dizer: { tipo: 'alerta' | 'feito', texto }.
const recado = ref({ tipo: '', texto: '' });
const falta = ref('');
// O que o "Criar o funil" tem a dizer, no cartão do funil.
const recadoDoFunil = ref({ tipo: '', texto: '' });
const dialogoDeSair = useTemplateRef('dialogoDeSair');
// Para onde a pessoa ia quando a tela perguntou "Sair sem salvar?".
const saidaPendente = ref(null);
let saiSemSalvar = false;

const pronto = computed(() => tela.estado.value === ESTADOS.PRONTO);
// Na demonstração tudo aparece, como na lista e na ficha.
const podeMudar = computed(
  () => (fonte.usaDemo || podeAjustar.value) && !conta.value?.semPermissao
);
const temFunis = computed(() => Boolean(conta.value?.funis?.length));
const funilCriado = computed(() =>
  recadoDoFunil.value.tipo === 'feito' ? recadoDoFunil.value.texto : ''
);
const podeCriarFunil = computed(
  () => !fonte.usaDemo && funilNovo.podeCriar.value
);
// A conta já escolheu, e o funil escolhido ainda serve.
const temFunilQueServe = computed(
  () => tela.jaEscolheu.value && !tela.funilParou.value
);
// O cartão das mensagens só é montado quando o servidor manda a escolha.
const comMensagens = computed(() => temMensagens(rascunho.value));
// O da cotação, quando a chave dela está ligada na conta.
const comCotacao = computed(() => Boolean(conta.value?.cotacaoLiberada));

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

// A escolha de hoje, para quem só lê. O funil que parou vem antes: a pessoa
// precisa saber que as renovações não estão aparecendo.
const escolhaDeHoje = computed(() => {
  if (tela.funilParou.value) return ta(`HOJE_PAROU.${tela.funilParou.value}`);
  const escolha = ondeFicam(conta.value.funis, rascunho.value);
  const { dias } = rascunho.value;
  return escolha
    ? ta('HOJE', { ...escolha, count: dias }, dias)
    : ta('HOJE_SEM_FUNIL');
});

const SEM_RECADO = Object.freeze({ tipo: '', texto: '' });
// Mexer em qualquer escolha, ou salvar, tira também o recado do funil criado.
const semRecado = () => {
  recado.value = SEM_RECADO;
  recadoDoFunil.value = SEM_RECADO;
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
  if (falta.value === FALTAS.CAIXA) {
    cotacao.value?.focar();
    return;
  }
  onde.value?.focar(falta.value);
};

// O funil ou a etapa que o servidor recusou já não existe (ou o WhatsApp, ou o
// Agente de Cotação, ou a própria cotação, que foi desligada): a tela relê o
// que a conta tem, e o aviso continua dizendo o que fazer.
const CONTA_MUDOU = [
  'funil_desconhecido',
  'etapa_de_outro_funil',
  'caixa_invalida',
  'caixa_distribui',
  'sem_agente_de_cotacao',
  'cotacao_desligada',
];

// Um pedido por vez: o segundo clique, com o primeiro ainda a caminho, não
// manda outro pedido nem troca o "Ajustes salvos." por um alerta.
// Devolve se guardou.
const salvar = async () => {
  if (tela.salvando.value) return false;
  falta.value = faltaNosAjustes(rascunho.value, conta.value.funis);
  if (falta.value) {
    alertar(ta(`FALTA.${falta.value}`));
    focarOQueFalta();
    return false;
  }
  if (!tela.mudou.value) {
    alertar(ta('NADA_MUDOU'));
    return false;
  }
  if (await tela.salvar()) {
    recadoDoFunil.value = SEM_RECADO;
    recado.value = { tipo: 'feito', texto: ta('SALVO') };
    return true;
  }
  const codigo = tela.recusa.value;
  alertar(
    t(chaveDaRecusa(codigo, 'RELACIONAMENTOS_CARTEIRA.AJUSTES.ERRO_SALVAR'))
  );
  if (CONTA_MUDOU.includes(codigo)) tela.carregar();
  return false;
};

// Criou: o funil e a primeira etapa ficam escolhidos, e o foco vai ao funil
// (o leitor de tela ouve qual é). Se a releitura dos funis falha depois de
// criar, a tela recarrega e o funil novo aparece na lista para escolher.
// O recado diz se ficou faltando alguma etapa (`incompleto`).
const escolherOFunilCriado = async (funil, incompleto = false) => {
  try {
    await tela.escolherFunilNovo(funil.id);
  } catch {
    tela.carregar();
    return;
  }
  semRecado();
  recadoDoFunil.value = incompleto
    ? {
        tipo: 'alerta',
        texto: ta('ONDE.FUNIL_INCOMPLETO', { funil: funil.name }),
      }
    : {
        tipo: 'feito',
        texto: ta('ONDE.FUNIL_CRIADO', { funil: funil.name }),
      };
  await nextTick();
  onde.value?.focar(FALTAS.FUNIL);
};
// Não criou: o recado diz para tentar de novo, e a tela relê o que a conta tem
// (o funil pode ter nascido sem uma parte das etapas).
const criarFunil = async () => {
  if (funilNovo.criando.value) return;
  recadoDoFunil.value = SEM_RECADO;
  let funil;
  try {
    funil = await funilNovo.criar();
  } catch (falha) {
    if (falha?.name === FUNIL_INCOMPLETO) {
      await escolherOFunilCriado(falha.funil, true);
      return;
    }
    recadoDoFunil.value = {
      tipo: 'alerta',
      texto: ta('ONDE.ERRO_CRIAR_FUNIL'),
    };
    tela.carregar();
    return;
  }
  await escolherOFunilCriado(funil);
};

const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: ABA_SEGUROS } });
const abrirCrm = () => router.push({ name: 'crm_kanban_index' });

const temAlgoSemSalvar = () =>
  pronto.value && podeMudar.value && tela.mudou.value;
onBeforeRouteLeave(destino => {
  if (saiSemSalvar || !temAlgoSemSalvar()) return true;
  saidaPendente.value = destino;
  dialogoDeSair.value?.abrir();
  return false;
});
const seguirSaida = () => {
  const destino = saidaPendente.value;
  saidaPendente.value = null;
  dialogoDeSair.value?.fechar();
  if (destino) router.push(destino);
};
const sairSemSalvar = () => {
  saiSemSalvar = true;
  seguirSaida();
};
// Salvou: segue para onde ia. Não salvou: a pergunta fecha e o rodapé diz o
// que falta ou o que houve, como no Salvar de sempre.
const salvarESair = async () => {
  if (await salvar()) {
    seguirSaida();
    return;
  }
  saidaPendente.value = null;
  dialogoDeSair.value?.fechar();
};

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
            {{ ta(temFunilQueServe ? 'APOIO' : 'APOIO_SEM_FUNIL') }}
          </p>
        </div>

        <EsqueletoDeLista
          v-if="tela.estado.value === ESTADOS.CARREGANDO"
          :linhas="6"
          data-carteira="carregando"
        />
        <div
          v-else-if="tela.estado.value === ESTADOS.SEM_ACESSO"
          data-carteira="ajustes-sem-acesso"
        >
          <VazioComUmBotao
            :frase="ta('SEM_ACESSO')"
            :botao="ta('VOLTAR_ROTULO')"
            @acao="voltar"
          />
        </div>
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
            <Banner
              v-if="tela.funilParou.value"
              color="amber"
              role="alert"
              data-carteira="funil-parou"
              :data-estado="tela.funilParou.value"
            >
              {{ ta(`PAROU.${tela.funilParou.value}`) }}
            </Banner>
            <OndeFicamAsRenovacoes
              ref="onde"
              :model-value="rascunho"
              :funis="conta.funis"
              :falta="falta"
              :id-do-aviso="`${id}-recado`"
              :pode-criar="podeCriarFunil"
              :criando="funilNovo.criando.value"
              @update:model-value="mudar"
              @abrir-crm="abrirCrm"
              @criar-funil="criarFunil"
            />
            <!-- A região viva nasce vazia (é assim que o leitor de tela anuncia
                 o texto que chega) e não ocupa lugar; o recado à vista vem à
                 parte. -->
            <AvisoVivo :texto="funilCriado" />
            <p
              v-if="funilCriado"
              data-carteira="funil-criado"
              class="m-0 text-base font-medium text-n-teal-11"
            >
              {{ funilCriado }}
            </p>
            <p
              v-if="recadoDoFunil.tipo === 'alerta'"
              data-carteira="funil-nao-criado"
              role="alert"
              class="m-0 text-base font-medium text-n-ruby-11"
            >
              {{ recadoDoFunil.texto }}
            </p>
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

            <CartaoDeAjuste
              v-if="comCotacao"
              marca="ajuste-cotacao"
              :titulo="ta('COTACAO.TITULO')"
            >
              <CotacaoDaRenovacao
                ref="cotacao"
                :model-value="rascunho"
                :conta="conta"
                :consumo="tela.consumo.value"
                :falta="falta"
                :id-do-aviso="`${id}-recado`"
                @update:model-value="mudar"
              />
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
    <DialogoDeConfirmacao
      ref="dialogoDeSair"
      marca="sair-dos-ajustes"
      tipo="edit"
      :titulo="ta('SAIR.TITULO')"
      :aviso="ta('SAIR.AVISO')"
      :confirmar="ta('SAIR.SALVAR')"
      :voltar="ta('SAIR.SAIR')"
      :ocupado="tela.salvando.value"
      @confirmar="salvarESair"
      @fechou="saidaPendente = null"
    >
      <template #rodape>
        <div class="flex flex-col-reverse w-full gap-3 sm:flex-row">
          <Button
            slate
            faded
            type="button"
            class="w-full"
            data-carteira="sair-sem-salvar"
            :label="ta('SAIR.SAIR')"
            @click="sairSemSalvar"
          />
          <Button
            type="button"
            class="w-full"
            data-carteira="salvar-e-sair"
            :is-loading="tela.salvando.value"
            :label="ta('SAIR.SALVAR')"
            @click="salvarESair"
          />
        </div>
      </template>
    </DialogoDeConfirmacao>
  </section>
</template>
