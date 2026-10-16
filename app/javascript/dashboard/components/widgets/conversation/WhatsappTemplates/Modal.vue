<script>
import TemplatesPicker from './TemplatesPicker.vue';
import WhatsAppTemplateReply from './WhatsAppTemplateReply.vue';
// Fork #1716: produto e carrossel seguem pela tela própria da conversa.
import EnviarModeloDaConversa from 'dashboard/routes/dashboard/campaigns/modelos/conversa/EnviarModeloDaConversa.vue';
import { tipoNaConversa } from 'dashboard/routes/dashboard/campaigns/modelos/conversa/modeloNaConversa';
export default {
  components: {
    TemplatesPicker,
    WhatsAppTemplateReply,
    EnviarModeloDaConversa,
  },
  props: {
    show: {
      type: Boolean,
      default: false,
    },
    inboxId: {
      type: Number,
      default: undefined,
    },
    sendRenderedContent: {
      type: Boolean,
      default: false,
    },
    requestContactInfoOnly: {
      type: Boolean,
      default: false,
    },
  },
  // Fork #1716: 'close' repassado do woot-modal (o template agora tem duas raízes).
  emits: ['onSend', 'cancel', 'update:show', 'close'],
  data() {
    return {
      selectedWaTemplate: null,
    };
  },
  computed: {
    localShow: {
      get() {
        return this.show;
      },
      set(value) {
        this.$emit('update:show', value);
      },
    },
    modalHeaderContent() {
      return this.selectedWaTemplate
        ? this.$t('WHATSAPP_TEMPLATES.MODAL.TEMPLATE_SELECTED_SUBTITLE', {
            templateName: this.selectedWaTemplate.name,
          })
        : this.$t('WHATSAPP_TEMPLATES.MODAL.SUBTITLE');
    },
  },
  watch: {
    show(value) {
      if (!value) this.selectedWaTemplate = null;
    },
    requestContactInfoOnly() {
      this.selectedWaTemplate = null;
    },
  },
  methods: {
    pickTemplate(template) {
      if (tipoNaConversa(template)) {
        this.$emit('cancel');
        this.$refs.modeloDaConversa.abrir(template);
        return;
      }
      this.selectedWaTemplate = template;
    },
    onResetTemplate() {
      this.selectedWaTemplate = null;
    },
    onSendMessage(message) {
      this.$emit('onSend', message);
    },
    onClose() {
      this.$emit('cancel');
    },
  },
};
</script>

<template>
  <woot-modal
    v-model:show="localShow"
    :on-close="onClose"
    size="modal-big"
    @close="$emit('close')"
  >
    <woot-modal-header
      :header-title="$t('WHATSAPP_TEMPLATES.MODAL.TITLE')"
      :header-content="modalHeaderContent"
    />
    <div class="row modal-content">
      <TemplatesPicker
        v-if="!selectedWaTemplate"
        :inbox-id="inboxId"
        :request-contact-info-only="requestContactInfoOnly"
        @on-select="pickTemplate"
      />
      <WhatsAppTemplateReply
        v-else
        :template="selectedWaTemplate"
        :send-rendered-content="sendRenderedContent"
        @reset-template="onResetTemplate"
        @send-message="onSendMessage"
      />
    </div>
  </woot-modal>
  <EnviarModeloDaConversa
    v-if="inboxId"
    ref="modeloDaConversa"
    :caixa="inboxId"
    @enviar="onSendMessage"
  />
</template>

<style scoped>
.modal-content {
  padding: 1.5625rem 2rem;
}
</style>
