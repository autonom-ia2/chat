import { mount } from '@vue/test-utils';
import CabecalhoDaPessoa from '../../components/ficha/CabecalhoDaPessoa.vue';
import MenuMais from '../../components/ficha/MenuMais.vue';
import FaixaNaoQuer from '../../components/ficha/FaixaNaoQuer.vue';
import SecaoConversas from '../../components/ficha/SecaoConversas.vue';
import SecaoCards from '../../components/ficha/SecaoCards.vue';
import SecaoNotas from '../../components/ficha/SecaoNotas.vue';
import SecaoArquivos from '../../components/ficha/SecaoArquivos.vue';
import GavetaDoCard from '../../components/ficha/GavetaDoCard.vue';
import GavetaDeInformacoes from '../../components/ficha/GavetaDeInformacoes.vue';
import ListaDeInformacoes from '../../components/ficha/ListaDeInformacoes.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BotaoCopiar from '../../components/ficha/BotaoCopiar.vue';
import CampoDeTexto from '../../components/ficha/CampoDeTexto.vue';
import DeOndeVeio from '../../components/ficha/DeOndeVeio.vue';
import CabecalhoDaEmpresa from '../../components/ficha/CabecalhoDaEmpresa.vue';
import SecaoPessoasDaEmpresa from '../../components/ficha/SecaoPessoasDaEmpresa.vue';

// Os blocos da ficha (#2894): cada um cheio, vazio e com a ação principal.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const SEGUNDOS = Date.UTC(2026, 10, 1, 12) / 1000;
const AGORA = Date.UTC(2026, 10, 11, 12);
const DIA = 86_400;
const stubs = {
  TeleportWithDirection: { template: '<div><slot /></div>' },
  Dialog: {
    template:
      '<div data-dialog><button data-confirmar @click="$emit(\'confirm\')" /></div>',
    methods: { open() {}, close() {} },
  },
};

const pessoa = (extra = {}) => ({
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana@exemplo.com.br',
  phone_number: '+5511900001007',
  thumbnail: '',
  contact_type: 'lead',
  customer_since: null,
  company_id: 3,
  labels: ['feira'],
  opted_out_at: null,
  opt_out_source: null,
  additional_attributes: {
    city: 'Santos',
    company_name: 'Padaria Dornelaz',
    social_profiles: {},
  },
  custom_attributes: { cpf: '52998224725', melhor_horario: 'Tarde' },
  ...extra,
});
const conversa = (id, extra = {}) => ({
  id,
  canal: 'whatsapp',
  trecho: `Trecho ${id}`,
  quando: SEGUNDOS - id * DIA,
  situacao: 'aberta',
  ...extra,
});
const card = (id, extra = {}) => ({
  id,
  titulo: `Card ${id}`,
  funil: 'Vendas',
  etapa: 'Novo',
  valor: 1200,
  situacao: 'aberto',
  ...extra,
});

// Com a máquina carregada, o primeiro mount do arquivo passa dos 5 s padrão.
vi.setConfig({ testTimeout: 30000 });

describe('CabecalhoDaPessoa', () => {
  const montar = props =>
    mount(CabecalhoDaPessoa, { props, global: { stubs } });

  it('mostra o selo de cliente com o mês, sem o botão de marcar', () => {
    const w = montar({
      pessoa: pessoa({
        contact_type: 'customer',
        customer_since: Date.UTC(2024, 2, 15) / 1000,
      }),
    });
    expect(w.get('[data-selo="cliente"]').text()).toContain('mar. de 2024');
    expect(w.find('[data-relacionamentos="marcar-cliente"]').exists()).toBe(
      false
    );
  });

  it('quem não é cliente tem o botão discreto, que emite', async () => {
    const w = montar({ pessoa: pessoa() });
    expect(w.find('[data-selo]').exists()).toBe(false);
    await w.get('[data-relacionamentos="marcar-cliente"]').trigger('click');
    expect(w.emitted('marcarCliente')).toHaveLength(1);
  });

  it('Conversar é a ação principal e emite', async () => {
    const w = montar({ pessoa: pessoa() });
    await w.get('[data-relacionamentos="conversar"]').trigger('click');
    expect(w.emitted('conversar')).toHaveLength(1);
  });

  it('a empresa é um link que leva à ficha dela', async () => {
    const w = montar({ pessoa: pessoa() });
    await w.get('[data-relacionamentos="empresa-da-pessoa"]').trigger('click');
    expect(w.emitted('abrirEmpresa')[0]).toEqual([3]);
  });

  it('sem telefone não desenha o telefone nem o copiar', () => {
    const w = montar({ pessoa: pessoa({ phone_number: null }) });
    expect(w.find('[data-copiar]').exists()).toBe(false);
  });

  it('repassa a escolha do "⋯"', async () => {
    const w = montar({ pessoa: pessoa() });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    await itens[1].trigger('click');
    expect(w.emitted('maisAcao')[0]).toEqual(['juntar']);
  });
});

