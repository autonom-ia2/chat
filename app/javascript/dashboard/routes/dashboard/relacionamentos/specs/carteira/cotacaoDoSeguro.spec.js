import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { ref } from 'vue';
import CotacaoDoSeguro from '../../components/carteira/CotacaoDoSeguro.vue';
import {
  camposQueFaltam,
  nomeDaCaixaNaFrase,
  podeEnviarProposta,
  situacaoDaCotacao,
  variacaoDaCotacao,
} from '../../carteira/cotacaoDaRenovacao';
import { fraseDoPasso } from '../../carteira/passoDoHistorico';
import { useSeguroAberto } from '../../carteira/useSeguroAberto';
import { daCarteira, recusa } from './apoio';

// A cotação da renovação no seguro (#2901, E8), com o texto de verdade em
// pt_BR: a frase de cada etapa e motivo (nunca o código do servidor), o que
// faltou em palavras, o preço e a variação contra o ano passado, e "Enviar
// proposta" só com a proposta pronta para quem pode enviar. Todos os dados são
// inventados.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));

withFullI18n('pt_BR');

const SEM_NADA = {
  resposta: null,
  motivo: null,
  faltam: [],
  premioCentavos: null,
  seguradora: null,
  variacaoPercentual: null,
  enviadaEm: null,
  podeEnviar: false,
};
const cotacaoCom = mudancas => ({ ...SEM_NADA, ...mudancas });
const seguroCom = (cotacao, resto = {}) => ({
  id: 7,
  canceladoEm: null,
  renovacao: { cardId: 88, funil: 'Renovação', etapa: 'A vencer' },
  cotacao,
  ...resto,
});

let montada;
const montar = (cotacao, props = {}) => {
  montada = mount(CotacaoDoSeguro, {
    attachTo: document.body,
    props: { seguro: seguroCom(cotacao), ...props },
  });
  return montada;
};
const situacao = w => w.get(daCarteira('situacao-da-cotacao')).text();
afterEach(() => {
  montada?.unmount();
  montada = null;
});

describe('a linha de situação, por etapa e motivo', () => {
  it.each([
    ['cotacao_pedida', {}, 'Perguntamos ao cliente se algo mudou no seguro.'],
    [
      'respondeu_algo_mudou',
      { resposta: 'nada_mudou' },
      'O cliente disse que nada mudou. A cotação vai começar.',
    ],
    [
      'respondeu_algo_mudou',
      { resposta: 'mudou' },
      'O cliente disse que algo mudou. A cotação parou para alguém ver o que mudou.',
    ],
    [
      'cliente_respondeu',
      {},
      'O cliente contou o que mudou. Veja na conversa.',
    ],
    ['proposta_pedida', {}, 'Estamos cotando a renovação nas seguradoras.'],
    [
      'proposta_nao_saiu',
      { motivo: 'sem_preco' },
      'Nenhuma seguradora deu preço para esta renovação.',
    ],
    [
      'proposta_nao_saiu',
      { motivo: 'sem_conexao' },
      'Não deu para cotar: a conexão com o portal de cotação não está pronta.',
    ],
    [
      'proposta_nao_saiu',
      { motivo: 'motivo_de_amanha' },
      'Não deu para cotar esta renovação.',
    ],
    ['etapa_de_amanha', {}, 'A cotação da renovação está em andamento.'],
  ])('%s %j', (etapa, mudancas, frase) => {
    const w = montar(cotacaoCom({ etapa, ...mudancas }));

    expect(situacao(w)).toBe(frase);
    expect(w.text()).not.toContain('COTACAO');
    expect(w.text()).not.toContain(etapa);
  });

  it('o que faltou vira a lista de nomes em português', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_nao_saiu',
        motivo: 'faltou_dado',
        faltam: ['insured.birthDate', 'address.zipCode', 'vehicle.plate'],
      })
    );

    expect(situacao(w)).toBe(
      'Não deu para cotar: falta nascimento do segurado, CEP e placa do veículo.'
    );
    expect(w.text()).not.toContain('insured');
    expect(w.get(daCarteira('equipe-avisada')).text()).toBe(
      'A equipe foi avisada no card da renovação.'
    );
  });

  // #3043 (E8.1) — faltou algo que a apólice traz: a tela ensina o caminho.
  it('faltou dado da apólice: ensina a anexar o PDF ou corrigir à mão', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_nao_saiu',
        motivo: 'faltou_dado',
        faltam: ['insured.document', 'segurado.cep'],
      })
    );

    expect(situacao(w)).toBe(
      'Não deu para cotar: falta CPF ou CNPJ do segurado e CEP.'
    );
    expect(w.get(daCarteira('como-completar')).text()).toBe(
      'Anexe o PDF da apólice ou corrija o seguro à mão.'
    );
  });

  it('faltou só o que a apólice não traz: sem a frase do caminho', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_nao_saiu',
        motivo: 'faltou_dado',
        faltam: ['insured.document'],
      })
    );

    expect(w.find(daCarteira('como-completar')).exists()).toBe(false);
  });

  it('o campo que a tela não sabe nomear vira "outros dados do seguro"', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_nao_saiu',
        motivo: 'faltou_dado',
        faltam: ['quotation.bonusClass', 'campo.deAmanha'],
      })
    );

    expect(situacao(w)).toBe(
      'Não deu para cotar: falta classe de bônus e outros dados do seguro.'
    );
    expect(w.text()).not.toContain('deAmanha');
  });

  it('a pergunta que não saiu diz por quê, sem o código', () => {
    const w = montar(
      cotacaoCom({ etapa: 'algo_mudou_nao_saiu', motivo: 'sem_telefone' })
    );

    expect(situacao(w)).toBe('A pergunta ao cliente não saiu.');
    expect(w.get(daCarteira('por-que-nao-saiu')).text()).toBe(
      'O cliente não tem telefone na ficha.'
    );
    expect(w.text()).not.toContain('sem_telefone');
  });

  it('a conferência que caiu não diz que a equipe foi avisada: ela tenta de novo', () => {
    const w = montar(
      cotacaoCom({ etapa: 'proposta_nao_saiu', motivo: 'conferencia_caiu' })
    );

    expect(situacao(w)).toContain('Tentamos de novo sozinhos');
    expect(w.find(daCarteira('equipe-avisada')).exists()).toBe(false);
  });

  it('a proposta pronta diz o preço e a seguradora', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_pronta',
        premioCentavos: 276000,
        seguradora: 'Seguradora Atlântica',
        podeEnviar: true,
      })
    );

    expect(situacao(w)).toContain('Proposta pronta:');
    expect(situacao(w)).toContain('2.760,00');
    expect(situacao(w)).toContain('Seguradora Atlântica');
    expect(w.find(daCarteira('proposta-da-cotacao')).exists()).toBe(false);
  });

  it('a proposta que saiu sozinha diz quando, e o preço continua embaixo', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_enviada_sozinha',
        premioCentavos: 150000,
        seguradora: 'Seguradora Boreal',
        enviadaEm: 1795000000,
      })
    );

    expect(situacao(w).startsWith('A proposta saiu sozinha em ')).toBe(true);
    expect(situacao(w).endsWith('.')).toBe(true);
    expect(w.get(daCarteira('proposta-da-cotacao')).text()).toContain(
      'Seguradora Boreal'
    );
  });
});

