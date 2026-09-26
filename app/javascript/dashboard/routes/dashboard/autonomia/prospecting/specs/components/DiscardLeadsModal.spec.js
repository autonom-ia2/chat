// Janela "Descartar" (#732, item 10): um lead do painel ou a seleção da
// busca, sempre com motivo. O motivo é uma das escolhas prontas ou o texto
// que a pessoa escreve em "Outro motivo".
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import { isFixedPanelOpen } from 'dashboard/composables/useFixedPanelState';
import DiscardLeadsModal from '../../components/search/DiscardLeadsModal.vue';
import { ChoiceSelectStub } from '../support/searchPageHarness';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();

const LEADS = [
  { id: 101, name: 'Padaria Sol' },
  { id: 102, name: 'Pão Quente' },
];

const mountModal = (discard = vi.fn().mockResolvedValue({ leads: [] })) =>
  mount(DiscardLeadsModal, {
    props: { leads: LEADS, discard },
    global: { stubs: { ChoiceSelect: ChoiceSelectStub } },
  });

const reasonChoice = wrapper =>
  wrapper
    .findAllComponents(ChoiceSelectStub)
    .find(item => item.props('ariaLabel') === 'Motivo');
const submit = wrapper => wrapper.find('[data-test="discard-submit"]');
const chooseReason = async (wrapper, value) => {
  reasonChoice(wrapper).vm.$emit('update:modelValue', value);
  await flushPromises();
};

describe('DiscardLeadsModal', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  it('é uma janela com título, diz quantos leads e avisa o lançador do Guia', () => {
    const wrapper = mountModal();

    expect(wrapper.find('[role="dialog"]').attributes('aria-modal')).toBe(
      'true'
    );
    expect(wrapper.find('h2').text()).toBe('Descartar leads');
    expect(wrapper.text()).toContain('2 lead(s) saem do envio ao CRM');
    expect(isFixedPanelOpen.value).toBe(true);
    wrapper.unmount();
    expect(isFixedPanelOpen.value).toBe(false);
  });

  it('sem motivo não descarta', async () => {
    const discard = vi.fn();
    const wrapper = mountModal(discard);

    expect(submit(wrapper).attributes('disabled')).toBeDefined();
    await submit(wrapper).trigger('click');
    expect(discard).not.toHaveBeenCalled();
  });

  it('descarta com o motivo escolhido e avisa quantos', async () => {
    const response = { leads: [{ id: 101 }, { id: 102 }] };
    const discard = vi.fn().mockResolvedValue(response);
    const wrapper = mountModal(discard);

    expect(
      reasonChoice(wrapper)
        .props('options')
        .map(option => option.label)
    ).toEqual([
      'Sem interesse',
      'Fora do perfil',
      'Já é cliente',
      'Dados errados',
      'Empresa fechada',
      'Outro motivo',
    ]);
    await chooseReason(wrapper, 'OUT_OF_PROFILE');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(discard).toHaveBeenCalledWith([101, 102], 'Fora do perfil');
    expect(useAlert).toHaveBeenCalledWith('2 lead(s) descartado(s).');
    expect(wrapper.emitted('discarded')[0][0]).toEqual(response);
  });

  it('"Outro motivo" pede o texto e manda o que a pessoa escreveu', async () => {
    const discard = vi.fn().mockResolvedValue({ leads: [] });
    const wrapper = mountModal(discard);

    await chooseReason(wrapper, 'OTHER');
    expect(submit(wrapper).attributes('disabled')).toBeDefined();
    await wrapper.find('input[type="text"]').setValue('  Mudou de cidade  ');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(discard).toHaveBeenCalledWith([101, 102], 'Mudou de cidade');
  });

  it('recusa do servidor aparece na janela e nada é emitido', async () => {
    const discard = vi.fn().mockRejectedValue({
      response: { data: { error: 'Informe o motivo do descarte.' } },
    });
    const wrapper = mountModal(discard);

    await chooseReason(wrapper, 'NO_INTEREST');
    await submit(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Informe o motivo do descarte.'
    );
    expect(wrapper.emitted('discarded')).toBeUndefined();
  });
});