describe('MenuMais', () => {
  it('abre com 4 itens, anda pelas setas e fecha com Esc', async () => {
    const w = mount(MenuMais, { attachTo: document.body, global: { stubs } });
    const gatilho = w.get('[data-relacionamentos="mais-acoes"]');
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    await gatilho.trigger('click');
    expect(gatilho.attributes('aria-expanded')).toBe('true');
    const itens = w.findAll('.n-dropdown-item button');
    expect(itens).toHaveLength(4);
    await gatilho.trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(itens[0].element);
    await itens[0].trigger('keydown', { key: 'ArrowUp' });
    expect(document.activeElement).toBe(itens[3].element);
    await itens[3].trigger('keydown', { key: 'Escape' });
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    w.unmount();
  });

  it('emite a escolha e fecha', async () => {
    const w = mount(MenuMais, { global: { stubs } });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    await w.findAll('.n-dropdown-item button')[0].trigger('click');
    expect(w.emitted('acao')[0]).toEqual(['alterar']);
    expect(w.find('.n-dropdown-item').exists()).toBe(false);
  });
});

describe('CabecalhoDaPessoa: celular e contato', () => {
  const montar = props =>
    mount(CabecalhoDaPessoa, { props, global: { stubs } });

  it('mostra o telefone formatado e copia o número inteiro', () => {
    const w = montar({ pessoa: pessoa({ phone_number: '+5511916820023' }) });
    expect(w.text()).toContain('+55 11 91682-0023');
    expect(w.findComponent(BotaoCopiar).props('valor')).toBe('+5511916820023');
  });

  it('telefone, e-mail e empresa têm cada um um ícone e a mesma estrutura', () => {
    const w = montar({ pessoa: pessoa() });
    const icones = ['phone', 'mail', 'building-2'].map(nome =>
      w.find(`[data-contato] .i-lucide-${nome}`).exists()
    );
    expect(icones).toEqual([true, true, true]);
    expect(w.findAll('[data-contato]')).toHaveLength(3);
  });

  it('o e-mail quebra em vez de empurrar a página', () => {
    const w = montar({ pessoa: pessoa() });
    const email = w.get('[data-contato="email"]');
    expect(email.classes()).toContain('min-w-0');
    expect(email.get('span[title]').classes()).toContain('break-words');
  });

  it('em 390 px Conversar ocupa a linha e as outras três dividem a de baixo', () => {
    const w = montar({ pessoa: pessoa() });
    expect(w.get('[data-relacionamentos="conversar"]').classes()).toContain(
      'w-full'
    );
    expect(
      w.get('[data-relacionamentos="acoes-secundarias"]').classes()
    ).toEqual(expect.arrayContaining(['grid']));
  });
});

