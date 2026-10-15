<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { MARCA } from '../api/autorizacao';
import { useAutorizacao } from '../helpers/useAutorizacao';
import { numero } from '../helpers/datas';

// Autorização do dono para o sistema criar modelos sozinho (#1586). Uma ação
// por tela: desligada, marcar e "Ligar" (com o custo antes de confirmar);
// ligada, ver quem ligou e quando, mexer na Divulgação ou "Desligar". O texto
// das confirmações vem do servidor: é o mesmo que o registro grava.
const { t, locale } = useI18n();
const { installationName } = useBranding();
const { estado, autorizacao, carregar, mudar, dinheiro, quando, diaDaData } =
  useAutorizacao();

const marca = computed(() => installationName.value || 'Chat2You');
const ligada = computed(() => Boolean(autorizacao.value?.servico));
const divulgacao = computed(() => Boolean(autorizacao.value?.divulgacao));

const querServico = ref(false);
const querDivulgacao = ref(false);
const aoMudarServico = valor => {
  if (!valor) querDivulgacao.value = false;
};

const precoDe = tipo =>
  autorizacao.value ? dinheiro(autorizacao.value.precos[tipo]) : '';

const vigencia = computed(() => {
  const data = autorizacao.value?.vigenteDesde;
  return data ? diaDaData(data) : '';
});

// "Ligada por Ana em 15/10/2026 às 14:32, no fuso da conta (...)". Sem fuso na
// conta: só "no fuso da sua conta", nunca o do navegador.
const frase = ultima => {
  if (!ultima) return '';
  const { dia, hora, fuso } = quando(ultima.em);
  const base = ultima.acao === 'ligou' ? 'LIGADA_POR' : 'DESLIGADA_POR';
  const chave = fuso ? base : `${base}_SEM_FUSO`;
  return t(`MODELOS_WHATSAPP.AUTORIZACAO.${chave}`, {
    nome: ultima.por || t('MODELOS_WHATSAPP.AUTORIZACAO.ALGUEM'),
    dia,
    hora,
    fuso,
  });
};
const mudanca = computed(() => frase(autorizacao.value?.mudanca));
const mudancaDivulgacao = computed(() =>
  ligada.value ? frase(autorizacao.value?.mudancaDivulgacao) : ''
);

// O pedido que a confirmação aberta vai mandar.
const pedido = ref(null);
const dialogoLigar = ref(null);
const dialogoDesligar = ref(null);
const salvando = ref(false);
const falha = ref('');

const textosDo = (acao, tipos) =>
  tipos.map(tipo => autorizacao.value.textos[acao][tipo]);

const pedir = (acao, tipos, chave) => {
  falha.value = '';
  pedido.value = {
    acao,
    marcas: tipos.map(tipo => MARCA[tipo]),
    textos: textosDo(acao, tipos),
    titulo: t(`MODELOS_WHATSAPP.AUTORIZACAO.${chave}.TITULO`),
    sim: t(`MODELOS_WHATSAPP.AUTORIZACAO.${chave}.SIM`),
  };
  (acao === 'ligar' ? dialogoLigar : dialogoDesligar).value?.open();
};

const pedirLigar = () =>
  pedir(
    'ligar',
    querDivulgacao.value ? ['servico', 'divulgacao'] : ['servico'],
    'CONFIRMAR_LIGAR'
  );
const pedirDesligar = () =>
  pedir('desligar', ['servico'], 'CONFIRMAR_DESLIGAR');
const pedirDivulgacao = () =>
  divulgacao.value
    ? pedir('desligar', ['divulgacao'], 'CONFIRMAR_DESLIGAR_DIVULGACAO')
    : pedir('ligar', ['divulgacao'], 'CONFIRMAR_DIVULGACAO');

