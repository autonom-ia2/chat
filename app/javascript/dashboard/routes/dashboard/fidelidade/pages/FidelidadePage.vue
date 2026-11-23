<script setup>
import { nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { FIDELIDADE_MANAGE_PERMISSION } from 'dashboard/constants/permissions';
import ErroComTentarDeNovo from 'dashboard/routes/dashboard/relacionamentos/components/comum/ErroComTentarDeNovo.vue';
import FidelidadeTela from '../components/FidelidadeTela.vue';
import { abaValida } from '../abas';
import { ligarPrograma, lerPrograma, lerResumo } from '../fonte';
import { F } from '../useTextosDaFidelidade';

// #3100 — a página Fidelidade (Crescer > Fidelidade): lê o cartão da conta e
// os números do painel e entrega à FidelidadeTela. Criar e "Mudar as regras"
// abrem a tela de montar; "Ver quem está perto do prêmio" abre a lista de
// Relacionamentos já filtrada (?fidelidade=perto); pausar e ligar de novo
// gravam na hora e dizem que deu certo. Quem só vê (fidelidade_view) lê o
// painel sem os botões de mudar (useCanManage). Os cupons chegam na etapa
// deles: até lá a tela mostra só o cartão (`com-cupons` falso).
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

const montar = () => router.push({ name: 'fidelidade_montar' });
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
          :com-cupons="false"
          @update:aba="trocarAba"
          @criar="montar"
          @mudar="montar"
          @ver-perto="verPerto"
          @pausar="ligar(false)"
          @ligar="ligar(true)"
        />
      </div>
    </main>
  </section>
</template>
