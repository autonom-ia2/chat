<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharHeroi from '../components/AcharHeroi.vue';
import AcharOndeCampo from '../components/AcharOndeCampo.vue';
import AcharLinhaFrase from '../components/AcharLinhaFrase.vue';
import AcharBuscaCartao from '../components/AcharBuscaCartao.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharComoProcurarPainel from '../components/AcharComoProcurarPainel.vue';
import AcharMaisAjustesPainel from '../components/AcharMaisAjustesPainel.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { fatoDaBusca } from '../utils/acharQuando';
import { ROTAS } from '../utils/acharRotas';

// #2692 — T0, a porta (v4): "O quê?" e "Onde?", a linha-frase "Como vamos
// procurar" com "Alterar" e um botão. Com uma sugestão de lugar só, ela vale
// sozinha; com várias, a lista ganha borda azul e a primeira fica marcada.
// Rodada 2: o botão diz sempre "Achar empresas"; o que falta (um por vez) vai
// numa linha acima dele, no rodapé, e o botão fica desligado até resolver.
const { t } = useI18n();
const { demo, papel, fonte, permissoes, irPara } = useAcharTela();

const NS = 'PROSPECTING_ACHAR.PORTA';
const IDEIAS = ['RESTAURANTES', 'ESCRITORIOS', 'ACADEMIAS'];
const MIN_LETRAS = 3;

const oQue = ref('');
const ondeTexto = ref('');
const lugar = ref(null);
const sugestoes = ref([]);
const procurando = ref(false);
const naoAchou = ref(false);
const congelado = ref(false);
const como = ref({ km: 3, quais: 'todas', n: 20, primeiro: 'melhores' });
// Qual painel está aberto por cima: "Como procurar" (como) ou "Mais ajustes".
const painel = ref(null);
const modelos = ref([]);
const ocupado = ref(false);
const erro = ref(false);
const ultimas = ref([]);
// A gestora vê as últimas da equipe; os outros, só as próprias (rodada 3).
const daEquipe = computed(() => papel.value === 'gestora');
const ultimasDoPapel = computed(() =>
  (daEquipe.value
    ? ultimas.value
    : ultimas.value.filter(b => !b.feitaPor)
  ).slice(0, 3)
);
const googlePronto = ref(true);
const emTeste = ref(false);
const ondeCampo = ref(null);

const escolherLugar = async sugestao => {
  sugestoes.value = [];
  naoAchou.value = false;
  try {
    lugar.value = await fonte.value.detalheDoLugar(sugestao);
  } catch {
    lugar.value = sugestao;
  }
};

const procurarLugares = useDebounceFn(async texto => {
  if (lugar.value || congelado.value) return;
  if (texto.trim().length < MIN_LETRAS) {
    sugestoes.value = [];
    naoAchou.value = false;
    procurando.value = false;
    return;
  }
  procurando.value = true;
  try {
    const achados = await fonte.value.sugestoesDeLugar(texto.trim());
    if (texto !== ondeTexto.value) return;
    sugestoes.value = achados;
    naoAchou.value = achados.length === 0;
    if (achados.length === 1) await escolherLugar(achados[0]);
  } catch {
    sugestoes.value = [];
    naoAchou.value = true;
  } finally {
    procurando.value = false;
  }
}, 300);

watch(ondeTexto, texto => {
  if (!congelado.value) procurarLugares(texto);
});

const alterarLugar = () => {
  lugar.value = null;
  ondeTexto.value = '';
  sugestoes.value = [];
};

const falta = computed(() => {
  if (!oQue.value.trim()) return 'O_QUE';
  if (lugar.value) return null;
  if (!ondeTexto.value.trim()) return 'ONDE';
  if (procurando.value) return 'PROCURANDO';
  if (sugestoes.value.length > 1) return 'TOCAR';
  return 'EXISTA';
});

const rotuloDoBotao = computed(() =>
  ocupado.value ? t(`${NS}.BOTAO_OCUPADO`) : t(`${NS}.BOTAO`)
);
// Rodada 3: quando o próprio campo já avisa (procurando ou lugar não achado),
// o rodapé só mostra o botão desligado, sem repetir.
const dica = computed(() => {
  if (!falta.value || ocupado.value) return '';
  if (['PROCURANDO', 'EXISTA'].includes(falta.value)) return '';
  return t(`${NS}.FALTA.${falta.value}`);
});

