import { enableAutoUnmount, mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import { withFullI18n } from 'test-i18n';
import ToolDialog from './ToolDialog.vue';

withFullI18n();
enableAutoUnmount(afterEach);

const DialogStub = {
  props: [
    'title',
    'description',
    'width',
    'overflowYAuto',
    'showConfirmButton',
    'showCancelButton',
  ],
  emits: ['confirm', 'close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
      this.$emit('close');
    },
  },
  template: `
    <form
      v-if="isOpen"
      data-test="dialog-stub"
      @submit.prevent="$emit('confirm')"
    >
      <slot />
      <slot name="footer" />
    </form>
  `,
};

describe('ToolDialog', () => {
  it('abre uma ferramenta nova com campos vazios', async () => {
    const wrapper = mount(ToolDialog, {
      props: { isOpen: true, tool: null, isSaving: false },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });
    await nextTick();

    expect(wrapper.find('input[data-test="tool-name"]').element.value).toBe('');
    expect(wrapper.find('input[data-test="tool-slug"]').element.value).toBe('');
    expect(wrapper.find('input[data-test="tool-url"]').element.value).toBe('');
    expect(wrapper.find('[data-test="stock-template"]').exists()).toBe(true);
  });

  it('aplica o modelo de estoque apenas depois da ação explícita', async () => {
    const wrapper = mount(ToolDialog, {
      props: { isOpen: true, tool: null, isSaving: false },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });
    await nextTick();

    await wrapper.find('[data-test="stock-template"]').trigger('click');

    expect(wrapper.find('input[data-test="tool-name"]').element.value).not.toBe(
      ''
    );
    expect(wrapper.find('input[data-test="tool-slug"]').element.value).not.toBe(
      ''
    );
  });

  it('emite somente o DTO editável e nunca o placeholder do segredo', async () => {
    const wrapper = mount(ToolDialog, {
      props: {
        isOpen: true,
        tool: {
          id: 7,
          name: 'Busca',
          slug: 'buscar',
          description: 'Consulta',
          enabled: true,
          http_method: 'GET',
          endpoint_url: 'https://example.test/search',
          request_body_template: '',
          headers_config: [
            { key: 'x-api-key', value: '••••••••', secret: true },
          ],
          param_schema: [],
        },
        isSaving: false,
      },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });
    await nextTick();

    await wrapper.find('[data-test="dialog-stub"]').trigger('submit');

    const [payload] = wrapper.emitted('save');
    expect(payload[0].headers_config[0]).not.toHaveProperty('value');
    expect(payload[0].headers_config[0].secret).toBe(true);
  });
});
