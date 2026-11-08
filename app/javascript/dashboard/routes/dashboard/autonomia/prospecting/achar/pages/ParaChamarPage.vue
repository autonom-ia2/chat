<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import AcharLinhaFrase from '../components/AcharLinhaFrase.vue';
import AcharMotivos from '../components/AcharMotivos.vue';
import AcharParaOndePainel from '../components/AcharParaOndePainel.vue';
import AcharEmpresaGaveta from '../components/AcharEmpresaGaveta.vue';
import ParaChamarCartao from '../components/ParaChamarCartao.vue';
import ParaChamarFim from '../components/ParaChamarFim.vue';
import AcharBarra from '../components/AcharBarra.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { escolherDestino } from '../utils/destinoPronto';
import { ROTAS } from '../utils/acharRotas';

// #2692 — T5, a fila "Para chamar" (v4, fase 5): uma empresa por vez, sem
// pensar em busca. Um botão principal no rodapé ("Mandar para o funil"); depois
// de mandar, o principal vira "Chamar no WhatsApp" (ou "Ligar") e o link
// "Próxima empresa" anda. "Não serve" pede um dos 4 motivos e a fila anda;
// "Depois" volta amanhã. Fora da demonstração a fila vem vazia: ela pede o
// backend leads#index com view=queue (v4, PR 5a).
// Rodada 2: o aviso guarda a chave do texto (não o texto pronto), para nunca
// ficar na língua de antes de o idioma da conta carregar; "Ver mais sobre a
// empresa" abre a gaveta; o fim do dia sai da própria jornada.
const { t } = useI18n();
const { route, router, demo, fonte, permissoes, irPara, mudarEstado } =
  useAcharTela();

const NS = 'PROSPECTING_ACHAR.FILA';
const ESPERA = 500;

const carregando = ref(true);
const cartoes = ref([]);
const indice = ref(0);
const fase = ref('cartao');
const mandando = ref(false);
const aviso = ref(null);
const foram = ref(0);
const voltam = ref(0);
const naoServem = ref(0);
const funis = ref([]);
const destino = ref(null);
const painelDestino = ref(false);
const gavetaAberta = ref(false);

const estado = computed(() => demo.value || '');
const pode = computed(() => permissoes.value);
const atual = computed(() => cartoes.value[indice.value] || null);
const temWhatsapp = computed(() => atual.value?.whatsapp === 'tem');
const rotuloChamar = computed(() =>
  temWhatsapp.value
    ? t('PROSPECTING_ACHAR.COMUM.CHAMAR_WHATSAPP')
    : t('PROSPECTING_ACHAR.COMUM.LIGAR')
);
const principal = computed(() => {
  if (fase.value === 'sucesso' || !pode.value.funil) {
    return { rotulo: rotuloChamar.value, acao: 'chamar' };
  }
  if (!destino.value) {
    return {
      rotulo: t('PROSPECTING_ACHAR.FOLHA.ESCOLHA_FUNIL'),
      acao: 'destino',
    };
  }
  return {
    rotulo: mandando.value ? t(`${NS}.MANDANDO`) : t(`${NS}.MANDAR`),
    acao: 'mandar',
  };
});
// O cartão da fila tem menos campos que a lista; a gaveta completa o resto.
const empresaDaGaveta = computed(() => ({
  socios: [],
  cnpj: '',
  situacao: '',
  noFunil: null,
  fora: null,
  ...atual.value,
}));
const temRodape = computed(
  () =>
    !carregando.value &&
    (fase.value === 'fim' ? cartoes.value.length > 0 : Boolean(atual.value))
);

const ESTADOS = {
  'fila-sucesso': { fase: 'sucesso' },
  'fila-sucesso-ligar': { indice: 2, fase: 'sucesso' },
  'fila-nao-serve': { fase: 'nao-serve' },
  'fila-depois': { indice: 1, depois: true },
  'fila-procurando-dono': { indice: 3 },
  'fila-sem-dono': { indice: 2 },
  'fila-so-telefone': { indice: 2 },
  'fila-fim': { fase: 'fim' },
  'fila-fim-adiados': { fase: 'fim' },
};

const andar = () => {
  fase.value = 'cartao';
  if (indice.value + 1 >= cartoes.value.length) {
    fase.value = 'fim';
    return;
  }
  indice.value += 1;
};

