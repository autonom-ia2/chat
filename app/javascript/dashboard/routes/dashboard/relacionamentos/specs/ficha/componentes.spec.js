import { mount } from '@vue/test-utils';
import CabecalhoDaPessoa from '../../components/ficha/CabecalhoDaPessoa.vue';
import MenuMais from '../../components/ficha/MenuMais.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import FaixaNaoQuer from '../../components/ficha/FaixaNaoQuer.vue';
import SecaoConversas from '../../components/ficha/SecaoConversas.vue';
import SecaoCards from '../../components/ficha/SecaoCards.vue';
import SecaoNotas from '../../components/ficha/SecaoNotas.vue';
import SecaoArquivos from '../../components/ficha/SecaoArquivos.vue';
import GavetaDoCard from '../../components/ficha/GavetaDoCard.vue';
import GavetaDeInformacoes from '../../components/ficha/GavetaDeInformacoes.vue';
import ListaDeInformacoes from '../../components/ficha/ListaDeInformacoes.vue';
import GavetaDaEmpresa from '../../components/ficha/GavetaDaEmpresa.vue';
import DialogoDaFicha from '../../components/ficha/DialogoDaFicha.vue';
import DialogoMandarMensagem from '../../components/ficha/DialogoMandarMensagem.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BotaoCopiar from '../../components/ficha/BotaoCopiar.vue';
import CampoDeTexto from '../../components/ficha/CampoDeTexto.vue';
import DeOndeVeio from '../../components/ficha/DeOndeVeio.vue';
import CabecalhoDaEmpresa from '../../components/ficha/CabecalhoDaEmpresa.vue';
import SecaoPessoasDaEmpresa from '../../components/ficha/SecaoPessoasDaEmpresa.vue';
import CorpoDaFichaDaPessoa from '../../components/ficha/CorpoDaFichaDaPessoa.vue';

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
      '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
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

  it('com `podeConversar`, Conversar é a ação principal e emite', async () => {
    const w = montar({ pessoa: pessoa(), podeConversar: true });
    await w.get('[data-relacionamentos="conversar"]').trigger('click');
    expect(w.emitted('conversar')).toHaveLength(1);
  });

  // #2970 — sem conversa para abrir o botão não existe (a demonstração mostra
  // "Lembrete" e o menu inteiro: `naDemonstracao`).
  it('sem `podeConversar` não tem Conversar, e as outras ações seguem discretas, sem botão preenchido', () => {
    const w = montar({ pessoa: pessoa(), naDemonstracao: true });
    expect(w.find('[data-relacionamentos="conversar"]').exists()).toBe(false);
    const secundarias = w.get('[data-relacionamentos="acoes-secundarias"]');
    expect(
      secundarias.find('[data-relacionamentos="novo-card"]').exists()
    ).toBe(true);
    expect(secundarias.classes()).toContain('grid-cols-[1fr_1fr_auto]');
    const rotulos = ['NOVO_CARD', 'LEMBRETE'].map(
      chave => `RELACIONAMENTOS_FICHA.ACOES.${chave}`
    );
    const discretos = secundarias
      .findAllComponents(Button)
      .filter(b => rotulos.includes(b.props('label')));
    expect(discretos).toHaveLength(2);
    discretos.forEach(b =>
      expect(b.vm.$attrs).toMatchObject({ slate: '', faded: '' })
    );
  });

  it('na demonstração, sem poder criar card, Lembrete e o "⋯" dividem a linha', () => {
    const w = montar({
      pessoa: pessoa(),
      podeCriarCards: false,
      naDemonstracao: true,
    });
    expect(w.find('[data-relacionamentos="novo-card"]').exists()).toBe(false);
    expect(
      w.get('[data-relacionamentos="acoes-secundarias"]').classes()
    ).toContain('grid-cols-[1fr_auto]');
  });

  // #2970 — "Lembrete" e, no "⋯", Juntar, Bloquear e Apagar ainda só avisam.
  // Com um item só não há menu: "Alterar informações" é um botão.
  describe('sem `naDemonstracao`', () => {
    const CLIENTE = { contact_type: 'customer' };
    const ALTERAR = '[data-relacionamentos="alterar-informacoes"]';
    const MAIS = '[data-relacionamentos="mais-acoes"]';
    const itensDoMais = async w => {
      await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
      return w.findAll('.n-dropdown-item button').map(item => item.text());
    };
    const grade = w =>
      w.get('[data-relacionamentos="acoes-secundarias"]').classes();

    it('não tem Lembrete nem "⋯": "Alterar informações" é um botão discreto, que emite', async () => {
      const w = montar({ pessoa: pessoa() });
      expect(w.text()).not.toContain('ACOES.LEMBRETE');
      expect(w.find('[data-relacionamentos="novo-card"]').exists()).toBe(true);
      expect(w.find(MAIS).exists()).toBe(false);
      expect(grade(w)).toContain('grid-cols-1');
      expect(grade(w)).not.toContain('justify-items-end');
      const alterar = w
        .findAllComponents(Button)
        .find(
          b =>
            b.props('label') ===
            'RELACIONAMENTOS_FICHA.ACOES.ALTERAR_INFORMACOES'
        );
      expect(alterar.vm.$attrs).toMatchObject({ slate: '', faded: '' });
      await w.get(ALTERAR).trigger('click');
      expect(w.emitted('maisAcao')[0]).toEqual(['alterar']);
    });

    it('de quem é cliente, o "⋯" guarda "Alterar informações" e "Não é mais cliente", sem botão solto', async () => {
      const w = montar({ pessoa: pessoa(CLIENTE) });
      expect(w.find(ALTERAR).exists()).toBe(false);
      expect(grade(w)).toContain('grid-cols-[1fr_auto]');
      const itens = await itensDoMais(w);
      expect(itens).toHaveLength(2);
      expect(itens[0]).toContain('ACOES.ALTERAR_INFORMACOES');
      expect(itens[1]).toContain('ACOES.DESMARCAR_CLIENTE');
    });

    it('sem poder criar card, o "⋯" de quem é cliente fica sozinho, na ponta', () => {
      const w = montar({ pessoa: pessoa(CLIENTE), podeCriarCards: false });
      expect(w.get('[role="group"]').findAll('button')).toHaveLength(1);
      expect(w.find(MAIS).exists()).toBe(true);
      expect(grade(w)).toEqual(
        expect.arrayContaining(['grid-cols-1', 'justify-items-end'])
      );
    });

    it('sem poder criar card, quem não é cliente fica só com "Alterar informações", na linha toda', () => {
      const w = montar({ pessoa: pessoa(), podeCriarCards: false });
      expect(w.get('[role="group"]').findAll('button')).toHaveLength(1);
      expect(w.find(ALTERAR).exists()).toBe(true);
      expect(grade(w)).toContain('grid-cols-1');
      expect(grade(w)).not.toContain('justify-items-end');
    });

    it('quem só pode ver não tem "⋯" nem "Alterar informações": sobra Novo card, na linha toda', () => {
      const w = montar({ pessoa: pessoa(), podeEditar: false });
      expect(w.find(MAIS).exists()).toBe(false);
      expect(w.find(ALTERAR).exists()).toBe(false);
      expect(w.get('[role="group"]').findAll('button')).toHaveLength(1);
      expect(grade(w)).toContain('grid-cols-1');
      expect(grade(w)).not.toContain('justify-items-end');
    });

    it('quem só pode ver e não cria card fica sem grupo de ações; com conversa, só Conversar', () => {
      const semNada = montar({
        pessoa: pessoa(),
        podeEditar: false,
        podeCriarCards: false,
      });
      expect(semNada.find('[role="group"]').exists()).toBe(false);
      const comConversa = montar({
        pessoa: pessoa(),
        podeEditar: false,
        podeCriarCards: false,
        podeConversar: true,
      });
      const grupo = comConversa.get('[role="group"]');
      expect(grupo.findAll('button')).toHaveLength(1);
      expect(
        grupo.find('[data-relacionamentos="acoes-secundarias"]').exists()
      ).toBe(false);
    });
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
    const w = montar({ pessoa: pessoa(), naDemonstracao: true });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    await itens[1].trigger('click');
    expect(w.emitted('maisAcao')[0]).toEqual(['juntar']);
  });

  it('de quem é cliente, o "⋯" tem "Não é mais cliente" e repassa a escolha', async () => {
    const w = montar({ pessoa: pessoa({ contact_type: 'customer' }) });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    expect(itens[1].text()).toContain('ACOES.DESMARCAR_CLIENTE');
    await itens[1].trigger('click');
    expect(w.emitted('maisAcao')[0]).toEqual(['desmarcar']);
  });
});

