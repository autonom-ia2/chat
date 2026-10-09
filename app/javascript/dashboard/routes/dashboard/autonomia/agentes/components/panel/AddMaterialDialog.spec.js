import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaSourcesAPI from 'dashboard/api/autonomia/sources';
import AddMaterialDialog from './AddMaterialDialog.vue';

vi.mock('dashboard/api/autonomia/sources', () => ({
  default: {
    create: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

const DialogStub = {
  template: `
    <form data-testid="dialog" @submit.prevent="$emit('confirm')">
      <slot />
      <slot name="footer" />
    </form>
  `,
  props: ['title', 'confirmButtonLabel', 'disableConfirmButton', 'isLoading'],
  emits: ['confirm', 'close'],
  methods: {
    open() {},
    close() {},
  },
};

const mountDialog = props =>
  mount(AddMaterialDialog, {
    props: { agentId: 42, ...props },
    global: {
      stubs: { Dialog: DialogStub },
    },
  });

const chooseFile = async (wrapper, file) => {
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', {
    configurable: true,
    value: [file],
  });
  await input.trigger('change');
};

describe('AddMaterialDialog', () => {
  beforeEach(() => {
    AutonomiaSourcesAPI.create.mockReset();
    AutonomiaSourcesAPI.create.mockResolvedValue({ data: {} });
  });

  it('envia link validado com o descriptor real de knowledge', async () => {
    const wrapper = mountDialog();
    await wrapper.get('input[type="url"]').setValue('https://example.com/help');
    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();

    expect(AutonomiaSourcesAPI.create).toHaveBeenCalledWith(42, {
      url: 'https://example.com/help',
      kind: 'knowledge',
    });
    expect(wrapper.emitted('added')).toHaveLength(1);
    expect(wrapper.find('[data-action="choose-file"]').exists()).toBe(false);
  });

  it('não envia URL inválida', async () => {
    const wrapper = mountDialog();
    await wrapper.get('input[type="url"]').setValue('example.com/help');
    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();

    expect(AutonomiaSourcesAPI.create).not.toHaveBeenCalled();
    expect(wrapper.get('[role="alert"]').text()).toContain('URL');

    await wrapper.get('input[type="url"]').setValue('https://example.com/help');
    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();
    expect(AutonomiaSourcesAPI.create).toHaveBeenCalledWith(42, {
      url: 'https://example.com/help',
      kind: 'knowledge',
    });
  });

  it('rejeita arquivo acima de 25 MB antes do POST', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-action="mode-file"]').trigger('click');
    const file = new File(['x'], 'manual.pdf', { type: 'application/pdf' });
    Object.defineProperty(file, 'size', { value: 25 * 1024 * 1024 + 1 });
    await chooseFile(wrapper, file);
    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();

    expect(AutonomiaSourcesAPI.create).not.toHaveBeenCalled();
    expect(wrapper.get('[role="alert"]').text()).toContain('25');
  });

  it('envia arquivo com kind knowledge e bloqueia o diálogo quando disabled', async () => {
    const wrapper = mountDialog();
    await wrapper.get('[data-action="mode-file"]').trigger('click');
    const file = new File(['x'], 'manual.pdf', { type: 'application/pdf' });
    await chooseFile(wrapper, file);
    await wrapper.get('[data-testid="dialog"]').trigger('submit');
    await flushPromises();

    expect(AutonomiaSourcesAPI.create).toHaveBeenCalledWith(42, {
      file,
      kind: 'knowledge',
    });

    const disabled = mountDialog({ disabled: true });
    expect(disabled.get('[data-action="confirm"]').attributes('disabled')).toBe(
      ''
    );
  });
});
