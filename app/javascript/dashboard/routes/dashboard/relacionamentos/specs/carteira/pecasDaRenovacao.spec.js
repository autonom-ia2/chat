import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ControlesDeSeguros from '../../components/carteira/ControlesDeSeguros.vue';
import HistoriaDoSeguro from '../../components/carteira/HistoriaDoSeguro.vue';
import RenovacaoDoSeguro from '../../components/carteira/RenovacaoDoSeguro.vue';
import BarraDeResultado from '../../components/carteira/renovacao/BarraDeResultado.vue';
import CampoDeDias from '../../components/carteira/renovacao/CampoDeDias.vue';
import ConviteDasRenovacoes from '../../components/carteira/renovacao/ConviteDasRenovacoes.vue';
import DialogoMotivo from '../../components/carteira/renovacao/DialogoMotivo.vue';
import OndeFicamAsRenovacoes from '../../components/carteira/renovacao/OndeFicamAsRenovacoes.vue';
import { FALTAS } from '../../carteira/ajustesDaRenovacao';
import { baixarArquivo } from '../../carteira/exportarHistoria';
import { daCarteira } from './apoio';

// As peças da renovação no funil (#2898), com o texto de verdade em pt_BR: o
// diálogo do motivo em um toque, a parte "Renovação" da gaveta, o convite da
// aba Seguros, os atalhos da faixa de controles, as peças de "Ajustar
// renovações", a barra dos resultados e o "Exportar" do histórico. Todos os
// dados são inventados.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('../../carteira/exportarHistoria', async importOriginal => ({
  ...(await importOriginal()),
  baixarArquivo: vi.fn(),
}));

withFullI18n('pt_BR');

let montada;
const montar = (Peca, props = {}) => {
  montada = mount(Peca, { attachTo: document.body, props });
  return montada;
};
afterEach(() => {
  montada?.unmount();
  montada = null;
  baixarArquivo.mockClear();
});

const RENOVACAO = {
  cardId: 88,
  funil: 'Renovação',
  etapa: 'A vencer',
  desfecho: null,
  cuida: 'Bruna Teixeirão',
};
const seguroCom = (renovacao, resto = {}) => ({
  id: 7,
  renovacao: { ...RENOVACAO, ...renovacao },
  renovadoEm: null,
  motivo: null,
  motivoEscrito: '',
  apoliceNova: false,
  ...resto,
});

