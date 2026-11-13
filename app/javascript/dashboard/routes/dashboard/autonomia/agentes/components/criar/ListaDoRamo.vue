<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AgenteBotao from '../AgenteBotao.vue';
import {
  MAXIMO_DE_ITENS,
  MAXIMO_DE_LETRAS_DO_ITEM,
} from '../../constants/modelosDeRamo';

// #2881 — uma lista do agente pronto por ramo que o dono pode mudar: tirar (e voltar), editar o texto e incluir um
// item novo. Serve às perguntas da cotação e aos documentos. A lista é a que o servidor guarda: cada mudança sai
// daqui como a lista inteira nova (`mudar`), quem chama grava e devolve a lista do servidor. Aqui só ficam o rascunho
// do item em edição e o do item novo. Um item em edição por vez. O campo mostra a contagem de letras: é ela que
// liga o limite do item (o mesmo do servidor).
// itens: [{ id, texto, tirada }]. O item novo vai sem `id`: quem dá é o servidor.
// `podeMudar` falso: só leitura. `gravando`: uma mudança ainda está indo, e os botões esperam.
const props = defineProps({
  itens: { type: Array, required: true },
  rotuloIncluir: { type: String, required: true },
  exemplo: { type: String, default: '' },
  podeMudar: { type: Boolean, default: false },
  gravando: { type: Boolean, default: false },
});

const emit = defineEmits(['mudar']);

const { t } = useI18n();
const NS = 'AGENTS.JORNADA.RAMOS.CONFIRA';

const editando = ref(null);
const rascunho = ref('');
const incluindo = ref(false);
const novo = ref('');
const cheia = computed(() => props.itens.length >= MAXIMO_DE_ITENS);

const trocar = (id, mudanca) =>
  emit(
    'mudar',
    props.itens.map(item => (item.id === id ? { ...item, ...mudanca } : item))
  );

const editar = item => {
  incluindo.value = false;
  editando.value = item.id;
  rascunho.value = item.texto;
};
const salvar = () => {
  const texto = rascunho.value.trim();
  if (!texto) return;
  trocar(editando.value, { texto });
  editando.value = null;
};
const alternar = item => trocar(item.id, { tirada: !item.tirada });
const abrirInclusao = () => {
  editando.value = null;
  novo.value = '';
  incluindo.value = true;
};
const incluir = () => {
  const texto = novo.value.trim();
  if (!texto) return;
  emit('mudar', [...props.itens, { texto, tirada: false }]);
  incluindo.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <ol
      data-itens-do-ramo
      :aria-busy="gravando ? 'true' : undefined"
      class="flex flex-col gap-2 p-0 m-0 list-none"
    >
      <li
        v-for="(item, indice) in itens"
        :key="item.id"
        :data-item="item.id"
        class="flex items-start gap-3 p-3 rounded-xl bg-n-solid-1 ring-1 ring-inset ring-n-weak"
      >
        <span
          aria-hidden="true"
          class="grid text-sm font-semibold rounded-full place-items-center size-7 shrink-0 bg-n-blue-3 text-n-blue-11"
        >
          {{ indice + 1 }}
        </span>
        <div
          v-if="editando === item.id"
          data-editando
          class="flex flex-col flex-1 min-w-0 gap-2"
        >
          <TextArea
            v-model="rascunho"
            auto-height
            autofocus
            :max-length="MAXIMO_DE_LETRAS_DO_ITEM"
            show-character-count
          />
          <div class="flex flex-wrap gap-2">
            <AgenteBotao
              data-salvar-item
              :inativo="!rascunho.trim() || gravando"
              @click="salvar"
            >
              {{ t(`${NS}.SALVAR`) }}
            </AgenteBotao>
            <AgenteBotao variante="fantasma" @click="editando = null">
              {{ t(`${NS}.CANCELAR`) }}
            </AgenteBotao>
          </div>
        </div>
        <div v-else class="flex flex-col flex-1 min-w-0">
          <span
            data-texto-do-item
            class="pt-0.5 text-base leading-relaxed"
            :class="
              item.tirada ? 'line-through text-n-slate-10' : 'text-n-slate-12'
            "
          >
            {{ item.texto }}
          </span>
          <div v-if="podeMudar" class="flex flex-wrap gap-1 -ms-3">
            <AgenteBotao
              v-if="!item.tirada"
              data-editar-item
              variante="fantasma"
              :inativo="gravando"
              :aria-label="t(`${NS}.EDITAR_SR`, { item: item.texto })"
              @click="editar(item)"
            >
              {{ t(`${NS}.EDITAR`) }}
            </AgenteBotao>
            <AgenteBotao
              data-tirar-item
              variante="fantasma"
              :inativo="gravando"
              :aria-label="
                t(item.tirada ? `${NS}.VOLTAR_SR` : `${NS}.TIRAR_SR`, {
                  item: item.texto,
                })
              "
              @click="alternar(item)"
            >
              {{
                item.tirada
                  ? t(`${NS}.VOLTAR`)
                  : t('AGENTS.VITRINE.JA_VEM.TIRAR')
              }}
            </AgenteBotao>
          </div>
        </div>
      </li>
    </ol>

    <template v-if="podeMudar">
      <div
        v-if="incluindo"
        data-incluindo
        class="flex flex-col gap-2 p-3 rounded-xl bg-n-solid-2 ring-1 ring-inset ring-n-weak"
      >
        <TextArea
          v-model="novo"
          auto-height
          autofocus
          :placeholder="exemplo"
          :max-length="MAXIMO_DE_LETRAS_DO_ITEM"
          show-character-count
        />
        <div class="flex flex-wrap gap-2">
          <AgenteBotao
            data-confirmar-inclusao
            :inativo="!novo.trim() || gravando"
            @click="incluir"
          >
            {{ t(`${NS}.INCLUIR`) }}
          </AgenteBotao>
          <AgenteBotao variante="fantasma" @click="incluindo = false">
            {{ t(`${NS}.CANCELAR`) }}
          </AgenteBotao>
        </div>
      </div>
      <p v-else-if="cheia" data-lista-cheia class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.LISTA_CHEIA`, { n: MAXIMO_DE_ITENS }) }}
      </p>
      <AgenteBotao
        v-else
        data-incluir-item
        variante="contorno"
        icone="i-lucide-plus"
        class="w-fit"
        :inativo="gravando"
        @click="abrirInclusao"
      >
        {{ rotuloIncluir }}
      </AgenteBotao>
    </template>
  </div>
</template>
