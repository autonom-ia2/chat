import { createApp, h } from 'vue';
import { createI18n } from 'vue-i18n';
import 'dashboard/assets/scss/app.scss';
import { buildDashboardI18nMessages } from 'dashboard/i18n/localeLoader';
import MedirVendas from 'dashboard/components-next/CampaignJourney/MedirVendas.vue';
import ResultVendas from 'dashboard/components-next/CampaignResult/ResultVendas.vue';
import StepReview from 'dashboard/components-next/CampaignJourney/StepReview.vue';
import ComprasDaAutomacao from 'dashboard/routes/dashboard/automacoes/livre/components/ComprasDaAutomacao.vue';

const q = new URLSearchParams(location.search);
const cena = q.get('cena');
const BRL = c => [{ currency: 'BRL', cents: c }];
const agora = Math.floor(Date.now() / 1000);

const VENDAS = {
  vazio: { janela_dias: 7, contando_ate: null, receberam: 0, compraram: { pessoas: 0, valor: null }, responderam: { pessoas: 0, valor: null }, sem_responder: { pessoas: 0, valor: null }, controle: null },
  semcompra: { janela_dias: 7, contando_ate: null, receberam: 237, compraram: { pessoas: 0, valor: BRL(0) }, responderam: { pessoas: 0, valor: BRL(0) }, sem_responder: { pessoas: 0, valor: BRL(0) }, controle: null },
  completo: { janela_dias: 7, contando_ate: null, receberam: 1350,
    compraram: { pessoas: 69, valor: BRL(5520000) }, responderam: { pessoas: 27, valor: BRL(2460000) },
    sem_responder: { pessoas: 42, valor: BRL(3060000) }, controle: { pessoas: 150, compraram: 3 } },
  contando: { janela_dias: 7, contando_ate: agora + 4 * 86400, receberam: 1200,
    compraram: { pessoas: 6, valor: BRL(390000) }, responderam: { pessoas: 4, valor: BRL(250000) },
    sem_responder: { pessoas: 2, valor: BRL(140000) }, controle: null },
  semvalor: { janela_dias: 15, contando_ate: null, receberam: 450,
    compraram: { pessoas: 23, valor: null }, responderam: { pessoas: 9, valor: null },
    sem_responder: { pessoas: 14, valor: null }, controle: { pessoas: 50, compraram: 4 } },
  poucos: { janela_dias: 7, contando_ate: null, receberam: 180,
    compraram: { pessoas: 0, valor: BRL(0) }, responderam: { pessoas: 0, valor: BRL(0) },
    sem_responder: { pessoas: 0, valor: BRL(0) }, controle: { pessoas: 9, compraram: 0 } },
};

const quadro = (filhos, largura = 'max-w-3xl') =>
  h('main', { class: 'min-h-screen bg-n-background p-4 sm:p-8' },
    h('div', { class: `mx-auto flex flex-col gap-6 ${largura}` }, filhos));

const App = {
  data: () => ({ janela: 7, controle: Number(q.get('controle') || 0), draft: { janelaDeCompra: 7, grupoDeControle: Number(q.get('controle') || 0) } }),
  render() {
    if (cena === 'revisao')
      return quadro([
        h('section', { class: 'rounded-2xl border border-n-weak bg-n-solid-1 px-5 shadow-sm' }, [
          h('h2', { class: 'm-0 py-4 text-base font-semibold text-n-slate-12' }, 'Revisar e enviar'),
          h(MedirVendas, { janela: this.janela, controle: this.controle,
            publico: Number(q.get('publico') || 450),
            podeControlar: q.get('pode') !== '0',
            onUpdate: m => Object.assign(this, m) }),
        ]),
      ]);
    if (cena === 'passo3')
      return h('main', { class: 'min-h-screen bg-n-background p-4 sm:p-8' }, h('div', { class: 'mx-auto max-w-6xl' },
        h(StepReview, {
          draft: { ...this.draft, when: 'now' },
          blocks: [
            { key: 'audience', step: 1, title: 'Público', main: 'Renovação outubro', detail: 'Por WhatsApp · 450 com celular' },
            { key: 'channel', step: 2, title: 'Canal e mensagem', main: 'WhatsApp Oficial', detail: 'Caixa Comercial' },
          ],
          channelLabel: 'WhatsApp Oficial', onChannelLabel: 'No público com celular', crmTag: 'Renovação outubro',
          reach: 450, preview: { total: 462, receive: 450, reasons: { opted_out: 12 } }, timeZone: 'America/Sao_Paulo',
          onUpdate: m => { this.draft = { ...this.draft, ...m }; },
        })));
    if (cena === 'resultado')
      return quadro((q.get('v') || 'completo').split(',').map(v => h(ResultVendas, { vendas: VENDAS[v] })));
    if (cena === 'automacao')
      return quadro([
        h('section', { class: 'flex flex-col gap-4 rounded-3xl border border-n-weak bg-n-solid-1 p-6' }, [
          h('h2', { class: 'm-0 text-lg font-semibold text-n-slate-12' }, 'Histórico'),
          h('p', { class: 'm-0 text-[0.9375rem] text-n-slate-11' }, 'O que a automação fez nos últimos 30 dias.'),
          h(ComprasDaAutomacao, { resumo: { dias: 30, janela: 7, passaram: Number(q.get('p') || 312),
            compraram: Number(q.get('c') ?? 18), valor: q.get('semvalor') ? null : BRL(920000) } }),
          h('div', { class: 'h-40 rounded-2xl bg-n-alpha-1' }),
        ]),
      ]);
    return h('p', 'cena?');
  },
};

const { locale, fallbackLocale, messages } = await buildDashboardI18nMessages('pt_BR');
const lojaFalsa = { getters: new Proxy({}, { get: () => undefined }), state: {}, dispatch: () => Promise.resolve(), commit: () => {} };
const app = createApp(App).use(createI18n({ legacy: false, locale, fallbackLocale, messages }));
app.provide('store', lojaFalsa);
app.config.globalProperties.$store = lojaFalsa;
app.mount('#app');
