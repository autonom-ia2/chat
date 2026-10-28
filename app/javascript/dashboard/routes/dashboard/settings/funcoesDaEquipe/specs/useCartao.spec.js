import { defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { useCartao } from '../guiada/useCartao';
import { global } from './montar';

// #2308, especificação 5.B1: a trava do cartão pronto diz o que falta sem contradizer o cartão (rodada 4): "Sem mexer
// em Relatórios" ao lado de "Vê os relatórios" e "Sem mexer em Campanhas" quando só falta disparar.
const comCartao = () => {
  let cartao;
  mount(
    defineComponent({
      setup() {
        cartao = useCartao();
        return () => null;
      },
    }),
    { global: global() }
  );
  return cartao;
};

describe('useCartao › trava', () => {
  it('disparar campanhas e os relatórios de atendimento têm nome próprio', () => {
    const { trava } = comCartao();
    expect(trava({ motivo: 'MISSING', chaves: ['campaign_send'] })).toBe(
      'Sem disparar campanhas: você não tem isto.'
    );
    expect(trava({ motivo: 'MISSING', chaves: ['report_manage'] })).toBe(
      'Sem ver os relatórios de atendimento: você não tem isto.'
    );
  });

  it('na reserva, ver ou mexer pelo nível da chave', () => {
    const { trava } = comCartao();
    expect(trava({ motivo: 'MISSING', chaves: ['inbox_view'] })).toBe(
      'Sem ver Canais (números de WhatsApp, Instagram, e-mail): você não tem isto.'
    );
    expect(trava({ motivo: 'MISSING', chaves: ['inbox_manage'] })).toBe(
      'Sem mexer em Canais (números de WhatsApp, Instagram, e-mail): você não tem isto.'
    );
  });
});
