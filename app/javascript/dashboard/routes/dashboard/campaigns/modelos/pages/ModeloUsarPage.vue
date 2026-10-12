<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import api from '../api/modelosWhatsapp';
import { camposUsados } from '../helpers/conteudo';
import { ligacaoDoCatalogo, useRotuloDoCampo } from '../helpers/campos';
import ModeloCelular from '../components/ModeloCelular.vue';

// Usar em uma campanha (jornada 5): abre a Nova campanha com o canal, a caixa e
// o modelo já escolhidos (?modelo=<id da Meta>&caixa=<inbox_id>). Com uma caixa
// só, vai direto; com mais de uma, pergunta de qual número sai.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { currentAccount } = useAccount();

const estado = ref('carregando');
const modelo = ref(null);
const numeros = ref([]);
const numero = ref(null);

// De onde vem cada campo na campanha: o catálogo liga sozinho (#1331); o resto a
// pessoa escolhe lá.
const ORIGEM = { nome_cliente: 'CONTATO', nome_empresa: 'EMPRESA' };
const origemDo = campo => {
  if (ORIGEM[campo]) return ORIGEM[campo];
  return ligacaoDoCatalogo(campo) ? 'CADASTRO' : 'VOCE_ESCREVE';
};
const rotulo = useRotuloDoCampo();

const abrirCampanha = caixa =>
  router.replace({
    name: 'campaigns_journey_new',
    query: { modelo: modelo.value.id, caixa: String(caixa) },
  });

onMounted(async () => {
  try {
    const [dados, lista] = await Promise.all([
      api.obterModelo(route.params.id),
      api.listarNumeros(),
    ]);
    modelo.value = dados;
    numeros.value = lista.filter(item => dados.numeros.includes(item.id));
    numero.value = numeros.value[0]?.id ?? null;
    if (dados.situacao === 'pronto' && numeros.value.length === 1) {
      abrirCampanha(numero.value);
      return;
    }
    estado.value = 'pronto';
  } catch {
    estado.value = 'erro';
  }
});

const opcoesDeNumero = computed(() =>
  numeros.value.map(item => ({ value: item.id, label: item.nome }))
);

const campos = computed(() =>
  camposUsados(modelo.value.conteudo.texto).map(campo => ({
    campo,
    origem: origemDo(campo),
  }))
);

const remetente = computed(
  () => numeros.value.find(item => item.id === numero.value)?.conta.nome || ''
);

const pronto = computed(() => modelo.value?.situacao === 'pronto');
const titulo = computed(() =>
  t('MODELOS_WHATSAPP.USAR.TITULO', { nome: modelo.value?.nome || '' })
);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        class="flex flex-col w-full gap-6 px-5 pt-8 pb-24 mx-auto max-w-6xl md:px-8 md:py-10"
      >
        <router-link
          :to="{ name: 'modelos_whatsapp_lista' }"
          class="inline-flex items-center self-start gap-2 text-[0.9375rem] font-medium rounded-lg min-h-11 text-n-blue-11 hover:underline"
        >
          <span
            class="i-lucide-arrow-left size-4 rtl:rotate-180"
            aria-hidden="true"
          />
          {{ $t('MODELOS_WHATSAPP.MODELO.VOLTAR') }}
        </router-link>

        <div
          v-if="estado === 'carregando'"
          aria-busy="true"
          class="h-96 rounded-3xl bg-n-alpha-2 animate-pulse"
        />
        <p
          v-else-if="estado === 'erro' || !pronto"
          role="alert"
          class="p-8 mb-0 text-base border rounded-2xl border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          {{ $t('MODELOS_WHATSAPP.USAR.SO_PRONTO') }}
        </p>

        <template v-else>
          <h1
            class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
          >
            {{ titulo }}
          </h1>
          <div
            class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_20rem]"
          >
            <div data-usar class="flex flex-col min-w-0 gap-6">
              <section class="flex flex-col gap-3">
                <label
                  for="modelo-usar-numero"
                  class="text-base font-semibold text-n-slate-12"
                >
                  {{ $t('MODELOS_WHATSAPP.USAR.DE_QUAL_NUMERO') }}
                </label>
                <ChoiceSelect
                  v-model="numero"
                  trigger-id="modelo-usar-numero"
                  :options="opcoesDeNumero"
                  :aria-label="$t('MODELOS_WHATSAPP.USAR.DE_QUAL_NUMERO')"
                />
              </section>

              <section
                v-if="campos.length"
                class="flex flex-col gap-3 p-6 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
              >
                <h2 class="m-0 text-base font-semibold text-n-slate-12">
                  {{ $t('MODELOS_WHATSAPP.USAR.CAMPOS') }}
                </h2>
                <ul class="flex flex-col gap-3 p-0 m-0 list-none">
                  <li
                    v-for="item in campos"
                    :key="item.campo"
                    class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[0.9375rem]"
                  >
                    <span
                      class="px-1.5 py-0.5 text-sm font-medium rounded-md bg-n-blue-3 text-n-blue-11"
                    >
                      {{ rotulo(item.campo) }}
                    </span>
                    <span
                      class="i-lucide-arrow-right size-4 text-n-slate-9 rtl:rotate-180"
                      aria-hidden="true"
                    />
                    <span
                      :class="
                        item.origem === 'VOCE_ESCREVE'
                          ? 'text-n-slate-11'
                          : 'text-n-teal-11 font-medium'
                      "
                    >
                      {{
                        $t(`MODELOS_WHATSAPP.USAR.ORIGEM.${item.origem}`, {
                          conta: currentAccount?.name || '',
                        })
                      }}
                    </span>
                  </li>
                </ul>
              </section>

              <Button
                data-continuar-campanha
                :label="$t('MODELOS_WHATSAPP.USAR.CONTINUAR')"
                icon="i-lucide-arrow-right"
                trailing-icon
                size="lg"
                class="self-start !min-h-12 !rounded-xl"
                :disabled="!numero"
                @click="abrirCampanha(numero)"
              />
            </div>
            <ModeloCelular :conteudo="modelo.conteudo" :remetente="remetente" />
          </div>
        </template>
      </div>
    </main>
  </section>
</template>