describe('CabecalhoDaPessoa: terceira rodada', () => {
  const montar = props =>
    mount(CabecalhoDaPessoa, { props, global: { stubs } });

  it('nenhum rótulo de botão do cabeçalho encolhe ou quebra', () => {
    const w = montar({ pessoa: pessoa() });
    const botoes = [
      w.get('[data-relacionamentos="conversar"]'),
      ...w.get('[data-relacionamentos="acoes-secundarias"]').findAll('button'),
    ];
    botoes.slice(0, 3).forEach(b => {
      expect(b.classes()).toEqual(
        expect.arrayContaining(['whitespace-nowrap', 'shrink-0'])
      );
    });
  });

  it('no celular o contato e as etiquetas descem sob a faixa do nome, na largura toda', () => {
    const w = montar({ pessoa: pessoa() });
    const baixo = w.get('[data-relacionamentos="contato-e-etiquetas"]');
    expect(baixo.classes()).toContain('col-span-2');
    expect(baixo.find('[data-contato="telefone"]').exists()).toBe(true);
    expect(baixo.find('ul').exists()).toBe(true);
    expect(
      w.get('[data-contato="telefone"] span.tabular-nums').classes()
    ).toContain('whitespace-nowrap');
  });

  it('Marcar como cliente é botão discreto com ícone de selo', () => {
    const w = montar({ pessoa: pessoa() });
    const botao = w.get('[data-relacionamentos="marcar-cliente"]');
    expect(botao.html()).toContain('i-lucide-badge-check');
    expect(w.findComponent(Button).vm.$attrs).toMatchObject({
      slate: '',
      faded: '',
    });
  });
});

describe('MenuMais: foco', () => {
  it('ao escolher, o foco volta ao "⋯" antes de emitir', async () => {
    let focoNaHoraDeEmitir = null;
    const w = mount(MenuMais, {
      attachTo: document.body,
      props: {
        onAcao: () => {
          focoNaHoraDeEmitir = document.activeElement;
        },
      },
      global: { stubs },
    });
    const gatilho = w.get('[data-relacionamentos="mais-acoes"]');
    await gatilho.trigger('click');
    const item = w.findAll('.n-dropdown-item button')[0];
    item.element.focus();
    await item.trigger('click');
    expect(focoNaHoraDeEmitir).toBe(gatilho.element);
    w.unmount();
  });

  it('fecha quando o foco sai para fora do menu, mas não quando anda dentro dele', async () => {
    const fora = document.createElement('button');
    document.body.appendChild(fora);
    const w = mount(MenuMais, { attachTo: document.body, global: { stubs } });
    const gatilho = w.get('[data-relacionamentos="mais-acoes"]');
    await gatilho.trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    await itens[0].trigger('focusout', { relatedTarget: itens[1].element });
    expect(gatilho.attributes('aria-expanded')).toBe('true');
    await itens[0].trigger('focusout', { relatedTarget: fora });
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    w.unmount();
    fora.remove();
  });
});

describe('FaixaNaoQuer', () => {
  const montar = origem =>
    mount(FaixaNaoQuer, {
      props: {
        pessoa: pessoa({
          opted_out_at: Date.UTC(2026, 8, 12, 12) / 1000,
          opt_out_source: origem,
        }),
      },
      global: { stubs },
    });

  it('diz quando e de onde veio, em palavra simples', () => {
    const texto = montar('campaign_reply').text();
    expect(texto).toContain('RELACIONAMENTOS_FICHA.FAIXA.TEXTO');
    expect(texto).toContain('"data":"12/09"');
    expect(texto).toContain('FAIXA.ORIGEM.campaign_reply');
  });

  it('tem Liberar nas origens liberáveis e confirma antes de emitir', async () => {
    const w = montar('manual');
    expect(w.text()).toContain('FAIXA.LIBERAR');
    await w.get('[data-confirmar]').trigger('click');
    expect(w.emitted('liberar')).toHaveLength(1);
  });

  it('é aviso fixo: não nasce como região viva', () => {
    expect(montar('manual').find('[role="status"], [aria-live]').exists()).toBe(
      false
    );
  });

  it('não tem Liberar nas outras origens', () => {
    expect(
      montar('email_unsubscribe').find('button:not([data-confirmar])').exists()
    ).toBe(false);
  });
});

