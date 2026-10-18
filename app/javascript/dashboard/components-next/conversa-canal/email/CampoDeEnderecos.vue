<script setup>
// Campo de destinatários do e-mail (#1786): cada endereço vira uma etiqueta com o
// nome, e o campo sugere os contatos do Chat2You enquanto se digita (combobox do
// WAI-ARIA). Enter, vírgula ou sair do campo confirmam; Backspace no vazio tira a
// última. Endereço errado fica em vermelho. Guarda o mesmo texto de sempre
// ("a@x.com, b@y.com"), então o envio não muda.
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import Avatar from 'next/avatar/Avatar.vue';
import ContactsAPI from 'dashboard/api/contacts';
import { validEmailsByComma } from 'dashboard/components/widgets/conversation/helpers/emailHeadHelper';
import { lerEndereco } from './dadosDoEmail';

const props = defineProps({
  rotulo: { type: String, required: true },
  placeholder: { type: String, default: '' },
});
const valor = defineModel({ type: String, default: '' });

const { t } = useI18n();
const id = useId();
const MINIMO_PARA_BUSCAR = 2;
const MAXIMO_DE_SUGESTOES = 6;

const enderecos = computed(() =>
  String(valor.value || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean)
);
const gravar = lista => {
  valor.value = lista.join(', ');
};

// Nomes conhecidos (das sugestões escolhidas), para a etiqueta mostrar a pessoa.
const nomes = ref({});
const rotuloDaEtiqueta = endereco =>
  nomes.value[endereco.toLowerCase()] || lerEndereco(endereco).endereco;
const valido = endereco => validEmailsByComma(endereco);
// Errado não fica só na cor: ícone na etiqueta e a frase embaixo, ligada ao campo.
const temInvalido = computed(() => enderecos.value.some(e => !valido(e)));

const digitado = ref('');
const sugestoes = ref([]);
const aberta = ref(false);
const ativa = ref(-1);
let ultimaBusca = 0;

const buscar = useDebounceFn(async texto => {
  ultimaBusca += 1;
  const numero = ultimaBusca;
  try {
    const { data } = await ContactsAPI.search(texto);
    if (numero !== ultimaBusca || texto !== digitado.value.trim()) return;
    const ja = new Set(enderecos.value.map(e => e.toLowerCase()));
    sugestoes.value = (data.payload || [])
      .filter(c => c.email && !ja.has(c.email.toLowerCase()))
      .slice(0, MAXIMO_DE_SUGESTOES)
      .map(c => ({
        id: c.id,
        nome: c.name || c.email,
        email: c.email,
        foto: c.thumbnail,
      }));
    aberta.value = sugestoes.value.length > 0;
    ativa.value = aberta.value ? 0 : -1;
  } catch {
    if (numero === ultimaBusca) aberta.value = false;
  }
}, 250);

const aoDigitar = () => {
  const texto = digitado.value.trim();
  if (texto.length < MINIMO_PARA_BUSCAR) {
    ultimaBusca += 1;
    aberta.value = false;
    return;
  }
  buscar(texto);
};

const adicionar = (endereco, nome) => {
  const limpo = String(endereco || '').trim();
  if (!limpo) return;
  if (nome) nomes.value = { ...nomes.value, [limpo.toLowerCase()]: nome };
  if (!enderecos.value.some(e => e.toLowerCase() === limpo.toLowerCase())) {
    gravar([...enderecos.value, limpo]);
  }
  digitado.value = '';
  aberta.value = false;
  ultimaBusca += 1;
};
const escolher = sugestao => adicionar(sugestao.email, sugestao.nome);
const confirmarDigitado = () => {
  // Colar vários de uma vez ("a@x.com, b@y.com") vira várias etiquetas.
  digitado.value
    .split(',')
    .map(item => item.trim())
    .filter(Boolean)
    .forEach(item => adicionar(item));
  digitado.value = '';
};
const remover = endereco =>
  gravar(enderecos.value.filter(item => item !== endereco));

