<script setup>
import { nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ErroComTentarDeNovo from 'dashboard/routes/dashboard/relacionamentos/components/comum/ErroComTentarDeNovo.vue';
import LinkDeVolta from 'dashboard/routes/dashboard/relacionamentos/components/ficha/LinkDeVolta.vue';
import MontarPrograma from '../components/MontarPrograma.vue';
import ProgramaPronto from '../components/ProgramaPronto.vue';
import { programaNovo } from '../regras';
import { lerPrograma, salvarPrograma } from '../fonte';
import { esquecerProgramaDaConta } from '../programaDaConta';
import { RECEITA_DO_AVISO } from '../../automacoes/livre/passosNovos/fidelidadeNaAutomacao';
import { F } from '../useTextosDaFidelidade';

// #3100 — criar ou mudar o cartão fidelidade da conta (rota fidelidade_montar,
// só para quem pode mudar). Sem cartão, começa pelo que serve à maioria
// (programaNovo); com cartão, pelas regras de hoje. Criar leva ao "Pronto!",
// com os dois avisos prontos pelo WhatsApp: cada um abre a automação já
// montada e desligada (?receita=…) em outra aba, para o outro aviso continuar
// à mão nesta; "Agora não" volta para o painel. Mudar as regras volta para o
// painel com o aviso de que mudou. "‹ Fidelidade" no topo volta sem gravar.
const { t } = useI18n();
const router = useRouter();

const carregando = ref(true);
const falhou = ref(false);
const novo = ref(true);
const rascunho = ref(programaNovo());
const salvando = ref(false);
const criado = ref(null);
const raiz = ref(null);

const focarTitulo = async () => {
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
};

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    const deHoje = await lerPrograma();
    novo.value = !deHoje;
    rascunho.value = deHoje ? { ...deHoje } : programaNovo();
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
  focarTitulo();
};

const voltar = () => router.push({ name: 'fidelidade_index' });

const salvar = async () => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    const gravado = await salvarPrograma(rascunho.value);
    esquecerProgramaDaConta();
    if (novo.value) {
      criado.value = gravado;
      focarTitulo();
      return;
    }
    useAlert(t(`${F}.PAGINA.SALVO`));
    voltar();
  } catch {
    useAlert(t(`${F}.PAGINA.ERRO_SALVAR`));
  } finally {
    salvando.value = false;
  }
};

// "Usar o aviso": a automação nova já com a receita do aviso, desligada, em
// outra aba (o ProgramaPronto marca o aviso como aberto).
const usarAviso = aviso => {
  const { href } = router.resolve({
    name: 'automacoes_livre_nova',
    query: { receita: RECEITA_DO_AVISO[aviso], unidade: criado.value.tipo },
  });
  window.open(href, '_blank');
};

onMounted(carregar);
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 bg-n-surface-1"
    data-fidelidade="pagina-montar"
  >
    <main class="flex-1 min-w-0 overflow-y-auto">
      <div
        ref="raiz"
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <LinkDeVolta
          v-if="!criado"
          :texto="t(`${F}.PAGINA.VOLTAR`)"
          :rotulo="t(`${F}.PAGINA.VOLTAR_ROTULO`)"
          class="-mb-4"
          @voltar="voltar"
        />
        <div
          v-if="carregando"
          data-fidelidade="carregando"
          aria-busy="true"
          class="h-96 rounded-3xl bg-n-alpha-2 animate-pulse"
        />
        <ErroComTentarDeNovo
          v-else-if="falhou"
          :mensagem="t(`${F}.PAGINA.ERRO`)"
          @tentar="carregar"
        />
        <ProgramaPronto
          v-else-if="criado"
          :programa="criado"
          @usar="usarAviso"
          @depois="voltar"
        />
        <MontarPrograma
          v-else
          v-model="rascunho"
          :novo="novo"
          :salvando="salvando"
          @salvar="salvar"
          @cancelar="voltar"
        />
      </div>
    </main>
  </section>
</template>
