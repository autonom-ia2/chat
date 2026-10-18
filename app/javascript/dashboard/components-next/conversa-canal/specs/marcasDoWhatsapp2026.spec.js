import {
  ENCAMINHADA,
  apagadaPeloCliente,
  audioOuvido,
  encaminhamento,
  foiEditada,
  ocultaNaPele,
  tipoNaoSuportado,
  versoesAnteriores,
} from '../marcasDaMensagem';
import { contarSoEmojis, ehSoEmoji } from '../soEmoji';
import { ehPedido, resumoDoPedido, valorEmDinheiro } from '../pedido/pedido';
import { apurarEnquete, ehEnquete, totalDeEleitores } from '../enquete/enquete';
import { ligacaoPerdida, resumoDaLigacao } from '../ligacao/ligacao';
import { contatosDoBalao, variosContatos } from '../midia/contatos';

describe('marcas da mensagem (#1702)', () => {
  it('apagada pelo cliente só com deleted_by_contact_at', () => {
    expect(
      apagadaPeloCliente({ deletedByContactAt: '2026-10-16T18:00Z' })
    ).toBe(true);
    expect(apagadaPeloCliente({ deleted: true })).toBe(false);
    expect(apagadaPeloCliente(undefined)).toBe(false);
  });

  it('editada e as versões anteriores válidas', () => {
    const atributos = {
      editedAt: '2026-10-16T18:05Z',
      editHistory: [
        { content: 'oi', editedAt: '2026-10-16T18:01Z' },
        null,
        { editedAt: 'x' },
      ],
    };
    expect(foiEditada(atributos)).toBe(true);
    expect(foiEditada({})).toBe(false);
    expect(versoesAnteriores(atributos)).toEqual([
      { content: 'oi', editedAt: '2026-10-16T18:01Z' },
    ]);
    expect(versoesAnteriores({ editHistory: 'x' })).toEqual([]);
  });

  it('encaminhada: com frequência vence a simples', () => {
    expect(encaminhamento({ forwarded: true })).toBe(ENCAMINHADA.SIMPLES);
    expect(encaminhamento({ forwarded: true, frequentlyForwarded: true })).toBe(
      ENCAMINHADA.FREQUENTE
    );
    expect(encaminhamento({})).toBeNull();
  });

  it('não suportada: só tipos conhecidos', () => {
    expect(
      tipoNaoSuportado({ isUnsupported: true, unsupportedKind: 'poll' })
    ).toBe('poll');
    expect(
      tipoNaoSuportado({ isUnsupported: true, unsupportedKind: 'outro' })
    ).toBeNull();
    expect(tipoNaoSuportado({ isUnsupported: true })).toBeNull();
    expect(tipoNaoSuportado({ unsupportedKind: 'gif' })).toBeNull();
  });

  it('oculta (c2y_hidden, reação do agente) e áudio ouvido (played_at)', () => {
    expect(
      ocultaNaPele({ messageType: 2, contentAttributes: { c2yHidden: true } })
    ).toBe(true);
    expect(
      ocultaNaPele({ messageType: 0, contentAttributes: { c2yHidden: true } })
    ).toBe(true);
    // Mensagem nossa nunca se esconde (mesma regra do #1709).
    expect(
      ocultaNaPele({ messageType: 1, contentAttributes: { c2yHidden: true } })
    ).toBe(false);
    expect(
      ocultaNaPele({
        contentAttributes: { autonomiaReaction: { emoji: '👍' } },
      })
    ).toBe(true);
    expect(ocultaNaPele({ contentAttributes: {} })).toBe(false);
    expect(audioOuvido({ playedAt: '2026-10-16T18:00Z' })).toBe(true);
    expect(audioOuvido({})).toBe(false);
  });
});

describe('só emoji (#1702)', () => {
  it.each([
    ['😀', 1],
    ['❤️', 1],
    ['👨‍👩‍👧', 1],
    ['👍🏽', 1],
    ['1️⃣', 1],
    ['🇧🇷🇧🇷', 2],
    [' 😀 😂 🙏 ', 3],
    ['⭐', 1],
    ['🇧🇷', 1],
    ['❤️‍🔥', 1],
    ['✔️', 1],
    ['✅', 1],
  ])('"%s" tem %i emoji(s)', (texto, quantos) => {
    expect(contarSoEmojis(texto)).toBe(quantos);
  });

  it.each([
    '😀😂🙏👍',
    'oi 😀',
    'ok',
    '',
    '   ',
    '©',
    '1',
    null,
    '✓',
    '✔',
    '✖',
    '✳',
    '❤',
    'a\uFE0F',
    '✓\uFE0F',
  ])('"%s" não é só emoji', texto => {
    expect(ehSoEmoji(texto)).toBe(false);
  });
});

