require 'rails_helper'

# E6 (#2899): o que o leitor devolve a quem chama. Dados fictícios.
RSpec.describe Carteira::Leitor::Resultado do
  let(:lidos) do
    { 'tipo' => 'auto', 'seguradora' => 'Seguradora Exemplo S.A.', 'numero' => 'EX-2026.001234', 'fim_vigencia' => '2027-11-12',
      'valor_centavos' => 225_498, 'segurado_nome' => 'Marina Exemplo de Souza', 'segurado_documento' => '12345678900',
      'fora_da_lista' => 'não entra' }
  end
  let(:resultado) { described_class.lido(campos: lidos, paginas_total: 160, paginas_enviadas: [1, 2]) }

  it 'lido: traz todos os campos da lista, com nil no que não foi achado, e as dúvidas são os que ficaram sem valor' do
    expect(resultado).to have_attributes(lido?: true, recusa: nil, motivo: nil, paginas_total: 160, paginas_enviadas: [1, 2])
    expect(resultado.campos.keys).to eq(described_class::CAMPOS)
    expect(resultado.campos).to include('numero' => 'EX-2026.001234', 'bem' => nil, 'segurado_telefone' => nil)
    expect(resultado.duvidas).to eq(%w[ramo_original inicio_vigencia bem corretora segurado_telefone segurado_email])
  end

  # Decisão de produto da revisão (achados D e E): telefone e e-mail lidos de PDF nunca são dados por certos.
  it 'a confirmar: o telefone e o e-mail que vieram com valor, separados das dúvidas' do
    com_contato = described_class.lido(campos: lidos.merge('segurado_telefone' => '11999990001', 'segurado_email' => 'marina@exemplo.invalid'),
                                       paginas_total: 2, paginas_enviadas: [1])
    so_com_telefone = described_class.lido(campos: lidos.merge('segurado_telefone' => '11999990001'), paginas_total: 2, paginas_enviadas: [1])

    expect(com_contato.a_confirmar).to eq(%w[segurado_telefone segurado_email])
    expect(com_contato.duvidas & com_contato.a_confirmar).to eq([])
    expect([so_com_telefone.a_confirmar, so_com_telefone.duvidas.include?('segurado_email')]).to eq([['segurado_telefone'], true])
    expect([resultado.a_confirmar, described_class.recusado('nao_e_apolice').a_confirmar]).to eq([[], []])
  end

  it 'entrega os dados da apólice como o gravador recebe, com as chaves de comparação' do
    expect(resultado.dados_da_apolice).to eq(
      tipo: 'auto', ramo_original: nil, seguradora: 'Seguradora Exemplo S.A.', numero: 'EX-2026.001234', inicio_vigencia: nil,
      fim_vigencia: '2027-11-12', valor_centavos: 225_498, bem: nil, seguradora_chave: 'seguradoraexemplosa', numero_chave: 'EX2026001234'
    )
    sem_numero = described_class.lido(campos: lidos.except('numero', 'seguradora'), paginas_total: 1, paginas_enviadas: [1])
    expect(sem_numero.dados_da_apolice).to include(numero: nil, numero_chave: nil, seguradora_chave: nil)
  end

  it 'recusado: sem campo e sem dúvida, só com as recusas conhecidas' do
    described_class::RECUSAS.each do |recusa|
      recusado = described_class.recusado(recusa, motivo: :sem_texto)

      expect(recusado).to have_attributes(lido?: false, recusa: recusa, motivo: :sem_texto, campos: {}, duvidas: [], paginas_enviadas: [])
    end
    expect { described_class.recusado('inventada') }.to raise_error(ArgumentError)
  end

  it 'o inspect não mostra o que foi lido' do
    texto = resultado.inspect

    expect(texto).to eq('#<Carteira::Leitor::Resultado recusa=nil motivo=nil duvidas=6 a_confirmar=0 paginas=2/160>')
    expect(lidos.values.map(&:to_s).none? { |valor| texto.include?(valor) }).to be(true)
  end
end
