<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import BlocoDoPainel from 'dashboard/components-next/painel-do-contato/BlocoDoPainel.vue';
import EsqueletoOuErro from 'dashboard/components-next/painel-do-contato/EsqueletoOuErro.vue';
import { ESTADO } from 'dashboard/components-next/painel-do-contato/useParteDoPainel';
import { carteiraFonteReal } from '../../fonte/carteiraFonteReal';
import {
  ESTADOS_DOS_SEGUROS as ESTADOS,
  useSegurosDe,
} from '../../carteira/useSegurosDe';
import { leituraDePdf } from '../../carteira/leituraDePdf';
import { useVerPdf } from '../../carteira/useVerPdf';
import EntradaDeFora from './EntradaDeFora.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import LinhaDoSeguroNoPainel from './LinhaDoSeguroNoPainel.vue';

// #2897 — os seguros de quem está na conversa, no painel do contato: quem
// atende vê o que a pessoa tem com a corretora sem sair do chat. Só é montada
// na conta que tem a carteira e para quem pode ver contatos
// (carteira/segurosNoPainel.js); lê sempre do servidor.
//
// A peça é curta e segue a regra dos blocos do painel: sem conteúdo, não
// aparece. Pessoa sem seguro não ganha bloco nem frase (a maior parte das
// conversas de uma corretora é com quem ainda não é cliente), e enquanto a
// leitura não chega nada é desenhado, para o painel não piscar. Quem não pode
// ver os seguros também não vê nada. Só a leitura que falhou aparece, com
// "Tentar de novo".
//
// Aqui é leitura: os três seguros mais urgentes (o servidor já manda em ordem),
// "Ver PDF" e a gaveta do seguro por cima da conversa, sem botão de mudar nada.
// Corrigir, cancelar e guardar o PDF ficam na ficha: "Ver na ficha" leva à
// pessoa, e o nome do segurado, dentro da gaveta, leva à ficha dele já com
// este seguro aberto.
//
// #2899 (E6.5) — a única escrita daqui: "Guardar seguro de outra corretora",
// na conta que lê PDF e para quem pode editar a pessoa. Aí o bloco aparece
// mesmo sem seguro nenhum (quem ainda não é cliente costuma ter o seguro em
// outro lugar). Quem decide se pode é o servidor: a entrada só aparece depois
// que a lista de PDFs da conversa respondeu (ela pede poder editar a pessoa e a
// leitura liberada); sem isso, o painel fica como era.
const props = defineProps({
  contactId: { type: [Number, String], default: null },
});

const A_VISTA = 3;

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.PAINEL.${chave}`, valores);
const router = useRouter();
const fonte = carteiraFonteReal();
const verPdfDe = useVerPdf(fonte);
const lista = useSegurosDe(() => fonte.daPessoa(props.contactId));

const apoliceAberta = ref(null);
const todosAVista = ref(false);
// A conta lê PDF (perguntado uma vez) e quem atende pode guardar o seguro de
// outra corretora desta pessoa (perguntado a cada pessoa).
let lePdf = null;
const guardaDeFora = ref(false);

const comErro = computed(() => lista.estado.value === ESTADOS.ERRO);
const seguros = computed(() =>
  lista.estado.value === ESTADOS.PRONTO ? lista.seguros.value : []
);
const visivel = computed(
  () =>
    Boolean(props.contactId) &&
    (comErro.value || seguros.value.length > 0 || guardaDeFora.value)
);
const nomeDaPessoa = computed(() => seguros.value[0]?.pessoa?.name || '');
const outros = computed(() => seguros.value.length - A_VISTA);
const naTela = computed(() =>
  todosAVista.value ? seguros.value : seguros.value.slice(0, A_VISTA)
);

const verPdf = async seguro => {
  const naoAbriu = await verPdfDe(seguro.id);
  if (!naoAbriu) return;
  useAlert(naoAbriu);
  lista.atualizar();
};

const fichaDaPessoa = contactId => ({
  name: 'relacionamentos_pessoa',
  params: { contactId },
});
const fichaDaEmpresa = companyId => ({
  name: 'relacionamentos_empresa',
  params: { companyId },
});
const verNaFicha = () => router.push(fichaDaPessoa(props.contactId));
// Na ficha a gaveta mora no endereço (`?apolice=`): ela abre no mesmo seguro.
const abrirSegurado = ({ tipo, id }) =>
  router.push({
    ...(tipo === 'empresa' ? fichaDaEmpresa(id) : fichaDaPessoa(id)),
    query: { apolice: String(apoliceAberta.value) },
  });

const perguntarSeGuardaDeFora = async id => {
  guardaDeFora.value = false;
  lePdf = lePdf ?? leituraDePdf({ fonte });
  if (!(await lePdf)) return;
  try {
    await fonte.arquivosDeFora(id);
    guardaDeFora.value = id === props.contactId;
  } catch {
    guardaDeFora.value = false;
  }
};

// Outra conversa, outra pessoa: o que estava aberto era da anterior.
watch(
  () => props.contactId,
  id => {
    apoliceAberta.value = null;
    todosAVista.value = false;
    if (!id) return;
    lista.carregar();
    perguntarSeGuardaDeFora(id);
  },
  { immediate: true }
);
</script>

<template>
  <BlocoDoPainel
    v-if="visivel"
    data-carteira="painel-seguros"
    :titulo="tp('TITULO')"
  >
    <EsqueletoOuErro
      v-if="comErro"
      :estado="ESTADO.ERRO"
      @tentar="lista.carregar"
    />
    <template v-else>
      <ul v-if="naTela.length" class="flex flex-col gap-2 p-0 m-0 list-none">
        <LinhaDoSeguroNoPainel
          v-for="seguro in naTela"
          :key="seguro.id"
          :seguro="seguro"
          @abrir="apoliceAberta = $event.id"
          @pdf="verPdf"
        />
      </ul>
      <div class="flex flex-col items-start">
        <Button
          v-if="outros > 0"
          variant="link"
          color="blue"
          size="sm"
          class="min-h-11"
          data-carteira="painel-ver-outros"
          :aria-expanded="todosAVista"
          :label="
            todosAVista ? tp('MOSTRAR_MENOS') : tp('VER_OS_OUTROS', outros)
          "
          @click="todosAVista = !todosAVista"
        />
        <Button
          v-if="seguros.length"
          variant="link"
          color="blue"
          size="sm"
          class="min-h-11"
          data-carteira="painel-ver-ficha"
          :label="tp('VER_NA_FICHA')"
          @click="verNaFicha"
        />
        <EntradaDeFora
          v-if="guardaDeFora"
          :pessoa-id="Number(contactId)"
          :fonte="fonte"
          :nome="nomeDaPessoa"
          marca="painel-guardar-de-fora"
          @mudou="lista.atualizar"
        />
      </div>
    </template>
  </BlocoDoPainel>
  <GavetaDoSeguro
    :apolice-id="apoliceAberta"
    :fonte="fonte"
    @fechar="apoliceAberta = null"
    @mudou="lista.atualizar"
    @abrir-segurado="abrirSegurado"
  />
</template>
