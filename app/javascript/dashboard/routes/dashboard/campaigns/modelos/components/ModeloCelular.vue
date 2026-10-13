<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CODIGO_DE_EXEMPLO, TIPOS_DE_BOTAO } from '../constants';
import { trocarCamposPorExemplos } from '../helpers/conteudo';
import { rotuloDoCampo } from '../helpers/campos';
import { botoesNoCelular } from '../helpers/regraEstrutural';
import CelularCartoes from './celular/CelularCartoes.vue';
import CelularOferta from './celular/CelularOferta.vue';

// "Como o cliente vê": a mensagem dentro de um celular, com os exemplos no lugar
// dos campos (destacados, para mostrar o que muda para cada cliente). Moldura
// própria: as prévias que já existem (template-preview) mostram topo, rodapé e
// botões em variantes separadas, e aqui tudo aparece junto, em cada formato.
const props = defineProps({
  conteudo: { type: Object, required: true },
  remetente: { type: String, default: '' },
  compacto: { type: Boolean, default: false },
});

const { t } = useI18n();

const formato = computed(() => props.conteudo.formato || 'padrao');

const pedacos = computed(() => {
  if (formato.value === 'codigo') {
    const resto = [
      t('MODELOS_WHATSAPP.FORMATOS.codigo.TEXTO_FIXO'),
      props.conteudo.codigo.avisoDeSeguranca
        ? t('MODELOS_WHATSAPP.FORMATOS.codigo.AVISO_FIXO')
        : '',
    ]
      .filter(Boolean)
      .join(' ');
    return [
      { t: 'exemplo', v: CODIGO_DE_EXEMPLO },
      { t: 'texto', v: ` ${resto}` },
    ];
  }
  return trocarCamposPorExemplos(
    props.conteudo.texto,
    props.conteudo.exemplos,
    campo => rotuloDoCampo(t, campo)
  );
});

const ICONES_EXTRAS = {
  catalogo: 'i-lucide-shopping-bag',
  formulario: 'i-lucide-clipboard-list',
  preencher: 'i-lucide-text-cursor-input',
};

const iconeDoBotao = tipo =>
  ICONES_EXTRAS[tipo] ||
  TIPOS_DE_BOTAO.find(item => item.chave === tipo)?.icone ||
  'i-lucide-reply';

const botoes = computed(() => {
  const { conteudo } = props;
  if (formato.value === 'oferta') {
    return [
      ...(conteudo.oferta.cupom
        ? [
            {
              tipo: 'copiar_codigo',
              texto: t('MODELOS_WHATSAPP.BOTOES_PRONTOS.COPIAR_CODIGO'),
            },
          ]
        : []),
      { tipo: 'site', texto: t('MODELOS_WHATSAPP.FORMATOS.oferta.BOTAO') },
    ];
  }
  if (formato.value === 'catalogo') {
    return [{ tipo: 'catalogo', texto: conteudo.catalogo.botao }];
  }
  if (formato.value === 'codigo') {
    return conteudo.codigo.botao === 'preencher'
      ? [
          {
            tipo: 'preencher',
            texto: t('MODELOS_WHATSAPP.FORMATOS.codigo.BOTOES.preencher'),
          },
        ]
      : [
          {
            tipo: 'copiar_codigo',
            texto: t('MODELOS_WHATSAPP.FORMATOS.codigo.BOTOES.copiar'),
          },
        ];
  }
  if (formato.value === 'formulario') {
    return [{ tipo: 'formulario', texto: conteudo.formulario.botao }];
  }
  if (formato.value === 'carrossel') return [];
  // O texto do "Copiar código" é fixo do WhatsApp: a prévia mostra o de verdade.
  return conteudo.botoes.map(botao =>
    botao.tipo === 'copiar_codigo'
      ? { ...botao, texto: t('MODELOS_WHATSAPP.BOTOES_PRONTOS.COPIAR_CODIGO') }
      : botao
  );
});

// Mais de 3 botões: o WhatsApp mostra 2 e "Ver todas as opções" (#1387, L8).
const botoesNaTela = computed(() => botoesNoCelular(botoes.value));

const rodape = computed(() => {
  if (formato.value === 'codigo') {
    const minutos = props.conteudo.codigo.validade;
    return t(
      'MODELOS_WHATSAPP.FORMATOS.codigo.VALIDADE_FIXA',
      { n: minutos },
      minutos
    );
  }
  return formato.value === 'padrao' ? props.conteudo.rodape : '';
});

const topo = computed(() => {
  if (formato.value === 'catalogo') return 'catalogo';
  if (['padrao', 'oferta'].includes(formato.value)) {
    return props.conteudo.topo?.tipo || 'nenhum';
  }
  return 'nenhum';
});

const vazio = computed(() => !pedacos.value.length);
</script>

