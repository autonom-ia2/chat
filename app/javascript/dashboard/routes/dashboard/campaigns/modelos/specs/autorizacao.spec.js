import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import AutorizacaoPage from '../pages/AutorizacaoPage.vue';
import AutorizacaoResumo from '../components/AutorizacaoResumo.vue';
import { autorizacaoDaApi } from '../api/autorizacao';

// #1586: autorização do dono para o sistema criar modelos, pela API real
// (whatsapp_template_consent). Os textos das confirmações vêm do servidor.
const api = vi.hoisted(() => ({ getConsent: vi.fn(), updateConsent: vi.fn() }));
vi.mock('dashboard/api/whatsappTemplates', () => ({ default: api }));
const conta = vi.hoisted(() => ({ atual: null }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: conta.atual }),
}));
const admin = vi.hoisted(() => ({ eh: true }));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(admin.eh) }),
}));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ installationName: ref('Chat2You') }),
}));

const TEXTOS = {
  ligar: {
    utility: 'Você autoriza o Chat2You a criar modelos de Aviso de serviço.',
    marketing: 'Você autoriza também a Divulgação.',
  },
  desligar: {
    utility: 'O Chat2You para de criar modelos sozinho.',
    marketing: 'O Chat2You para de criar modelos de Divulgação.',
  },
};

const payload = ({ servico = null, divulgacao = null } = {}) => ({
  utility: { ativo: servico?.acao === 'ligou', mudanca: servico },
  marketing: { ativo: divulgacao?.acao === 'ligou', mudanca: divulgacao },
  aviso: {
    versao: '2026-10-01',
    vigente_desde: '2026-10-01',
    moeda: 'BRL',
    precos: { utility: '0.0350', marketing: '0.3217' },
    textos: TEXTOS,
    limites: { modelos: 250, modelos_verificada: 6000, por_hora: 100 },
  },
});

const LIGOU = { acao: 'ligou', por: 'Ana Souza', em: '2026-10-15T17:32:00Z' };
const resposta = dados => Promise.resolve({ data: { payload: dados } });

// Dublê do Dialog: <dialog> nativo não abre no jsdom.
const DialogFalso = {
  props: ['title', 'description'],
  emits: ['confirm'],
  data: () => ({ aberto: false }),
  methods: {
    open() {
      this.aberto = true;
    },
    close() {
      this.aberto = false;
    },
  },
  template:
    '<div v-if="aberto" data-dialogo :data-titulo="title"><p>{{ description }}</p><slot /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
};

const montar = componente =>
  mount(componente, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: {
        'router-link': { template: '<a><slot /></a>' },
        Dialog: DialogFalso,
      },
    },
  });

const confirmar = async wrapper => {
  await wrapper.find('[data-confirmar]').trigger('click');
  await flushPromises();
};

beforeEach(() => {
  api.getConsent.mockReset();
  api.updateConsent.mockReset();
  conta.atual = ref({ timezone: 'America/Sao_Paulo' });
  admin.eh = true;
});

describe('autorizacaoDaApi', () => {
  it('maps the API payload to the screen names and numbers', () => {
    const dados = autorizacaoDaApi(payload({ servico: LIGOU }));

    expect(dados).toMatchObject({
      servico: true,
      divulgacao: false,
      mudanca: LIGOU,
      mudancaDivulgacao: null,
      versao: '2026-10-01',
      precos: {
        servico: { valor: 0.035, moeda: 'BRL' },
        divulgacao: { valor: 0.3217, moeda: 'BRL' },
      },
      textos: {
        ligar: { servico: TEXTOS.ligar.utility },
        desligar: { divulgacao: TEXTOS.desligar.marketing },
      },
      limites: { modelos: 250, modelosVerificada: 6000, porHora: 100 },
    });
  });
});