// Rodada 4: o resumo repete a opção de "Quem vem primeiro" ou o modelo.
// Rodada 5: a ordem é escolhida em "Mais ajustes"; o modelo, em "Como procurar".
const quaisTexto = computed(() => {
  const modelo = modelos.value.find(item => item.id === como.value.quais);
  if (modelo) return modelo.nome;
  return t(
    `${NS}.COMO.${como.value.primeiro === 'pouco' ? 'POUCO' : 'MELHORES'}`
  );
});
const ideiaEscolhida = ideia =>
  oQue.value.trim() === t(`${NS}.IDEIAS.${ideia}`);

const achar = async () => {
  if (falta.value === 'TOCAR') {
    ondeCampo.value?.focarPrimeira();
    return;
  }
  if (falta.value || ocupado.value) return;
  ocupado.value = true;
  erro.value = false;
  try {
    const { searchId } = await fonte.value.criarBusca({
      oQue: oQue.value,
      lugar: lugar.value,
      como: como.value,
    });
    await irPara(ROTAS.BUSCA, { params: { searchId }, estado: 'buscando' });
  } catch {
    erro.value = true;
  } finally {
    ocupado.value = false;
  }
};

const salvarComo = novo => {
  como.value = { ...como.value, ...novo };
  painel.value = null;
};
const aplicarAjustes = ajustes => {
  como.value = { ...como.value, ajustes, primeiro: ajustes.primeiro };
  painel.value = null;
};

const abrirBusca = busca =>
  irPara(ROTAS.BUSCA, { params: { searchId: busca.id }, estado: 'confira' });

const falarComSuporte = () => window.$chatwoot?.toggle?.('open');

const preencher = ({ dados, preenchido = { usarSalvo: true } }) => {
  congelado.value = Boolean(preenchido.procurando);
  oQue.value = preenchido.oQue || '';
  lugar.value = preenchido.usarSalvo ? dados.lugarSalvo : null;
  sugestoes.value = [];
  naoAchou.value = false;
  procurando.value = Boolean(preenchido.procurando);
  erro.value = Boolean(preenchido.erro);
  ondeTexto.value = preenchido.ondeTexto || '';
  painel.value = preenchido.painel || null;
  como.value = {
    ...como.value,
    n: dados.limite || como.value.n,
    primeiro: preenchido.primeiro || 'melhores',
  };
};

const carregar = async () => {
  try {
    const dados = await fonte.value.porta();
    ultimas.value = dados.ultimas;
    googlePronto.value = dados.googlePronto;
    emTeste.value = dados.emTeste;
    modelos.value = dados.modelos || [];
    preencher({ dados, preenchido: dados.preenchido });
  } catch {
    ultimas.value = [];
  }
};

