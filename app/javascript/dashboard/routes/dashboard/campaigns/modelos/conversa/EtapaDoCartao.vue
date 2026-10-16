<script setup>
// Um cartão do carrossel de fotos por vez ("Cartão 1 de 3", #1716). Duas
// perguntas só: qual foto vai (uma das fotos aprovadas do modelo ou uma do
// computador) e o que vai em cada espaço do texto do cartão. Foto grande demais
// nem sobe: o motivo e o que fazer aparecem embaixo.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import api from '../api/modelosWhatsapp';
import { localeDoIntl } from '../helpers/datas';
import { comEspacos, exemploDoCampo } from './modeloNaConversa';

const props = defineProps({
  caixa: { type: [Number, String], required: true },
  // cartoesDoModelo(template)[i]
  cartao: { type: Object, required: true },
  // { imagem, referencia, nome, campos }
  valor: { type: Object, default: () => ({}) },
  // [{ url, referencia, nome }]: as fotos aprovadas do modelo
  galeria: { type: Array, default: () => [] },
  podeSubir: { type: Boolean, default: false },
  galeriaFalhou: { type: Boolean, default: false },
});
const emit = defineEmits(['update', 'miniatura']);

const { t, locale } = useI18n();
const NS = 'MODELOS_WHATSAPP.CONVERSA.CARTAO';

// Foto JPG ou PNG de até 5 MB: o que a Meta aceita no topo de um cartão
// (Whatsapp::Templates::HeaderMedia::UPLOAD_LIMITS, conferido de novo no servidor).
const MB = 1024 * 1024;
const MAXIMO = 5 * MB;
const ACEITA = ['image/jpeg', 'image/png'];

const seletor = ref(null);
const subindo = ref('');
const erro = ref('');

// Sempre com o cartão que pediu: a foto que sobe depois de a pessoa ir ao
// próximo cartão não cai no cartão errado.
const atualizar = mudanca =>
  emit('update', props.cartao.indice, { ...props.valor, ...mudanca });

const usarDaGaleria = foto => {
  erro.value = '';
  atualizar({ imagem: foto.url, referencia: foto.referencia, nome: foto.nome });
};

const tamanho = bytes =>
  new Intl.NumberFormat(localeDoIntl(locale.value), {
    maximumFractionDigits: 1,
  }).format(bytes / MB);

const motivoDoArquivo = arquivo => {
  if (!ACEITA.includes(arquivo.type)) return t(`${NS}.ERRO_TIPO`);
  if (arquivo.size > MAXIMO) {
    return t(`${NS}.ERRO_GRANDE`, { tamanho: tamanho(arquivo.size) });
  }
  return '';
};

const aoEscolher = async evento => {
  const arquivo = evento.target.files?.[0];
  // Limpa o campo: escolher o mesmo arquivo de novo também avisa.
  seletor.value.value = '';
  if (!arquivo) return;
  erro.value = motivoDoArquivo(arquivo);
  if (erro.value) return;
  subindo.value = arquivo.name;
  try {
    const subido = await api.subirArquivoDaCampanha(props.caixa, arquivo);
    const imagem = URL.createObjectURL(arquivo);
    emit('miniatura', imagem);
    atualizar({ imagem, referencia: subido.referencia, nome: subido.nome });
  } catch (falha) {
    erro.value = falha?.mensagem || t(`${NS}.ERRO_ENVIO`);
  } finally {
    subindo.value = '';
  }
};

const daGaleria = computed(() =>
  props.galeria.some(foto => foto.referencia === props.valor.referencia)
);
const textoComEspacos = computed(() =>
  comEspacos(props.cartao.corpo?.text, {}, n => t(`${NS}.ESPACO`, { n }))
);
const valorDoCampo = nome => props.valor.campos?.[nome] || '';
const mudarCampo = (nome, texto) =>
  atualizar({ campos: { ...(props.valor.campos || {}), [nome]: texto } });
</script>