describe('AutorizacaoPage', () => {
  it('starts unchecked; Promotion only unlocks with Service notice', async () => {
    api.getConsent.mockReturnValue(resposta(payload()));
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    const [servico, divulgacao] = wrapper.findAll('input[type="checkbox"]');
    expect(servico.element.checked).toBe(false);
    expect(divulgacao.element.disabled).toBe(true);
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain('Service notice');
    expect(wrapper.text()).toContain('even while the conversation is open');
    expect(wrapper.text()).toContain('in effect since 10/01/2026');
  });

  it('turns both on with the server texts and the shown version', async () => {
    api.getConsent.mockReturnValue(resposta(payload()));
    api.updateConsent.mockReturnValue(
      resposta(payload({ servico: LIGOU, divulgacao: LIGOU }))
    );
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
    await wrapper.findAll('input[type="checkbox"]')[1].setValue(true);
    await wrapper.find('[data-ligar]').trigger('click');

    const dialogo = wrapper.find('[data-dialogo-ligar]');
    expect(dialogo.text()).toContain(TEXTOS.ligar.utility);
    expect(dialogo.text()).toContain(TEXTOS.ligar.marketing);

    await confirmar(wrapper);

    expect(api.updateConsent).toHaveBeenCalledWith({
      acao: 'ligar',
      marcas: ['utility', 'marketing'],
      versaoAviso: '2026-10-01',
    });
    expect(wrapper.find('[data-situacao]').attributes('data-situacao')).toBe(
      'ligada'
    );
    // 17:32 UTC = 14:32 em São Paulo, com o rótulo do fuso da plataforma.
    expect(wrapper.find('[data-mudanca]').text()).toBe(
      'Turned on by Ana Souza on 10/15/2026 at 02:32 PM, in the account time zone (America/Sao Paulo).'
    );
  });

  it('with permission on, Promotion turns on alone with the same cost confirmation', async () => {
    api.getConsent.mockReturnValue(resposta(payload({ servico: LIGOU })));
    api.updateConsent.mockReturnValue(
      resposta(payload({ servico: LIGOU, divulgacao: LIGOU }))
    );
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    await wrapper.find('[data-mexer-divulgacao]').trigger('click');
    expect(wrapper.find('[data-dialogo-ligar]').text()).toBe(
      TEXTOS.ligar.marketing
    );
    await confirmar(wrapper);

    expect(api.updateConsent).toHaveBeenCalledWith({
      acao: 'ligar',
      marcas: ['marketing'],
      versaoAviso: '2026-10-01',
    });
    expect(wrapper.find('[data-mexer-divulgacao]').text()).toBe(
      'Turn off Promotion'
    );
    expect(wrapper.find('[data-mudanca-divulgacao]').exists()).toBe(true);
  });

  it('turning off shows the server text and sends only Service notice', async () => {
    api.getConsent.mockReturnValue(
      resposta(payload({ servico: LIGOU, divulgacao: LIGOU }))
    );
    api.updateConsent.mockReturnValue(
      resposta(
        payload({
          servico: { ...LIGOU, acao: 'desligou' },
          divulgacao: { ...LIGOU, acao: 'desligou' },
        })
      )
    );
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    await wrapper.find('[data-desligar]').trigger('click');
    expect(wrapper.find('[data-dialogo]').text()).toContain(
      TEXTOS.desligar.utility
    );
    await confirmar(wrapper);

    expect(api.updateConsent).toHaveBeenCalledWith({
      acao: 'desligar',
      marcas: ['utility'],
      versaoAviso: '2026-10-01',
    });
    expect(wrapper.find('[data-situacao]').attributes('data-situacao')).toBe(
      'desligada'
    );
  });

  it('price changed while reading: shows the server message and reloads', async () => {
    api.getConsent.mockReturnValue(resposta(payload()));
    api.updateConsent.mockRejectedValue({
      response: {
        status: 409,
        data: { error: 'aviso_mudou', message: 'Meta prices changed.' },
      },
    });
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    await wrapper.findAll('input[type="checkbox"]')[0].setValue(true);
    await wrapper.find('[data-ligar]').trigger('click');
    await confirmar(wrapper);

    expect(api.getConsent).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-falha]').text()).toBe('Meta prices changed.');
  });

  // Mudar é só do administrador da conta; quem gerencia modelos vê só leitura.
  it('shows read-only to non-admins: everything disabled, with the reason', async () => {
    admin.eh = false;
    api.getConsent.mockReturnValue(resposta(payload()));
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    const caixas = wrapper.findAll('input[type="checkbox"]');
    expect(caixas).not.toHaveLength(0);
    expect(caixas.every(caixa => caixa.element.disabled)).toBe(true);
    expect(wrapper.find('[data-ligar]').attributes('disabled')).toBeDefined();
    const frase = wrapper.find('[data-so-admin]');
    expect(frase.text()).toBe('Only account administrators can change this.');
    // A frase descreve os controles travados (leitor de tela).
    const id = frase.attributes('id');
    expect(wrapper.find('[data-marcas]').attributes('aria-describedby')).toBe(
      id
    );
    expect(wrapper.find('[data-ligar]').attributes('aria-describedby')).toBe(
      id
    );

    await wrapper.find('[data-ligar]').trigger('click');
    expect(wrapper.find('[data-dialogo]').exists()).toBe(false);
  });

  it('read-only also when on: Promotion and Turn off stay disabled', async () => {
    admin.eh = false;
    api.getConsent.mockReturnValue(resposta(payload({ servico: LIGOU })));
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    const divulgacaoBotao = wrapper.find('[data-mexer-divulgacao]');
    const desligar = wrapper.find('[data-desligar]');
    expect(divulgacaoBotao.attributes('disabled')).toBeDefined();
    expect(desligar.attributes('disabled')).toBeDefined();
    const id = wrapper.find('[data-so-admin]').attributes('id');
    expect(divulgacaoBotao.attributes('aria-describedby')).toBe(id);
    expect(desligar.attributes('aria-describedby')).toBe(id);

    await divulgacaoBotao.trigger('click');
    await desligar.trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-dialogo]').exists()).toBe(false);
    expect(api.updateConsent).not.toHaveBeenCalled();
  });

  it('without a time zone on the account, says only "your account time zone"', async () => {
    conta.atual = ref({});
    api.getConsent.mockReturnValue(resposta(payload({ servico: LIGOU })));
    const wrapper = montar(AutorizacaoPage);
    await flushPromises();

    expect(wrapper.find('[data-mudanca]').text()).toContain(
      'in your account time zone.'
    );
  });
});

describe('AutorizacaoResumo', () => {
  it('summarizes what is on', async () => {
    api.getConsent.mockReturnValue(
      resposta(payload({ servico: LIGOU, divulgacao: LIGOU }))
    );
    const wrapper = montar(AutorizacaoResumo);
    await flushPromises();

    expect(wrapper.text()).toContain('On for Service notice and Promotion.');
  });
});
