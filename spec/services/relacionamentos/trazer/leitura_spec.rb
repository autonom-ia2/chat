require 'rails_helper'

# #2896 — a leitura de "Trazer minha lista" no formato da tela: os exemplos, as linhas que precisam da pessoa (uma página
# por vez) e o tipo de cada problema. O contrato inteiro da API está em relacionamentos_trazer_spec.rb.
RSpec.describe Relacionamentos::Trazer::Leitura, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:planilha) do
    <<~CSV
      Nome;Celular;E-mail
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br
      Bruno Brandolim;11987650002;
      Carla Carvalhedo;11987650003;
      Davi Dornelino;11987650004;
      =SOMA(A1);11987650005;
      Fabio Ferreirinho;=1+1;fabio.ferreirinho@exemplo.com.br
      Gil Repetido;;ANA.ALBUQUERINO@exemplo.com.br
    CSV
  end

  def lida(texto = planilha)
    importacao = create_contact_import(account: account, user: user, content: texto)
    importacao.update!(options: importacao.options.merge('trazer' => {}))
    ContactImports::Validator.new(importacao).perform
    importacao.reload
  end

  def leitura(importacao, **dados)
    described_class.new(importacao, **dados).call
  end

  it 'mostra só as três primeiras pessoas como exemplo, com o telefone como vai ser gravado' do
    exemplos = leitura(lida)[:exemplos]

    expect(exemplos.pluck(:nome)).to eq(['Ana Albuquerino', 'Bruno Brandolim', 'Carla Carvalhedo'])
    expect(exemplos.first).to eq(nome: 'Ana Albuquerino', telefone: '+5511987650001', email: 'ana.albuquerino@exemplo.com.br', empresa: '',
                                 cliente: false)
  end

  it 'diz o tipo da linha que ficou de fora por uma célula que parece fórmula: a do telefone, a do e-mail ou, no resto, a do nome' do
    problemas = leitura(lida)[:problemas]

    expect(problemas.first(2)).to eq(
      [
        { linha: 6, tipo: 'nome', nome: '=SOMA(A1)', valor: '=SOMA(A1)', estado: 'aberto' },
        { linha: 7, tipo: 'telefone', nome: 'Fabio Ferreirinho', valor: '=1+1', estado: 'aberto' }
      ]
    )
  end

  it 'acha a outra linha da pessoa repetida pelo e-mail, sem diferença de maiúscula' do
    repetida = leitura(lida)[:problemas].last

    expect(repetida).to eq(
      linha: 8, tipo: 'duplicada', nome: 'Gil Repetido', valor: 'ANA.ALBUQUERINO@exemplo.com.br', estado: 'aberto', outraLinha: 2,
      duplicadas: [{ linha: 2, telefone: '11987650001', email: 'ana.albuquerino@exemplo.com.br' },
                   { linha: 8, telefone: '', email: 'ANA.ALBUQUERINO@exemplo.com.br' }]
    )
  end

  it 'entrega os problemas uma página por vez e conta todos' do
    stub_const("#{described_class}::POR_PAGINA", 2)
    importacao = lida

    primeira = leitura(importacao)
    segunda = leitura(importacao, pagina: '2')

    expect(primeira).to include(problemas_total: 3, pagina: 1, por_pagina: 2)
    expect(primeira[:problemas].pluck(:linha)).to eq([6, 7])
    expect(segunda).to include(problemas_total: 3, pagina: 2, por_pagina: 2)
    expect(segunda[:problemas].pluck(:linha)).to eq([8])
    ['0', '-4', 'abc', nil].each { |pagina| expect(leitura(importacao, pagina: pagina)[:pagina]).to eq(1), pagina.inspect }
    %w[3 40 99999999999999999999999999].each do |pagina|
      alem_da_ultima = leitura(importacao, pagina: pagina)

      expect(alem_da_ultima).to include(pagina: 2), pagina
      expect(alem_da_ultima[:problemas].pluck(:linha)).to eq([8]), pagina
    end
  end

  it 'não abre a planilha original quando nenhuma linha da página tem problema' do
    importacao = lida("Nome;Celular\nAna Albuquerino;11987650001\n")
    allow(importacao.original_file).to receive(:download).and_call_original

    pronta = leitura(importacao)

    expect(pronta).to include(situacao: 'pronta', valores: 'inteiros', problemas: [], problemas_total: 0, pagina: 1)
    expect(pronta[:resumo]).to eq(total: 1, novas: 1, completadas: 0, comProblema: 0)
    expect(importacao.original_file).not_to have_received(:download)
  end

  it 'fica sem exemplos, sem quebrar, quando o arquivo conferido já foi apagado' do
    importacao = lida
    importacao.normalized_csv.purge

    expect(leitura(importacao)).to include(situacao: 'pronta', valores: 'inteiros', exemplos: [])
  end

  it 'abre a planilha original uma vez só quando a página não tem linha repetida' do
    importacao = lida("Nome;Celular\nAna Albuquerino;11987650001\nBruno Brandolim;123\n")
    allow(importacao.original_file).to receive(:download).and_call_original

    expect(leitura(importacao)[:problemas].pluck(:linha, :valor)).to eq([[3, '123']])
    expect(importacao.original_file).to have_received(:download).once
  end

  it 'diz "leitura" para a planilha que o sistema não conseguiu ler por outro motivo' do
    importacao = lida
    importacao.update!(status: :validation_failed, validation_summary: { 'errors' => { 'file_could_not_be_processed' => 1 } })

    expect(leitura(importacao)).to eq(id: importacao.id, situacao: 'falhou', erro: 'leitura')
  end
end
