<script setup>
import { onMounted, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ErroComTentarDeNovo from '../comum/ErroComTentarDeNovo.vue';
import EsqueletoDeLista from '../comum/EsqueletoDeLista.vue';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import {
  PESSOA_DO_PAINEL_NA_DEMO,
  casoPedido,
  pecaPedida,
} from '../../fonte/modoCarteira';
import { estadoDemo } from '../../fonte/modoDemo';
import {
  ESTADOS_DOS_SEGUROS as ESTADOS,
  useSegurosDe,
} from '../../carteira/useSegurosDe';
import { useTextosDoSeguro } from '../../carteira/useTextosDoSeguro';
import EntradaDeFora from './EntradaDeFora.vue';
import GavetaDoSeguro from './GavetaDoSeguro.vue';
import LinhaDoSeguroNaFicha from './LinhaDoSeguroNaFicha.vue';

// #2897 — os seguros da pessoa no painel da conversa: quem atende vê sem sair
// do chat. É leitura: cada linha abre a gaveta do seguro por cima da conversa.
// Recolhe e abre pelo título; começa aberto. Na demonstração a conversa é de
// verdade e a pessoa dela não está na base inventada: o painel mostra os
// seguros da pessoa de exemplo das outras jornadas. "Guardar seguro de outra
// corretora" abre a gaveta da Tela 20 (EntradaDeFora).
const { t } = useI18n();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.PAINEL.${chave}`);
const router = useRouter();
const textos = useTextosDoSeguro();
const idDaLista = useId();

const pessoaId = PESSOA_DO_PAINEL_NA_DEMO;
const doEndereco = Object.fromEntries(
  new URLSearchParams(window.location.search)
);
const fonte = carteiraFonte({
  demo: estadoDemo(),
  peca: pecaPedida(doEndereco),
  caso: casoPedido(doEndereco),
});
const lista = useSegurosDe(() => fonte.daPessoa(pessoaId));

const aberto = ref(true);
const apoliceAberta = ref(null);

const verNaFicha = () =>
  router.push({
    name: 'relacionamentos_pessoa',
    params: { contactId: pessoaId },
  });
const abrirSegurado = ({ tipo, id }) => {
  apoliceAberta.value = null;
  return router.push(
    tipo === 'empresa'
      ? { name: 'relacionamentos_empresa', params: { companyId: id } }
      : { name: 'relacionamentos_pessoa', params: { contactId: id } }
  );
};
const verPdf = seguro =>
  useAlert(
    t('RELACIONAMENTOS_CARTEIRA.FICHA.ABRINDO_PDF', {
      tipo: textos.tipo(seguro),
    })
  );

onMounted(lista.carregar);
</script>

<template>
  <section
    data-carteira="painel-seguros"
    class="flex flex-col gap-2 px-4 py-4 border-t border-n-weak"
  >
    <h3 class="m-0">
      <button
        type="button"
        data-carteira="painel-titulo"
        :aria-expanded="aberto"
        :aria-controls="idDaLista"
        class="flex items-center justify-between w-full gap-2 p-0 text-base font-semibold leading-6 bg-transparent border-0 rounded-lg min-h-11 text-start text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        @click="aberto = !aberto"
      >
        {{ tp('TITULO') }}
        <span
          aria-hidden="true"
          class="size-4 shrink-0 text-n-slate-11"
          :class="aberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>
    </h3>
    <div v-show="aberto" :id="idDaLista" class="flex flex-col gap-2">
      <div
        v-if="lista.estado.value === ESTADOS.ERRO"
        data-carteira="painel-erro"
      >
        <ErroComTentarDeNovo :mensagem="tp('ERRO')" @tentar="lista.carregar" />
      </div>
      <EsqueletoDeLista
        v-else-if="lista.estado.value === ESTADOS.CARREGANDO"
        :linhas="2"
        data-carteira="painel-carregando"
      />
      <template v-else>
        <p
          v-if="!lista.seguros.value.length"
          data-carteira="painel-vazio"
          class="m-0 text-sm text-n-slate-11"
        >
          {{ tp('VAZIO') }}
        </p>
        <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
          <LinhaDoSeguroNaFicha
            v-for="seguro in lista.seguros.value"
            :key="seguro.id"
            compacta
            :seguro="seguro"
            @abrir="apoliceAberta = $event.id"
            @pdf="verPdf"
          />
        </ul>
        <div class="flex flex-col items-start">
          <Button
            v-if="lista.seguros.value.length"
            link
            size="lg"
            data-carteira="painel-ver-ficha"
            :label="tp('VER_NA_FICHA')"
            @click="verNaFicha"
          />
          <EntradaDeFora
            marca="painel-guardar-de-fora"
            :pessoa-id="pessoaId"
            :fonte="fonte"
            @mudou="lista.atualizar"
          />
        </div>
      </template>
    </div>
    <GavetaDoSeguro
      :apolice-id="apoliceAberta"
      :fonte="fonte"
      @fechar="apoliceAberta = null"
      @mudou="lista.atualizar"
      @abrir-segurado="abrirSegurado"
    />
  </section>
</template>