<template>
  <div class="flex flex-col gap-5" data-etapa-cartao>
    <section class="flex flex-col gap-2">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.FOTO`) }}
      </h4>
      <p class="m-0 text-xs text-n-slate-11">
        {{ podeSubir ? t(`${NS}.FOTO_AJUDA`) : t(`${NS}.FOTO_AJUDA_GALERIA`) }}
      </p>
      <ul
        v-if="galeria.length"
        class="grid grid-cols-3 gap-2 p-0 m-0 list-none"
        role="radiogroup"
        :aria-label="t(`${NS}.GALERIA`)"
      >
        <li v-for="foto in galeria" :key="foto.referencia">
          <button
            type="button"
            role="radio"
            :aria-checked="valor.referencia === foto.referencia"
            :aria-label="t(`${NS}.USAR_FOTO`, { nome: foto.nome })"
            class="relative block w-full overflow-hidden rounded-xl aspect-square bg-n-slate-3 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              valor.referencia === foto.referencia
                ? 'ring-[3px] ring-n-blue-9'
                : 'ring-1 ring-n-weak hover:ring-n-blue-6'
            "
            :data-foto-da-galeria="foto.nome"
            @click="usarDaGaleria(foto)"
          >
            <img :src="foto.url" alt="" class="object-cover size-full" />
            <span
              v-if="valor.referencia === foto.referencia"
              class="absolute grid text-white rounded-full shadow top-1.5 ltr:right-1.5 rtl:left-1.5 size-7 place-items-center bg-n-blue-9"
              aria-hidden="true"
            >
              <span class="i-lucide-check size-4" />
            </span>
          </button>
        </li>
      </ul>
      <p
        v-else-if="galeriaFalhou || !podeSubir"
        role="status"
        class="m-0 text-sm text-n-amber-11"
        data-sem-galeria
      >
        {{ galeriaFalhou ? t(`${NS}.GALERIA_FALHOU`) : t(`${NS}.SEM_GALERIA`) }}
      </p>
      <div
        v-if="valor.referencia && !daGaleria"
        class="flex items-center gap-3 p-2 border rounded-xl border-n-blue-7 bg-n-solid-1"
        data-foto-do-computador
      >
        <img
          :src="valor.imagem"
          alt=""
          class="object-cover rounded-lg size-11 shrink-0"
        />
        <span class="flex-1 min-w-0 text-sm break-words text-n-slate-12">
          {{ t(`${NS}.DO_COMPUTADOR`, { nome: valor.nome }) }}
        </span>
      </div>
      <div v-if="podeSubir" class="flex flex-wrap items-center gap-2">
        <Button
          type="button"
          icon="i-lucide-upload"
          color="slate"
          variant="faded"
          class="min-h-11"
          :is-loading="Boolean(subindo)"
          :label="
            subindo
              ? t(`${NS}.ENVIANDO`, { nome: subindo })
              : t(`${NS}.DO_COMPUTADOR_BOTAO`)
          "
          data-foto-computador
          @click="seletor?.click()"
        />
        <input
          ref="seletor"
          type="file"
          class="hidden"
          accept="image/jpeg,image/png"
          data-arquivo-do-cartao
          @change="aoEscolher"
        />
      </div>
      <div
        v-if="erro"
        role="alert"
        class="flex gap-2 p-3 text-sm rounded-xl bg-n-ruby-2 text-n-ruby-11"
        data-erro-da-foto
      >
        <span
          class="i-lucide-circle-alert size-4 mt-0.5 shrink-0"
          aria-hidden="true"
        />
        <span>{{ erro }}</span>
      </div>
    </section>

    <section v-if="cartao.campos.length" class="flex flex-col gap-3">
      <h4 class="m-0 text-sm font-medium text-n-slate-12">
        {{ t(`${NS}.TEXTO`) }}
      </h4>
      <p
        class="px-3 py-2 m-0 text-sm break-words rounded-xl bg-n-alpha-1 text-n-slate-12"
      >
        {{ textoComEspacos }}
      </p>
      <Input
        v-for="nome in cartao.campos"
        :key="nome"
        :model-value="valorDoCampo(nome)"
        :label="t(`${NS}.CAMPO`, { n: nome })"
        :placeholder="
          t(`${NS}.EXEMPLO`, { exemplo: exemploDoCampo(cartao.corpo, nome) })
        "
        custom-input-class="!h-11"
        :data-campo-do-cartao="nome"
        @update:model-value="texto => mudarCampo(nome, texto)"
      />
    </section>
  </div>
</template>
