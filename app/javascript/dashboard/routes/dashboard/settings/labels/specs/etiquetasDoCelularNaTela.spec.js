import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import EtiquetasDoCelularAPI from 'dashboard/api/etiquetasDoCelular';
import NomeDaEtiquetaCelula from '../NomeDaEtiquetaCelula.vue';
import EtiquetasDoCelularAviso from '../EtiquetasDoCelularAviso.vue';
import EtiquetaDoWhatsappIcone from 'dashboard/components-next/label/EtiquetaDoWhatsappIcone.vue';
import Label from 'dashboard/components-next/label/Label.vue';

vi.mock('dashboard/api/nomesDeEtiquetas', () => ({
  default: { listar: vi.fn() },
}));
vi.mock('dashboard/api/etiquetasDoCelular', () => ({
  default: { listar: vi.fn() },
}));

// #1823, F1b — selos e aviso das etiquetas do WhatsApp do celular, só com a
// flag `etiquetas_do_celular`. O nome legível segue com `etiquetas_do_whatsapp`.
// O estado do composable é único no módulo e segue a store do último componente
// montado (no painel só existe uma). Cada teste tem a sua: desmontar entre eles.
enableAutoUnmount(afterEach);
const ETIQUETAS = [
  { id: 1, title: 'novo_cliente' },
  { id: 2, title: 'vip' },
];

const montar = (
  componente,
  { accountId, celular, nomeLivre = true, props }
) => {
  const flags = {
    [FEATURE_FLAGS.ETIQUETAS_DO_WHATSAPP]: nomeLivre,
    [FEATURE_FLAGS.ETIQUETAS_DO_CELULAR]: celular,
  };
  const store = createStore({
    getters: {
      getCurrentAccountId: () => accountId,
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        Boolean(flags[flag]),
      'labels/getLabels': () => ETIQUETAS,
    },
  });
  return mount(componente, {
    props,
    global: {
      plugins: [store],
      mocks: {
        $t: (chave, valores) => `${chave} ${JSON.stringify(valores || {})}`,
      },
      directives: { tooltip: {} },
    },
  });
};

describe('etiquetas do celular na tela', () => {
  beforeEach(() => {
    NomesDeEtiquetasAPI.listar.mockResolvedValue({ data: { payload: [] } });
    EtiquetasDoCelularAPI.listar.mockResolvedValue({
      data: {
        payload: [
          {
            label_id: 1,
            inbox_id: 7,
            caixa: 'Atendimento',
            nome_no_celular: 'Novo cliente 🔥',
            color_index: 1,
            criada_pelo_celular: true,
          },
        ],
      },
    });
  });

  afterEach(() => vi.clearAllMocks());

  it('mostra caixa e "criada pelo celular"; o nome do celular já está em destaque', async () => {
    const tela = montar(NomeDaEtiquetaCelula, {
      accountId: 40,
      celular: true,
      props: { titulo: 'novo_cliente' },
    });
    await flushPromises();

    expect(tela.text()).toContain('Novo cliente 🔥');
    expect(tela.text()).toContain(
      'LABEL_MGMT.WHATSAPP.BADGE {"caixa":"Atendimento"}'
    );
    expect(tela.text()).toContain('LABEL_MGMT.WHATSAPP.CREATED_BY_PHONE');
    expect(tela.text()).not.toContain('NAME_ON_PHONE');
  });

  it('mostra "No celular" quando o nome em destaque é o guardado aqui', async () => {
    NomesDeEtiquetasAPI.listar.mockResolvedValue({
      data: { payload: [{ label_id: 1, nome: 'Cliente novo' }] },
    });
    const tela = montar(NomeDaEtiquetaCelula, {
      accountId: 41,
      celular: true,
      props: { titulo: 'novo_cliente' },
    });
    await flushPromises();

    expect(tela.text()).toContain('Cliente novo');
    expect(tela.text()).toContain(
      'LABEL_MGMT.WHATSAPP.NAME_ON_PHONE {"nome":"Novo cliente 🔥"}'
    );
  });

  it('sem a flag etiquetas_do_celular: sem selo, sem aviso e sem ícone', async () => {
    const celula = montar(NomeDaEtiquetaCelula, {
      accountId: 42,
      celular: false,
      props: { titulo: 'novo_cliente' },
    });
    const aviso = montar(EtiquetasDoCelularAviso, {
      accountId: 42,
      celular: false,
    });
    const icone = montar(EtiquetaDoWhatsappIcone, {
      accountId: 42,
      celular: false,
      props: { titulo: 'novo_cliente' },
    });
    await flushPromises();

    expect(celula.text()).not.toContain('WHATSAPP');
    expect(aviso.text()).toBe('');
    expect(icone.find('[role="img"]').exists()).toBe(false);
    expect(EtiquetasDoCelularAPI.listar).not.toHaveBeenCalled();
  });

  it('com a flag: aviso no topo e ícone só na etiqueta que veio do celular', async () => {
    const aviso = montar(EtiquetasDoCelularAviso, {
      accountId: 43,
      celular: true,
    });
    const doCelular = montar(EtiquetaDoWhatsappIcone, {
      accountId: 43,
      celular: true,
      props: { titulo: 'novo_cliente' },
    });
    const soDaqui = montar(EtiquetaDoWhatsappIcone, {
      accountId: 43,
      celular: true,
      props: { titulo: 'vip' },
    });
    await flushPromises();

    expect(aviso.text()).toContain('LABEL_MGMT.WHATSAPP.NOTICE');
    expect(doCelular.find('[role="img"]').exists()).toBe(true);
    expect(soDaqui.find('[role="img"]').exists()).toBe(false);
  });

  it('chip: sem a flag não monta o ícone; com a flag, monta só onde há vínculo', async () => {
    const desligado = montar(Label, {
      accountId: 45,
      celular: false,
      props: { label: 'novo_cliente' },
    });
    await flushPromises();
    expect(desligado.findComponent(EtiquetaDoWhatsappIcone).exists()).toBe(
      false
    );
    expect(EtiquetasDoCelularAPI.listar).not.toHaveBeenCalled();
    desligado.unmount();

    const ligado = montar(Label, {
      accountId: 46,
      celular: true,
      props: { label: 'novo_cliente' },
    });
    await flushPromises();
    expect(ligado.find('[role="img"]').exists()).toBe(true);
    expect(EtiquetasDoCelularAPI.listar).toHaveBeenCalledTimes(1);
  });

  it('sem a flag do nome livre, mostra o título técnico com o selo', async () => {
    const tela = montar(NomeDaEtiquetaCelula, {
      accountId: 44,
      celular: true,
      nomeLivre: false,
      props: { titulo: 'novo_cliente' },
    });
    await flushPromises();

    expect(tela.find('span').text()).toBe('novo_cliente');
    expect(tela.text()).toContain('LABEL_MGMT.WHATSAPP.BADGE');
  });
});