describe('o diálogo "Por que não renovou?"', () => {
  const abrir = async () => {
    const w = montar(DialogoMotivo);
    w.vm.abrir();
    await w.vm.$nextTick();
    return w;
  };
  const umToque = w => w.findAll(daCarteira('motivo-de-um-toque'));
  const aberto = w => w.find('[data-dialogo-falso]').exists();

  it('oferece os quatro motivos de um toque e o caminho para escrever outro', async () => {
    const w = await abrir();

    expect(w.get('[data-relacionamentos="titulo-do-dialogo"]').text()).toBe(
      'Por que não renovou?'
    );
    expect(umToque(w).map(botao => botao.text())).toEqual([
      'Achou caro',
      'Foi para outra corretora',
      'Vendeu o bem',
      'Não respondeu',
    ]);
    expect(w.get(daCarteira('motivo-outro')).text()).toBe('Outro motivo');
    expect(w.find(daCarteira('motivo-escrito')).exists()).toBe(false);
  });

  it('um toque no motivo já guarda e fecha', async () => {
    const w = await abrir();

    await w.get('[data-motivo="outra_corretora"]').trigger('click');

    expect(w.emitted('escolher')).toEqual([[{ motivo: 'outra_corretora' }]]);
    expect(aberto(w)).toBe(false);
  });

  it('"Outro motivo" abre a linha de escrever e leva o foco até ela', async () => {
    const w = await abrir();

    await w.get(daCarteira('motivo-outro')).trigger('click');
    await w.vm.$nextTick();

    const campo = w.get(daCarteira('motivo-escrito'));
    expect(document.activeElement).toBe(campo.element);
    expect(w.find(daCarteira('motivo-outro')).exists()).toBe(false);
    expect(w.emitted('escolher')).toBeUndefined();
  });

  it('salvar sem escrever diz o que falta e não guarda nada', async () => {
    const w = await abrir();
    await w.get(daCarteira('motivo-outro')).trigger('click');
    await w.get(daCarteira('motivo-escrito')).setValue('   ');

    await w.get('[data-confirmar]').trigger('click');

    expect(w.get(daCarteira('falta-o-motivo')).text()).toBe(
      'Escreva o motivo ou toque em um dos motivos acima.'
    );
    expect(w.get(daCarteira('motivo-escrito')).attributes('aria-invalid')).toBe(
      'true'
    );
    expect(w.emitted('escolher')).toBeUndefined();
    expect(aberto(w)).toBe(true);
  });

  it('o motivo escrito vai sem os espaços das pontas, como "outro"', async () => {
    const w = await abrir();
    await w.get(daCarteira('motivo-outro')).trigger('click');
    await w.get(daCarteira('motivo-escrito')).setValue('  Mudou de país ');

    await w.get('[data-confirmar]').trigger('click');

    expect(w.emitted('escolher')).toEqual([
      [{ motivo: 'outro', texto: 'Mudou de país' }],
    ]);
    expect(aberto(w)).toBe(false);
  });

  it('Enter na linha de escrever também salva', async () => {
    const w = await abrir();
    await w.get(daCarteira('motivo-outro')).trigger('click');
    const campo = w.get(daCarteira('motivo-escrito'));
    await campo.setValue('Vendeu a empresa');

    await campo.trigger('keydown', { key: 'Enter' });

    expect(w.emitted('escolher')).toEqual([
      [{ motivo: 'outro', texto: 'Vendeu a empresa' }],
    ]);
  });

  it('abrir de novo começa do zero', async () => {
    const w = await abrir();
    await w.get(daCarteira('motivo-outro')).trigger('click');
    await w.get(daCarteira('motivo-escrito')).setValue('Rascunho');
    await w.get('[data-cancelar]').trigger('click');

    w.vm.abrir();
    await w.vm.$nextTick();

    expect(w.find(daCarteira('motivo-escrito')).exists()).toBe(false);
    expect(w.find(daCarteira('motivo-outro')).exists()).toBe(true);
    expect(w.emitted('escolher')).toBeUndefined();
  });
});