describe('pedido (#1702)', () => {
  const pedido = {
    catalogId: 'c1',
    text: 'Entrega hoje?',
    items: [
      {
        productRetailerId: 'SKU1',
        quantity: 2,
        itemPrice: 10.5,
        currency: 'BRL',
      },
      {
        productRetailerId: 'SKU2',
        quantity: '1',
        itemPrice: '4',
        currency: 'BRL',
      },
      { quantity: 9 },
    ],
  };

  it('soma unidades e total; ignora item sem código', () => {
    const resumo = resumoDoPedido(pedido);
    expect(resumo.unidades).toBe(3);
    expect(resumo.total).toBe(25);
    expect(resumo.moeda).toBe('BRL');
    expect(resumo.itens.map(item => item.codigo)).toEqual(['SKU1', 'SKU2']);
  });

  it('moedas misturadas não somam', () => {
    const misturado = {
      items: [
        { productRetailerId: 'A', quantity: 1, itemPrice: 1, currency: 'BRL' },
        { productRetailerId: 'B', quantity: 1, itemPrice: 1, currency: 'USD' },
      ],
    };
    expect(resumoDoPedido(misturado).total).toBeNull();
  });

  it('reconhece o pedido e formata o dinheiro', () => {
    expect(ehPedido({ order: pedido })).toBe(true);
    expect(ehPedido({ order: { items: [] } })).toBe(false);
    expect(valorEmDinheiro(25, 'BRL', 'pt-BR')).toBe('R$ 25,00');
    expect(valorEmDinheiro(5, 'XX', 'pt-BR')).toBe('XX 5');
    expect(valorEmDinheiro(5, '', 'pt-BR')).toBe('5');
  });
});

describe('enquete (#1702)', () => {
  const atributos = {
    richMessage: {
      type: 'poll',
      name: 'Qual dia?',
      options: [
        { id: 1, title: 'Seg' },
        { id: 2, title: 'Ter' },
      ],
      multipleAnswers: false,
    },
    pollVotes: [
      { senderType: 'Contact', senderId: 7, options: ['Ter'], at: 'x' },
      { senderType: 'User', senderId: 1, options: [] },
      { senderType: 'User', senderId: 2, options: ['Ter'] },
      { options: 'quebrado' },
    ],
  };

  it('reconhece a enquete', () => {
    expect(ehEnquete(atributos)).toBe(true);
    expect(ehEnquete({ richMessage: { type: 'link_button' } })).toBe(false);
  });

  it('conta votos e fração por eleitor que votou', () => {
    const [seg, ter] = apurarEnquete(atributos);
    expect(totalDeEleitores(atributos)).toBe(2);
    expect(seg).toMatchObject({ titulo: 'Seg', votos: 0, fracao: 0 });
    expect(ter).toMatchObject({ titulo: 'Ter', votos: 2, fracao: 1 });
    expect(ter.quem.map(voto => voto.senderId)).toEqual([7, 2]);
  });
});

describe('ligação (#1702)', () => {
  it('lê o resumo e marca a perdida e a recusada', () => {
    const resumo = resumoDaLigacao({
      wahaCallSummary: {
        outcome: 'missed',
        isVideo: true,
        at: '2026-10-16T18:00:00Z',
      },
    });
    expect(resumo).toEqual({
      resultado: 'missed',
      video: true,
      quando: Date.UTC(2026, 9, 16, 18) / 1000,
    });
    expect(ligacaoPerdida(resumo)).toBe(true);
    expect(ligacaoPerdida({ resultado: 'rejected' })).toBe(true);
    expect(ligacaoPerdida({ resultado: 'accepted' })).toBe(false);
    expect(resumoDaLigacao({ wahaCallSummary: { outcome: 'x' } })).toBeNull();
    expect(resumoDaLigacao({})).toBeNull();
  });
});

describe('vários contatos (#1702)', () => {
  const contato = (id, firstName) => ({
    id,
    fileType: 'contact',
    fallbackTitle: `+55 11 9999-000${id}`,
    meta: { firstName },
  });

  it('só quando todos os anexos são contatos e há mais de um', () => {
    expect(variosContatos([contato(1, 'Ana'), contato(2, 'Bia')])).toBe(true);
    expect(variosContatos([contato(1, 'Ana')])).toBe(false);
    expect(
      variosContatos([contato(1, 'Ana'), { id: 3, fileType: 'image' }])
    ).toBe(false);
  });

  it('nome e telefone de cada um', () => {
    expect(contatosDoBalao([contato(1, 'Ana'), contato(2)])).toEqual([
      {
        chave: 1,
        nome: 'Ana',
        telefone: '+55 11 9999-0001',
        telefones: ['+55 11 9999-0001'],
      },
      {
        chave: 2,
        nome: '',
        telefone: '+55 11 9999-0002',
        telefones: ['+55 11 9999-0002'],
      },
    ]);
  });
});
