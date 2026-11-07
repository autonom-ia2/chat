<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import AcharPainel from './AcharPainel.vue';
import AcharLinhaFrase from './AcharLinhaFrase.vue';
import AcharMotivos from './AcharMotivos.vue';
import { seloDe } from '../utils/acharChance';

// #2692 — T1d, a gaveta da empresa (v4): tudo da empresa e uma ação principal,
// que muda pelo caso — "Mandar para o funil", "Ver no funil" ou, para quem só
// vê (ou depois de mandar), "Chamar no WhatsApp" / "Ligar". O resto fica em
// "Mais". "Mandar" abre a folha curta dentro da própria gaveta.
const props = defineProps({
  empresa: { type: Object, required: true },
  primeiro: { type: Boolean, default: false },
  leitura: { type: Boolean, default: false },
  // Aberta de dentro da fila: o próximo passo fica no cartão (rodada 3).
  semRodape: { type: Boolean, default: false },
  podeTrocarPessoa: { type: Boolean, default: false },
  podeFunil: { type: Boolean, default: false },
  passo: { type: String, default: 'ver' },
  destino: { type: Object, default: null },
  pessoa: { type: String, required: true },
  enviando: { type: Boolean, default: false },
});
const emit = defineEmits([
  'close',
  'passo',
  'mandar',
  'naoServe',
  'naoQuer',
  'chamar',
  'verNoFunil',
  'alterarDestino',
  'alterarPessoa',
  'procurarDeNovo',
]);

const { t } = useI18n();
const NS = 'PROSPECTING_ACHAR.GAVETA';
const maisAberto = ref(false);
const googleAberto = ref(false);
const sobreAberto = ref(false);
const copiado = ref(false);

// O mesmo selo da lista: o 1º continua "Chame primeiro" aqui (rodada 2).
// Já no funil: sem selo de chance, só o cinza "Já está no funil" (rodada 4).
const selo = computed(() =>
  props.empresa.noFunil
    ? { chave: `${NS}.NO_FUNIL_SELO`, classe: 'bg-n-slate-3 text-n-slate-11' }
    : seloDe(props.empresa.chance, props.primeiro)
);
const temWhatsapp = computed(() => props.empresa.whatsapp === 'tem');
const rotuloChamar = computed(() =>
  temWhatsapp.value
    ? t('PROSPECTING_ACHAR.COMUM.CHAMAR_WHATSAPP')
    : t('PROSPECTING_ACHAR.COMUM.LIGAR')
);

const principal = computed(() => {
  if (props.passo === 'mandou')
    return { rotulo: rotuloChamar.value, acao: 'chamar' };
  if (props.empresa.noFunil) {
    return {
      rotulo: t('PROSPECTING_ACHAR.COMUM.VER_NO_FUNIL'),
      acao: 'verNoFunil',
    };
  }
  if (props.podeFunil && !props.leitura) {
    return { rotulo: t(`${NS}.MANDAR`), acao: 'abrirMandar' };
  }
  return { rotulo: rotuloChamar.value, acao: 'chamar' };
});

const agir = acao => {
  if (acao === 'abrirMandar') emit('passo', 'mandar');
  else if (acao === 'chamar')
    emit('chamar', temWhatsapp.value ? 'whatsapp' : 'ligar');
  else emit(acao);
};

const doMenu = acao => {
  maisAberto.value = false;
  agir(acao);
};

const pilulas = computed(() =>
  props.empresa.avaliacoes
    ? [
        t(`${NS}.GOOGLE_RESUMO`, {
          nota: String(props.empresa.nota || '').replace('.', ','),
          n: props.empresa.avaliacoes,
        }),
      ]
    : []
);

const situacaoAtiva = computed(
  () =>
    !props.empresa.situacao || props.empresa.situacao.toUpperCase() === 'ATIVA'
);

const copiarCnpj = async () => {
  try {
    await navigator.clipboard.writeText(props.empresa.cnpj);
    copiado.value = true;
  } catch {
    copiado.value = false;
  }
};