describe('a parte "Renovação" da gaveta do seguro', () => {
  const situacao = w => w.get(daCarteira('situacao-da-renovacao')).text();
  const abrir = (seguro, podeEditar = true) =>
    montar(RenovacaoDoSeguro, { seguro, podeEditar });

  it('aberta: diz o funil, a etapa e quem cuida, e leva ao card', async () => {
    const w = abrir(seguroCom());

    expect(situacao(w)).toBe('Está no funil Renovação, na etapa A vencer.');
    expect(w.get(daCarteira('quem-cuida')).text()).toBe(
      'Quem cuida: Bruna Teixeirão'
    );
    expect(w.find(daCarteira('dizer-o-motivo')).exists()).toBe(false);

    await w.get(daCarteira('abrir-no-crm')).trigger('click');

    expect(w.emitted('abrirCard')).toEqual([[88]]);
  });

  it('sem card e sem quem cuida, não mostra o link nem a linha', () => {
    const w = abrir(seguroCom({ cardId: null, cuida: null }));

    expect(w.find(daCarteira('abrir-no-crm')).exists()).toBe(false);
    expect(w.find(daCarteira('quem-cuida')).exists()).toBe(false);
  });

  it('renovou: diz se a apólice nova já foi guardada', () => {
    const renovou = seguroCom(
      { desfecho: 'renovou' },
      { renovadoEm: 1790000000 }
    );

    expect(situacao(abrir(renovou))).toBe(
      'Renovou. Falta guardar a apólice nova.'
    );
    montada.unmount();
    expect(situacao(abrir({ ...renovou, apoliceNova: true }))).toBe(
      'Renovou. A apólice nova já está guardada.'
    );
  });

  it('não renovou: escreve o motivo de um toque por extenso', () => {
    const w = abrir(
      seguroCom({ desfecho: 'nao_renovou' }, { motivo: 'achou_caro' })
    );

    expect(situacao(w)).toBe('Não renovou: achou caro.');
    expect(w.find(daCarteira('dizer-o-motivo')).exists()).toBe(false);
  });

  it('não renovou por outro motivo: escreve o que a pessoa escreveu', () => {
    const w = abrir(
      seguroCom(
        { desfecho: 'nao_renovou' },
        { motivo: 'outro', motivoEscrito: 'Mudou de país' }
      )
    );

    expect(situacao(w)).toBe('Não renovou. Motivo: Mudou de país');
  });

  it('não renovou e ninguém disse por quê: convida quem pode alterar a dizer', async () => {
    const w = abrir(seguroCom({ desfecho: 'nao_renovou' }));

    expect(situacao(w)).toBe('Não renovou. Ninguém disse o motivo.');
    const botao = w.get(daCarteira('dizer-o-motivo'));
    expect(botao.text()).toBe('Dizer por que não renovou');

    await botao.trigger('click');

    expect(w.emitted('dizerMotivo')).toHaveLength(1);
  });

  it('quem só pode ver não é convidado a dizer o motivo', () => {
    const w = abrir(seguroCom({ desfecho: 'nao_renovou' }), false);

    expect(w.find(daCarteira('dizer-o-motivo')).exists()).toBe(false);
    expect(w.find(daCarteira('abrir-no-crm')).exists()).toBe(true);
  });
});

describe('o convite para escolher o funil das renovações', () => {
  const fonteCom = resposta => ({
    ajustes: vi.fn().mockResolvedValue(resposta),
  });
  const abrir = async fonte => {
    const w = montar(ConviteDasRenovacoes, { fonte });
    await flushPromises();
    return w;
  };
  const convite = w => w.find(daCarteira('convite-das-renovacoes'));
  const SEM_FUNIL = { funilId: null, etapaId: null, dias: 60 };

  it('conta que ainda não escolheu: uma frase e um botão', async () => {
    const w = await abrir(
      fonteCom({ ajustes: SEM_FUNIL, semPermissao: false })
    );

    expect(convite(w).text()).toContain(
      'Escolha em que funil as renovações aparecem.'
    );
    const botao = w.get(daCarteira('escolher-funil-das-renovacoes'));
    expect(botao.text()).toBe('Escolher o funil');
    expect(botao.classes()).toContain('basis-full');
    expect(botao.classes()).toContain('whitespace-nowrap');

    await botao.trigger('click');

    expect(w.emitted('escolher')).toHaveLength(1);
  });

  it('conta que já escolheu não vê nada', async () => {
    const w = await abrir(
      fonteCom({ ajustes: { ...SEM_FUNIL, funilId: 3, etapaId: 31 } })
    );

    expect(convite(w).exists()).toBe(false);
  });

  it('quem o servidor não deixa mudar não é convidado', async () => {
    const w = await abrir(fonteCom({ ajustes: SEM_FUNIL, semPermissao: true }));

    expect(convite(w).exists()).toBe(false);
  });

  it('se a leitura falhar, o convite só não aparece', async () => {
    const w = await abrir({
      ajustes: vi.fn().mockRejectedValue(new Error('Network Error')),
    });

    expect(convite(w).exists()).toBe(false);
  });
});

