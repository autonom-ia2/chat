<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharFaixaDoMenu from '../components/AcharFaixaDoMenu.vue';
import AcharLinhaFrase from '../components/AcharLinhaFrase.vue';
import AcharMotivos from '../components/AcharMotivos.vue';
import AcharParaOndePainel from '../components/AcharParaOndePainel.vue';
import AcharComQuemFica from '../components/AcharComQuemFica.vue';
import AcharEmpresaGaveta from '../components/AcharEmpresaGaveta.vue';
import ParaChamarCartao from '../components/ParaChamarCartao.vue';
import ParaChamarFim from '../components/ParaChamarFim.vue';
import AcharBarra from '../components/AcharBarra.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { useDonoDaLista } from '../composables/useDonoDaLista';
import { useFilaParaChamar } from '../composables/useFilaParaChamar';
import { ROTAS } from '../utils/acharRotas';

// #2692 — T5, a fila "Para chamar" (v4, fase 5): uma empresa por vez, sem
// pensar em busca. Um botão principal no rodapé ("Mandar para o funil"); depois
// de mandar, o principal vira "Chamar no WhatsApp" (ou "Ligar") e o link
// "Próxima empresa" anda. "Não serve" pede um dos 4 motivos e a fila anda;
// "Depois" volta amanhã.
// Rodada 2: o aviso guarda a chave do texto (não o texto pronto), para nunca
// ficar na língua de antes de o idioma da conta carregar; "Ver mais sobre a
// empresa" abre a gaveta; o fim do dia sai da própria jornada.
// #2697 (F5): a fila vem do servidor (leads?view=queue) e as ações gravam; a
// lógica mora em useFilaParaChamar. Quem gere funis escolhe com quem a empresa
// fica ("Com quem fica", #2694).
const { t } = useI18n();
const {
  route,
  router,
  demo,
  fonte,
  permissoes,
  ajustes,
  carregarAjustes,
  irPara,
  mudarEstado,
  contaId,
  usuarioId,
} = useAcharTela();

const NS = 'PROSPECTING_ACHAR.FILA';

const destino = ref(null);
const painel = ref(null);
const gavetaAberta = ref(false);
const pode = computed(() => permissoes.value);

const { pessoas, pessoaId, pessoaNome, donoId } = useDonoDaLista({
  fonte,
  permissoes,
  destino,
});
const {
  carregando,
  erro,
  cartoes,
  indice,
  fase,
  mandando,
  aviso,
  foram,
  voltam,
  naoServem,
  funis,
  mandado,
  atual,
  temWhatsapp,
  andar,
  carregar,
  mandar,
  chamar,
  tirar,
  depois,
  desfazer,
} = useFilaParaChamar({
  demo,
  fonte,
  carregarAjustes,
  ajustes,
  contaId,
  usuarioId,
  destino,
  donoId,
  pessoaNome,
});

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
    !erro.value &&
    (fase.value === 'fim' ? cartoes.value.length > 0 : Boolean(atual.value))
);
const linhasDoRodape = computed(
  () => pode.value.funil && destino.value && fase.value === 'cartao'
);

const agir = () => {
  const acoes = {
    chamar: () => chamar(),
    mandar,
    destino: () => {
      painel.value = 'destino';
    },
  };
  acoes[principal.value.acao]();
};

const verFunil = () =>
  router.push({
    name: 'crm_kanban_index',
    params: { accountId: route.params.accountId },
    query: destino.value ? { pipeline_id: destino.value.funil.id } : {},
  });
const acharMais = () => irPara(ROTAS.PORTA, { estado: 'porta' });
const atualizar = () => (demo.value ? mudarEstado('fila') : carregar());
const salvarDestino = novo => {
  destino.value = novo;
  painel.value = null;
};
const salvarPessoa = id => {
  pessoaId.value = id;
  painel.value = null;
};

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
          role="status"
          :aria-label="$t(`${NS}.CARREGANDO`)"
          data-carregando
        />

        <AcharEstado
          v-else-if="erro"
          tom="erro"
          :texto="$t(`${NS}.ERRO`)"
          :botao="$t('PROSPECTING_ACHAR.COMUM.TENTAR_DE_NOVO')"
          data-erro-fila
          @acao="carregar"
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
            <div class="flex flex-col gap-1">
              <p class="m-0 text-xl font-semibold text-n-slate-12">
                {{
                  $t(`${NS}.MANDOU`, {
                    nome: atual.nome,
                    funil: destino?.funil.nome,
                  })
                }}
              </p>
              <p
                v-if="mandado?.etapa"
                class="m-0 text-base text-n-slate-11"
                data-etapa-e-dono
              >
                {{ $t(`${NS}.ETAPA_E_DONO`, mandado) }}
              </p>
            </div>
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
            <div v-if="linhasDoRodape" class="flex flex-col gap-1">
              <AcharLinhaFrase
                compacta
                icone="i-lucide-columns-3"
                :texto="$t(`${NS}.DESTINO`, { funil: destino.funil.nome })"
                pode-alterar
                @alterar="painel = 'destino'"
              />
              <AcharLinhaFrase
                v-if="pode.trocarDono"
                compacta
                icone="i-lucide-user-round"
                :texto="
                  $t('PROSPECTING_ACHAR.FOLHA.COM_QUEM', { pessoa: pessoaNome })
                "
                pode-alterar
                data-com-quem
                @alterar="painel = 'pessoa'"
              />
            </div>
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
      v-if="painel === 'destino'"
      :funis="funis"
      :destino="destino"
      @salvar="salvarDestino"
      @close="painel = null"
    />
    <AcharComQuemFica
      v-if="painel === 'pessoa'"
      :pessoas="pessoas"
      :escolhida="pessoaId"
      @salvar="salvarPessoa"
      @close="painel = null"
    />
  </section>
</template>
