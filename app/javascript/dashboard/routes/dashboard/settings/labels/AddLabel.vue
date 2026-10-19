<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import validations, { getLabelTitleErrorMessage } from './validations';
import { getRandomColor } from 'dashboard/helper/labelColor';
import { useVuelidate } from '@vuelidate/core';

import NextButton from 'dashboard/components-next/button/Button.vue';
import NomeTecnicoDaEtiqueta from './NomeTecnicoDaEtiqueta.vue';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';
import {
  TAMANHO_MAXIMO_DO_NOME,
  tituloTecnicoDoNome,
} from 'dashboard/helper/nomeDaEtiqueta';
import { nomeLivreLongoDemais, nomeLivreValido } from './nomeLivre';

export default {
  components: {
    NextButton,
    NomeTecnicoDaEtiqueta,
  },
  props: {
    prefillTitle: {
      type: String,
      default: '',
    },
  },
  emits: ['close'],
  setup() {
    const { ligada, guardarNome } = useNomeDaEtiqueta();
    return {
      v$: useVuelidate(),
      nomeLegivelLigado: ligada,
      guardarNome,
    };
  },
  data() {
    return {
      color: '#000',
      description: '',
      title: '',
      showOnSidebar: true,
    };
  },
  validations() {
    // Flag ligada (#1823): digita-se o nome livre; valida-se o `title` que sai dele.
    if (!this.nomeLegivelLigado) return validations;
    return { ...validations, title: { nomeLivreValido } };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'labels/getUIFlags',
    }),
    tituloTecnico() {
      if (!this.nomeLegivelLigado) return this.title.toLowerCase();
      return tituloTecnicoDoNome(this.title);
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
  mounted() {
    this.color = getRandomColor();
    this.title = this.nomeLegivelLigado
      ? this.prefillTitle
      : this.prefillTitle.toLowerCase();
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    // O nome livre vai depois da etiqueta criada (o id vem da lista da store).
    // Se falhar, a etiqueta fica com o nome derivado do título e a pessoa sabe.
    async guardarNomeDaCriada() {
      const criada = this.$store.getters['labels/getLabels'].find(
        ({ title }) => title === this.tituloTecnico
      );
      if (!criada) return false;
      try {
        await this.guardarNome(criada.id, this.title.trim());
        return true;
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Nome da etiqueta: falha ao gravar', criada.id, error);
        return false;
      }
    },
    async addLabel() {
      try {
        await this.$store.dispatch('labels/create', {
          color: this.color,
          description: this.description,
          title: this.tituloTecnico,
          show_on_sidebar: this.showOnSidebar,
        });
        const nomeGuardado =
          !this.nomeLegivelLigado || (await this.guardarNomeDaCriada());
        useAlert(
          nomeGuardado
            ? this.$t('LABEL_MGMT.ADD.API.SUCCESS_MESSAGE')
            : this.$t('LABEL_MGMT.READABLE_NAME.SAVE_ERROR')
        );
        this.onClose();
      } catch (error) {
        const errorMessage =
          error.message || this.$t('LABEL_MGMT.ADD.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="$t('LABEL_MGMT.ADD.TITLE')"
      :header-content="$t('LABEL_MGMT.ADD.DESC')"
    />
    <form class="flex flex-wrap mx-0" @submit.prevent="addLabel">
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
        data-testid="label-title"
        @input="v$.title.$touch"
        @blur="v$.title.$touch"
      />
      <NomeTecnicoDaEtiqueta
        v-if="nomeLegivelLigado"
        :tecnico="tituloTecnico"
        :nome-digitado="title"
      />

      <woot-input
        v-model="description"
        :class="{ error: v$.description.$error }"
        class="w-full"
        :label="$t('LABEL_MGMT.FORM.DESCRIPTION.LABEL')"
        :placeholder="$t('LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER')"
        data-testid="label-description"
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
          data-testid="label-submit"
          :label="$t('LABEL_MGMT.FORM.CREATE')"
          :disabled="v$.title.$invalid || uiFlags.isCreating"
          :is-loading="uiFlags.isCreating"
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