describe('os atalhos da renovação na faixa de controles', () => {
  const abrir = (props = {}) =>
    montar(ControlesDeSeguros, { ordem: 'vence_primeiro', ...props });
  const doMenu = w =>
    w
      .findAll(`${daCarteira('mais-da-carteira')} [role="menuitem"]`)
      .map(item => item.attributes('data-acao'));

  it('"Resultados" aparece para todos; "Ajustar renovações" só para quem pode mudar', () => {
    const quemSoVe = abrir();

    expect(quemSoVe.get(daCarteira('resultados')).text()).toBe('Resultados');
    expect(quemSoVe.find(daCarteira('ajustar')).exists()).toBe(false);
    expect(doMenu(quemSoVe)).toEqual(['resultados']);
    quemSoVe.unmount();

    const quemMuda = abrir({ podeAjustar: true });

    expect(quemMuda.get(daCarteira('ajustar')).text()).toBe(
      'Ajustar renovações'
    );
    expect(doMenu(quemMuda)).toEqual(['resultados', 'ajustar']);
  });

  it('cada atalho avisa a página com o próprio evento', async () => {
    const w = abrir({ podeAjustar: true });

    await w.get(daCarteira('resultados')).trigger('click');
    await w.get(daCarteira('ajustar')).trigger('click');

    expect(w.emitted('resultados')).toHaveLength(1);
    expect(w.emitted('ajustar')).toHaveLength(1);
  });

  it('no celular os atalhos moram no "⋯", que abre para baixo', async () => {
    const w = abrir({ podeAjustar: true });
    const gatilho = w.get(
      `${daCarteira('mais-da-carteira')} [aria-haspopup="menu"]`
    );

    expect(gatilho.attributes('aria-label')).toBe('Mais opções da carteira');
    expect(w.get(daCarteira('mais-da-carteira')).classes()).toContain(
      'sm:hidden'
    );
    expect(w.get('[role="menu"]').classes()).toContain('top-full');

    await gatilho.trigger('click');
    await w.get('[role="menuitem"][data-acao="ajustar"]').trigger('click');

    expect(w.emitted('ajustar')).toHaveLength(1);
    expect(w.emitted('resultados')).toBeUndefined();
  });
});

describe('quantos dias antes', () => {
  const abrir = (modelValue = 60) =>
    montar(CampoDeDias, { modelValue, id: 'dias-antes' });
  const mudancas = w => w.emitted('update:modelValue');

  it('mostra o número e tem um botão de cada lado, com nome', () => {
    const w = abrir();

    expect(w.get('#dias-antes').element.value).toBe('60');
    expect(w.get('[data-dias="menos"]').attributes('aria-label')).toBe(
      'Um dia a menos'
    );
    expect(w.get('[data-dias="mais"]').attributes('aria-label')).toBe(
      'Um dia a mais'
    );
    expect(w.get('[data-dias="menos"]').classes()).toContain('size-11');
  });

  it('os botões andam de um em um e não passam de 1', async () => {
    const w = abrir(1);

    await w.get('[data-dias="menos"]').trigger('click');
    await w.get('[data-dias="mais"]').trigger('click');

    expect(mudancas(w)).toEqual([[1], [2]]);
  });

  it('o que a pessoa escreve vira número, e o que não é número vira nada', async () => {
    const w = abrir();
    const campo = w.get('#dias-antes');

    await campo.setValue('45');
    await campo.setValue('quarenta');
    await campo.setValue('');

    expect(mudancas(w)).toEqual([[45], [null], [null]]);
  });

  it('acompanha o número que muda por fora', async () => {
    const w = abrir();

    await w.setProps({ modelValue: 59 });

    expect(w.get('#dias-antes').element.value).toBe('59');
  });

  it('com o número faltando, o campo fica marcado e aponta para o aviso', () => {
    const w = montar(CampoDeDias, {
      modelValue: null,
      id: 'dias-antes',
      invalido: true,
      descritoPor: 'aviso',
    });
    const campo = w.get('#dias-antes');

    expect(campo.element.value).toBe('');
    expect(campo.attributes('aria-invalid')).toBe('true');
    expect(campo.attributes('aria-describedby')).toBe('aviso');
  });
});

