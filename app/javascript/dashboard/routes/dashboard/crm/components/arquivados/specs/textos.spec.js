import { motivoDoErro, motivoDoPulado } from '../motivoDoErro';
import {
  avisoDoRestaurado,
  avisoDosDoisAbertos,
  nomeDoCliente,
  quemArquivou,
  valorDaLinha,
} from '../textosDoArquivado';

const t = (chave, params) =>
  params ? `${chave}${JSON.stringify(params)}` : chave;
const formato = {
  diaCurto: () => '14 de outubro',
  dinheiro: centavos => `R$ ${centavos / 100}`,
};

describe('motivoDoErro', () => {
  it('sem resposta é a internet', () => {
    expect(motivoDoErro(t, new Error('Network Error'))).toBe(
      'CRM_ARQUIVADOS.ERROS.SEM_CONEXAO'
    );
  });
  it('código conhecido vira frase da tela', () => {
    const error = {
      response: {
        status: 422,
        data: { error: 'crm.card_restore_pipeline_archived' },
      },
    };
    expect(motivoDoErro(t, error)).toBe('CRM_ARQUIVADOS.ERROS.FUNIL_ARQUIVADO');
  });
  it('marcar resultado num card arquivado tem frase própria', () => {
    const error = {
      response: { status: 422, data: { error: 'crm.card_close_archived' } },
    };
    expect(motivoDoErro(t, error)).toBe(
      'CRM_ARQUIVADOS.ERROS.FECHAR_ARQUIVADO'
    );
  });
  it('código desconhecido não mostra o texto cru do servidor', () => {
    const error = {
      response: { status: 500, data: { error: 'boom', exception: 'X' } },
    };
    expect(motivoDoErro(t, error)).toBe('CRM_ARQUIVADOS.ERROS.RECUSOU');
  });
  it('401 é falta de permissão', () => {
    expect(motivoDoErro(t, { response: { status: 401, data: {} } })).toBe(
      'CRM_ARQUIVADOS.ERROS.SEM_PERMISSAO'
    );
  });
  it('pulado por conflito tem frase própria', () => {
    expect(motivoDoPulado(t, 'crm.card_restore_conflict')).toBe(
      'CRM_ARQUIVADOS.ERROS.CONFLITO'
    );
  });
});

describe('textos do arquivado', () => {
  it('a IA arquivou com motivo', () => {
    const linha = {
      archived_at: '2026-10-14T10:00:00Z',
      archived_by: { type: 'ai' },
      archive_reason: 'fora_do_negocio',
    };
    expect(quemArquivou(t, formato, linha)).toBe(
      'CRM_ARQUIVADOS.LINHA.PELA_IA_MOTIVO{"dia":"14 de outubro","motivo":"CRM_ARQUIVADOS.MOTIVO_IA.FORA_DO_NEGOCIO"}'
    );
  });
  it('uma pessoa arquivou', () => {
    const linha = {
      archived_at: '2026-10-14T10:00:00Z',
      archived_by: { type: 'user', name: 'Ana' },
    };
    expect(quemArquivou(t, formato, linha)).toContain('LINHA.POR');
  });
  it('valor oculto não aparece; zero diz "Sem valor"', () => {
    expect(valorDaLinha(t, formato, { value_hidden: true })).toBe('');
    expect(valorDaLinha(t, formato, { value_cents: 0 })).toBe(
      'CRM_ARQUIVADOS.SEM_VALOR'
    );
  });
  it('card ganho volta para a Lista, com o nome da aba', () => {
    const aviso = avisoDoRestaurado(t, {
      nome: 'Card X',
      card: { status: 'won', stage: { name: 'Proposta' } },
      funil: { counts_as_sale: true },
      retornosParados: 0,
    });
    expect(aviso.lista).toBe(true);
    expect(aviso.texto).toContain('RESTAURADO.LISTA');
  });
  it('card aberto volta para a etapa e avisa dos retornos parados', () => {
    const aviso = avisoDoRestaurado(t, {
      nome: 'Card X',
      card: { status: 'open', stage: { name: 'Proposta' } },
      funil: null,
      retornosParados: 2,
    });
    expect(aviso.lista).toBe(false);
    expect(aviso.retornos).toBe(true);
    expect(aviso.texto).toContain('"etapa":"Proposta"');
    expect(aviso.texto).toContain('RESTAURADO.RETORNOS');
  });
});

describe('nomeDoCliente', () => {
  it('usa o nome do cliente, não o título do card (decisão 6)', () => {
    expect(
      nomeDoCliente({ title: 'Plano de Ana', contact: { name: 'Ana Souza' } })
    ).toBe('Ana Souza');
  });

  it('sem contato, usa o título do card', () => {
    expect(nomeDoCliente({ title: 'Plano de Ana', contact: null })).toBe(
      'Plano de Ana'
    );
  });
});

describe('avisoDosDoisAbertos (#2145)', () => {
  const tp = (chave, params, n) =>
    `${chave}${JSON.stringify(params)}${n ?? ''}`;
  const juntar = nomes => nomes.join(', ');

  it('sem cliente com dois abertos, nada', () => {
    expect(avisoDosDoisAbertos(tp, juntar, {}, 'Vendas')).toBeNull();
    expect(
      avisoDosDoisAbertos(
        tp,
        juntar,
        { clients_with_two_open: { count: 0, items: [] } },
        'Vendas'
      )
    ).toBeNull();
  });

  it('lista até 3 nomes e conta o resto', () => {
    const resposta = {
      clients_with_two_open: {
        count: 5,
        items: ['Ana', 'Bia', 'Caio', 'Duda'].map((name, i) => ({
          name,
          card_id: i,
        })),
      },
    };
    expect(avisoDosDoisAbertos(tp, juntar, resposta, 'Vendas')).toBe(
      'CRM_ARQUIVADOS.FUNIL.MAIS_DE_UM_ABERTO_QUEM{"count":5,"funil":"Vendas","nomes":"Ana, Bia, Caio, CRM_ARQUIVADOS.FUNIL.MAIS_N{\\"count\\":2}2"}5'
    );
  });

  it('nenhum nome visível para quem arquivou: só a contagem, sem lista vazia', () => {
    const resposta = { clients_with_two_open: { count: 3, items: [] } };
    expect(avisoDosDoisAbertos(tp, juntar, resposta, 'Vendas')).toBe(
      'CRM_ARQUIVADOS.FUNIL.MAIS_DE_UM_ABERTO{"count":3,"funil":"Vendas"}3'
    );
  });

  it('sem nomes, só a contagem', () => {
    const resposta = {
      clients_with_two_open: { count: 1, items: [{ name: null, card_id: 1 }] },
    };
    expect(avisoDosDoisAbertos(tp, juntar, resposta, 'Vendas')).toBe(
      'CRM_ARQUIVADOS.FUNIL.MAIS_DE_UM_ABERTO{"count":1,"funil":"Vendas"}1'
    );
  });
});
