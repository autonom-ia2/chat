<script setup>
import { nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import LinkDeVolta from 'dashboard/routes/dashboard/relacionamentos/components/ficha/LinkDeVolta.vue';
import MontarCupom from '../components/cupons/MontarCupom.vue';
import { cupomNovo } from '../regras';
import { salvarCupom } from '../fonte';
import { esquecerCuponsDaConta } from '../cuponsDaConta';
import { F } from '../useTextosDaFidelidade';

// #3100 — criar um cupom (rota fidelidade_cupom_novo, só para quem pode mudar
// o cartão). Começa pelo que serve à maioria (cupomNovo: 10% de desconto,
// vale 15 dias). Criar volta para a aba Cupons com o aviso de que deu certo;
// lá, "Mandar este cupom" abre a automação pronta. Cancelar (ou "‹ Fidelidade"
// no topo) volta sem gravar.
const { t } = useI18n();
const router = useRouter();

const rascunho = ref(cupomNovo());
const salvando = ref(false);
const raiz = ref(null);
const agora = Date.now();

const voltar = () =>
  router.push({ name: 'fidelidade_index', query: { aba: 'cupons' } });

const salvar = async () => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    await salvarCupom(rascunho.value);
    esquecerCuponsDaConta();
    useAlert(t(`${F}.PAGINA.CUPOM_CRIADO`));
    voltar();
  } catch {
    useAlert(t(`${F}.PAGINA.ERRO_SALVAR_CUPOM`));
  } finally {
    salvando.value = false;
  }
};

onMounted(async () => {
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
});
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 bg-n-surface-1"
    data-fidelidade="pagina-montar-cupom"
  >
    <main class="flex-1 min-w-0 overflow-y-auto">
      <div
        ref="raiz"
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <LinkDeVolta
          :texto="t(`${F}.PAGINA.VOLTAR`)"
          :rotulo="t(`${F}.PAGINA.VOLTAR_ROTULO`)"
          class="-mb-4"
          @voltar="voltar"
        />
        <MontarCupom
          v-model="rascunho"
          :salvando="salvando"
          :agora="agora"
          @salvar="salvar"
          @cancelar="voltar"
        />
      </div>
    </main>
  </section>
</template>