describe('MenuMais', () => {
  it('na demonstração abre com 4 itens, anda pelas setas e fecha com Esc', async () => {
    const w = mount(MenuMais, {
      props: { naDemonstracao: true },
      attachTo: document.body,
      global: { stubs },
    });
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

  const textosDoMenu = async props => {
    const w = mount(MenuMais, { props, global: { stubs } });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    return w.findAll('.n-dropdown-item button').map(item => item.text());
  };

  it('"Não é mais cliente" vem logo depois de "Alterar informações", só para quem é cliente', async () => {
    const deCliente = await textosDoMenu({
      ehCliente: true,
      naDemonstracao: true,
    });
    expect(deCliente).toHaveLength(5);
    expect(deCliente[0]).toContain('ACOES.ALTERAR_INFORMACOES');
    expect(deCliente[1]).toContain('ACOES.DESMARCAR_CLIENTE');
    expect((await textosDoMenu({ ehCliente: false })).join(' ')).not.toContain(
      'DESMARCAR_CLIENTE'
    );
    expect((await textosDoMenu()).join(' ')).not.toContain('DESMARCAR_CLIENTE');
  });

  it('quem só pode ver não tem "Não é mais cliente", mesmo com cliente', async () => {
    const textos = await textosDoMenu({
      ehCliente: true,
      podeAlterar: false,
      naDemonstracao: true,
    });
    expect(textos).toHaveLength(3);
    expect(textos.join(' ')).not.toContain('DESMARCAR_CLIENTE');
  });

  // #2970 — Juntar, Bloquear e Apagar ainda só avisam: só na demonstração.
  it('sem `naDemonstracao` não tem Juntar, Bloquear nem Apagar', async () => {
    const deCliente = await textosDoMenu({ ehCliente: true });
    expect(deCliente).toHaveLength(2);
    expect(deCliente[0]).toContain('ACOES.ALTERAR_INFORMACOES');
    expect(deCliente[1]).toContain('ACOES.DESMARCAR_CLIENTE');
    expect(await textosDoMenu({ ehCliente: false })).toHaveLength(1);
  });

  it('escolher "Não é mais cliente" emite desmarcar', async () => {
    const w = mount(MenuMais, {
      props: { ehCliente: true },
      global: { stubs },
    });
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    await w.findAll('.n-dropdown-item button')[1].trigger('click');
    expect(w.emitted('acao')[0]).toEqual(['desmarcar']);
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
    const w = montar({
      pessoa: pessoa(),
      podeConversar: true,
      naDemonstracao: true,
    });
    expect(w.get('[data-relacionamentos="conversar"]').classes()).toContain(
      'w-full'
    );
    expect(
      w.get('[data-relacionamentos="acoes-secundarias"]').classes()
    ).toEqual(expect.arrayContaining(['grid']));
  });
});

describe('CabecalhoDaPessoa: quem não quer mensagens', () => {
  const conversar = w =>
    w
      .findAllComponents(Button)
      .find(b => b.vm.$attrs['data-relacionamentos'] === 'conversar');

  it('Conversar segue como botão principal, cheio e clicável, mesmo com a faixa de não quer', async () => {
    const normal = mount(CabecalhoDaPessoa, {
      props: { pessoa: pessoa(), podeConversar: true },
      global: { stubs },
    });
    const calada = mount(CabecalhoDaPessoa, {
      props: {
        pessoa: pessoa({ opted_out_at: SEGUNDOS }),
        podeConversar: true,
      },
      global: { stubs },
    });
    [normal, calada].forEach(w => {
      expect(conversar(w).props('variant')).toBeNull();
      expect(conversar(w).props('color')).toBeNull();
      expect(conversar(w).vm.$attrs).not.toHaveProperty('faded');
      expect(conversar(w).vm.$attrs).not.toHaveProperty('slate');
    });
    const botao = calada.get('[data-relacionamentos="conversar"]');
    expect(botao.attributes('disabled')).toBeUndefined();
    await botao.trigger('click');
    expect(calada.emitted('conversar')).toHaveLength(1);
  });
});

describe('botões de ação usam o Button da casa', () => {
  it('sem rounded-xl nem min-h-12 nos botões de ação do cabeçalho e das gavetas', () => {
    const pessoaW = mount(CabecalhoDaPessoa, {
      props: { pessoa: pessoa(), podeConversar: true },
      global: { stubs },
    });
    const empresaW = mount(CabecalhoDaEmpresa, {
      props: {
        empresa: { id: 1, name: 'Padaria Dornelaz' },
        podeMandarMensagem: true,
      },
    });
    const gaveta = mount(GavetaDaEmpresa, {
      props: {
        aberta: true,
        empresa: { id: 1, name: 'Padaria Dornelaz' },
      },
      global: { stubs },
    });
    const botoes = [
      pessoaW.get('[data-relacionamentos="conversar"]').element,
      empresaW.get('[data-relacionamentos="mandar-mensagem"]').element,
      empresaW.get('[data-relacionamentos="alterar-empresa"]').element,
      ...gaveta.findAll('footer button').map(b => b.element),
    ];
    expect(botoes).toHaveLength(5);
    const classes = botoes.flatMap(b => [...b.classList]);
    expect(classes).not.toContain('rounded-xl');
    expect(classes.filter(c => c.includes('min-h-12'))).toEqual([]);
    gaveta.unmount();
  });
});

describe('ficha da empresa: ações', () => {
  const empresa = { id: 1, name: 'Padaria Dornelaz', cnpj: '11222333000181' };
  const quemPodeReceber = pessoa({ id: 1 });
  const quemPediuSilencio = pessoa({ id: 2, opted_out_at: SEGUNDOS });

  it('com `podeMandarMensagem`, o cabeçalho tem Mandar mensagem (cheio) e Alterar (discreto)', async () => {
    const w = mount(CabecalhoDaEmpresa, {
      props: { empresa, podeMandarMensagem: true },
    });
    const botoes = w.findAllComponents(Button);
    const mandar = botoes.find(
      b => b.vm.$attrs['data-relacionamentos'] === 'mandar-mensagem'
    );
    const alterar = botoes.find(
      b => b.vm.$attrs['data-relacionamentos'] === 'alterar-empresa'
    );
    expect(mandar.props('variant')).toBeNull();
    expect(alterar.vm.$attrs).toMatchObject({ slate: '', faded: '' });
    await w.get('[data-relacionamentos="mandar-mensagem"]').trigger('click');
    await w.get('[data-relacionamentos="alterar-empresa"]').trigger('click');
    expect(w.emitted('mandarMensagem')).toHaveLength(1);
    expect(w.emitted('alterar')).toHaveLength(1);
  });

  // #2970 — "Mandar mensagem" ainda só simula: sem a página ligar, não há.
  it('sem `podeMandarMensagem` sobra só Alterar, discreto', async () => {
    const w = mount(CabecalhoDaEmpresa, { props: { empresa } });
    expect(w.find('[data-relacionamentos="mandar-mensagem"]').exists()).toBe(
      false
    );
    const grupo = w.get('[role="group"]');
    expect(grupo.findAll('button')).toHaveLength(1);
    const alterar = grupo.getComponent(Button);
    expect(alterar.vm.$attrs).toMatchObject({
      'data-relacionamentos': 'alterar-empresa',
      slate: '',
      faded: '',
    });
    await grupo.get('button').trigger('click');
    expect(w.emitted('alterar')).toHaveLength(1);
  });

  it('Mandar mensagem nunca fica desligado, nem explica o motivo no cabeçalho', () => {
    const w = mount(CabecalhoDaEmpresa, {
      props: { empresa, podeMandarMensagem: true },
    });
    expect(
      w.get('[data-relacionamentos="mandar-mensagem"]').attributes('disabled')
    ).toBeUndefined();
    expect(w.find('[data-relacionamentos="motivo-sem-envio"]').exists()).toBe(
      false
    );
  });

  const montarDialogo = pessoas =>
    mount(DialogoMandarMensagem, {
      props: { pessoas },
      global: { stubs },
    });
  const continuar = w =>
    w.get('[data-relacionamentos="mandar-mensagem-continuar"]');

  it('o diálogo diz quem recebe pelo nome e quem fica de fora com o motivo', async () => {
    const w = montarDialogo([
      quemPodeReceber,
      pessoa({ id: 2, name: 'Bruno Ouriveira', opted_out_at: SEGUNDOS }),
    ]);
    const texto = w.get('[data-relacionamentos="dialogo-mensagem"]').text();
    expect(texto).toContain('LISTA.MENSAGEM.QUEM_RECEBE');
    expect(texto).toContain('"quem":"Ana"');
    expect(texto).toContain('FORA_NOMES_NAO_QUER');
    expect(texto).toContain('"quem":"Bruno"');
    expect(
      w.get('[data-relacionamentos="dialogo-mensagem-proximo"]').text()
    ).toContain('PROXIMO_PASSO');
    expect(continuar(w).attributes('disabled')).toBeUndefined();
    await w.get('[data-confirmar]').trigger('click');
    expect(w.emitted('continuar')).toHaveLength(1);
  });

  it('ninguém pode receber: o diálogo explica e traz um botão só, "Entendi", que fecha', async () => {
    const fechar = vi.fn();
    const w = mount(DialogoMandarMensagem, {
      props: { pessoas: [quemPediuSilencio] },
      global: {
        stubs: {
          ...stubs,
          Dialog: {
            template: '<div data-dialog><slot /><slot name="footer" /></div>',
            methods: { open() {}, close: fechar },
          },
        },
      },
    });
    expect(w.get('[data-relacionamentos="dialogo-mensagem"]').text()).toContain(
      'NINGUEM_PODE'
    );
    expect(w.findComponent(DialogoDaFicha).props('soEntendi')).toBe(true);
    expect(
      w.find('[data-relacionamentos="mandar-mensagem-continuar"]').exists()
    ).toBe(false);
    expect(w.findAll('button')).toHaveLength(1);
    const entendi = w.get('[data-relacionamentos="entendi"]');
    expect(entendi.attributes('disabled')).toBeUndefined();
    expect(entendi.text()).toContain('MENSAGEM.ENTENDI');
    await entendi.trigger('click');
    expect(fechar).toHaveBeenCalledTimes(1);
    expect(
      w.find('[data-relacionamentos="dialogo-mensagem-proximo"]').exists()
    ).toBe(false);
  });

  it('empresa sem pessoas: uma frase simples e só "Entendi"', () => {
    const w = montarDialogo([]);
    expect(w.get('[data-relacionamentos="dialogo-mensagem"]').text()).toContain(
      'SEM_PESSOAS'
    );
    expect(w.find('[data-relacionamentos="entendi"]').exists()).toBe(true);
    expect(
      w.find('[data-relacionamentos="mandar-mensagem-continuar"]').exists()
    ).toBe(false);
  });

  it('com `podeConversar`, cada pessoa da lista tem o botão de conversar, com nome para o leitor de tela', async () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [quemPodeReceber], podeConversar: true },
    });
    const botao = w.get('[data-relacionamentos="conversar-com-pessoa"]');
    expect(botao.attributes('aria-label')).toContain('CONVERSAR_COM');
    expect(botao.classes()).toContain('size-11');
    await botao.trigger('click');
    expect(w.emitted('conversar')[0][0]).toMatchObject({ id: 1 });
    expect(w.emitted('abrir')).toBeUndefined();
  });

  // #2970 — o ícone de conversar ainda só simula: sem a página ligar, não há,
  // e a linha não guarda o espaço dele no celular.
  it('sem `podeConversar` a pessoa da lista não tem o botão de conversar e a linha usa a largura toda', async () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [quemPodeReceber] },
    });
    expect(
      w.find('[data-relacionamentos="conversar-com-pessoa"]').exists()
    ).toBe(false);
    expect(w.get('li').findAll('button')).toHaveLength(1);
    const linha = w.get('[data-relacionamentos="pessoa-da-empresa"]');
    expect(linha.classes()).not.toContain('pe-14');
    await linha.trigger('click');
    expect(w.emitted('abrir')[0]).toEqual([1]);
  });

  // #2895 — a ficha traz as primeiras pessoas da empresa. Quando a empresa tem
  // mais gente do que veio, a tela diz quantas está mostrando.
  it('diz quantas mostra quando a empresa tem mais gente do que veio', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [quemPodeReceber], total: 250 },
    });
    const aviso = w.get('[data-relacionamentos="mostrando-parte"]');
    expect(aviso.text()).toContain('MOSTRANDO_PARTE');
    expect(aviso.text()).toContain('"mostradas":1');
    expect(aviso.text()).toContain('"total":250');
  });

  it('não diz nada quando todas as pessoas vieram', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [quemPodeReceber], total: 1 },
    });
    expect(w.find('[data-relacionamentos="mostrando-parte"]').exists()).toBe(
      false
    );
  });
});