<template>
  <figure
    data-celular
    class="m-0 mx-auto w-full overflow-hidden border-[6px] shadow-xl rounded-[2rem] border-n-slate-12 bg-n-slate-3"
    :class="compacto ? 'max-w-[17rem]' : 'max-w-[20rem]'"
  >
    <figcaption class="sr-only">
      {{ $t('MODELOS_WHATSAPP.CELULAR.LEGENDA') }}
    </figcaption>
    <div class="flex items-center gap-2.5 px-4 py-3 bg-n-teal-10 text-white">
      <span
        class="grid text-sm font-semibold rounded-full place-items-center size-8 bg-white/20"
        aria-hidden="true"
      >
        {{ (remetente || 'H').slice(0, 1) }}
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-sm font-semibold truncate">{{ remetente }}</span>
        <span class="text-xs text-white/80">
          {{ $t('MODELOS_WHATSAPP.CELULAR.CONTA_COMERCIAL') }}
        </span>
      </span>
    </div>
    <div
      class="flex flex-col gap-1.5 px-3 pt-4 pb-6"
      :class="compacto ? 'min-h-[18rem]' : 'min-h-[24rem]'"
    >
      <div
        class="flex flex-col gap-2 p-2 shadow-sm rounded-xl rounded-tl-sm bg-n-solid-1 max-w-[92%]"
      >
        <div
          v-if="topo !== 'nenhum'"
          data-celular-topo
          class="grid gap-1 rounded-lg place-items-center h-28 bg-n-slate-4 text-n-slate-11"
        >
          <span
            class="size-8"
            :class="{
              'i-lucide-image': topo === 'foto',
              'i-lucide-video': topo === 'video',
              'i-lucide-file-text': topo === 'documento',
              'i-lucide-shopping-bag': topo === 'catalogo',
            }"
            aria-hidden="true"
          />
          <span class="max-w-full px-2 text-xs truncate">
            {{
              topo === 'catalogo'
                ? $t('MODELOS_WHATSAPP.CELULAR.CATALOGO')
                : conteudo.topo.arquivo ||
                  $t(`MODELOS_WHATSAPP.TOPOS.${topo}.ROTULO`)
            }}
          </span>
        </div>
        <CelularOferta
          v-if="formato === 'oferta'"
          :oferta="conteudo.oferta"
          :na-campanha="conteudo.naCampanha"
        />
        <p
          class="px-1 mb-0 text-sm leading-relaxed whitespace-pre-wrap break-words text-n-slate-12"
        >
          <span v-if="vazio" class="text-n-slate-10">
            {{ $t('MODELOS_WHATSAPP.CELULAR.VAZIO') }}
          </span>
          <template v-for="(pedaco, indice) in pedacos" :key="indice">
            <mark
              v-if="pedaco.t === 'exemplo'"
              class="px-0.5 rounded bg-n-amber-3 text-n-slate-12"
              :class="formato === 'codigo' ? 'font-semibold' : ''"
            >
              <span>{{ pedaco.v }}</span>
            </mark>
            <span v-else>{{ pedaco.v }}</span>
          </template>
        </p>
        <p v-if="rodape" class="px-1 mb-0 text-xs break-words text-n-slate-10">
          {{ rodape }}
        </p>
        <span class="self-end px-1 text-[0.6875rem] text-n-slate-10">
          {{ $t('MODELOS_WHATSAPP.CELULAR.HORA') }}
        </span>
      </div>
      <CelularCartoes
        v-if="formato === 'carrossel'"
        :cartoes="conteudo.cartoes"
      />
      <span
        v-for="(botao, indice) in botoesNaTela.aVista"
        :key="indice"
        data-celular-botao
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium shadow-sm rounded-xl bg-n-solid-1 text-n-blue-11 max-w-[92%]"
      >
        <span
          class="size-4"
          :class="iconeDoBotao(botao.tipo)"
          aria-hidden="true"
        />
        {{ botao.texto || $t('MODELOS_WHATSAPP.CELULAR.BOTAO_SEM_TEXTO') }}
        <span
          v-if="
            conteudo.naCampanha && botao.tipo === 'copiar_codigo' && botao.valor
          "
          data-celular-codigo
          class="font-mono text-n-slate-11"
        >
          {{ botao.valor }}
        </span>
      </span>
      <span
        v-if="botoesNaTela.escondidos"
        data-celular-ver-todas
        class="flex items-center justify-center gap-1.5 py-2 text-sm font-medium shadow-sm rounded-xl bg-n-solid-1 text-n-blue-11 max-w-[92%]"
      >
        <span class="i-lucide-list size-4" aria-hidden="true" />
        {{ $t('MODELOS_WHATSAPP.CELULAR.VER_TODAS_AS_OPCOES') }}
      </span>
    </div>
  </figure>
</template>
