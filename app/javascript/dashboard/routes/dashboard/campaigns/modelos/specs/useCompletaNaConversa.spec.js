import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useCompletaNaConversa } from '../conversa/useCompletaNaConversa';

// #1716: quem atende a caixa completa produto e carrossel na conversa; numa
// caixa que a pessoa não atende (fora da lista de caixas dela), nada muda.
const flags = vi.hoisted(() => ({ ligadas: [] }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.ligadas.includes(flag),
  }),
}));

const CLOUD = {
  id: 7,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
};
const PRODUTOS = 'whatsapp_campaign_products';

const ler = ({ caixas, ligadas = [] }) => {
  flags.ligadas = ligadas;
  let resultado;
  const Teste = defineComponent({
    setup() {
      resultado = useCompletaNaConversa(7);
      return () => h('div');
    },
  });
  mount(Teste, {
    global: {
      plugins: [
        createStore({
          getters: {
            'inboxes/getInbox': () => id =>
              caixas.find(item => item.id === Number(id)),
          },
        }),
      ],
    },
  });
  return {
    opcoes: resultado.opcoes.value,
    podeSubirFoto: resultado.podeSubirFoto.value,
  };
};

describe('useCompletaNaConversa (#1716)', () => {
  it('quem atende a caixa oficial completa fotos e, com a flag, produtos', () => {
    expect(ler({ caixas: [CLOUD], ligadas: [PRODUTOS] })).toEqual({
      opcoes: { completa: { fotos: true, produtos: true } },
      podeSubirFoto: true,
    });
    expect(ler({ caixas: [CLOUD] }).opcoes).toEqual({
      completa: { fotos: true, produtos: false },
    });
  });

  it('caixa que a pessoa não atende: o seletor fica como antes', () => {
    expect(ler({ caixas: [], ligadas: [PRODUTOS] })).toEqual({
      opcoes: {},
      podeSubirFoto: false,
    });
  });

  it('WhatsApp de outro fornecedor: o seletor fica como antes', () => {
    const outro = { ...CLOUD, provider: 'default' };
    expect(ler({ caixas: [outro] }).opcoes).toEqual({});
  });
});