describe('a variação contra o ano passado', () => {
  const pronta = variacaoPercentual =>
    cotacaoCom({
      etapa: 'proposta_pronta',
      premioCentavos: 100000,
      seguradora: 'Seguradora Atlântica',
      variacaoPercentual,
    });

  it('positiva: subiu', () => {
    const w = montar(pronta(12));
    const linha = w.get(daCarteira('variacao-da-cotacao')).text();

    expect(linha).toContain('Subiu 12');
    expect(linha).toContain('em relação ao ano passado.');
  });

  it('negativa: caiu, sem o sinal de menos', () => {
    const w = montar(pronta(-5.5));
    const linha = w.get(daCarteira('variacao-da-cotacao')).text();

    expect(linha).toContain('Caiu 5,5');
    expect(linha).not.toContain('-');
  });

  it('ausente (sem o valor do ano passado): a linha não aparece', () => {
    const w = montar(pronta(null));

    expect(w.find(daCarteira('variacao-da-cotacao')).exists()).toBe(false);
  });

  it('as regras puras', () => {
    expect(variacaoDaCotacao({ variacaoPercentual: 0 })).toEqual({
      id: 'IGUAL',
      percentual: 0,
    });
    expect(variacaoDaCotacao({ variacaoPercentual: null })).toBeNull();
    expect(variacaoDaCotacao(null)).toBeNull();
  });
});

