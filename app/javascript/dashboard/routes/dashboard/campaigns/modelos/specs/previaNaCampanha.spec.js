import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import { conteudoDaMeta } from '../api/daMeta';
import PontePrevia from '../ponte/PontePrevia.vue';

// #1456: "Como o cliente vê" na Nova campanha mostra o que o cliente recebe de
// verdade (topo, botões, cupom digitado, "vale até" da oferta, cartões), com ou
// sem a ponte de Modelos. Campo sem valor mostra o rótulo, nunca "{{1}}".
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: ref({ name: 'Hub2you' }) }),
}));

const ZONA = 'America/Sao_Paulo';

// Sem a ponte, o modelo da prévia vem direto do modelo da Meta.
const daMeta = (template, extra = {}) => ({
  ...conteudoDaMeta(template),
  template,
  ...extra,
});

const montar = (modelo, props = {}) =>
  mount(PontePrevia, {
    props: { modelo, remetente: 'Hub2you', timeZone: ZONA, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

const botoes = wrapper =>
  wrapper.findAll('[data-celular-botao]').map(item => item.text());

const normal = {
  name: 'colecao_nova',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'IMAGE' },
    { type: 'BODY', text: 'Oi, {{1}}! Chegou a coleção da {{2}}.' },
    { type: 'FOOTER', text: 'Responda SAIR para não receber' },
    {
      type: 'BUTTONS',
      buttons: [
        { type: 'QUICK_REPLY', text: 'Quero ver' },
        { type: 'URL', text: 'Abrir loja', url: 'https://loja.com' },
        { type: 'PHONE_NUMBER', text: 'Ligar', phone_number: '+5511' },
      ],
    },
  ],
};

describe('PontePrevia — Como o cliente vê na campanha (#1456)', () => {
  it('modelo normal: foto no topo, rodapé e os três botões', () => {
    const wrapper = montar(daMeta(normal), {
      bindings: { 1: { source: 'contact', value: 'first_name' } },
      sample: { name: 'Ana Souza' },
    });

    expect(wrapper.find('[data-celular-topo]').text()).toContain('Photo');
    expect(botoes(wrapper)).toEqual(['Quero ver', 'Abrir loja', 'Ligar']);
    expect(wrapper.text()).toContain('Responda SAIR');
    expect(wrapper.text()).toContain('Oi, Ana!');
  });

  it('campo sem valor mostra o rótulo, nunca a variável crua', () => {
    const wrapper = montar(daMeta(normal));

    expect(wrapper.text()).not.toContain('{{');
    expect(wrapper.text()).toContain('Field 1');
  });

  it('empresa do contato vem da empresa, não do nome', () => {
    const wrapper = montar(daMeta(normal), {
      bindings: { 2: { source: 'contact', value: 'company' } },
      sample: { name: 'Ana Souza', company_name: 'Loja da Ana' },
    });

    expect(wrapper.text()).toContain('coleção da Loja da Ana');
  });

  it('cupom: o botão "Copiar código" mostra o código digitado', () => {
    const cupom = {
      name: 'cupom',
      category: 'MARKETING',
      components: [
        { type: 'BODY', text: 'Seu cupom chegou.' },
        {
          type: 'BUTTONS',
          buttons: [{ type: 'COPY_CODE', example: ['EXEMPLO'] }],
        },
      ],
    };
    const wrapper = montar(daMeta(cupom), { valores: { cupom: ' OUT10 ' } });

    expect(botoes(wrapper)).toHaveLength(1);
    expect(botoes(wrapper)[0]).toContain('Copy code');
    expect(botoes(wrapper)[0]).toContain('OUT10');
    expect(wrapper.text()).not.toContain('EXEMPLO');
  });

  const ofertaCom = ({ prazo }) => ({
    name: 'oferta',
    category: 'MARKETING',
    components: [
      {
        type: 'LIMITED_TIME_OFFER',
        limited_time_offer: { text: 'Só hoje', has_expiration: prazo },
      },
      { type: 'BODY', text: 'Aproveite.' },
      {
        type: 'BUTTONS',
        buttons: [
          { type: 'COPY_CODE', example: 'EXEMPLO' },
          { type: 'URL', text: 'Comprar', url: 'https://loja.com' },
        ],
      },
    ],
  });

  it('oferta com prazo: título, cupom e "vale até" no fuso da conta', () => {
    const wrapper = montar(daMeta(ofertaCom({ prazo: true })), {
      valores: { cupom: 'OUT10', validade: '2026-10-20T18:00' },
    });

    const caixa = wrapper.find('[data-celular-oferta]');
    expect(caixa.text()).toContain('Só hoje');
    expect(caixa.text()).toContain('OUT10');
    // 18:00 em São Paulo (a hora do fuso da conta, não a de UTC).
    expect(caixa.text()).toContain('Valid until Oct 20, 2026, 6:00');
    expect(caixa.text()).not.toContain('(example)');
  });

  it('carrossel: os cartões com o arquivo aprovado ou o escolhido agora', () => {
    const cartao = texto => ({
      components: [
        { type: 'HEADER', format: 'IMAGE' },
        { type: 'BODY', text: texto },
        {
          type: 'BUTTONS',
          buttons: [{ type: 'QUICK_REPLY', text: 'Quero' }],
        },
      ],
    });
    const carrossel = {
      name: 'vitrine',
      category: 'MARKETING',
      components: [
        { type: 'BODY', text: 'Veja a vitrine.' },
        { type: 'CAROUSEL', cards: [cartao('Tênis'), cartao('Bolsa')] },
      ],
    };
    const wrapper = montar(
      daMeta(carrossel, { cartoesGuardados: [{ nome: 'tenis.jpg' }] }),
      { valores: { cartoes: { 1: { referencia: 'x', nome: 'bolsa.png' } } } }
    );

    const cartoes = wrapper.findAll('[data-celular-cartoes] li');
    expect(cartoes).toHaveLength(2);
    expect(cartoes[0].text()).toContain('tenis.jpg');
    expect(cartoes[0].text()).toContain('Tênis');
    expect(cartoes[1].text()).toContain('bolsa.png');
    expect(cartoes[1].text()).toContain('Quero');
  });

  it('oferta sem cupom digitado nem prazo: nada de exemplo nem contagem inventada', () => {
    const wrapper = montar(daMeta(ofertaCom({ prazo: false })));

    const caixa = wrapper.find('[data-celular-oferta]');
    expect(caixa.text()).toContain('Só hoje');
    expect(caixa.text()).not.toContain('EXEMPLO');
    expect(caixa.text()).not.toContain('(example)');
    expect(caixa.text()).not.toContain('Valid until');
  });

  it('cupom ainda vazio: o botão não mostra código nenhum', () => {
    const cupom = {
      name: 'cupom',
      components: [
        { type: 'BODY', text: 'Seu cupom.' },
        { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', example: 'EX1' }] },
      ],
    };
    const wrapper = montar(daMeta(cupom));

    expect(wrapper.find('[data-celular-codigo]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('EX1');
  });

  it('sem o valor da pessoa, usa o texto padrão da variável e depois o nome da coluna', () => {
    const bindings = {
      1: { source: 'column', value: 'Vencimento' },
      2: { source: 'column', value: 'Loja' },
    };
    const wrapper = montar(daMeta(normal), {
      bindings,
      defaults: { 1: 'em breve' },
      sample: { name: 'Ana', extra_values: {} },
    });

    expect(wrapper.text()).toContain('Oi, em breve!');
    expect(wrapper.text()).toContain('coleção da [Loja].');
  });
});
