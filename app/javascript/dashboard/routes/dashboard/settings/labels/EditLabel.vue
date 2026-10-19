<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import validations, { getLabelTitleErrorMessage } from './validations';
import { useVuelidate } from '@vuelidate/core';

import NextButton from 'dashboard/components-next/button/Button.vue';
import NomeTecnicoDaEtiqueta from './NomeTecnicoDaEtiqueta.vue';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';
import { TAMANHO_MAXIMO_DO_NOME } from 'dashboard/helper/nomeDaEtiqueta';
import { nomeLivreEditavel, nomeLivreLongoDemais } from './nomeLivre';

export default {
  components: {
    NextButton,
    NomeTecnicoDaEtiqueta,
  },
  props: {
    selectedResponse: {
      type: Object,
      default: () => {},
    },
  },
  emits: ['close'],
  setup() {
    const { ligada, guardarNome, nomeDe } = useNomeDaEtiqueta();
    return {
      v$: useVuelidate(),
      nomeLegivelLigado: ligada,
      guardarNome,
      nomeDe,
    };
  },
  data() {
    return {
      title: '',
      nomeInicial: '',
      description: '',
      showOnSidebar: true,
      color: '',
    };
  },
  validations() {
    // Flag ligada (#1823): o campo edita só o nome livre; o `title` não muda.
    if (!this.nomeLegivelLigado) return validations;
    return { ...validations, title: { nomeLivreEditavel } };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'labels/getUIFlags',
    }),
    pageTitle() {
      const nome = this.nomeLegivelLigado
        ? this.nomeInicial
        : this.selectedResponse.title;
      return `${this.$t('LABEL_MGMT.EDIT.TITLE')} - ${nome}`;
    },
    nomeAtual() {
      return this.nomeDe(this.selectedResponse.title);
    },
    // Flag ligada (#1823): editar nunca renomeia o `title`. O Labels::UpdateService
    // só acompanha conversas e contatos; automações, macros, filtros salvos, CRM
    // e n8n que usam o nome técnico quebrariam sem aviso.
    dadosDaEtiqueta() {
      const dados = {
        id: this.selectedResponse.id,
        color: this.color,
        description: this.description,
        show_on_sidebar: this.showOnSidebar,
      };
      if (this.nomeLegivelLigado) return dados;
      return { ...dados, title: this.title.toLowerCase() };
    },
    labelTitleErrorMessage() {
      if (this.nomeLegivelLigado) {
        return nomeLivreLongoDemais(this.title)
          ? this.$t('LABEL_MGMT.READABLE_NAME.TOO_LONG', {
              max: TAMANHO_MAXIMO_DO_NOME,
            })
          : '';
      }
      const errorMessage = getLabelTitleErrorMessage(this.v$);
      return this.$t(errorMessage);
    },
  },
  watch: {
    // Os nomes chegaram depois de o formulário abrir: troca o campo que ninguém mexeu.
    nomeAtual(novo) {
      if (this.title !== this.nomeInicial) return;
      this.title = novo;
      this.nomeInicial = novo;
    },
  },
  mounted() {
    this.setFormValues();
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    // Só guarda o nome que a pessoa mudou: salvar sem mexer não fixa o nome
    // derivado do título. O nome fica preso ao id da etiqueta, não ao título.
    async guardarNomeSeMudou() {
      if (!this.nomeLegivelLigado || this.title === this.nomeInicial) {
        return true;
      }
      const { id } = this.selectedResponse;
      try {
        await this.guardarNome(id, this.title.trim());
        return true;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Nome da etiqueta: falha ao gravar', id, error);
        return false;
      }
    },
    setFormValues() {
      this.title = this.nomeAtual;
      this.nomeInicial = this.title;
      this.description = this.selectedResponse.description;
      this.showOnSidebar = this.selectedResponse.show_on_sidebar;
      this.color = this.selectedResponse.color;
    },
    editLabel() {
      this.$store
        .dispatch('labels/update', this.dadosDaEtiqueta)
        .then(async () => {
          const nomeGuardado = await this.guardarNomeSeMudou();
          useAlert(
            nomeGuardado
              ? this.$t('LABEL_MGMT.EDIT.API.SUCCESS_MESSAGE')
              : this.$t('LABEL_MGMT.READABLE_NAME.SAVE_ERROR')
          );
          setTimeout(() => this.onClose(), 10);
        })
        .catch(() => {
          useAlert(this.$t('LABEL_MGMT.EDIT.API.ERROR_MESSAGE'));
        });
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="flex flex-wrap mx-0" @submit.prevent="editLabel">
      <woot-input
        v-model="title"
        :class="{
          error: v$.title.$error,
          'label-name--input': !nomeLegivelLigado,
        }"
        class="w-full"
        :label="$t('LABEL_MGMT.FORM.NAME.LABEL')"
        :placeholder="$t('LABEL_MGMT.FORM.NAME.PLACEHOLDER')"
        :error="labelTitleErrorMessage"
        @input="v$.title.$touch"
        @blur="v$.title.$touch"
      />
      <NomeTecnicoDaEtiqueta
        v-if="nomeLegivelLigado"
        :tecnico="selectedResponse.title"
        fixo
      />
      <woot-input
        v-model="description"
        :class="{ error: v$.description.$error }"
        class="w-full"
        :label="$t('LABEL_MGMT.FORM.DESCRIPTION.LABEL')"
        :placeholder="$t('LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER')"
        @input="v$.description.$touch"
        @blur="v$.description.$touch"
      />

      <div class="w-full">
        <label>
          {{ $t('LABEL_MGMT.FORM.COLOR.LABEL') }}
          <woot-color-picker v-model="color" />
        </label>
      </div>
      <div class="flex items-center w-full gap-2">
        <input v-model="showOnSidebar" type="checkbox" :value="true" />
        <label for="conversation_creation">
          {{ $t('LABEL_MGMT.FORM.SHOW_ON_SIDEBAR.LABEL') }}
        </label>
      </div>
      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="$t('LABEL_MGMT.FORM.CANCEL')"
          @click.prevent="onClose"
        />
        <NextButton
          type="submit"
          :label="$t('LABEL_MGMT.FORM.EDIT')"
          :disabled="v$.title.$invalid || uiFlags.isUpdating"
          :is-loading="uiFlags.isUpdating"
        />
      </div>
    </form>
  </div>
</template>

<style lang="scss" scoped>
// Label API supports only lowercase letters
.label-name--input {
  :deep(input) {
    @apply lowercase;
  }
}
</style>