const aoTeclar = evento => {
  if (aberta.value && ['ArrowDown', 'ArrowUp'].includes(evento.key)) {
    evento.preventDefault();
    const total = sugestoes.value.length;
    const passo = evento.key === 'ArrowDown' ? 1 : -1;
    ativa.value = (ativa.value + passo + total) % total;
    return;
  }
  if (evento.key === 'Enter' || evento.key === ',') {
    if (aberta.value && ativa.value >= 0) {
      evento.preventDefault();
      escolher(sugestoes.value[ativa.value]);
      return;
    }
    if (digitado.value.trim()) {
      evento.preventDefault();
      confirmarDigitado();
    }
    return;
  }
  if (evento.key === 'Escape' && aberta.value) {
    evento.preventDefault();
    evento.stopPropagation();
    aberta.value = false;
    return;
  }
  if (evento.key === 'Backspace' && !digitado.value && enderecos.value.length) {
    remover(enderecos.value.at(-1));
  }
};
</script>

<template>
  <div
    v-on-click-outside="() => (aberta = false)"
    class="relative flex items-start gap-2 min-h-11 px-1 py-1 border-b border-n-weak focus-within:border-n-brand"
  >
    <label
      :for="`${id}-campo`"
      class="w-16 flex-shrink-0 pt-2 text-sm text-n-slate-11"
    >
      {{ props.rotulo }}
    </label>
    <div class="flex flex-1 flex-wrap items-center gap-1.5 min-w-0">
      <span
        v-for="endereco in enderecos"
        :key="endereco"
        class="inline-flex items-center gap-1 max-w-full h-8 ps-2.5 pe-1 rounded-full text-sm"
        :class="
          valido(endereco)
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'bg-n-ruby-3 text-n-ruby-11'
        "
        :title="endereco"
        data-etiqueta-de-endereco
      >
        <Icon
          v-if="!valido(endereco)"
          icon="i-lucide-circle-alert"
          class="size-3.5 flex-shrink-0"
        />
        <span class="truncate">{{ rotuloDaEtiqueta(endereco) }}</span>
        <!-- O círculo é de 24 px; a área de toque vai a 44 px (after:-inset-2.5). -->
        <button
          type="button"
          class="relative grid place-content-center size-6 rounded-full hover:bg-n-alpha-3 after:absolute after:-inset-2.5 after:content-['']"
          :aria-label="t('CONVERSA_CANAL.EMAIL.REMOVER_ENDERECO', { endereco })"
          @click="remover(endereco)"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </span>
      <input
        :id="`${id}-campo`"
        v-model="digitado"
        type="text"
        role="combobox"
        autocomplete="off"
        :aria-expanded="aberta"
        :aria-controls="`${id}-lista`"
        :aria-activedescendant="ativa >= 0 ? `${id}-op-${ativa}` : undefined"
        :aria-invalid="temInvalido || undefined"
        :aria-describedby="temInvalido ? `${id}-erro` : undefined"
        :placeholder="enderecos.length ? '' : placeholder"
        class="reset-base flex-1 min-w-[6rem] h-8 bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
        @input="aoDigitar"
        @keydown="aoTeclar"
        @blur="confirmarDigitado"
      />
      <p
        v-if="temInvalido"
        :id="`${id}-erro`"
        role="alert"
        class="w-full text-xs text-n-ruby-11"
        data-erro-de-endereco
      >
        {{ t('CONVERSA_CANAL.EMAIL.ENDERECO_INVALIDO') }}
      </p>
    </div>
    <slot />
    <!-- v-if: a lista fechada não fica no DOM (o Esc da resposta procura listas abertas). -->
    <ul
      v-if="aberta"
      :id="`${id}-lista`"
      role="listbox"
      class="reset-base list-none absolute top-full start-12 z-40 mt-1 w-[min(24rem,calc(100%-3rem))] py-1 rounded-xl bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-lg"
    >
      <li
        v-for="(sugestao, indice) in sugestoes"
        :id="`${id}-op-${indice}`"
        :key="sugestao.id"
        role="option"
        :aria-selected="indice === ativa"
        class="list-none flex items-center gap-3 min-h-11 px-3 cursor-pointer"
        :class="indice === ativa ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
        @mousedown.prevent="escolher(sugestao)"
      >
        <Avatar
          :name="sugestao.nome"
          :src="sugestao.foto"
          :size="28"
          rounded-full
        />
        <span class="flex flex-col min-w-0">
          <span class="truncate text-sm text-n-slate-12">
            {{ sugestao.nome }}
          </span>
          <span class="truncate text-xs text-n-slate-11">
            {{ sugestao.email }}
          </span>
        </span>
      </li>
    </ul>
  </div>
</template>
