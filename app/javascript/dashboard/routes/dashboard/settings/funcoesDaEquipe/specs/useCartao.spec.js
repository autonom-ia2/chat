import { defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { useCartao } from '../guiada/useCartao';
import { global } from './montar';

// #2308, especificação 5.B1: a trava do cartão pronto diz o que falta sem contradizer o cartão (rodada 4): nada de "Sem
// mudar os Relatórios" ao lado de "Vê os relatórios", nem "Sem mudar as Campanhas" quando só falta disparar.
let montado = null;
const comCartao = () => {
  let cartao;
  montado = mount(
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

afterEach(() => {
  montado?.unmount();
  montado = null;
});

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

  // Rodada 5: a área vai com artigo, como numa frase. Rodada 6: em minúscula, a mesma forma da Perda de acesso
  // ("Sem ver o desempenho da equipe", "Sem mudar os canais").
  it('na reserva, ver ou mudar pelo nível da chave, com a área e o artigo', () => {
    const { trava } = comCartao();
    expect(trava({ motivo: 'MISSING', chaves: ['inbox_view'] })).toBe(
      'Sem ver os canais: você não tem isto.'
    );
    expect(trava({ motivo: 'MISSING', chaves: ['inbox_manage'] })).toBe(
      'Sem mudar os canais: você não tem isto.'
    );
    expect(trava({ motivo: 'MISSING', chaves: ['desempenho_view'] })).toBe(
      'Sem ver o desempenho da equipe: você não tem isto.'
    );
    expect(trava({ motivo: 'DELEGATION', chaves: ['label_manage'] })).toBe(
      'Sem mudar as etiquetas: só o administrador dá.'
    );
  });
});

describe('useCartao › capacidade', () => {
  it('"Só olha" e "Vê" com a lista das áreas', () => {
    const { capacidade } = comCartao();
    expect(
      capacidade({ chave: 'SO_OLHA_AREAS', areas: ['CONTACTS', 'CRM'] })
    ).toBe('Só olha contatos e vendas');
    expect(capacidade({ chave: 'VE_AREAS', areas: ['REPORTS'] })).toBe(
      'Vê relatórios'
    );
  });
});