describe('CabecalhoDaPessoa: terceira rodada', () => {
  const montar = props =>
    mount(CabecalhoDaPessoa, { props, global: { stubs } });

  it('nenhum rótulo de botão do cabeçalho encolhe ou quebra', () => {
    const w = montar({
      pessoa: pessoa(),
      podeConversar: true,
      naDemonstracao: true,
    });
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
    // #2970 — fora da demonstração o menu só existe com dois itens: é o de
    // quem é cliente (Alterar informações e Não é mais cliente).
    const w = mount(MenuMais, {
      attachTo: document.body,
      props: { ehCliente: true },
      global: { stubs },
    });
    const gatilho = w.get('[data-relacionamentos="mais-acoes"]');
    await gatilho.trigger('click');
    const itens = w.findAll('.n-dropdown-item button');
    expect(itens).toHaveLength(2);
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

  it('diz o que a recusa significa, em frase de apoio', () => {
    expect(
      montar('manual').get('[data-relacionamentos="faixa-apoio"]').text()
    ).toContain('FAIXA.APOIO');
  });

  it('não supõe gênero: a frase de apoio e o diálogo usam o primeiro nome', () => {
    const w = mount(FaixaNaoQuer, {
      props: {
        pessoa: pessoa({
          name: 'Otávio Prado',
          opted_out_at: Date.UTC(2026, 8, 12, 12) / 1000,
          opt_out_source: 'manual',
        }),
      },
      global: { stubs },
    });
    const apoio = w.get('[data-relacionamentos="faixa-apoio"]').text();
    expect(apoio).toContain('"nome":"Otávio"');
    expect(apoio).not.toContain('Prado');
    const texto = w.findComponent(DialogoDaFicha).props('texto');
    expect(texto).toContain('CONFIRMA_TEXTO');
    expect(texto).toContain('"nome":"Otávio"');
    expect(texto).not.toContain('Prado');
  });

  it('a faixa é o Banner da casa, em âmbar; Liberar é um botão da casa (o do Banner é pequeno para o dedo)', () => {
    const w = montar('manual');
    const banner = w.findComponent(Banner);
    expect(banner.props('color')).toBe('amber');
    expect(banner.props('actionLabel')).toBeNull();
    const liberar = w.get('[data-relacionamentos="liberar"]');
    expect(liberar.text()).toContain('FAIXA.LIBERAR');
    expect(liberar.classes()).toContain('h-10');
    expect(banner.findAll('button')).toHaveLength(1);
    expect(w.html()).not.toContain('bg-n-amber-3 text-n-amber-11 sm:flex-row');
  });

  it('um clique em Liberar NUNCA libera sem passar pelo diálogo', async () => {
    const abrir = vi.fn();
    const w = mount(FaixaNaoQuer, {
      props: {
        pessoa: pessoa({
          opted_out_at: Date.UTC(2026, 8, 12, 12) / 1000,
          opt_out_source: 'manual',
        }),
        agora: AGORA,
      },
      global: {
        stubs: {
          ...stubs,
          Dialog: {
            template:
              '<div data-dialog><slot /><slot name="footer" /><button data-confirmar @click="$emit(\'confirm\')" /></div>',
            methods: { open: abrir, close() {} },
          },
        },
      },
    });
    const liberar = () => w.get('[data-relacionamentos="liberar"]');
    await liberar().trigger('click');
    await liberar().trigger('click');
    expect(abrir).toHaveBeenCalledTimes(2);
    expect(w.emitted('liberar')).toBeUndefined();
    expect(
      w.get('[data-relacionamentos="liberar-confirmar"]').attributes('type')
    ).toBe('submit');
    await w.get('[data-confirmar]').trigger('click');
    expect(w.emitted('liberar')).toHaveLength(1);
  });

  it('o diálogo pergunta se a própria pessoa pediu', () => {
    const w = montar('manual');
    const dialogo = w.findComponent(DialogoDaFicha);
    expect(dialogo.props('titulo')).toContain('CONFIRMA_TITULO');
    expect(dialogo.props('texto')).toContain('CONFIRMA_TEXTO');
    expect(
      w.get('[data-relacionamentos="liberar-confirmar"]').text()
    ).toContain('CONFIRMA_BOTAO');
  });

  it('origem que a casa não conhece: só a primeira frase', () => {
    const texto = montar('origem_nova').text();
    expect(texto).toContain('FAIXA.TEXTO_SIMPLES');
    expect(texto).not.toContain('FAIXA.ORIGEM');
  });

  it('é aviso fixo: não nasce como região viva', () => {
    expect(montar('manual').find('[role="status"], [aria-live]').exists()).toBe(
      false
    );
  });

  it('não tem Liberar nas outras origens', () => {
    expect(
      montar('email_unsubscribe').findComponent(Banner).find('button').exists()
    ).toBe(false);
  });
});

describe('SecaoConversas', () => {
  it('mostra só as 3 últimas, com canal, quando e situação', () => {
    const w = mount(SecaoConversas, {
      props: {
        conversas: [1, 2, 3, 4, 5].map(id => conversa(id)),
        agora: AGORA,
        podeVerTodas: true,
      },
    });
    expect(w.findAll('li')).toHaveLength(3);
    expect(w.text()).toContain('Trecho 1');
    expect(w.text()).not.toContain('Trecho 4');
    expect(w.text()).toContain('há 11 dias');
    expect(w.text()).toContain('SITUACAO.aberta');
    expect(w.text()).toContain('CONVERSAS.VER_TODAS');
  });

  it('com `podeVerTodas`, Ver todas emite', async () => {
    const w = mount(SecaoConversas, {
      props: { conversas: [conversa(1)], agora: AGORA, podeVerTodas: true },
    });
    await w.get('button').trigger('click');
    expect(w.emitted('verTodas')).toHaveLength(1);
  });

  // #2970 — "Ver todas" ainda só avisa: sem a página ligar, não há. O título e
  // as conversas continuam.
  it('sem `podeVerTodas` não tem Ver todas, e a seção segue com título e conversas', () => {
    const w = mount(SecaoConversas, {
      props: { conversas: [conversa(1), conversa(2)], agora: AGORA },
    });
    expect(w.find('button').exists()).toBe(false);
    expect(w.text()).not.toContain('VER_TODAS');
    expect(w.get('h2').text()).toContain('CONVERSAS.TITULO');
    expect(w.findAll('li')).toHaveLength(2);
  });

  it('vazio dentro da seção: só a frase, sem cartão interno nem botão', () => {
    const w = mount(SecaoConversas, { props: { conversas: [] } });
    const vazio = w.get('[data-vazio]');
    expect(vazio.classes()).not.toContain('border');
    expect(vazio.classes()).not.toContain('text-center');
    expect(vazio.find('button').exists()).toBe(false);
    const cards = mount(SecaoCards, { props: { cards: [] } });
    expect(cards.get('[data-vazio]').classes()).not.toContain('border');
    expect(cards.find('[data-vazio] button').exists()).toBe(false);
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

  it('vazio: só a frase (a ação já está no cabeçalho)', () => {
    const w = mount(SecaoConversas, { props: { conversas: [] } });
    expect(w.get('[data-vazio]').text()).toContain('CONVERSAS.VAZIO');
    expect(w.find('button').exists()).toBe(false);
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

  it('vazio: só a frase', () => {
    const w = mount(SecaoCards, { props: { cards: [] } });
    expect(w.get('[data-vazio]').text()).toContain('CARDS.VAZIO');
    expect(w.find('button').exists()).toBe(false);
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

  it('Salvar nunca fica desligado: vazio, o clique diz o que falta e leva o foco à caixa', async () => {
    const w = mount(SecaoNotas, {
      props: { notas: [], agora: AGORA },
      attachTo: document.body,
    });
    const guardar = w.get('[data-relacionamentos="guardar-nota"]');
    const erro = w.get('[data-relacionamentos="nota-erro"]');
    expect(guardar.attributes('disabled')).toBeUndefined();
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.text()).toBe('');
    await guardar.trigger('click');
    await w.get('form').trigger('submit');
    expect(w.emitted('guardar')).toBeUndefined();
    expect(erro.text()).toContain('NOTAS.ESCREVA_ANTES');
    expect(document.activeElement).toBe(
      w.get('[data-relacionamentos="nota-caixa"]').element
    );
    await w.get('[data-relacionamentos="nota-caixa"]').setValue('Oi');
    expect(erro.text()).toBe('');
    w.unmount();
  });

  it('Guardar emite o texto limpo', async () => {
    const w = mount(SecaoNotas, { props: { notas: [], agora: AGORA } });
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

  it('nota de quem já saiu da plataforma (sem autor) mostra só quando', () => {
    const w = mount(SecaoNotas, {
      props: {
        notas: [{ id: 'a', autor: null, quando: SEGUNDOS, texto: 'Antiga.' }],
        agora: AGORA,
      },
    });
    const nota = w.get('[data-relacionamentos="nota"]');
    expect(nota.text()).toContain('Antiga.');
    expect(nota.text()).toContain('há 10 dias');
    expect(nota.text()).not.toContain('NOTAS.POR');
    expect(nota.text()).not.toContain('null');
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

  it('o rótulo de Redes sociais fica na mesma margem dos campos, com a seta depois', () => {
    const w = montar();
    const botao = w.get('[data-relacionamentos="redes-sociais"]');
    expect(botao.classes()).toContain('p-0');
    expect(botao.element.firstChild.nodeType).toBe(Node.TEXT_NODE);
    expect(botao.element.lastElementChild.className).toContain(
      'i-lucide-chevron-right'
    );
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

  it('sem nada preenchido mostra a frase de vazio, não uma lista de "Não informado"', () => {
    const w = mount(ListaDeInformacoes, {
      props: {
        linhas: [
          { chave: 'cpf', valor: '' },
          { chave: 'cidade', valor: '' },
        ],
      },
    });
    expect(w.get('[data-vazio]').text()).toContain('INFORMACOES.VAZIO');
    expect(w.find('[data-informacao]').exists()).toBe(false);
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
      props: {
        pessoas: [pessoa({ contact_type: 'customer' })],
        podeConversar: true,
      },
    });
    const email = w.get('[data-relacionamentos="email-da-pessoa"]');
    // O e-mail começa na mesma coluna do nome, nunca debaixo do avatar.
    expect(email.classes()).toContain('col-start-2');
    expect(email.classes()).not.toContain('col-span-2');
    expect(email.classes()).not.toContain('col-start-1');
    const linha = w.get('[data-relacionamentos="pessoa-da-empresa"]');
    // Celular: nome em até 2 linhas (sem reticências) e o selo desce para
    // baixo do nome; o botão de conversar fica na primeira linha.
    expect(linha.get('span.line-clamp-2').classes()).toContain('md:truncate');
    expect(
      w.get('[data-relacionamentos="selos-da-pessoa"]').classes()
    ).toContain('col-start-2');
    expect(
      w.get('[data-relacionamentos="conversar-com-pessoa"]').classes()
    ).toContain('absolute');
    expect(linha.classes()).toEqual(
      expect.arrayContaining(['pe-14', 'md:pe-2'])
    );
    // Celular: o e-mail inteiro (quebra se preciso); md+: uma linha com reticências.
    expect(email.classes()).toEqual(
      expect.arrayContaining(['break-words', 'md:truncate'])
    );
    expect(w.get('[data-selo="cliente"]').exists()).toBe(true);
  });
});

describe('SecaoPessoasDaEmpresa: quem não quer mensagens', () => {
  it('a linha de quem tem opted_out_at leva o selo "Não quer mensagens"', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: {
        pessoas: [
          pessoa({ id: 1, opted_out_at: Date.UTC(2026, 8, 12) / 1000 }),
          pessoa({ id: 2, name: 'Bruno Lima', opted_out_at: null }),
        ],
      },
    });
    const linhas = w.findAll('li');
    const selo = linhas[0].get('[data-selo="alerta"]');
    expect(selo.text()).toContain('SELO_NAO_QUER_MENSAGENS');
    expect(linhas[1].find('[data-selo="alerta"]').exists()).toBe(false);
  });

  it('o e-mail só quebra no @ (wbr), sem partir "com." de "br"', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [pessoa({ email: 'ana@padaria.com.br' })] },
    });
    const email = w.get('[data-relacionamentos="email-da-pessoa"]');
    expect(email.text()).toBe('ana@padaria.com.br');
    expect(email.findAll('wbr')).toHaveLength(1);
    expect(email.html()).toContain('ana<wbr>@padaria.com.br');
  });

  it('sem e-mail, mostra o telefone inteiro', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: {
        pessoas: [pessoa({ email: '', phone_number: '+5511999990000' })],
      },
    });
    const email = w.get('[data-relacionamentos="email-da-pessoa"]');
    expect(email.text()).toBe('+5511999990000');
    expect(email.find('wbr').exists()).toBe(false);
  });

  it('o botão de conversar tem alvo de 44 px e não encolhe', () => {
    const w = mount(SecaoPessoasDaEmpresa, {
      props: { pessoas: [pessoa()], podeConversar: true },
    });
    expect(
      w.get('[data-relacionamentos="conversar-com-pessoa"]').classes()
    ).toEqual(expect.arrayContaining(['size-11', 'shrink-0']));
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

describe('gavetas: não apagam o que a pessoa digitou', () => {
  const empresa = { id: 1, name: 'Padaria Dornelaz', cnpj: '11222333000181' };

  it('GavetaDaEmpresa só reabre na transição fechada para aberta', async () => {
    const w = mount(GavetaDaEmpresa, {
      props: { aberta: true, empresa },
      attachTo: document.body,
      global: { stubs },
    });
    const campo = () => document.querySelector('[data-foco]');
    campo().value = 'Digitei isto';
    campo().dispatchEvent(new Event('input'));
    await w.vm.$nextTick();
    await w.setProps({
      empresa: { ...empresa, domain: 'novo.exemplo.com.br' },
    });
    expect(campo().value).toBe('Digitei isto');
    await w.setProps({ aberta: false });
    await w.setProps({ aberta: true });
    // A gaveta sai por uma transição: o campo novo é o último no documento.
    await vi.waitFor(() => {
      const campos = [...document.querySelectorAll('[data-foco]')];
      expect(campos.at(-1).value).toBe('Padaria Dornelaz');
    });
    w.unmount();
  });

  it('GavetaDeInformacoes também', async () => {
    const w = mount(GavetaDeInformacoes, {
      props: { aberta: true, pessoa: pessoa() },
      attachTo: document.body,
      global: { stubs },
    });
    const campo = () => document.querySelector('[data-foco]');
    campo().value = 'Digitei isto';
    campo().dispatchEvent(new Event('input'));
    await w.vm.$nextTick();
    await w.setProps({ pessoa: pessoa({ contact_type: 'customer' }) });
    expect(campo().value).toBe('Digitei isto');
    w.unmount();
  });
});

// #2895 — o que o servidor manda e a demonstração não tinha.
describe('valores novos do servidor', () => {
  const linha = props =>
    mount(SecaoConversas, { props: { agora: AGORA, ...props } }).get('li');

  it('canal `outro` (ou desconhecido) tem ícone neutro e nome para o leitor de tela', () => {
    ['outro', 'telegram'].forEach(canal => {
      const icone = linha({ conversas: [conversa(1, { canal })] }).get(
        '[role="img"]'
      );
      expect(icone.classes()).toContain('i-lucide-messages-square');
      expect(icone.attributes('aria-label')).toContain('CANAL.outro');
    });
  });

  it('conversa adiada diz que está adiada; situação desconhecida, o rótulo neutro', () => {
    expect(
      linha({ conversas: [conversa(1, { situacao: 'adiada' })] }).text()
    ).toContain('SITUACAO.adiada');
    expect(
      linha({ conversas: [conversa(1, { situacao: 'nova' })] }).text()
    ).toContain('SITUACAO.outra');
  });

  it('conversa sem trecho diz que não tem texto, na pessoa e na empresa', () => {
    const daPessoa = linha({ conversas: [conversa(1, { trecho: null })] });
    expect(daPessoa.text()).toContain('CONVERSAS.SEM_TRECHO');
    const daEmpresa = linha({
      conversas: [conversa(1, { trecho: null, pessoa: 'Bruno' })],
    });
    expect(daEmpresa.text()).toContain('"pessoa":"Bruno"');
    expect(daEmpresa.text()).toContain('CONVERSAS.SEM_TRECHO');
    expect(daEmpresa.text()).not.toContain('null');
  });

  it('card sem valor (quem não pode ver valor) não mostra valor nenhum', () => {
    const w = mount(SecaoCards, {
      props: { cards: [card(1, { valor: null })] },
    });
    const item = w.get('[data-relacionamentos="card"]');
    expect(item.find('[data-relacionamentos="card-valor"]').exists()).toBe(
      false
    );
    expect(item.text()).not.toContain('R$');
    expect(item.text()).toContain('SITUACAO.aberto');
  });

  it('card com valor zero mostra o zero', () => {
    const w = mount(SecaoCards, { props: { cards: [card(1, { valor: 0 })] } });
    expect(w.get('[data-relacionamentos="card-valor"]').text()).toContain('R$');
  });

  it('card em outro estado do CRM tem rótulo; estado desconhecido, o neutro', () => {
    const w = mount(SecaoCards, {
      props: {
        cards: [
          card(1, { situacao: 'cancelado' }),
          card(2, { situacao: 'estado_novo' }),
        ],
      },
    });
    const itens = w.findAll('[data-relacionamentos="card"]');
    expect(itens[0].text()).toContain('SITUACAO.cancelado');
    expect(itens[1].text()).toContain('SITUACAO.outra');
    expect(itens[1].text()).not.toContain('estado_novo');
  });

  it('a gaveta do card sem valor não tem a linha de valor, e o estado desconhecido é neutro', () => {
    const w = mount(GavetaDoCard, {
      props: { card: card(5, { valor: null, situacao: 'estado_novo' }) },
      global: { stubs },
    });
    expect(w.text()).not.toContain('GAVETA.VALOR');
    expect(w.text()).toContain('SITUACAO.outra');
    const comValor = mount(GavetaDoCard, {
      props: { card: card(5) },
      global: { stubs },
    });
    expect(comValor.text()).toContain('GAVETA.VALOR');
  });
});

describe('parte da ficha que não carregou', () => {
  const FALHA = '[data-relacionamentos="falha-da-parte"]';

  it.each([
    ['SecaoConversas', SecaoConversas, { conversas: [] }],
    ['SecaoCards', SecaoCards, { cards: [] }],
    ['SecaoNotas', SecaoNotas, { notas: [] }],
    ['SecaoArquivos', SecaoArquivos, { arquivos: [] }],
    ['SecaoPessoasDaEmpresa', SecaoPessoasDaEmpresa, { pessoas: [] }],
    ['DeOndeVeio', DeOndeVeio, { origem: null }],
  ])(
    '%s diz que não conseguiu, sem a frase de vazio, e "Tentar de novo" emite',
    async (_nome, Peca, props) => {
      const w = mount(Peca, {
        props: { ...props, falhou: true, agora: AGORA },
      });
      const falha = w.get(FALHA);
      expect(falha.attributes('role')).toBe('alert');
      expect(falha.text()).toContain('ESTADOS.ERRO_DA_PARTE');
      expect(w.text()).not.toContain('VAZIO');
      await falha.get('button').trigger('click');
      expect(w.emitted('tentar')).toHaveLength(1);
    }
  );

  it('sem falha nenhuma peça mostra o aviso', () => {
    expect(
      mount(SecaoCards, { props: { cards: [] } })
        .find(FALHA)
        .exists()
    ).toBe(false);
    expect(
      mount(DeOndeVeio, { props: { origem: null } })
        .find('[data-relacionamentos="de-onde-veio"]')
        .exists()
    ).toBe(false);
  });
});

describe('quem só pode ver não tem os botões de escrita', () => {
  it('cabeçalho da pessoa: sem Marcar como cliente, sem "⋯" e sem "Alterar informações"', () => {
    const w = mount(CabecalhoDaPessoa, {
      props: { pessoa: pessoa(), podeEditar: false },
      global: { stubs },
    });
    expect(w.find('[data-relacionamentos="marcar-cliente"]').exists()).toBe(
      false
    );
    expect(w.find('[data-relacionamentos="mais-acoes"]').exists()).toBe(false);
    expect(
      w.find('[data-relacionamentos="alterar-informacoes"]').exists()
    ).toBe(false);
    expect(w.text()).not.toContain('ALTERAR_INFORMACOES');
  });

  it('cabeçalho da pessoa: quem é cliente continua com o selo', () => {
    const w = mount(CabecalhoDaPessoa, {
      props: {
        pessoa: pessoa({ contact_type: 'customer' }),
        podeEditar: false,
      },
      global: { stubs },
    });
    expect(w.find('[data-selo="cliente"]').exists()).toBe(true);
  });

  it('Novo card some para quem não pode criar card, e o resto do cabeçalho fica', () => {
    const montar = podeCriarCards =>
      mount(CabecalhoDaPessoa, {
        props: { pessoa: pessoa(), podeCriarCards },
        global: { stubs },
      });
    const com = montar(true);
    expect(com.find('[data-relacionamentos="novo-card"]').exists()).toBe(true);
    const sem = montar(false);
    expect(sem.find('[data-relacionamentos="novo-card"]').exists()).toBe(false);
    expect(
      sem.find('[data-relacionamentos="alterar-informacoes"]').exists()
    ).toBe(true);
    expect(sem.find('[data-relacionamentos="marcar-cliente"]').exists()).toBe(
      true
    );
  });

  it('a faixa de quem não quer mensagens fica sem Liberar', () => {
    const w = mount(FaixaNaoQuer, {
      props: {
        pessoa: pessoa({ opted_out_at: SEGUNDOS, opt_out_source: 'manual' }),
        agora: AGORA,
        podeLiberar: false,
      },
      global: { stubs },
    });
    expect(w.find('[data-relacionamentos="liberar"]').exists()).toBe(false);
    expect(w.text()).toContain('FAIXA.TEXTO');
  });

  it('as notas ficam sem a caixa de escrever, mas mostram a lista', () => {
    const w = mount(SecaoNotas, {
      props: {
        notas: [{ id: 'a', autor: 'Sônia', quando: SEGUNDOS, texto: 'Oi.' }],
        agora: AGORA,
        podeEscrever: false,
      },
    });
    expect(w.find('form').exists()).toBe(false);
    expect(w.find('[data-relacionamentos="guardar-nota"]').exists()).toBe(
      false
    );
    expect(w.get('[data-relacionamentos="nota"]').text()).toContain('Oi.');
  });

  it('o corpo da ficha fica sem Alterar', () => {
    const montar = podeEditar =>
      mount(CorpoDaFichaDaPessoa, {
        props: {
          conversas: [],
          cards: [],
          notas: [],
          arquivos: [],
          linhas: [],
          redes: [],
          agora: AGORA,
          podeEditar,
        },
        global: { stubs },
      });
    expect(montar(true).find('[data-relacionamentos="alterar"]').exists()).toBe(
      true
    );
    const semEditar = montar(false);
    expect(semEditar.find('[data-relacionamentos="alterar"]').exists()).toBe(
      false
    );
    expect(semEditar.find('form').exists()).toBe(false);
  });

  it('o corpo esconde a parte que a pessoa não pode ver e repassa o "tentar de novo" da que falhou', async () => {
    const w = mount(CorpoDaFichaDaPessoa, {
      props: {
        conversas: [],
        cards: [],
        notas: [],
        arquivos: [],
        linhas: [],
        redes: [],
        agora: AGORA,
        falhas: { cards: 'semAcesso', conversas: 'erro' },
      },
      global: { stubs },
    });
    expect(w.find('[data-relacionamentos="cards"]').exists()).toBe(false);
    expect(w.find('[data-relacionamentos="notas"]').exists()).toBe(true);
    await w
      .get(
        '[data-relacionamentos="conversas"] [data-relacionamentos="falha-da-parte"] button'
      )
      .trigger('click');
    expect(w.emitted('tentar')[0]).toEqual(['conversas']);
  });

  it('cabeçalho da empresa: sem Alterar, com Mandar mensagem quando a página liga', () => {
    const w = mount(CabecalhoDaEmpresa, {
      props: {
        empresa: { id: 1, name: 'Padaria' },
        podeEditar: false,
        podeMandarMensagem: true,
      },
    });
    expect(w.find('[data-relacionamentos="alterar-empresa"]').exists()).toBe(
      false
    );
    expect(w.find('[data-relacionamentos="mandar-mensagem"]').exists()).toBe(
      true
    );
  });

  // #2970 — fora da demonstração "Mandar mensagem" não existe: quem só pode ver
  // fica sem botão nenhum, e o grupo de ações não sobra vazio.
  it('cabeçalho da empresa: sem Alterar e sem Mandar mensagem, não há grupo de ações', () => {
    const w = mount(CabecalhoDaEmpresa, {
      props: { empresa: { id: 1, name: 'Padaria' }, podeEditar: false },
    });
    expect(w.find('[role="group"]').exists()).toBe(false);
    expect(w.find('button').exists()).toBe(false);
    expect(w.get('h1').text()).toBe('Padaria');
  });
});