describe('SecaoConversas', () => {
  it('mostra só as 3 últimas, com canal, quando e situação', () => {
    const w = mount(SecaoConversas, {
      props: {
        conversas: [1, 2, 3, 4, 5].map(id => conversa(id)),
        agora: AGORA,
      },
    });
    expect(w.findAll('li')).toHaveLength(3);
    expect(w.text()).toContain('Trecho 1');
    expect(w.text()).not.toContain('Trecho 4');
    expect(w.text()).toContain('há 11 dias');
    expect(w.text()).toContain('SITUACAO.aberta');
    expect(w.text()).toContain('CONVERSAS.VER_TODAS');
  });

  it('Ver todas emite', async () => {
    const w = mount(SecaoConversas, {
      props: { conversas: [conversa(1)], agora: AGORA },
    });
    await w.get('button').trigger('click');
    expect(w.emitted('verTodas')).toHaveLength(1);
  });

  it('vazio dentro da seção: sem cartão interno e com botão discreto', () => {
    const w = mount(SecaoConversas, { props: { conversas: [] } });
    const vazio = w.get('[data-vazio]');
    expect(vazio.classes()).not.toContain('border');
    expect(vazio.classes()).not.toContain('text-center');
    expect(vazio.findComponent(Button).vm.$attrs).toMatchObject({
      slate: '',
      faded: '',
    });
    const cards = mount(SecaoCards, { props: { cards: [] } });
    expect(cards.get('[data-vazio]').classes()).not.toContain('border');
    expect(cards.findComponent(Button).vm.$attrs.faded).toBe('');
  });

  it('no celular o trecho tem 2 linhas e a situação desce para junto do tempo', () => {
    const w = mount(SecaoConversas, {
      props: { conversas: [conversa(1)], agora: AGORA },
    });
    expect(w.get('li p').classes()).toContain('line-clamp-2');
    const tempo = w.findAll('li p')[1];
    expect(tempo.get('span').classes()).toContain('md:hidden');
    expect(tempo.text()).toContain('SITUACAO.aberta');
  });

  it('vazio: uma frase e Conversar', async () => {
    const w = mount(SecaoConversas, { props: { conversas: [] } });
    expect(w.get('[data-vazio]').text()).toContain('CONVERSAS.VAZIO');
    await w.get('[data-vazio] button').trigger('click');
    expect(w.emitted('conversar')).toHaveLength(1);
    expect(w.text()).not.toContain('VER_TODAS');
  });

  it('na empresa, cada linha diz de quem é', () => {
    const w = mount(SecaoConversas, {
      props: {
        conversas: [conversa(1, { pessoa: 'Bruno Dornelaz' })],
        agora: AGORA,
      },
    });
    expect(w.text()).toContain('Bruno Dornelaz');
  });
});

describe('SecaoCards', () => {
  it('lista título, funil e etapa, valor e situação; clicar abre', async () => {
    const w = mount(SecaoCards, {
      props: { cards: [card(1), card(2, { situacao: 'ganho' })] },
    });
    const itens = w.findAll('[data-relacionamentos="card"]');
    expect(itens).toHaveLength(2);
    expect(itens[0].text()).toContain('Card 1');
    expect(itens[0].text().replaceAll(' ', ' ')).toContain('R$ 1.200');
    expect(itens[1].text()).toContain('SITUACAO.ganho');
    await itens[1].trigger('click');
    expect(w.emitted('abrir')[0][0]).toMatchObject({ id: 2 });
  });

  it('vazio: uma frase e Novo card', async () => {
    const w = mount(SecaoCards, { props: { cards: [] } });
    expect(w.get('[data-vazio]').text()).toContain('CARDS.VAZIO');
    await w.get('[data-vazio] button').trigger('click');
    expect(w.emitted('novoCard')).toHaveLength(1);
  });
});

