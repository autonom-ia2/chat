<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import PhoneNumberInput from 'dashboard/components-next/phonenumberinput/PhoneNumberInput.vue';
import CrmCardRelationshipPanel from '../../CrmCardRelationshipPanel.vue';
import CardPessoaBasica from './CardPessoaBasica.vue';
import { useCardContato } from '../useCardContato';
import { textosCom } from '../textos';

// #1423 — a pessoa e a empresa do card (antiga aba Relacionamento). Reusa o
// painel de relacionamento inteiro (RL-01 a RL-12) e põe aqui o formulário de
// editar a pessoa (RL-05). A gaveta lê o que está sujo e qual botão vai ao
// rodapé pelo que esta tela expõe.
const props = defineProps({
  card: { type: Object, required: true },
  podeGerenciar: { type: Boolean, default: false },
  podeRegistros: { type: Boolean, default: false },
  // 'pessoa' (tela Contato) ou 'empresa' (tela Empresa).
  parte: { type: String, default: 'pessoa' },
  // Sem ver contatos (#1849), só nome, telefone e e-mail da pessoa do card.
  podeVerContatos: { type: Boolean, default: true },
});
const emit = defineEmits(['guard', 'mudou']);

const { t, te } = useI18n();
const route = useRoute();
const painel = ref(null);
const contato = useCardContato();
const formId = computed(() => `crm-card-pessoa-${props.card.id}`);
// As frases do painel reaproveitado vêm de CRM_CARD.PESSOA (OB-05).
const TEXTOS = 'CRM_CARD.PESSOA';
const rotulo = textosCom({ t, te }, TEXTOS, 'CRM_KANBAN.RELATIONSHIP');

watch(
  () => props.card?.contact,
  pessoa => {
    if (!contato.editando.value) contato.carregar(pessoa);
  },
  { immediate: true }
);

const comecar = pessoa => {
  if (props.podeRegistros) contato.comecar(pessoa);
};
const salvar = async () => {
  if (!props.podeRegistros) return;
  const id = props.card.id;
  const salvou = await contato.salvar(rotulo);
  if (!salvou || props.card.id !== id) return;
  await painel.value?.reload();
  emit('mudou');
  useAlert(rotulo('SAVED'));
};
// O servidor apontou o campo (422): "Confira este campo" embaixo dele.
const confira = campo =>
  contato.camposComErro.value.includes(campo) ? rotulo('CAMPO_CONFIRA') : '';
const desfazer = () => {
  contato.desfazer();
  painel.value?.reset();
};

defineExpose({
  sujo: computed(
    () =>
      (contato.editando.value && contato.sujo.value) ||
      painel.value?.dirty === true
  ),
  ocupado: computed(
    () => contato.salvando.value || painel.value?.saving === true
  ),
  editando: contato.editando,
  salvando: contato.salvando,
  podeSalvar: computed(() => Boolean(contato.form.name.trim())),
  formId,
  empresa: computed(() => painel.value?.companyAction || null),
  vinculando: computed(() => painel.value?.linking === true),
  desfazer,
});
</script>

<template>
  <section
    class="flex flex-col gap-4 [&_button]:min-h-11"
    :data-tela="parte === 'empresa' ? 'empresa' : 'contato'"
  >
    <CardPessoaBasica v-if="!podeVerContatos" :contato="card.contact" />
    <CrmCardRelationshipPanel
      v-else
      ref="painel"
      :key="`${route.params.accountId}:${card.id}`"
      :card="card"
      :can-manage="podeGerenciar"
      :can-manage-records="podeRegistros"
      :editing="contato.editando.value && podeRegistros"
      :textos="TEXTOS"
      :parte="parte"
      @edit="comecar"
      @guard="acao => emit('guard', acao)"
      @linked="emit('mudou')"
    >
      <template #editor>
        <form
          :id="formId"
          class="grid gap-4"
          data-contact-editor
          @submit.prevent="salvar"
        >
          <p class="mb-0 text-sm text-n-slate-11">{{ rotulo('EDIT_HELP') }}</p>
          <p
            v-if="contato.erro.value"
            role="alert"
            class="mb-0 rounded-xl bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
          >
            {{ contato.erro.value }}
          </p>
          <div class="grid grid-cols-1 gap-4 min-[440px]:grid-cols-2">
            <Input
              v-model="contato.form.name"
              :label="rotulo('NAME')"
              required
              :disabled="contato.salvando.value"
              :message="
                !contato.form.name.trim()
                  ? t('CRM_CARD.CLIENTE.NOME_FALTA')
                  : confira('name')
              "
              :message-type="
                !contato.form.name.trim() || confira('name') ? 'error' : 'info'
              "
              class="min-[440px]:col-span-2"
            />
            <Input
              v-model="contato.form.email"
              type="email"
              :label="rotulo('EMAIL')"
              :disabled="contato.salvando.value"
              :message="confira('email')"
              :message-type="confira('email') ? 'error' : 'info'"
            />
            <!-- Mesmo rótulo, espaço e altura das outras caixas (Input). -->
            <div class="flex min-w-0 flex-col gap-1" data-campo-telefone>
              <span class="mb-0.5 text-heading-3 text-n-slate-12">
                {{ rotulo('PHONE') }}
              </span>
              <PhoneNumberInput
                v-model="contato.form.phoneNumber"
                :aria-label="rotulo('PHONE')"
                :compact="false"
                :disabled="contato.salvando.value"
              />
              <p
                v-if="confira('phoneNumber')"
                class="mb-0 mt-1 text-label-small text-n-ruby-9"
              >
                {{ confira('phoneNumber') }}
              </p>
            </div>
            <Input
              v-model="contato.form.jobTitle"
              :label="rotulo('ROLE')"
              :disabled="contato.salvando.value"
            />
            <Input
              v-model="contato.form.city"
              :label="rotulo('CITY')"
              :disabled="contato.salvando.value"
            />
            <Input
              v-model="contato.form.address"
              :label="rotulo('ADDRESS')"
              :disabled="contato.salvando.value"
              class="min-[440px]:col-span-2"
            />
            <Input
              v-model="contato.form.country"
              :label="rotulo('COUNTRY')"
              :disabled="contato.salvando.value"
            />
          </div>
        </form>
      </template>
    </CrmCardRelationshipPanel>
  </section>
</template>