describe('onde ficam as renovações', () => {
  const FUNIS = [
    {
      id: 1,
      nome: 'Renovação',
      etapas: [
        { id: 11, nome: 'A vencer' },
        { id: 12, nome: 'Em conversa' },
      ],
    },
    { id: 2, nome: 'Vendas', etapas: [{ id: 21, nome: 'Novo contato' }] },
  ];
  const SEM_ESCOLHA = {
    funilId: null,
    etapaId: null,
    dias: 60,
    mensagens: 'mandar',
  };
  const abrir = (modelValue = SEM_ESCOLHA, resto = {}) =>
    montar(OndeFicamAsRenovacoes, { modelValue, funis: FUNIS, ...resto });
  const escolhas = w => w.findAllComponents(ChoiceSelect);
  const rotulos = escolha => escolha.props('options').map(o => o.label);

  it('conta sem funil: diz o que fazer e leva ao CRM, sem lista vazia', async () => {
    const w = abrir(SEM_ESCOLHA, { funis: [] });

    expect(w.get(daCarteira('sem-funil')).text()).toContain(
      'Sua conta ainda não tem funil. Crie um funil no CRM e volte aqui para escolher.'
    );
    expect(escolhas(w)).toHaveLength(0);
    expect(w.find('button[disabled]').exists()).toBe(false);

    await w.get(daCarteira('abrir-crm')).trigger('click');

    expect(w.emitted('abrirCrm')).toHaveLength(1);
  });

  it('sem funil escolhido, só o funil é perguntado', () => {
    const w = abrir();

    expect(escolhas(w)).toHaveLength(1);
    expect(rotulos(escolhas(w)[0])).toEqual(['Renovação', 'Vendas']);
    expect(w.find(daCarteira('escolher-etapa')).exists()).toBe(false);
  });

  it('escolher o funil já escolhe a primeira etapa dele', () => {
    const w = abrir();

    escolhas(w)[0].vm.$emit('update:modelValue', 2);

    expect(w.emitted('update:modelValue')).toEqual([
      [{ ...SEM_ESCOLHA, funilId: 2, etapaId: 21 }],
    ]);
  });

  it('com o funil escolhido, as etapas são as dele, e dá para trocar', () => {
    const escolhido = { ...SEM_ESCOLHA, funilId: 1, etapaId: 11 };
    const w = abrir(escolhido);
    const [, etapa] = escolhas(w);

    expect(rotulos(etapa)).toEqual(['A vencer', 'Em conversa']);

    etapa.vm.$emit('update:modelValue', 12);

    expect(w.emitted('update:modelValue')).toEqual([
      [{ ...escolhido, etapaId: 12 }],
    ]);
  });

  it('o que falta fica marcado e aponta para o aviso de quem usa', () => {
    const w = abrir(SEM_ESCOLHA, { falta: FALTAS.FUNIL, idDoAviso: 'aviso' });
    const [funil] = escolhas(w);

    expect(funil.props('invalid')).toBe(true);
    expect(funil.props('describedBy')).toBe('aviso');
  });
});

describe('uma barra dos resultados', () => {
  const abrir = (parte, total) =>
    montar(BarraDeResultado, {
      nome: 'Achou caro',
      valor: `${parte}`,
      parte,
      total,
    });
  const barra = w => w.get('[data-largura]');

  it('escreve o nome e o número, e a barra é só desenho', () => {
    const w = abrir(7, 9);

    expect(w.text()).toContain('Achou caro');
    expect(w.text()).toContain('7');
    expect(barra(w).attributes('data-largura')).toBe('78');
    expect(barra(w).classes()).toContain('w-[75%]');
    expect(barra(w).element.parentElement.getAttribute('aria-hidden')).toBe(
      'true'
    );
  });

  it('enche de vez só quando é tudo, e sem total fica vazia', () => {
    expect(barra(abrir(4, 4)).classes()).toContain('w-full');
    montada.unmount();
    expect(barra(abrir(0, 0)).classes()).toContain('w-0');
  });
});