const confirmar = async () => {
  const { acao, marcas } = pedido.value;
  salvando.value = true;
  falha.value = '';
  try {
    await mudar(acao, marcas);
    querServico.value = false;
    querDivulgacao.value = false;
  } catch (erro) {
    falha.value = erro?.mensagem || t('MODELOS_WHATSAPP.AUTORIZACAO.FALHOU');
    // O preço mudou enquanto a pessoa lia: a tela mostra o aviso novo.
    if (erro?.codigo === 'aviso_mudou') carregar();
  } finally {
    salvando.value = false;
    dialogoLigar.value?.close();
    dialogoDesligar.value?.close();
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <main class="flex-1 overflow-y-auto">
      <div
        data-autorizacao
        class="flex flex-col w-full gap-6 px-5 pt-8 pb-24 mx-auto max-w-3xl md:px-8 md:py-10"
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
        >
          <span class="sr-only">{{ $t('MODELOS_WHATSAPP.CARREGANDO') }}</span>
        </div>

        <div
          v-else-if="estado === 'erro'"
          role="alert"
          class="flex flex-col items-start gap-4 p-8 border rounded-2xl border-n-weak bg-n-solid-1"
        >
          <p class="mb-0 text-base text-n-slate-12">
            {{ $t('MODELOS_WHATSAPP.ERRO') }}
          </p>
          <Button
            :label="$t('MODELOS_WHATSAPP.TENTAR_DE_NOVO')"
            icon="i-lucide-refresh-cw"
            color="slate"
            variant="faded"
            class="min-h-11"
            @click="carregar"
          />
        </div>

        <template v-else>
          <header class="flex flex-col gap-3">
            <span
              class="self-start px-3 py-1 text-sm font-medium rounded-full"
              :class="
                ligada
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-slate-3 text-n-slate-11'
              "
              :data-situacao="ligada ? 'ligada' : 'desligada'"
            >
              {{
                ligada
                  ? $t('MODELOS_WHATSAPP.AUTORIZACAO.SITUACAO.LIGADA')
                  : $t('MODELOS_WHATSAPP.AUTORIZACAO.SITUACAO.DESLIGADA')
              }}
            </span>
            <h1
              class="m-0 text-3xl font-bold tracking-tight md:text-4xl text-n-slate-12"
            >
              {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.TITULO') }}
            </h1>
            <p class="mb-0 text-base md:text-lg text-n-slate-11">
              {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.AVISO', { marca }) }}
            </p>
          </header>

          <p
            v-if="mudanca"
            data-mudanca
            class="flex items-start gap-3 px-4 py-3 mb-0 text-[0.9375rem] rounded-xl"
            :class="
              ligada
                ? 'bg-n-teal-2 text-n-slate-12'
                : 'bg-n-slate-2 text-n-slate-11'
            "
          >
            <span
              class="size-5 mt-0.5 shrink-0"
              :class="
                ligada
                  ? 'i-lucide-circle-check text-n-teal-11'
                  : 'i-lucide-circle-pause text-n-slate-10'
              "
              aria-hidden="true"
            />
            {{ mudanca }}
          </p>

          <!-- Desligada: as duas marcas, desmarcadas. A segunda só abre com a primeira. -->
          <section
            v-if="!ligada"
            data-marcas
            class="flex flex-col gap-1 p-2 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
          >
            <label
              data-marca-servico
              class="flex items-start gap-4 p-4 cursor-pointer rounded-xl min-h-11 hover:bg-n-alpha-1"
            >
              <span class="grid place-items-center size-6 shrink-0">
                <Checkbox
                  v-model="querServico"
                  @update:model-value="aoMudarServico"
                />
              </span>
              <span class="flex flex-col gap-1">
                <span class="text-base font-semibold text-n-slate-12">
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.SERVICO.ROTULO') }}
                </span>
                <span class="text-[0.9375rem] text-n-slate-11">
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.SERVICO.EXPLICA') }}
                </span>
                <span class="text-[0.9375rem] font-medium text-n-teal-11">
                  {{
                    $t('MODELOS_WHATSAPP.AUTORIZACAO.PRECO', {
                      valor: precoDe('servico'),
                    })
                  }}
                </span>
              </span>
            </label>
            <label
              data-marca-divulgacao
              class="flex items-start gap-4 p-4 rounded-xl min-h-11"
              :class="
                querServico
                  ? 'cursor-pointer hover:bg-n-alpha-1'
                  : 'cursor-not-allowed opacity-60'
              "
            >
              <span class="grid place-items-center size-6 shrink-0">
                <Checkbox v-model="querDivulgacao" :disabled="!querServico" />
              </span>
              <span class="flex flex-col gap-1">
                <span class="text-base font-semibold text-n-slate-12">
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.ROTULO') }}
                  <span class="font-normal text-n-slate-11">
                    {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.OPCIONAL') }}
                  </span>
                </span>
                <span class="text-[0.9375rem] text-n-slate-11">
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.EXPLICA') }}
                </span>
                <span class="text-[0.9375rem] font-medium text-n-amber-11">
                  {{
                    $t('MODELOS_WHATSAPP.AUTORIZACAO.PRECO', {
                      valor: precoDe('divulgacao'),
                    })
                  }}
                </span>
                <span
                  v-if="!querServico"
                  class="text-sm text-n-slate-11"
                  data-divulgacao-travada
                >
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.TRAVADA') }}
                </span>
              </span>
            </label>
          </section>

          <!-- Ligada: o que está liberado; a Divulgação muda aqui, com confirmação. -->
          <section
            v-else
            data-liberado
            class="flex flex-col gap-3 px-5 py-4 rounded-2xl ring-1 ring-inset ring-n-weak bg-n-solid-1"
          >
            <h2 class="m-0 text-base font-semibold text-n-slate-12">
              {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.LIBERADO') }}
            </h2>
            <ul class="flex flex-col gap-3 p-0 m-0 list-none">
              <li class="flex items-start gap-3 text-[0.9375rem]">
                <span
                  class="i-lucide-check size-5 mt-0.5 shrink-0 text-n-teal-11"
                  aria-hidden="true"
                />
                <span class="text-n-slate-12">
                  {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.SERVICO.ROTULO') }}
                  <span class="text-n-slate-11">
                    ·
                    {{
                      $t('MODELOS_WHATSAPP.AUTORIZACAO.PRECO', {
                        valor: precoDe('servico'),
                      })
                    }}
                  </span>
                </span>
              </li>
              <li
                data-divulgacao
                class="flex flex-wrap items-start justify-between gap-3 text-[0.9375rem]"
              >
                <span class="flex items-start flex-1 min-w-0 gap-3">
                  <span
                    class="size-5 mt-0.5 shrink-0"
                    :class="
                      divulgacao
                        ? 'i-lucide-check text-n-teal-11'
                        : 'i-lucide-x text-n-slate-10'
                    "
                    aria-hidden="true"
                  />
                  <span class="flex flex-col gap-1">
                    <span
                      :class="
                        divulgacao ? 'text-n-slate-12' : 'text-n-slate-11'
                      "
                    >
                      {{
                        divulgacao
                          ? $t(
                              'MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.LIBERADA'
                            )
                          : $t(
                              'MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.NAO_LIBERADA'
                            )
                      }}
                      <span class="text-n-slate-11">
                        ·
                        {{
                          $t('MODELOS_WHATSAPP.AUTORIZACAO.PRECO', {
                            valor: precoDe('divulgacao'),
                          })
                        }}
                      </span>
                    </span>
                    <span
                      v-if="mudancaDivulgacao"
                      data-mudanca-divulgacao
                      class="text-sm text-n-slate-11"
                    >
                      {{ mudancaDivulgacao }}
                    </span>
                  </span>
                </span>
                <Button
                  data-mexer-divulgacao
                  :label="
                    divulgacao
                      ? $t('MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.DESLIGAR')
                      : $t('MODELOS_WHATSAPP.AUTORIZACAO.DIVULGACAO.LIGAR')
                  "
                  color="slate"
                  variant="faded"
                  class="!min-h-11"
                  @click="pedirDivulgacao"
                />
              </li>
            </ul>
          </section>

          <section
            data-regras-da-meta
            class="flex flex-col gap-2 px-5 py-4 rounded-2xl bg-n-slate-2"
          >
            <h2 class="m-0 text-base font-semibold text-n-slate-12">
              {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.META.TITULO') }}
            </h2>
            <ul
              class="flex flex-col gap-1.5 p-0 m-0 list-none text-[0.9375rem] text-n-slate-11"
            >
              <li>{{ $t('MODELOS_WHATSAPP.AUTORIZACAO.META.COBRA') }}</li>
              <li>
                {{
                  $t('MODELOS_WHATSAPP.AUTORIZACAO.META.TABELA', {
                    data: vigencia,
                  })
                }}
              </li>
              <li>
                {{
                  $t('MODELOS_WHATSAPP.AUTORIZACAO.META.LIMITE_MODELOS', {
                    modelos: numero(autorizacao.limites.modelos, locale),
                    verificada: numero(
                      autorizacao.limites.modelosVerificada,
                      locale
                    ),
                    porHora: numero(autorizacao.limites.porHora, locale),
                  })
                }}
              </li>
              <li>
                {{ $t('MODELOS_WHATSAPP.AUTORIZACAO.META.LIMITE_DIVULGACAO') }}
              </li>
            </ul>
          </section>

          <p
            v-if="falha"
            role="alert"
            data-falha
            class="px-4 py-3 mb-0 text-[0.9375rem] rounded-xl bg-n-ruby-2 text-n-ruby-11"
          >
            {{ falha }}
          </p>

          <div>
            <Button
              v-if="!ligada"
              data-ligar
              :label="$t('MODELOS_WHATSAPP.AUTORIZACAO.ACOES.LIGAR')"
              icon="i-lucide-power"
              size="lg"
              :disabled="!querServico"
              class="!min-h-12 !rounded-xl"
              @click="pedirLigar"
            />
            <Button
              v-else
              data-desligar
              :label="$t('MODELOS_WHATSAPP.AUTORIZACAO.ACOES.DESLIGAR')"
              icon="i-lucide-power-off"
              color="ruby"
              variant="faded"
              size="lg"
              class="!min-h-12 !rounded-xl"
              @click="pedirDesligar"
            />
          </div>
        </template>
      </div>
    </main>

    <Dialog
      ref="dialogoLigar"
      :title="pedido?.titulo"
      :confirm-button-label="pedido?.sim"
      :cancel-button-label="$t('MODELOS_WHATSAPP.AUTORIZACAO.AGORA_NAO')"
      :is-loading="salvando"
      @confirm="confirmar"
    >
      <div data-dialogo-ligar class="flex flex-col gap-3 text-n-slate-12">
        <p
          v-for="texto in pedido?.textos || []"
          :key="texto"
          class="mb-0 text-[0.9375rem]"
        >
          {{ texto }}
        </p>
      </div>
    </Dialog>

    <Dialog
      ref="dialogoDesligar"
      type="alert"
      :title="pedido?.titulo"
      :description="pedido?.textos.join(' ')"
      :confirm-button-label="pedido?.sim"
      :cancel-button-label="$t('MODELOS_WHATSAPP.AUTORIZACAO.AGORA_NAO')"
      :is-loading="salvando"
      @confirm="confirmar"
    />
  </section>
</template>
