import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import { saudeDe, sinalDe } from '../api/daMeta';
import ModeloSaude from '../components/ModeloSaude.vue';
import AlertaDeQualidade from '../components/AlertaDeQualidade.vue';
import ModeloLinha from '../components/ModeloLinha.vue';
import PonteSinalDoModelo from '../ponte/PonteSinalDoModelo.vue';

// Saúde do modelo (#1338): sinal da Meta e números dos últimos 30 dias.
const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en } });

const loja = () =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 1, role: 'administrator', permissions: [] }],
      }),
    },
  });

const montar = (componente, props) =>
  mount(componente, { props, global: { plugins: [i18n(), loja()] } });

const HEALTH = {
  days: 30,
  sent: 200,
  delivered: 190,
  read: 95,
  replied: 19,
  cost: { total: 61.12, per_reply: 3.2169, currency: 'BRL' },
  average_reply_rate: 14,
};

const modelo = (extra = {}) => ({
  id: '1',
  nome: 'Boas-vindas',
  situacao: 'pronto',
  sinal: 'bom',
  saude: saudeDe(HEALTH),
  conteudo: { formato: 'padrao', texto: [{ t: 'texto', v: 'Oi' }] },
  campos: {},
  objetivo: 'em_branco',
  numeros: [1],
  enviosNoMes: 200,
  ...extra,
});

describe('sinalDe', () => {
  it('maps the Meta quality score and treats anything else as no rating yet', () => {
    expect(sinalDe({ quality_score: { score: 'GREEN', date: 1 } })).toBe('bom');
    expect(sinalDe({ quality_score: { score: 'YELLOW' } })).toBe('atencao');
    expect(sinalDe({ quality_score: { score: 'RED' } })).toBe('ruim');
    expect(sinalDe({ quality_score: { score: 'UNKNOWN' } })).toBe('sem_nota');
    expect(sinalDe({})).toBe('sem_nota');
  });
});

describe('saudeDe', () => {
  it('turns the API health into the screen format', () => {
    expect(saudeDe(HEALTH)).toEqual({
      dias: 30,
      enviadas: 200,
      entregues: 190,
      lidas: 95,
      responderam: 19,
      custo: { total: 61.12, porResposta: 3.2169, moeda: 'BRL' },
      mediaDeRespostas: 14,
    });
  });

  it('keeps no health as undefined, never as zero sends', () => {
    expect(saudeDe(undefined)).toBeUndefined();
    expect(saudeDe({ ...HEALTH, cost: null }).custo).toBeNull();
  });
});

describe('ModeloSaude', () => {
  it('shows received, read, replied and cost per reply with the comparison', () => {
    const tela = montar(ModeloSaude, { modelo: modelo() });

    expect(tela.find('[data-numero="receberam"]').text()).toContain('190');
    expect(tela.find('[data-numero="leram"]').text()).toContain('50%');
    expect(tela.find('[data-numero="responderam"]').text()).toContain('10%');
    expect(tela.find('[data-numero="responderam"]').text()).toContain(
      'Below your templates average: 14%'
    );
    expect(tela.find('[data-numero="custo"]').text()).toContain('3.22');
    expect(tela.find('[data-sinal="bom"]').exists()).toBe(true);
  });

  it('hides the average when there are fewer than 3 templates with sends', () => {
    const semMedia = saudeDe({ ...HEALTH, average_reply_rate: null });
    const tela = montar(ModeloSaude, { modelo: modelo({ saude: semMedia }) });

    expect(tela.find('[data-numero="responderam"]').text()).not.toContain(
      'average'
    );
  });

  it('shows a dash, not 0%, when nothing was delivered yet', () => {
    const semEntrega = saudeDe({
      ...HEALTH,
      delivered: 0,
      read: 0,
      replied: 0,
      cost: { total: 0, per_reply: null, currency: 'BRL' },
    });
    const tela = montar(ModeloSaude, { modelo: modelo({ saude: semEntrega }) });

    expect(tela.find('[data-numero="leram"]').text()).toContain('—');
    expect(tela.find('[data-numero="responderam"]').text()).toContain('—');
    expect(tela.find('[data-numero="responderam"]').text()).not.toContain(
      'average'
    );
  });

  it('says nobody replied instead of a cost per reply', () => {
    const semResposta = saudeDe({
      ...HEALTH,
      replied: 0,
      cost: { ...HEALTH.cost, per_reply: null },
    });
    const tela = montar(ModeloSaude, {
      modelo: modelo({ saude: semResposta }),
    });

    expect(tela.find('[data-numero="custo"]').text()).toContain(
      'Nobody replied'
    );
  });

  it('says it was not sent only when the API says zero sends', () => {
    const zerada = saudeDe({ ...HEALTH, sent: 0, delivered: 0, cost: null });
    const tela = montar(ModeloSaude, { modelo: modelo({ saude: zerada }) });

    expect(tela.find('[data-sem-envios]').exists()).toBe(true);
    expect(tela.find('[data-numeros]').exists()).toBe(false);
  });

  it('leaves a bad signal to the alert at the top of the page', () => {
    const tela = montar(ModeloSaude, { modelo: modelo({ sinal: 'ruim' }) });

    expect(tela.find('[data-sinal]').exists()).toBe(false);
  });
});

describe('AlertaDeQualidade', () => {
  it('offers a better version (copy) to whoever creates templates', async () => {
    const tela = montar(AlertaDeQualidade, {
      sinal: 'ruim',
      podeMelhorar: true,
      podeUsar: true,
    });

    expect(tela.find('[data-melhorar]').text()).toBe('Make a better version');
    await tela.find('[data-melhorar]').trigger('click');
    expect(tela.emitted('melhorar')).toHaveLength(1);
    expect(tela.find('[data-usar]').text()).toBe('Use it anyway');
  });

  it('has no improve button for who only sees templates', () => {
    const tela = montar(AlertaDeQualidade, { sinal: 'atencao' });

    expect(tela.find('[data-melhorar]').exists()).toBe(false);
  });
});

describe('ModeloLinha', () => {
  it('shows the warning badge and the reply rate of a ready template', () => {
    const tela = montar(ModeloLinha, { modelo: modelo({ sinal: 'ruim' }) });

    expect(tela.find('[data-selo-sinal="ruim"]').text()).toBe('May be paused');
    expect(tela.find('[data-respostas]').text()).toBe('10% replied');
  });

  it('shows no badge for a good signal nor numbers without health', () => {
    const tela = montar(ModeloLinha, { modelo: modelo({ saude: undefined }) });

    expect(tela.find('[data-selo-sinal]').exists()).toBe(false);
    expect(tela.find('[data-respostas]').exists()).toBe(false);
  });
});

describe('PonteSinalDoModelo', () => {
  it('warns in the campaign about a ready template with a bad signal', () => {
    const tela = montar(PonteSinalDoModelo, {
      modelo: modelo({ sinal: 'atencao' }),
    });

    expect(tela.find('[data-ponte-sinal="atencao"]').text()).toContain(
      'Boas-vindas'
    );
  });

  it('says nothing for a good signal or a paused template', () => {
    expect(
      montar(PonteSinalDoModelo, { modelo: modelo() })
        .find('[data-ponte-sinal]')
        .exists()
    ).toBe(false);
    expect(
      montar(PonteSinalDoModelo, {
        modelo: modelo({ situacao: 'pausado', sinal: 'ruim' }),
      })
        .find('[data-ponte-sinal]')
        .exists()
    ).toBe(false);
  });
});