describe('SecaoNotas', () => {
  const notas = [
    { id: 'a', autor: 'Sônia', quando: SEGUNDOS, texto: 'Pediu retorno.' },
  ];

  it('mostra a lista com quem e quando', () => {
    const w = mount(SecaoNotas, { props: { notas, agora: AGORA } });
    expect(w.get('[data-relacionamentos="nota"]').text()).toContain(
      'Pediu retorno.'
    );
    expect(w.text()).toContain('"autor":"Sônia"');
  });

  it('Guardar fica parado sem texto e emite o texto limpo', async () => {
    const w = mount(SecaoNotas, { props: { notas: [], agora: AGORA } });
    const guardar = w.get('[data-relacionamentos="guardar-nota"]');
    expect(guardar.attributes('disabled')).toBeDefined();
    await w
      .get('[data-relacionamentos="nota-caixa"]')
      .setValue('  Ligar amanhã  ');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')[0]).toEqual(['Ligar amanhã']);
  });

  it('limpa a caixa quando a tela manda', async () => {
    const w = mount(SecaoNotas, { props: { notas: [], agora: AGORA } });
    const caixa = w.get('[data-relacionamentos="nota-caixa"]');
    await caixa.setValue('texto');
    w.vm.limpar();
    await w.vm.$nextTick();
    expect(caixa.element.value).toBe('');
  });

  it('sem notas, uma frase', () => {
    expect(mount(SecaoNotas, { props: { notas: [] } }).text()).toContain(
      'NOTAS.VAZIO'
    );
  });
});

describe('SecaoArquivos', () => {
  it('lista nome e quando; vazio é uma frase', () => {
    const cheio = mount(SecaoArquivos, {
      props: {
        arquivos: [
          { id: 1, nome: 'foto.jpg', tipo: 'imagem', quando: SEGUNDOS },
        ],
        agora: AGORA,
      },
    });
    expect(cheio.text()).toContain('foto.jpg');
    expect(cheio.text()).toContain('há 10 dias');
    expect(mount(SecaoArquivos, { props: { arquivos: [] } }).text()).toContain(
      'ARQUIVOS.VAZIO'
    );
  });
});

describe('GavetaDoCard', () => {
  it('fechada não desenha nada', () => {
    const w = mount(GavetaDoCard, { props: { card: null }, global: { stubs } });
    expect(w.find('[role="dialog"]').exists()).toBe(false);
  });

  it('aberta mostra o resumo, tem Abrir no CRM e fecha com Esc', async () => {
    const w = mount(GavetaDoCard, {
      props: { card: card(5) },
      global: { stubs },
    });
    const gaveta = w.get('[data-relacionamentos="gaveta-card"]');
    expect(gaveta.attributes('aria-modal')).toBe('true');
    expect(gaveta.get('[data-view-title]').text()).toBe('Card 5');
    await w.get('[data-foco]').trigger('click');
    expect(w.emitted('abrirNoCrm')).toHaveLength(1);
    await gaveta.trigger('keydown', { key: 'Escape' });
    expect(w.emitted('fechar')).toHaveLength(1);
  });
});