describe('"Enviar proposta"', () => {
  const pronta = cotacaoCom({
    etapa: 'proposta_pronta',
    premioCentavos: 100000,
    seguradora: 'Seguradora Atlântica',
    podeEnviar: true,
  });

  // #3057 (2ª rodada) — o botão é o azul do rodapé da gaveta
  // (gavetaDoAcabamento.spec.js); aqui fica só a linha de que nada sai antes.
  it('não tem botão: com a proposta para enviar, só a linha de que nada sai antes do toque', () => {
    const sem = montar(pronta, { podeEnviar: false });
    expect(sem.find(daCarteira('enviar-apoio')).exists()).toBe(false);
    sem.unmount();

    const w = montar(pronta, { podeEnviar: true });
    expect(w.find(daCarteira('enviar-proposta')).exists()).toBe(false);
    expect(w.findAll('button')).toHaveLength(0);
    expect(w.get(daCarteira('enviar-apoio')).text()).toBe(
      'A proposta só vai ao cliente quando você tocar em Enviar proposta.'
    );
  });

  it('incerta: pede para conferir na conversa', () => {
    const incerta = cotacaoCom({
      etapa: 'proposta_enviada',
      premioCentavos: 100000,
      podeEnviar: true,
      incerta: true,
    });

    const w = montar(incerta, { podeEnviar: true });

    expect(situacao(w)).toBe(
      'Não sabemos se a proposta chegou. Confira na conversa; se não chegou, envie de novo.'
    );
    expect(situacaoDaCotacao(incerta)).toEqual({ id: 'INCERTA' });
  });

  it('pode enviar: proposta pronta, quem altera a pessoa e vê o card, seguro não cancelado', () => {
    const seguro = seguroCom(pronta);
    const jaEnviada = seguroCom({ ...pronta, podeEnviar: false });
    const semVerOCard = seguroCom(pronta, { renovacao: { desfecho: null } });
    const cancelado = seguroCom(pronta, { canceladoEm: 1790000000 });

    expect(podeEnviarProposta(seguro, true)).toBe(true);
    expect(podeEnviarProposta(seguro, false)).toBe(false);
    expect(podeEnviarProposta(jaEnviada, true)).toBe(false);
    expect(podeEnviarProposta(semVerOCard, true)).toBe(false);
    expect(podeEnviarProposta(cancelado, true)).toBe(false);
    expect(podeEnviarProposta(seguroCom(null), true)).toBe(false);
  });

  it('depois do envio, o seguro novo entra sem recarregar; a recusa fica com o código', async () => {
    const enviado = seguroCom(
      cotacaoCom({
        etapa: 'proposta_enviada',
        premioCentavos: 100000,
        enviadaEm: 1795000000,
      })
    );
    const fonte = {
      seguro: vi.fn(async () => seguroCom(pronta)),
      historia: vi.fn(async () => []),
      enviarProposta: vi.fn(async () => enviado),
    };
    const aberto = useSeguroAberto(fonte, ref(7));
    await aberto.carregar();
    await flushPromises();

    expect(await aberto.enviarProposta()).toBe(true);
    expect(fonte.enviarProposta).toHaveBeenCalledWith(7, undefined);
    expect(fonte.seguro).toHaveBeenCalledTimes(1);
    expect(aberto.seguro.value.cotacao.etapa).toBe('proposta_enviada');

    fonte.enviarProposta.mockRejectedValue(recusa('sem_modelo'));
    expect(await aberto.enviarProposta()).toBe(false);
    expect(aberto.recusa.value).toBe('sem_modelo');
  });
});

describe('as puras', () => {
  it('sem cotação, nada', () => {
    expect(situacaoDaCotacao(null)).toBeNull();
    expect(situacaoDaCotacao({ etapa: null })).toBeNull();
  });

  it('o mesmo campo não se repete, e o que não tem nome vira `outros`', () => {
    expect(camposQueFaltam(['insured.name', 'insured.name', 'x.y'])).toEqual({
      campos: ['INSURED_NAME'],
      outros: true,
      daApolice: false,
    });
  });

  // #3043 (E8.1) — o que a apólice traz escrito.
  it('daApolice diz quando faltou algo que a apólice traz', () => {
    expect(camposQueFaltam(['segurado.cep', 'renovacao.bonus'])).toEqual({
      campos: ['SEGURADO_CEP', 'RENOVACAO_BONUS'],
      outros: false,
      daApolice: true,
    });
    expect(camposQueFaltam(['insured.document']).daApolice).toBe(false);
  });

  it('dois campos com o mesmo nome em português aparecem uma vez só', () => {
    const w = montar(
      cotacaoCom({
        etapa: 'proposta_nao_saiu',
        motivo: 'faltou_dado',
        faltam: ['insured.document', 'segurado.cpfCnpj'],
      })
    );

    expect(situacao(w)).toBe(
      'Não deu para cotar: falta CPF ou CNPJ do segurado.'
    );
  });

  it('os passos da cotação têm frase no histórico', () => {
    [
      'cotacao_pedida',
      'algo_mudou_nao_saiu',
      'respondeu_algo_mudou',
      'cliente_respondeu',
      'proposta_pedida',
      'proposta_nao_saiu',
      'proposta_pronta',
      'proposta_enviada',
      'proposta_enviada_sozinha',
    ].forEach(tipo => {
      expect(fraseDoPasso({ tipo }).chave).toBe(`TIPOS.${tipo.toUpperCase()}`);
    });
  });
});

describe('o nome da caixa na frase "pelo WhatsApp {caixa}"', () => {
  it('tira o "WhatsApp" do começo para a frase não repetir', () => {
    expect(nomeDaCaixaNaFrase('WhatsApp Renovações')).toBe('Renovações');
    expect(nomeDaCaixaNaFrase('whatsapp da loja')).toBe('da loja');
    expect(nomeDaCaixaNaFrase('WhatsApp')).toBe('');
  });

  it('deixa como está o nome que não começa com "WhatsApp"', () => {
    expect(nomeDaCaixaNaFrase('Renovações')).toBe('Renovações');
    expect(nomeDaCaixaNaFrase('Loja no WhatsApp')).toBe('Loja no WhatsApp');
    expect(nomeDaCaixaNaFrase()).toBe('');
    expect(nomeDaCaixaNaFrase(null)).toBe('');
    expect(nomeDaCaixaNaFrase('Whatsappzinho Vendas')).toBe(
      'Whatsappzinho Vendas'
    );
    expect(nomeDaCaixaNaFrase('WhatsApp-Vendas')).toBe('WhatsApp-Vendas');
  });
});