const carregar = async () => {
  carregando.value = true;
  try {
    const [fila, lista] = await Promise.all([
      fonte.value.fila(),
      fonte.value.funis(),
    ]);
    cartoes.value = fila.cartoes;
    funis.value = lista;
    destino.value = escolherDestino({ funis: lista });
    const preset = ESTADOS[estado.value] || {};
    indice.value = preset.indice || 0;
    fase.value = preset.fase || 'cartao';
    foram.value = preset.fase === 'fim' ? fila.fim?.foramParaOFunil || 0 : 0;
    voltam.value = preset.fase === 'fim' ? fila.fim?.voltamAmanha || 0 : 0;
    naoServem.value = preset.fase === 'fim' ? fila.fim?.naoServem || 0 : 0;
    aviso.value = preset.depois
      ? {
          chave: `${NS}.DEPOIS_AVISO`,
          params: { nome: fila.cartoes[0]?.nome },
          desfazer: () => {
            indice.value -= 1;
          },
        }
      : null;
  } catch {
    cartoes.value = [];
  }
  carregando.value = false;
};

const mandar = async () => {
  if (mandando.value) return;
  mandando.value = true;
  await new Promise(resolve => {
    setTimeout(resolve, demo.value ? ESPERA : 0);
  });
  mandando.value = false;
  foram.value += 1;
  fase.value = 'sucesso';
};
const chamar = () => useAlert(t('PROSPECTING_ACHAR.COMUM.DEMO_WHATSAPP'));
const agir = () => {
  const acoes = {
    chamar,
    mandar,
    destino: () => {
      painelDestino.value = true;
    },
  };
  acoes[principal.value.acao]();
};

const tirar = () => {
  const voltar = indice.value;
  naoServem.value += 1;
  andar();
  aviso.value = {
    chave: `${NS}.SAIU`,
    desfazer: () => {
      naoServem.value -= 1;
      indice.value = voltar;
      fase.value = 'cartao';
    },
  };
};
const depois = () => {
  const voltar = indice.value;
  const nome = atual.value?.nome;
  voltam.value += 1;
  andar();
  aviso.value = {
    chave: `${NS}.DEPOIS_AVISO`,
    params: { nome },
    desfazer: () => {
      voltam.value -= 1;
      indice.value = voltar;
      fase.value = 'cartao';
    },
  };
};
const desfazer = () => {
  aviso.value?.desfazer();
  aviso.value = null;
};

const verFunil = () =>
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: route.params.accountId },
  });
const acharMais = () => irPara(ROTAS.PORTA, { estado: 'porta' });
const atualizar = () => (demo.value ? mudarEstado('fila') : carregar());

