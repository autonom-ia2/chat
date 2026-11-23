<script setup>
import { nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { FIDELIDADE_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import ErroComTentarDeNovo from 'dashboard/routes/dashboard/relacionamentos/components/comum/ErroComTentarDeNovo.vue';
import FidelidadeTela from '../components/FidelidadeTela.vue';
import { abaValida } from '../abas';
import {
  conferirCupom,
  cupomVencido,
  lerCupons,
  lerPrograma,
  lerResumo,
  ligarCupom,
  ligarPrograma,
  usarCodigo,
} from '../fonte';
import { esquecerCuponsDaConta } from '../cuponsDaConta';
import { RECEITA_DO_CUPOM } from '../../automacoes/livre/passosNovos/fidelidadeNaAutomacao';
import { F } from '../useTextosDaFidelidade';

// #3100 — a página Fidelidade (Crescer > Fidelidade): lê o cartão da conta e
// os números do painel e entrega à FidelidadeTela. Criar e "Mudar as regras"
// abrem a tela de montar; "Ver quem está perto do prêmio" abre a lista de
// Relacionamentos já filtrada (?fidelidade=perto); pausar e ligar de novo
// gravam na hora e dizem que deu certo. Quem só vê (fidelidade_view) lê o
// painel sem os botões de mudar (useCanManage). A aba Cupons lê o relatório
// ao abrir: "Novo cupom" abre a tela de criar; "Mandar este cupom" abre a
// automação pronta e desligada (?receita=FIDELIDADE_CUPOM&cupom=…); pausar e
// ligar de novo gravam na hora. O Conferir pergunta ao servidor se o código
// vale e "Marcar como usado" marca (repetir não gasta de novo).
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const podeMudar = useCanManage(FIDELIDADE_MANAGE_PERMISSION);

const carregando = ref(true);
const falhou = ref(false);
const programa = ref(null);
const resumo = ref(null);
const mudando = ref(false);
const raiz = ref(null);
const agora = Date.now();

const cupons = ref(null);
const conferencia = ref({});

const aba = ref(abaValida(route.query.aba));
const trocarAba = nova => {
  aba.value = abaValida(nova);
  router.replace({ query: { ...route.query, aba: aba.value } });
};

const carregar = async () => {
  carregando.value = true;
  falhou.value = false;
  try {
    programa.value = await lerPrograma();
    resumo.value = programa.value ? await lerResumo() : null;
  } catch {
    falhou.value = true;
  } finally {
    carregando.value = false;
  }
  await nextTick();
  raiz.value?.querySelector('[data-titulo-da-tela]')?.focus();
};

const carregarCupons = async () => {
  cupons.value = null;
  try {
    cupons.value = await lerCupons();
  } catch {
    cupons.value = [];
    useAlert(t(`${F}.PAGINA.ERRO_CUPONS`));
  }
};

const montar = () => router.push({ name: 'fidelidade_montar' });
const criarCupom = () => router.push({ name: 'fidelidade_cupom_novo' });
const mandarCupom = cupom =>
  router.push({
    name: 'automacoes_livre_nova',
    query: { receita: RECEITA_DO_CUPOM, cupom: cupom.id },
  });

const trocarCupom = async (cupom, ligado) => {
  try {
    const gravado = await ligarCupom(cupom.id, ligado);
    cupons.value = cupons.value.map(item =>
      item.id === gravado.id ? gravado : item
    );
    esquecerCuponsDaConta();
    useAlert(t(`${F}.PAGINA.${ligado ? 'CUPOM_LIGADO' : 'CUPOM_PAUSADO'}`));
  } catch {
    useAlert(t(`${F}.PAGINA.ERRO_LIGAR_CUPOM`));
  }
};

const conferir = async codigo => {
  conferencia.value = { codigo, conferindo: true };
  try {
    const resultado = await conferirCupom(codigo);
    conferencia.value = { codigo, resultado };
  } catch {
    conferencia.value = { codigo };
    useAlert(t(`${F}.PAGINA.ERRO_CONFERIR`));
  }
};

const usarCupom = async () => {
  const { resultado } = conferencia.value;
  if (!resultado?.id || conferencia.value.usando) return;
  conferencia.value = { ...conferencia.value, usando: true };
  try {
    await usarCodigo(resultado.id);
    conferencia.value = { ...conferencia.value, usando: false, usado: true };
    carregarCupons();
  } catch (falha) {
    conferencia.value = { ...conferencia.value, usando: false };
    useAlert(
      t(`${F}.PAGINA.${cupomVencido(falha) ? 'CUPOM_VENCEU' : 'ERRO_USAR'}`)
    );
  }
};
const verPerto = () =>
  router.push({ name: 'relationships_home', query: { fidelidade: 'perto' } });

const ligar = async ligado => {
  if (mudando.value) return;
  mudando.value = true;
  try {
    programa.value = await ligarPrograma(ligado);
    useAlert(t(`${F}.PAGINA.${ligado ? 'LIGADO' : 'PAUSADO'}`));
  } catch {
    useAlert(t(`${F}.PAGINA.ERRO_LIGAR`));
  } finally {
    mudando.value = false;
  }
};

watch(
  aba,
  nova => {
    if (nova === 'cupons' && cupons.value === null) carregarCupons();
  },
  { immediate: true }
);

onMounted(carregar);
</script>

<template>
  <section
    class="flex flex-col w-full h-full min-w-0 bg-n-surface-1"
    data-fidelidade="pagina"
  >
    <main class="flex-1 min-w-0 overflow-y-auto">
      <div
        ref="raiz"
        class="flex flex-col w-full max-w-6xl min-w-0 gap-6 px-5 pt-8 pb-24 mx-auto md:px-8 md:pt-10 md:pb-10"
      >
        <ErroComTentarDeNovo
          v-if="falhou"
          :mensagem="t(`${F}.PAGINA.ERRO`)"
          @tentar="carregar"
        />
        <FidelidadeTela
          v-else
          :aba="aba"
          :programa="programa"
          :resumo="resumo"
          :carregando="carregando"
          :pode-mudar="podeMudar"
          :agora="agora"
          :cupons="cupons"
          :conferencia="conferencia"
          @update:aba="trocarAba"
          @criar="montar"
          @mudar="montar"
          @ver-perto="verPerto"
          @pausar="ligar(false)"
          @ligar="ligar(true)"
          @criar-cupom="criarCupom"
          @conferir="conferir"
          @usar-cupom="usarCupom"
          @mandar-cupom="mandarCupom"
          @pausar-cupom="cupom => trocarCupom(cupom, false)"
          @ligar-cupom="cupom => trocarCupom(cupom, true)"
        />
      </div>
    </main>
  </section>
</template>
