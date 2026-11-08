import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import BaixarRelatorio from '../BaixarRelatorio.vue';

// O "Baixar relatório" comum (Anúncios #1960, Números › Origens #2001): a escolha do formato, o pedido ao servidor
// com o formato escolhido, o nome do arquivo, o aviso de quem não pode exportar o CRM e o espaço para a tela pôr
// um botão no diálogo (com o `fechar`).
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const canExportCrm = ref(true);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canExportCrm }),
}));

const open = vi.fn();
const close = vi.fn();
const DialogStub = {
  props: ['description'],
  emits: ['confirm'],
  methods: { open, close },
  template:
    '<div><p data-descricao>{{ description }}</p><slot /><button data-dialog-confirm @click="$emit(\'confirm\')" /></div>',
};

const TEXTOS = {
  botao: 'Baixar',
  titulo: 'Baixar o relatório',
  descricao: 'Outubro, funil Vendas.',
  confirmar: 'Baixar',
  pdfTitulo: 'PDF',
  pdfDica: 'Para mostrar',
  planilhaTitulo: 'Planilha',
  planilhaDica: 'Para trabalhar',
  erro: 'Não deu',
  semPessoas: 'Só os números',
};

const montar = (props = {}, slots = {}) =>
  mount(BaixarRelatorio, {
    props: {
      textos: TEXTOS,
      pedir: vi.fn(() =>
        Promise.resolve({
          data: new Blob(['x']),
          headers: { 'content-disposition': 'attachment; filename="r.pdf"' },
        })
      ),
      nomeReserva: formato => `reserva.${formato}`,
      ...props,
    },
    attrs: { 'data-meu-botao': '' },
    slots,
    global: { stubs: { Dialog: DialogStub } },
  });

describe('BaixarRelatorio', () => {
  let clicked;

  beforeEach(() => {
    vi.clearAllMocks();
    canExportCrm.value = true;
    clicked = [];
    global.URL.createObjectURL = vi.fn(() => 'blob:x');
    global.URL.revokeObjectURL = vi.fn();
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
      function registrar() {
        clicked.push(this.getAttribute('download'));
      }
    );
  });

  it('puts the attributes on the button and shows the screen description', async () => {
    const wrapper = montar();

    await wrapper.find('[data-meu-botao]').trigger('click');

    expect(open).toHaveBeenCalled();
    expect(wrapper.find('[data-descricao]').text()).toBe(
      'Outubro, funil Vendas.'
    );
  });

  it('asks the server for the chosen format and saves with its file name', async () => {
    const pedir = vi.fn(() => Promise.resolve({ data: new Blob(['x']) }));
    const wrapper = montar({ pedir });

    await wrapper.find('[data-report-format="planilha"]').trigger('click');
    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(pedir).toHaveBeenCalledWith('planilha');
    expect(clicked).toEqual(['reserva.planilha']);
    expect(close).toHaveBeenCalled();
  });

  it('says the file has only the numbers without crm_export, and the people line with it', () => {
    expect(montar().find('[data-report-people]').exists()).toBe(false);
    expect(
      montar({ textos: { ...TEXTOS, comPessoas: 'Vai a lista' } })
        .find('[data-report-people]')
        .text()
    ).toBe('Vai a lista');

    canExportCrm.value = false;

    expect(montar().find('[data-report-no-people]').text()).toBe(
      'Só os números'
    );
  });

  it('warns and stays open when the download fails', async () => {
    const wrapper = montar({ pedir: vi.fn(() => Promise.reject(new Error())) });

    await wrapper.find('[data-dialog-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Não deu');
    expect(close).not.toHaveBeenCalled();
  });

  it('gives the slot a way to close the dialog', async () => {
    const wrapper = montar(
      {},
      {
        default: `<template #default="{ fechar }"><button data-extra @click="fechar" /></template>`,
      }
    );

    await wrapper.find('[data-extra]').trigger('click');

    expect(close).toHaveBeenCalled();
  });
});
