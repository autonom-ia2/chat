import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import * as demoDados from '../demo/acharDemo';
import AcharConfiraCabecalho from '../components/AcharConfiraCabecalho.vue';
import AcharFolhaEnvio from '../components/AcharFolhaEnvio.vue';
import {
  MOTIVO_NAO_SERVE,
  comoMandada,
  contasDaLista,
  naoVao,
} from '../utils/acharConfiraEstados';

// P3 da crítica r5, com os textos de verdade: "Ficam de fora" é só quem o
// sistema barra; a empresa mandada pela gaveta tem conta própria, no cabeçalho
// e na folha, e a soma fecha nas achadas (13 + 2 + 4 + 1 = 20).
config.global.plugins = [
  createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: { pt_BR: ptBR },
  }),
];

const TIRADAS = demoDados.TIRADAS_NA_JORNADA;
const MANDADA = 1;

const jornadaComMandada = () => {
  const empresas = demoDados
    .empresas()
    .map(empresa =>
      empresa.id === MANDADA ? comoMandada(empresa, 'você') : empresa
    );
  const elegiveis = empresas.filter(empresa => !empresa.fora);
  const escolhidas = elegiveis.filter(
    empresa => !TIRADAS.includes(empresa.id) && !empresa.mandada
  );
  return { empresas, elegiveis, escolhidas };
};

describe('contas da lista (P3)', () => {
  it('separa vão, você tirou, ficam de fora e você já mandou, e fecha nas achadas', () => {
    const contas = contasDaLista(jornadaComMandada());

    expect(contas).toEqual({
      achadas: 20,
      vao: 13,
      tiradas: 2,
      fora: 4,
      mandadas: 1,
    });
    expect(contas.vao + contas.tiradas + contas.fora + contas.mandadas).toBe(
      contas.achadas
    );
  });

  it('"Por que N não vão" não conta a empresa mandada', () => {
    const { empresas } = jornadaComMandada();
    const total = naoVao(empresas, 2).reduce((soma, item) => soma + item.n, 0);

    expect(total).toBe(6);
    expect(naoVao(empresas, 2).map(item => item.motivo)).not.toContain(
      'voce_mandou'
    );
  });

  it('"Não serve" nesta busca conta em "você tirou", não em "ficam de fora", e a soma fecha', () => {
    const base = jornadaComMandada();
    const tirada = base.escolhidas[0].id;
    const empresas = base.empresas.map(empresa =>
      empresa.id === tirada
        ? { ...empresa, fora: { motivo: MOTIVO_NAO_SERVE } }
        : empresa
    );
    const elegiveis = empresas.filter(empresa => !empresa.fora);
    const escolhidas = base.escolhidas.filter(empresa => empresa.id !== tirada);
    const contas = contasDaLista({ empresas, elegiveis, escolhidas });
    const motivos = naoVao(empresas, contas.tiradas);

    expect(contas).toEqual({
      achadas: 20,
      vao: 12,
      tiradas: 3,
      fora: 4,
      mandadas: 1,
    });
    expect(contas.vao + contas.tiradas + contas.fora + contas.mandadas).toBe(
      contas.achadas
    );
    expect(motivos.map(item => item.motivo)).not.toContain(MOTIVO_NAO_SERVE);
    expect(motivos.find(item => item.motivo === 'voce_tirou').n).toBe(3);
  });

  it('o cabeçalho mostra as contas separadas', () => {
    const wrapper = mount(AcharConfiraCabecalho, {
      props: {
        busca: { oQue: 'Escritórios', lugar: 'Centro, Campinas, SP' },
        contas: contasDaLista(jornadaComMandada()),
      },
    });

    expect(wrapper.find('[data-fatos]').text()).toBe(
      '20 achadas · 13 vão · 2 você tirou · 4 ficam de fora · 1 você já mandou'
    );
  });

  it('sem tirar nem mandar, as contas zeradas não aparecem; quem só lê vê só as achadas', () => {
    const busca = { oQue: 'Escritórios', lugar: 'Centro' };
    const contas = { achadas: 20, vao: 16, tiradas: 0, fora: 4, mandadas: 0 };
    const dona = mount(AcharConfiraCabecalho, { props: { busca, contas } });
    const leitura = mount(AcharConfiraCabecalho, {
      props: { busca, contas, leitura: true },
    });

    expect(dona.find('[data-fatos]').text()).toBe(
      '20 achadas · 16 vão · 4 ficam de fora'
    );
    expect(leitura.find('h1').text()).toBe('Escritórios · Centro');
    expect(leitura.find('[data-fatos]').text()).toBe('20 achadas');
  });

  it('a folha diz "Por que 6 não vão" e mostra "1 você já mandou" à parte', () => {
    const { empresas } = jornadaComMandada();
    const wrapper = mount(AcharFolhaEnvio, {
      attachTo: document.body,
      props: {
        n: 13,
        podeFunil: true,
        destino: {
          funil: { id: 101, nome: 'Vendas' },
          etapa: { id: 1001, nome: 'Novo contato' },
        },
        pessoa: 'você',
        naoVao: naoVao(empresas, 2),
        mandadas: 1,
        mostrarFora: true,
      },
    });

    expect(document.querySelector('[data-ver-fora]').textContent).toContain(
      'Por que 6 não vão'
    );
    expect(
      [...document.querySelectorAll('[data-lista-fora] li')].map(item =>
        item.textContent.trim()
      )
    ).toEqual([
      '2 já estão no funil',
      '1 não quer receber mensagem',
      '1 empresa fechada',
      '2 você tirou',
    ]);
    expect(document.querySelector('[data-ja-mandou]').textContent.trim()).toBe(
      '1 você já mandou'
    );
    wrapper.unmount();
  });
});
