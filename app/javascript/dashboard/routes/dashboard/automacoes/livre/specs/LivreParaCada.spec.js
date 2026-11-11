import { mount } from '@vue/test-utils';
import LivreParaCada from '../components/LivreParaCada.vue';
import { MAXIMO_DE_ITENS, fraseDoParaCada, paraCadaPronto } from '../paraCada';
import { fraseDoPasso } from '../frases';
import { comTextosDaIa, novoPasso } from '../catalogo';
import catalogoGerado from '../../../../../../../../lib/operator_guide/automacao-passos.json';

// #2414 G24 (#2771) — o passo "para cada item" no editor: a lista que a IA
// procura, os campos de cada item (o "nome" sempre), a etapa e o máximo. O
// "Salvar" só libera com tudo isso, e os passos seguintes ganham dois dados.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const t = (chave, valores) =>
  valores ? `${chave} ${JSON.stringify(valores)}` : chave;

const PRONTO = {
  id: 'lista',
  tipo: 'para_cada',
  le: ['mensagens_recentes'],
  descricao: 'Cada funcionário novo da lista',
  campos: [
    { chave: 'nome', descricao: 'Nome completo' },
    { chave: 'telefone', descricao: 'WhatsApp' },
  ],
  etapa_id: 34,
  maximo: 20,
};

describe('paraCada.js', () => {
  it('fica pronto com a descrição, o nome, a etapa e o máximo de 1 a 50', () => {
    expect(paraCadaPronto(PRONTO)).toBe(true);
    expect(paraCadaPronto({ ...PRONTO, descricao: '  ' })).toBe(false);
    expect(paraCadaPronto({ ...PRONTO, etapa_id: null })).toBe(false);
    expect(paraCadaPronto({ ...PRONTO, maximo: 0 })).toBe(false);
    expect(paraCadaPronto({ ...PRONTO, maximo: MAXIMO_DE_ITENS + 1 })).toBe(
      false
    );
    expect(paraCadaPronto({ ...PRONTO, campos: [PRONTO.campos[1]] })).toBe(
      false
    );
    expect(
      paraCadaPronto({
        ...PRONTO,
        campos: [...PRONTO.campos, { chave: 'idade', descricao: '' }],
      })
    ).toBe(false);
  });

  it('o passo novo nasce com o campo nome e a etapa a escolher', () => {
    expect(novoPasso({ tipo: 'para_cada' }, 'p9', t)).toEqual({
      id: 'p9',
      tipo: 'para_cada',
      le: ['mensagens_recentes'],
      descricao: '',
      campos: [{ chave: 'nome', descricao: '' }],
      etapa_id: null,
      maximo: 20,
    });
  });

  it('a frase da linha diz o que é cada item', () => {
    expect(fraseDoParaCada(PRONTO, t)).toBe(
      'AUTOMACAO_LIVRE.PARA_CADA.FRASE {"item":"Cada funcionário novo da lista"}'
    );
    expect(fraseDoParaCada({ ...PRONTO, descricao: '' }, t)).toBe(
      'AUTOMACAO_LIVRE.PARA_CADA.FRASE_SEM_ITEM'
    );
    expect(fraseDoPasso(PRONTO, catalogoGerado, t)).toBe(
      fraseDoParaCada(PRONTO, t)
    );
  });

  it('os passos seguintes ganham quantos itens e os nomes da lista', () => {
    const { valores } = comTextosDaIa({ valores: [] }, [PRONTO], t);

    expect(valores).toEqual([
      {
        caminho: 'ia.lista.quantos',
        chave: 'lista.quantos',
        rotulo: 'AUTOMACAO_LIVRE.PARA_CADA.VALOR_QUANTOS',
      },
      {
        caminho: 'ia.lista.nomes',
        chave: 'lista.nomes',
        rotulo: 'AUTOMACAO_LIVRE.PARA_CADA.VALOR_NOMES',
      },
    ]);
  });

  it('o catálogo gerado traz o passo no grupo IA, com a flag e a chave de funis', () => {
    const passo = catalogoGerado.passos.find(item => item.tipo === 'para_cada');

    expect(passo).toMatchObject({
      grupo: 'IA',
      requer: 'automacao_ia',
      funil: true,
    });
    expect(passo.campos.map(campo => campo.peca)).toEqual(
      Array(5).fill('para_cada')
    );
  });
});

describe('LivreParaCada', () => {
  const montar = modelValue =>
    mount(LivreParaCada, {
      props: {
        modelValue,
        etapas: [
          { label: 'Inclusões', options: [{ value: 34, label: 'A incluir' }] },
        ],
        opcoes: {},
        atributosDo: () => [],
      },
    });

  const ultimo = tela => tela.emitted('update:modelValue').at(-1)[0];

  it('o campo nome não muda de chave nem sai; os outros, sim', () => {
    const tela = montar(PRONTO);
    const itens = tela.findAll('[data-campo-extrair]');

    expect(itens[0].find('input').attributes('readonly')).toBeDefined();
    expect(itens[1].find('input').attributes('readonly')).toBeUndefined();
    expect(tela.find('[data-peca="campos_para_cada"]').exists()).toBe(true);
    expect(tela.text()).not.toContain('AUTOMACAO_LIVRE.IA.CAMPO.DESTINO');
  });

  it('mais um campo nasce sem o "onde gravar"', async () => {
    const tela = montar(PRONTO);

    await tela.find('[data-novo-campo]').trigger('click');

    expect(ultimo(tela).campos.at(-1)).toEqual({ chave: '', descricao: '' });
  });

  it('sem o telefone avisa e oferece pôr o campo', async () => {
    const tela = montar({ ...PRONTO, campos: [PRONTO.campos[0]] });

    expect(tela.find('[data-para-cada-sem-telefone]').exists()).toBe(true);
    await tela.find('[data-para-cada-por-telefone]').trigger('click');

    expect(ultimo(tela).campos.at(-1)).toEqual({
      chave: 'telefone',
      descricao: '',
    });
  });

  it('com o telefone, não avisa', () => {
    expect(montar(PRONTO).find('[data-para-cada-sem-telefone]').exists()).toBe(
      false
    );
  });

  it('o máximo vira número e, fora de 1 a 50, diz o porquê', () => {
    const tela = montar({ ...PRONTO, maximo: 51 });
    const maximo = tela.findComponent('[data-para-cada-maximo]');

    expect(maximo.props('messageType')).toBe('error');
    maximo.vm.$emit('update:modelValue', '12');
    expect(ultimo(tela).maximo).toBe(12);
    maximo.vm.$emit('update:modelValue', '');
    expect(ultimo(tela).maximo).toBeNull();
  });

  it('a etapa escolhida vai para o passo', () => {
    const tela = montar({ ...PRONTO, etapa_id: null });

    tela
      .findComponent({ name: 'LivreEtapa' })
      .vm.$emit('update:modelValue', 34);

    expect(ultimo(tela).etapa_id).toBe(34);
  });

  it('nenhum <select> nativo', () => {
    expect(montar(PRONTO).find('select').exists()).toBe(false);
  });
});