describe('GavetaDeInformacoes', () => {
  const montar = (props = {}) =>
    mount(GavetaDeInformacoes, {
      props: { aberta: true, pessoa: pessoa(), ...props },
      attachTo: document.body,
      global: { stubs },
    });
  const campo = (w, rotulo) =>
    w.findAll('label').find(l => l.text() === rotulo);

  it('abre com o que a pessoa tem hoje; o primeiro campo recebe o foco', () => {
    const w = montar();
    expect(w.get('[data-relacionamentos="gaveta-informacoes"]').exists()).toBe(
      true
    );
    expect(w.findAll('[data-foco]')).toHaveLength(1);
    expect(w.get('[data-foco]').element.tagName).toBe('INPUT');
    expect(w.get('[data-foco]').element.value).toBe('Ana Albuquerino');
    expect(w.get('[data-view-title]').attributes('tabindex')).toBe('-1');
  });

  it('esconde as redes sociais atrás de um botão que abre e fecha', async () => {
    const w = montar();
    const botao = w.get('[data-relacionamentos="redes-sociais"]');
    expect(botao.attributes('aria-expanded')).toBe('false');
    const painel = w.get(`#${botao.attributes('aria-controls')}`);
    expect(painel.isVisible()).toBe(false);
    await botao.trigger('click');
    expect(botao.attributes('aria-expanded')).toBe('true');
    expect(painel.isVisible()).toBe(true);
  });

  it('e-mail errado barra o Salvar e mostra a mensagem embaixo do campo', async () => {
    const w = montar();
    const email = campo(w, 'RELACIONAMENTOS_FICHA.GAVETA.EMAIL');
    await w.get(`#${email.attributes('for')}`).setValue('sem-arroba');
    await w.get('[data-relacionamentos="salvar-informacoes"]').trigger('click');
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.text()).toContain('RELACIONAMENTOS_FICHA.GAVETA.ERRO.EMAIL');
  });

  it('CPF errado barra o Salvar', async () => {
    const w = montar();
    const cpf = campo(w, 'RELACIONAMENTOS_FICHA.GAVETA.CPF');
    await w.get(`#${cpf.attributes('for')}`).setValue('123');
    await w.get('[data-relacionamentos="salvar-informacoes"]').trigger('click');
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.text()).toContain('GAVETA.ERRO.CPF');
  });

  it('sem o nome não salva', async () => {
    const w = montar();
    await w.get('[data-foco]').setValue('');
    await w.get('[data-relacionamentos="salvar-informacoes"]').trigger('click');
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.text()).toContain('GAVETA.ERRO.NOME');
  });

  it('salvar com dados bons emite o formato do contato', async () => {
    const w = montar();
    await w.get('[data-foco]').setValue('Ana Maria');
    await w.get('[data-relacionamentos="salvar-informacoes"]').trigger('click');
    const [dados] = w.emitted('salvar')[0];
    expect(dados.name).toBe('Ana Maria');
    expect(dados.additional_attributes.city).toBe('Santos');
    expect(dados.custom_attributes).toMatchObject({
      cpf: '52998224725',
      melhor_horario: 'Tarde',
    });
  });

  it('Cancelar e Esc fecham', async () => {
    const w = montar();
    await w
      .get('[data-relacionamentos="gaveta-informacoes"]')
      .trigger('keydown', { key: 'Escape' });
    expect(w.emitted('fechar')).toHaveLength(1);
    const botoes = w.findAll('footer button');
    await botoes[1].trigger('click');
    expect(w.emitted('fechar')).toHaveLength(2);
  });

  it('fechada não desenha a gaveta', () => {
    expect(montar({ aberta: false }).find('[role="dialog"]').exists()).toBe(
      false
    );
  });
});

describe('ListaDeInformacoes e De onde veio', () => {
  it('o que falta mostra "Não informado" e CPF tem copiar', () => {
    const w = mount(ListaDeInformacoes, {
      props: {
        linhas: [
          { chave: 'cpf', valor: '529.982.247-25', copiar: true },
          { chave: 'cidade', valor: '' },
        ],
        redes: [{ rede: 'instagram', usuario: '@ana' }],
      },
    });
    expect(w.get('[data-informacao="cidade"]').text()).toContain(
      'NAO_INFORMADO'
    );
    expect(w.get('[data-informacao="cidade"] dd').classes()).toContain(
      'text-n-slate-10'
    );
    expect(w.find('[data-informacao="cpf"] [data-copiar]').exists()).toBe(true);
    expect(w.find('[data-informacao="cidade"] [data-copiar]').exists()).toBe(
      false
    );
    expect(w.get('[data-informacao="instagram"]').text()).toContain('@ana');
  });

  it('diz a lista e a data, ou o canal e a data', () => {
    const lista = mount(DeOndeVeio, {
      props: {
        origem: { tipo: 'lista', nome: 'Clientes 2025', quando: SEGUNDOS },
      },
    });
    expect(lista.text()).toContain('"nome":"Clientes 2025","data":"01/11"');
    const canal = mount(DeOndeVeio, {
      props: { origem: { tipo: 'canal', canal: 'whatsapp', quando: SEGUNDOS } },
    });
    expect(canal.text()).toContain('ORIGEM.CANAL');
    const desconhecido = mount(DeOndeVeio, {
      props: { origem: { tipo: 'canal', canal: 'telegram', quando: SEGUNDOS } },
    });
    expect(desconhecido.text()).toContain('ORIGEM.CANAL_DESCONHECIDO');
    expect(desconhecido.text()).not.toContain('CANAL_NOME.telegram');
    expect(
      mount(DeOndeVeio, { props: { origem: null } })
        .find('section')
        .exists()
    ).toBe(false);
  });
});

