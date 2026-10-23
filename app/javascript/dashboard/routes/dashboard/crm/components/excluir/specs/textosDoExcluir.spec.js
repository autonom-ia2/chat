import {
  avisoDeReunioes,
  confere,
  ehVenda,
  linhaDoCardDoContato,
  motivoDoExcluir,
  somaDasVendas,
} from '../textosDoExcluir';

const t = (chave, params) =>
  params ? `${chave}${JSON.stringify(params)}` : chave;
const formato = { dinheiro: (centavos, moeda) => `${moeda} ${centavos / 100}` };
const venda = { id: 1, name: 'Vendas', counts_as_sale: true, status: 'active' };
const atender = { id: 2, name: 'Pós-venda', counts_as_sale: false };

describe('textosDoExcluir', () => {
  it('venda é o ganho, ou o arquivado que era ganho, num funil de venda', () => {
    expect(ehVenda({ status: 'won', pipeline: venda })).toBe(true);
    expect(
      ehVenda({ status: 'archived', desfecho: 'won', pipeline: venda })
    ).toBe(true);
    expect(ehVenda({ status: 'lost', pipeline: venda })).toBe(false);
    expect(ehVenda({ status: 'won', pipeline: atender })).toBe(false);
  });

  it('soma por moeda, sem converter uma na outra', () => {
    expect(
      somaDasVendas(formato, [
        { value_cents: 100000 },
        { value_cents: 50000, currency: 'BRL' },
        { value_cents: 2000, currency: 'USD' },
      ])
    ).toBe('BRL 1500 + USD 20');
  });

  it('reunião: Google e Microsoft avisam o cliente; WhatsApp ou só aqui, não', () => {
    expect(avisoDeReunioes(t, [])).toBe('');
    expect(
      avisoDeReunioes(t, [{ quando: 'sexta, 10h', provider: 'google' }])
    ).toContain('CRM_EXCLUIR.REUNIAO.CLIENTE_AVISADO');
    expect(
      avisoDeReunioes(t, [
        { quando: 'a', provider: 'internal' },
        { quando: 'b', provider: 'whatsapp' },
      ])
    ).toContain('CRM_EXCLUIR.REUNIAO.CLIENTE_SEM_AVISO');
    expect(
      avisoDeReunioes(t, [
        { quando: 'a', provider: 'google' },
        { quando: 'b', provider: 'internal' },
      ])
    ).toContain('CRM_EXCLUIR.REUNIAO.CLIENTE_DEPENDE');
    expect(avisoDeReunioes(t, [{ quando: 'a' }])).toContain(
      'CRM_EXCLUIR.REUNIAO.CLIENTE_DEPENDE'
    );
  });

  it('linha do card do contato: funil arquivado, valor só em funil de venda, e o desfecho do arquivado', () => {
    const linha = linhaDoCardDoContato(t, formato, {
      pipeline: { ...venda, status: 'archived' },
      stage_name: 'Proposta',
      value_cents: 300000,
      currency: 'BRL',
      status: 'archived',
      desfecho: 'won',
    });
    expect(linha.onde).toBe(
      'CRM_EXCLUIR.CONTATO.FUNIL_ARQUIVADO{"onde":"Vendas · Proposta"}'
    );
    expect(linha.valor).toBe('BRL 3000');
    expect(linha.situacao).toContain('CRM_EXCLUIR.CONTATO.ARQUIVADO_COM');
    const aberto = linhaDoCardDoContato(t, formato, {
      pipeline: atender,
      stage_name: 'Novo',
      value_cents: 1000,
      status: 'open',
    });
    expect(aberto).toEqual({
      onde: 'Pós-venda · Novo',
      valor: '',
      situacao: '',
    });
  });

  it('motivo: código conhecido vira frase; o novo mostra o código; sem resposta é falta de conexão', () => {
    const erro = codigo => ({
      response: { status: 422, data: { error: codigo } },
    });
    expect(
      motivoDoExcluir(t, erro('crm.permanent_delete.meeting_cancel_failed'))
    ).toBe('CRM_EXCLUIR.ERROS.REUNIAO');
    expect(motivoDoExcluir(t, erro('crm.qualquer'))).toBe(
      'CRM_EXCLUIR.ERROS.RECUSOU{"codigo":"crm.qualquer"}'
    );
    expect(motivoDoExcluir(t, new Error('rede'))).toBe(
      'CRM_EXCLUIR.ERROS.SEM_CONEXAO'
    );
  });

  it('confere: EXCLUIR aceita minúsculas; o nome do funil, só sem espaço nas pontas', () => {
    expect(confere(' excluir ', 'EXCLUIR', { ignorarMaiusculas: true })).toBe(
      true
    );
    expect(confere('Vendas ', 'Vendas')).toBe(true);
    expect(confere('vendas', 'Vendas')).toBe(false);
    expect(confere('', '')).toBe(false);
  });
});

describe('motivoDoExcluir com reuniões já canceladas', () => {
  it('diz quantas reuniões o calendário já tinha cancelado antes da recusa', () => {
    const erro = {
      response: {
        status: 422,
        data: {
          error: 'crm.permanent_delete.meeting_cancel_failed',
          canceled_meeting_ids: [3, 4],
        },
      },
    };
    expect(motivoDoExcluir(t, erro)).toBe(
      'CRM_EXCLUIR.ERROS.REUNIAO CRM_EXCLUIR.ERROS.JA_CANCELADAS{"count":2}'
    );
  });
});