const dono = computed(() => props.empresa.dono);
// Rodada 5: "Não serve" e "Não quer" são subpainel; a seta do topo volta.
const emMotivo = computed(() =>
  ['nao-serve', 'nao-quer'].includes(props.passo)
);
// Empresa no funil (já estava ou acabou de ir) nunca mostra "Não serve"/"Não quer".
const temMais = computed(
  () => !props.leitura && !props.empresa.noFunil && props.passo !== 'mandou'
);
// Rodada 3: o mesmo par da lista e da fila ("Dono:" / "Pode ser o dono:").
const textoDoDono = computed(() => {
  const { nome, cargo, estado } = dono.value;
  const chave = 'PROSPECTING_ACHAR.CONFIRA.DONO';
  if (estado !== 'confirmado') return t(`${chave}.POSSIVEL`, { nome });
  return cargo
    ? t(`${chave}.CONFIRMADO`, { nome, cargo })
    : t(`${chave}.CONFIRMADO_SEM_CARGO`, { nome });
});
</script>

<template>
  <AcharPainel
    :titulo="$t(`${NS}.ROTULO`, { nome: empresa.nome })"
    :voltar="emMotivo"
    @close="emMotivo ? emit('passo', 'ver') : emit('close')"
  >
    <template #topo>
      <span
        class="self-start px-2.5 py-0.5 text-xs font-semibold rounded-full"
        :class="selo.classe"
      >
        {{ $t(selo.chave) }}
      </span>
      <h2 class="m-0 text-2xl font-bold break-words text-n-slate-12">
        {{ empresa.nome }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11">
        {{ [empresa.categoria, empresa.endereco].filter(Boolean).join(' · ') }}
      </p>
    </template>

    <template v-if="passo === 'nao-serve'">
      <AcharMotivos
        :titulo="$t(`${NS}.NAO_SERVE.TITULO`)"
        @escolher="(motivo, texto) => emit('naoServe', texto || motivo)"
      />
    </template>

    <section
      v-else-if="passo === 'nao-quer'"
      class="flex flex-col gap-4"
      data-nao-quer
    >
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ $t(`${NS}.NAO_QUER.TITULO`) }}
      </h3>
      <p class="m-0 text-base text-n-slate-11">
        {{ $t(`${NS}.NAO_QUER.TEXTO`) }}
      </p>
      <Button
        :label="$t(`${NS}.NAO_QUER.CONFIRMAR`)"
        class="!min-h-12 !rounded-xl !text-base"
        @click="emit('naoQuer')"
      />
    </section>

    <template v-else>
      <div
        v-if="passo === 'mandou'"
        role="status"
        class="flex items-start gap-3 p-4 border rounded-2xl border-n-teal-6 bg-n-teal-2"
        data-mandou
      >
        <span
          class="grid text-white rounded-full size-8 shrink-0 place-items-center bg-n-teal-9"
          aria-hidden="true"
        >
          <span class="i-lucide-check size-5" />
        </span>
        <div class="flex flex-col gap-1">
          <p class="m-0 text-base text-n-slate-12">
            {{
              $t(`${NS}.MANDOU`, {
                nome: empresa.nome,
                funil: destino?.funil.nome,
                pessoa,
              })
            }}
          </p>
          <Button
            :label="$t('PROSPECTING_ACHAR.COMUM.VER_NO_FUNIL')"
            variant="link"
            class="self-start !min-h-11 !px-0"
            @click="emit('verNoFunil')"
          />
        </div>
      </div>

      <p
        v-if="empresa.noFunil && passo !== 'mandou'"
        class="px-4 py-3 m-0 text-base border rounded-2xl border-n-blue-6 bg-n-blue-2 text-n-slate-12"
        data-no-funil
      >
        {{
          empresa.noFunil.funil
            ? $t(`${NS}.NO_FUNIL`, {
                funil: empresa.noFunil.funil,
                etapa: empresa.noFunil.etapa,
                pessoa: empresa.noFunil.pessoa,
              })
            : $t(`${NS}.NO_FUNIL_SEM_NOME`)
        }}
      </p>

      <section v-if="!empresa.noFunil" class="flex flex-col gap-2">
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t(`${NS}.POR_QUE`) }}
        </h3>
        <p class="m-0 text-base text-n-slate-12">{{ empresa.porque }}</p>
        <div v-if="pilulas.length" class="flex flex-wrap gap-2">
          <span
            v-for="pilula in pilulas"
            :key="pilula"
            class="px-3 py-1 text-sm rounded-full bg-n-slate-3 text-n-slate-12"
          >
            {{ pilula }}
          </span>
        </div>
      </section>

      <section
        v-if="dono.estado !== 'desligada' && !empresa.noFunil"
        class="flex flex-col gap-2"
        data-quem-decide
      >
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t(`${NS}.QUEM_DECIDE`) }}
        </h3>
        <p
          v-if="dono.estado === 'procurando'"
          class="flex items-center gap-2 m-0 text-base text-n-slate-11"
        >
          <span class="i-lucide-loader-circle size-4 animate-spin" />
          {{ $t('PROSPECTING_ACHAR.CONFIRA.DONO.PROCURANDO') }}
        </p>
        <div
          v-else-if="dono.nome"
          class="flex flex-wrap items-center gap-2 p-4 border rounded-2xl border-n-weak"
        >
          <span class="text-base font-semibold text-n-slate-12" data-dono>
            {{ textoDoDono }}
          </span>
          <Button
            v-if="!leitura"
            :label="$t(`${NS}.OUTRA_PESSOA`)"
            slate
            faded
            size="sm"
            class="!min-h-11 !rounded-xl ms-auto"
            data-outra-pessoa
            @click="emit('procurarDeNovo')"
          />
        </div>
        <div v-else class="flex flex-col gap-1" data-sem-dono>
          <p class="m-0 text-base text-n-slate-12">
            {{ $t(`${NS}.SEM_DONO`) }}
          </p>
          <Button
            v-if="!leitura"
            :label="$t(`${NS}.PROCURAR_DE_NOVO`)"
            variant="link"
            class="self-start !min-h-11 !px-0"
            data-procurar-de-novo
            @click="emit('procurarDeNovo')"
          />
        </div>
      </section>

      <section class="flex flex-col gap-2">
        <h3 class="m-0 text-sm font-semibold text-n-slate-11">
          {{ $t(`${NS}.CONTATO`) }}
        </h3>
        <p
          v-if="empresa.telefone"
          class="m-0 text-xl font-semibold tabular-nums text-n-slate-12"
        >
          {{ empresa.telefone }}
        </p>
        <p
          class="m-0 text-sm"
          :class="temWhatsapp ? 'text-n-teal-11' : 'text-n-slate-11'"
        >
          {{
            temWhatsapp
              ? $t('PROSPECTING_ACHAR.CONFIRA.WHATS.TEM')
              : $t('PROSPECTING_ACHAR.CONFIRA.WHATS.SEM')
          }}
        </p>
        <p v-if="empresa.site" class="m-0 text-sm text-n-slate-11">
          {{ empresa.site }}
        </p>
      </section>

      <section class="flex flex-col border-t border-n-weak">
        <button
          type="button"
          class="flex items-center justify-between gap-2 text-base font-semibold min-h-12 text-n-slate-12"
          :aria-expanded="googleAberto"
          @click="googleAberto = !googleAberto"
        >
          {{ $t(`${NS}.GOOGLE`) }}
          <span
            class="transition-transform i-lucide-chevron-down size-5"
            :class="{ 'rotate-180': googleAberto }"
            aria-hidden="true"
          />
        </button>
        <p v-if="googleAberto" class="m-0 text-base text-n-slate-11">
          {{
            $t(`${NS}.GOOGLE_RESUMO`, {
              nota: String(empresa.nota || '').replace('.', ','),
              n: empresa.avaliacoes,
            })
          }}
        </p>
      </section>

      <section class="flex flex-col border-t border-n-weak">
        <button
          type="button"
          class="flex items-center justify-between gap-2 text-base font-semibold min-h-12 text-n-slate-12"
          :aria-expanded="sobreAberto"
          @click="sobreAberto = !sobreAberto"
        >
          {{ $t(`${NS}.MAIS_SOBRE`) }}
          <span
            class="transition-transform i-lucide-chevron-down size-5"
            :class="{ 'rotate-180': sobreAberto }"
            aria-hidden="true"
          />
        </button>
        <div v-if="sobreAberto" class="flex flex-col gap-2">
          <div v-if="empresa.cnpj" class="flex flex-wrap items-center gap-2">
            <span class="text-sm text-n-slate-11">{{ $t(`${NS}.CNPJ`) }}</span>
            <span class="text-base tabular-nums text-n-slate-12">
              {{ empresa.cnpj }}
            </span>
            <Button
              :label="copiado ? $t(`${NS}.COPIADO`) : $t(`${NS}.COPIAR`)"
              variant="link"
              class="!min-h-11"
              @click="copiarCnpj"
            />
          </div>
          <p v-if="empresa.situacao" class="m-0 text-base text-n-slate-12">
            {{ $t(`${NS}.SITUACAO_LINHA`, { situacao: empresa.situacao }) }}
          </p>
          <p
            v-if="!situacaoAtiva"
            class="px-4 py-3 m-0 text-sm border rounded-2xl border-n-amber-6 bg-n-amber-2 text-n-amber-11"
          >
            {{ $t(`${NS}.SITUACAO_ALERTA`, { situacao: empresa.situacao }) }}
          </p>
        </div>
      </section>
    </template>

    <template v-if="!semRodape && !emMotivo" #rodape>
      <template v-if="passo === 'mandar'">
        <div class="flex flex-col" data-mandar-previa>
          <AcharLinhaFrase
            compacta
            icone="i-lucide-columns-3"
            :texto="
              destino
                ? $t(`${NS}.VAI_PARA`, {
                    funil: destino.funil.nome,
                    etapa: destino.etapa.nome,
                  })
                : $t('PROSPECTING_ACHAR.FOLHA.ESCOLHA_FUNIL')
            "
            :rotulo-acao="destino ? '' : $t('PROSPECTING_ACHAR.COMUM.ESCOLHER')"
            pode-alterar
            @alterar="emit('alterarDestino')"
          />
          <AcharLinhaFrase
            compacta
            icone="i-lucide-user-round"
            :texto="$t(`${NS}.COM_QUEM`, { pessoa })"
            :pode-alterar="podeTrocarPessoa"
            @alterar="emit('alterarPessoa')"
          />
        </div>
        <Button
          :label="$t(`${NS}.MANDAR_CURTO`)"
          :disabled="!destino"
          :is-loading="enviando"
          class="!min-h-12 !rounded-xl !text-base"
          data-mandar-um
          @click="emit('mandar')"
        />
      </template>
      <div v-else class="flex items-stretch gap-2">
        <Button
          :label="principal.rotulo"
          class="flex-1 !h-auto !min-h-12 !whitespace-normal !rounded-xl !py-2 !text-base"
          data-principal-gaveta
          @click="agir(principal.acao)"
        />
        <div v-if="temMais" class="relative">
          <Button
            :label="$t('PROSPECTING_ACHAR.COMUM.MAIS')"
            icon="i-lucide-ellipsis"
            slate
            faded
            class="!min-h-12 !rounded-xl"
            :aria-expanded="maisAberto"
            data-mais
            @click="maisAberto = !maisAberto"
          />
          <ul
            v-if="maisAberto"
            role="menu"
            class="absolute bottom-full end-0 z-10 flex flex-col w-64 gap-0.5 p-1 m-0 mb-2 list-none border shadow-lg rounded-xl border-n-weak bg-n-solid-1"
          >
            <li v-if="principal.acao !== 'chamar'" role="none">
              <button
                type="button"
                role="menuitem"
                class="w-full px-3 text-base rounded-lg text-start min-h-11 text-n-slate-12 hover:bg-n-slate-3"
                @click="doMenu('chamar')"
              >
                {{ rotuloChamar }}
              </button>
            </li>
            <li role="none">
              <button
                type="button"
                role="menuitem"
                class="w-full px-3 text-base rounded-lg text-start min-h-11 text-n-slate-12 hover:bg-n-slate-3"
                data-menu-nao-serve
                @click="(maisAberto = false), emit('passo', 'nao-serve')"
              >
                {{ $t(`${NS}.MAIS.NAO_SERVE`) }}
              </button>
            </li>
            <li role="none">
              <button
                type="button"
                role="menuitem"
                class="w-full px-3 text-base rounded-lg text-start min-h-11 text-n-slate-12 hover:bg-n-slate-3"
                @click="(maisAberto = false), emit('passo', 'nao-quer')"
              >
                {{ $t(`${NS}.MAIS.NAO_QUER`) }}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </template>
  </AcharPainel>
</template>