describe('o histórico com a renovação e o "Exportar"', () => {
  const QUANDO = new Date(2026, 10, 10, 9, 30).getTime() / 1000;
  const AGORA = new Date(2026, 10, 12, 10).getTime();
  const passo = (tipo, resto = {}) => ({
    tipo,
    quando: QUANDO,
    quem: null,
    valores: {},
    mudancas: null,
    ...resto,
  });
  const ITENS = [
    passo('nao_renovou', {
      quem: { nome: 'Bruna Teixeirão' },
      valores: { motivo: 'achou_caro' },
    }),
    passo('card_nasceu'),
  ];
  const abrir = (props = {}) =>
    montar(HistoriaDoSeguro, { itens: ITENS, agora: AGORA, ...props });
  const frases = w =>
    w.findAll(daCarteira('item-da-historia')).map(item => item.text());

  it('conta os passos da renovação com o motivo por extenso', () => {
    const [naoRenovou, comecou] = frases(abrir());

    expect(naoRenovou).toContain('Não renovou: achou caro.');
    expect(naoRenovou).toContain('Bruna Teixeirão');
    expect(comecou).toContain('A renovação começou.');
  });

  it('escreve o motivo escrito e o número da apólice anterior', () => {
    const w = abrir({
      itens: [
        passo('nao_renovou_outro', { valores: { texto: 'Mudou de país' } }),
        passo('apolice_nova', { valores: { anterior: 'AT-000451' } }),
        passo('renovou'),
      ],
    });
    const [outro, nova, renovou] = frases(w);

    expect(outro).toContain('Não renovou. Motivo: Mudou de país');
    expect(nova).toContain(
      'Apólice nova guardada. A anterior era a nº AT-000451.'
    );
    expect(renovou).toContain('Renovou.');
  });

  it('passo que chega sem o detalhe usa a frase curta', () => {
    const [semMotivo] = frases(abrir({ itens: [passo('nao_renovou')] }));

    expect(semMotivo).toContain('Não renovou.');
    expect(semMotivo).not.toContain('{');
    expect(semMotivo).not.toContain('Não renovou:');
  });

  it('"Exportar" só aparece para quem pode exportar, e com passo para exportar', () => {
    const exportar = w => w.find(daCarteira('exportar-historico'));

    expect(exportar(abrir()).exists()).toBe(false);
    montada.unmount();
    expect(exportar(abrir({ podeExportar: true, itens: [] })).exists()).toBe(
      false
    );
    montada.unmount();
    expect(exportar(abrir({ podeExportar: true })).text()).toBe('Exportar');
  });

  it('"Exportar" baixa o que está na tela, num arquivo de nome neutro', async () => {
    const w = abrir({ podeExportar: true });

    await w.get(daCarteira('exportar-historico')).trigger('click');

    expect(baixarArquivo).toHaveBeenCalledTimes(1);
    const [nome, conteudo] = baixarArquivo.mock.calls[0];
    const [cabecalho, primeira, segunda] = conteudo.split('\r\n');
    expect(nome).toBe('historico-do-seguro.csv');
    expect(cabecalho).toContain('"Data";"Hora";"O que aconteceu";"Quem fez"');
    expect(primeira).toContain('"Não renovou: achou caro."');
    expect(primeira).toContain('"Bruna Teixeirão"');
    expect(segunda).toContain('"A renovação começou.";""');
    expect(conteudo.split('\r\n')).toHaveLength(3);
    expect(w.emitted('exportado')).toHaveLength(1);
  });
});