onMounted(carregar);
watch(demo, carregar);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-2xl gap-5 px-4 pt-6 mx-auto min-h-full md:px-8 md:pt-10"
        :class="temRodape ? 'pb-0' : 'md:pb-10'"
      >
        <header class="flex items-center justify-between gap-3">
          <h1
            class="m-0 text-2xl font-bold tracking-tight md:text-[2rem] text-n-slate-12"
          >
            {{ $t(`${NS}.TITULO`) }}
          </h1>
          <Button
            v-if="pode.buscar && cartoes.length && fase !== 'fim'"
            :label="$t(`${NS}.ACHAR_MAIS`)"
            icon="i-lucide-search"
            slate
            faded
            class="!min-h-12 !rounded-xl shrink-0"
            @click="acharMais"
          />
        </header>

        <div
          v-if="carregando"
          class="h-80 rounded-3xl bg-n-slate-3 animate-pulse"
        />

        <AcharEstado
          v-else-if="!cartoes.length"
          :texto="$t(`${NS}.VAZIA`)"
          :botao="
            pode.buscar
              ? $t('PROSPECTING_ACHAR.PORTA.BOTAO')
              : $t(`${NS}.ATUALIZAR`)
          "
          @acao="pode.buscar ? acharMais() : atualizar()"
        />

        <template v-else-if="fase === 'fim'">
          <ParaChamarFim
            :foram="foram"
            :voltam="voltam"
            :nao-servem="naoServem"
          />
          <AcharRodape
            :rotulo="
              pode.buscar
                ? $t('PROSPECTING_ACHAR.PORTA.BOTAO')
                : $t('PROSPECTING_ACHAR.BUSCAS.VER_FUNIL')
            "
            @principal="pode.buscar ? acharMais() : verFunil()"
          />
        </template>

        <template v-else-if="atual">
          <div class="flex flex-col gap-2">
            <span class="text-sm font-semibold tabular-nums text-n-slate-11">
              {{
                $t(`${NS}.CONTADOR`, {
                  atual: indice + 1,
                  total: cartoes.length,
                })
              }}
            </span>
            <AcharBarra
              :valor="indice + 1"
              :total="cartoes.length"
              :rotulo="
                $t(`${NS}.CONTADOR`, {
                  atual: indice + 1,
                  total: cartoes.length,
                })
              "
              tom="verde"
            />
          </div>

          <AcharEstado
            v-if="aviso"
            faixa
            tom="feito"
            :texto="$t(aviso.chave, aviso.params || {})"
            :botao="$t('PROSPECTING_ACHAR.COMUM.DESFAZER')"
            @acao="desfazer"
          />

          <section
            v-if="fase === 'nao-serve'"
            class="flex flex-col gap-4 p-5 border rounded-3xl border-n-weak bg-n-solid-1 md:p-8"
          >
            <AcharMotivos
              :titulo="$t(`${NS}.NAO_SERVE_TITULO`, { nome: atual.nome })"
              @escolher="tirar"
            />
          </section>

          <section
            v-else-if="fase === 'sucesso'"
            class="flex flex-col items-start gap-4 p-5 border rounded-3xl border-n-teal-6 bg-n-teal-2 motion-safe:transition md:p-8"
            role="status"
            data-sucesso-fila
          >
            <span
              class="grid text-white rounded-full size-12 place-items-center bg-n-teal-9"
              aria-hidden="true"
            >
              <span class="i-lucide-check size-7" />
            </span>
            <p class="m-0 text-xl font-semibold text-n-slate-12">
              {{
                $t('PROSPECTING_ACHAR.GAVETA.MANDOU', {
                  nome: atual.nome,
                  funil: destino?.funil.nome,
                  pessoa: $t('PROSPECTING_ACHAR.COMUM.VOCE'),
                })
              }}
            </p>
            <div class="flex flex-wrap gap-x-6">
              <Button
                :label="$t(`${NS}.PROXIMA`)"
                variant="link"
                trailing-icon
                icon="i-lucide-arrow-right"
                class="!min-h-11 !px-0"
                data-proxima
                @click="andar"
              />
              <Button
                :label="$t('PROSPECTING_ACHAR.COMUM.VER_NO_FUNIL')"
                variant="link"
                class="!min-h-11 !px-0"
                @click="verFunil"
              />
            </div>
          </section>

          <ParaChamarCartao
            v-else
            :empresa="atual"
            :primeiro="indice === 0"
            :achado-por="pode.verTodas ? atual.achadoPor : ''"
            :pode-decidir="pode.buscar"
            @nao-serve="fase = 'nao-serve'"
            @depois="depois"
            @ver-mais="gavetaAberta = true"
          />

          <Button
            v-if="fase === 'cartao' && !pode.funil"
            :label="$t(`${NS}.PROXIMA`)"
            variant="link"
            trailing-icon
            icon="i-lucide-arrow-right"
            class="self-start !min-h-11"
            @click="andar"
          />

          <AcharRodape
            v-if="fase === 'nao-serve'"
            :rotulo="$t('PROSPECTING_ACHAR.COMUM.VOLTAR')"
            icone="i-lucide-arrow-left"
            secundario
            @principal="fase = 'cartao'"
          />
          <AcharRodape
            v-else
            :rotulo="principal.rotulo"
            :ocupado="mandando"
            @principal="agir"
          >
            <AcharLinhaFrase
              v-if="pode.funil && destino && fase === 'cartao'"
              compacta
              icone="i-lucide-columns-3"
              :texto="$t(`${NS}.DESTINO`, { funil: destino.funil.nome })"
              pode-alterar
              @alterar="painelDestino = true"
            />
          </AcharRodape>
        </template>
        <AcharFaixaDoMenu v-if="!temRodape" />
      </div>
    </main>
    <AcharEmpresaGaveta
      v-if="gavetaAberta && atual"
      :empresa="empresaDaGaveta"
      :primeiro="indice === 0"
      leitura
      sem-rodape
      :pessoa="$t('PROSPECTING_ACHAR.COMUM.VOCE')"
      @close="gavetaAberta = false"
      @chamar="chamar"
    />
    <AcharParaOndePainel
      v-if="painelDestino"
      :funis="funis"
      :destino="destino"
      @salvar="(destino = $event), (painelDestino = false)"
      @close="painelDestino = false"
    />
  </section>
</template>
