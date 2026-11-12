<script setup>
import { computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharEstado from '../components/AcharEstado.vue';
import AcharRodape from '../components/AcharRodape.vue';
import AcharMembroDaLista from '../components/AcharMembroDaLista.vue';
import { useAcharTela } from '../composables/useAcharTela';
import { useListaAberta } from '../composables/useListaAberta';
import { ROTAS } from '../utils/acharRotas';

// #2775 — F6, uma lista aberta pela aba "Suas listas": os números, as
// empresas e "Tirar". Uma ação principal no rodapé: "Criar a mensagem" (abre a
// Nova campanha com a lista); na lista já enviada, que não muda mais, "Criar
// uma cópia para editar".
const { t } = useI18n();
const { route, router, demo, fonte, permissoes, irPara, mudarEstado } =
  useAcharTela();
const NS = 'PROSPECTING_ACHAR.LISTA';

const {
  carregando,
  erro,
  lista,
  membros,
  total,
  temMais,
  carregandoMais,
  ocupado,
  aviso,
  copiando,
  carregar,
  verMais,
  tirar,
  copiar,
} = useListaAberta({ fonte, listaId: () => route.params.listaId, demo });

const enviada = computed(() => lista.value?.enviada === true);
const numeros = computed(() =>
  lista.value
    ? [
        t('PROSPECTING_ACHAR.LISTAS.COM_WHATSAPP', { n: lista.value.whatsapp }),
        t('PROSPECTING_ACHAR.LISTAS.COM_EMAIL', { n: lista.value.email }),
        t('PROSPECTING_ACHAR.LISTAS.NO_FUNIL', { n: lista.value.noCrm }),
      ]
    : []
);
const mostraRodape = computed(
  () =>
    permissoes.value.lista && !carregando.value && !erro.value && lista.value
);

const voltar = () => irPara(ROTAS.LISTAS, { estado: 'listas' });
const escreverMensagem = () =>
  router.push({
    name: 'campaigns_journey_new',
    params: { accountId: route.params.accountId },
    query: demo.value ? {} : { audience: String(lista.value.id) },
  });
const copiarEAbrir = async () => {
  const copia = await copiar();
  if (copia) {
    irPara(ROTAS.LISTA, { params: { listaId: copia.id }, estado: 'lista' });
  }
};
const principal = () => (enviada.value ? copiarEAbrir() : escreverMensagem());
const tentarDeNovo = () => (demo.value ? mudarEstado('lista') : carregar());

onMounted(carregar);
watch(() => [route.params.listaId, demo.value], carregar);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full max-w-4xl gap-6 px-4 pt-6 mx-auto min-h-full md:px-8 md:pt-10"
        :class="mostraRodape ? 'pb-0' : 'pb-6 md:pb-10'"
      >
        <Button
          :label="$t(`${NS}.VOLTAR`)"
          icon="i-lucide-chevron-left"
          variant="link"
          class="self-start !min-h-11 !px-0"
          data-voltar
          @click="voltar"
        />
        <div v-if="carregando" class="flex flex-col gap-3" aria-busy="true">
          <div
            v-for="indice in 4"
            :key="indice"
            class="h-20 rounded-2xl bg-n-slate-3 animate-pulse"
          />
        </div>
        <AcharEstado
          v-else-if="erro"
          tom="erro"
          :texto="$t(`${NS}.ERRO`)"
          :botao="$t('PROSPECTING_ACHAR.COMUM.TENTAR_DE_NOVO')"
          @acao="tentarDeNovo"
        />
        <template v-else-if="lista">
          <header class="flex flex-col gap-2">
            <h1
              class="m-0 text-2xl font-bold tracking-tight break-words md:text-[2rem] text-n-slate-12"
            >
              {{ lista.nome }}
            </h1>
            <p class="m-0 text-lg text-n-slate-12" data-empresas>
              {{
                $t(
                  'PROSPECTING_ACHAR.LISTAS.EMPRESAS',
                  { n: lista.empresas },
                  lista.empresas
                )
              }}
            </p>
            <ul class="flex flex-wrap gap-2 p-0 m-0 list-none" data-numeros>
              <li
                v-for="numero in numeros"
                :key="numero"
                class="px-3 py-1 text-sm rounded-full bg-n-slate-3 text-n-slate-12"
              >
                {{ numero }}
              </li>
            </ul>
          </header>
          <AcharEstado
            v-if="enviada"
            faixa
            tom="aviso"
            :texto="$t(`${NS}.ENVIADA_AVISO`)"
            data-aviso-enviada
          />
          <AcharEstado
            v-if="aviso"
            faixa
            tom="feito"
            :texto="aviso.texto"
            :botao="$t('PROSPECTING_ACHAR.COMUM.DESFAZER')"
            :desligado="ocupado"
            data-aviso-tirou
            @acao="aviso.desfazer"
          />
          <AcharEstado
            v-if="!membros.length"
            :texto="$t(`${NS}.VAZIA`)"
            data-lista-vazia
          />
          <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
            <AcharMembroDaLista
              v-for="membro in membros"
              :key="membro.contatoId"
              :membro="membro"
              :pode-tirar="!enviada && permissoes.lista"
              :ocupado="ocupado"
              @tirar="tirar(membro)"
            />
          </ul>
          <Button
            v-if="temMais"
            :label="$t(`${NS}.VER_MAIS`, { n: total - membros.length })"
            :is-loading="carregandoMais"
            slate
            faded
            class="!min-h-12 !rounded-xl !text-base self-center"
            data-ver-mais
            @click="verMais"
          />
        </template>

        <AcharRodape
          v-if="mostraRodape"
          :rotulo="$t(enviada ? `${NS}.COPIAR` : `${NS}.ESCREVER`)"
          :icone="enviada ? 'i-lucide-copy' : 'i-lucide-send'"
          :ocupado="copiando"
          :desabilitado="copiando || (!enviada && !lista.empresas)"
          @principal="principal"
        />
      </div>
    </main>
  </section>
</template>