onMounted(() => {
  if (!permissoes.value.buscar) {
    irPara(ROTAS.BUSCAS, { query: { aviso: 'so-ver' }, estado: 'buscas' });
    return;
  }
  carregar();
});
watch(demo, carregar);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-5xl gap-8 px-4 pt-6 mx-auto min-h-full md:px-8 md:pt-10"
        :class="googlePronto ? 'pb-0' : 'md:pb-10'"
      >
        <AcharEstado
          v-if="emTeste"
          faixa
          tom="aviso"
          :texto="$t(`${NS}.TESTE`)"
        />
        <AcharEstado v-if="erro" faixa tom="erro" :texto="$t(`${NS}.ERRO`)" />

        <AcharHeroi
          :titulo="$t(`${NS}.TITULO`)"
          :class="{ 'my-auto': !ultimasDoPapel.length }"
        >
          <div
            v-if="!googlePronto"
            class="flex flex-col items-start gap-4"
            data-sem-google
          >
            <p class="m-0 text-lg text-white/80">
              {{ $t(`${NS}.ONDE.SEM_GOOGLE`) }}
            </p>
            <Button
              :label="$t(`${NS}.ONDE.FALAR_SUPORTE`)"
              class="!min-h-12 !rounded-xl !px-6 !text-base"
              @click="falarComSuporte"
            />
          </div>
          <form
            v-else
            class="flex flex-col gap-5 p-4 bg-white shadow-2xl rounded-2xl text-n-slate-12 dark:bg-n-solid-1 md:p-6"
            data-cartao-porta
            @submit.prevent="achar"
          >
            <div class="grid grid-cols-1 gap-4 md:grid-cols-[2fr_3fr]">
              <div class="flex flex-col gap-1.5">
                <label
                  for="achar-o-que"
                  class="text-sm font-semibold text-n-slate-11"
                >
                  {{ $t(`${NS}.O_QUE.ROTULO`) }}
                </label>
                <input
                  id="achar-o-que"
                  v-model="oQue"
                  type="text"
                  autocomplete="off"
                  :placeholder="$t(`${NS}.O_QUE.PLACEHOLDER`)"
                  class="w-full !h-12 px-3 text-base border outline-none !mb-0 rounded-xl border-n-slate-6 bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-blue-9"
                  data-campo-o-que
                />
              </div>
              <AcharOndeCampo
                ref="ondeCampo"
                v-model:texto="ondeTexto"
                :lugar="lugar"
                :sugestoes="sugestoes"
                :procurando="procurando"
                :nao-achou="naoAchou"
                :destacar="falta === 'TOCAR'"
                @escolher="escolherLugar"
                @alterar="alterarLugar"
              />
            </div>
            <div
              role="group"
              :aria-label="$t(`${NS}.IDEIAS.ROTULO`)"
              class="flex flex-wrap gap-2"
            >
              <button
                v-for="ideia in IDEIAS"
                :key="ideia"
                type="button"
                :aria-pressed="ideiaEscolhida(ideia)"
                class="flex items-center gap-1.5 px-4 text-sm font-medium border border-solid rounded-full min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                :class="
                  ideiaEscolhida(ideia)
                    ? 'border-n-blue-8 bg-n-blue-3 text-n-blue-11'
                    : 'border-n-slate-6 bg-n-slate-2 text-n-slate-12 hover:border-n-slate-8'
                "
                data-ideia
                @click="oQue = $t(`${NS}.IDEIAS.${ideia}`)"
              >
                <span
                  v-if="ideiaEscolhida(ideia)"
                  class="i-lucide-check size-4"
                  aria-hidden="true"
                />
                {{ $t(`${NS}.IDEIAS.${ideia}`) }}
              </button>
            </div>
            <AcharLinhaFrase
              icone="i-lucide-compass"
              tom="violeta"
              :rotulo="$t(`${NS}.COMO.ROTULO`)"
              :texto="
                $t(`${NS}.COMO.TEXTO`, {
                  km: como.km,
                  n: como.n,
                  quais: quaisTexto,
                })
              "
              pode-alterar
              alterar-embaixo
              @alterar="painel = 'como'"
            />
          </form>
        </AcharHeroi>

        <section
          v-if="ultimasDoPapel.length && googlePronto"
          class="flex flex-col gap-4"
          data-ultimas
        >
          <div class="flex items-center justify-between gap-3">
            <h2 class="m-0 text-lg font-semibold text-n-slate-12">
              {{
                daEquipe
                  ? $t(`${NS}.ULTIMAS.TITULO_EQUIPE`)
                  : $t(`${NS}.ULTIMAS.TITULO`)
              }}
            </h2>
            <Button
              :label="$t(`${NS}.ULTIMAS.VER_TODAS`)"
              variant="link"
              class="!min-h-11"
              @click="
                irPara(ROTAS.BUSCAS, {
                  estado: daEquipe ? 'buscas-equipe' : 'buscas',
                })
              "
            />
          </div>
          <ul class="grid gap-3 p-0 m-0 list-none md:grid-cols-3">
            <AcharBuscaCartao
              v-for="busca in ultimasDoPapel"
              :key="busca.id"
              compacto
              :titulo="`${busca.oQue} · ${busca.lugar}`"
              :fato="fatoDaBusca($t, busca)"
              :feita-por="
                daEquipe
                  ? $t('PROSPECTING_ACHAR.BUSCAS.FEITA_POR', {
                      pessoa:
                        busca.feitaPor || $t('PROSPECTING_ACHAR.COMUM.VOCE'),
                    })
                  : ''
              "
              @abrir="abrirBusca(busca)"
            />
          </ul>
        </section>

        <AcharRodape
          v-if="googlePronto"
          :rotulo="rotuloDoBotao"
          :dica="dica"
          :desabilitado="Boolean(falta)"
          :ocupado="ocupado"
          icone="i-lucide-search"
          @principal="achar"
        />
        <AcharFaixaDoMenu v-if="!googlePronto" />
      </div>
    </main>
    <AcharComoProcurarPainel
      v-if="painel === 'como'"
      :como="como"
      :modelos="modelos"
      @salvar="salvarComo"
      @mais-ajustes="painel = 'mais'"
      @close="painel = null"
    />
    <AcharMaisAjustesPainel
      v-if="painel === 'mais'"
      :primeiro="como.primeiro"
      :abrir-primeiro="Boolean(demo)"
      @aplicar="aplicarAjustes"
      @close="painel = 'como'"
    />
  </section>
</template>