describe('ficha da empresa: celular', () => {
  const empresa = {
    id: 1,
    name: 'Padaria Dornelaz',
    cnpj: '11222333000181',
    domain: 'farmacia-dornelaz.exemplo.com.br',
  };

  it('marca menor no celular; CNPJ e site descem, o CNPJ não quebra e o site é uma linha', () => {
    const w = mount(CabecalhoDaEmpresa, { props: { empresa } });
    const baixo = w.get('[data-relacionamentos="contato-da-empresa"]');
    expect(baixo.classes()).toContain('col-span-2');
    expect(baixo.get('span.tabular-nums').classes()).toContain(
      'whitespace-nowrap'
    );
    const site = baixo.get('[title]');
    expect(site.attributes('title')).toBe(empresa.domain);
    expect(site.classes()).toEqual(
      expect.arrayContaining(['truncate', 'whitespace-nowrap'])
    );
    expect(site.classes()).not.toContain('break-all');
    expect(w.findAllComponents({ name: 'Avatar' })).toHaveLength(2);
  });

  it('na lista de pessoas o selo fica ao lado do nome e o e-mail ganha a linha toda', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [pessoa({ contact_type: 'customer' })] },
    });
    const email = w.get('[data-relacionamentos="email-da-pessoa"]');
    expect(email.classes()).toContain('col-span-3');
    expect(email.classes()).toContain('truncate');
    expect(w.get('[data-selo="cliente"]').exists()).toBe(true);
  });
});

describe('datas com ano', () => {
  const antigo = Date.UTC(2025, 10, 27, 12) / 1000;

  it('De onde veio mostra o ano quando a data é de outro ano', () => {
    const w = mount(DeOndeVeio, {
      props: {
        origem: { tipo: 'canal', canal: 'instagram', quando: antigo },
        agora: AGORA,
      },
    });
    expect(w.text()).toContain('"data":"27/11/2025"');
  });

  it('a faixa de quem não quer mensagens também', () => {
    const w = mount(FaixaNaoQuer, {
      props: {
        pessoa: pessoa({ opted_out_at: antigo, opt_out_source: 'manual' }),
        agora: AGORA,
      },
      global: { stubs },
    });
    expect(w.text()).toContain('"data":"27/11/2025"');
  });
});

describe('ficha da empresa: peças', () => {
  it('cabeçalho mostra nome, CNPJ formatado com copiar e o site', () => {
    const w = mount(CabecalhoDaEmpresa, {
      props: {
        empresa: {
          id: 1,
          name: 'Padaria Dornelaz',
          cnpj: '11222333000181',
          domain: 'padaria.exemplo.com.br',
        },
      },
    });
    expect(w.get('h1').text()).toBe('Padaria Dornelaz');
    expect(w.text()).toContain('11.222.333/0001-81');
    expect(w.text()).toContain('padaria.exemplo.com.br');
    expect(w.find('[data-copiar]').exists()).toBe(true);
  });

  it('as pessoas levam à ficha; vazio é uma frase', async () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [pessoa({ contact_type: 'customer' })] },
    });
    expect(w.text()).toContain('Ana Albuquerino');
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
    await w.get('[data-relacionamentos="pessoa-da-empresa"]').trigger('click');
    expect(w.emitted('abrir')[0]).toEqual([7]);
    const vazio = mount(SecaoPessoasDaEmpresa, { props: { pessoas: [] } });
    expect(vazio.get('[data-relacionamentos="vazio"]').text()).toContain(
      'PESSOAS_VAZIO'
    );
  });
});

describe('CampoDeTexto: região viva', () => {
  it('a região do erro já existe sem erro e recebe o texto depois', async () => {
    const w = mount(CampoDeTexto, { props: { rotulo: 'Nome', erro: '' } });
    const regiao = w.get('[aria-live="polite"]');
    expect(regiao.text()).toBe('');
    await w.setProps({ erro: 'Escreva o nome.' });
    expect(w.get('[aria-live="polite"]').element).toBe(regiao.element);
    expect(regiao.text()).toBe('Escreva o nome.');
  });
});
