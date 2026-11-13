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
    expect(resultado.campos).to include('numero' => 'EX-2026.001234', 'bem' => nil)
    expect(resultado.duvidas).to eq(%w[ramo_original inicio_vigencia bem corretora segurado_telefone segurado_email])
  end

  # Segunda revisão, alto 3: o que só vale depois de uma pessoa confirmar não pode estar onde quem grava o alcança.
  describe 'achei, mas uma pessoa confirma' do
    let(:contato) { { 'segurado_telefone' => '11999990001', 'segurado_email' => 'marina@exemplo.invalid' } }

    it 'telefone e e-mail saem só em valores_a_confirmar: nunca em campos nem nos dados da apólice' do
      com_contato = described_class.lido(campos: lidos, a_confirmar: contato, paginas_total: 2, paginas_enviadas: [1])

      expect(com_contato.valores_a_confirmar).to eq(contato)
      expect(com_contato.a_confirmar).to eq(%w[segurado_telefone segurado_email])
      expect(com_contato.campos.keys & contato.keys).to eq([])
      expect(com_contato.campos.values + com_contato.dados_da_apolice.values).not_to include(*contato.values)
      expect(com_contato.duvidas & com_contato.a_confirmar).to eq([])
    end

    it 'o contato mandado por engano em campos não entra em lugar nenhum gravável, e fica como dúvida' do
      por_engano = described_class.lido(campos: lidos.merge(contato), paginas_total: 2, paginas_enviadas: [1])

      expect(por_engano.campos.keys).to eq(described_class::CAMPOS)
      expect(por_engano.campos.values).not_to include(*contato.values)
      expect([por_engano.valores_a_confirmar, por_engano.duvidas.last(2)]).to eq([{}, contato.keys])
    end

    it 'o valor a confirmar sai de campos e dos dados da apólice, mesmo mandado nos dois, e não é dúvida' do
      com_valor = described_class.lido(campos: lidos, a_confirmar: { 'valor_centavos' => 225_498 }, paginas_total: 2, paginas_enviadas: [1])

      expect(com_valor.valores_a_confirmar).to eq('valor_centavos' => 225_498)
      expect([com_valor.campos['valor_centavos'], com_valor.dados_da_apolice[:valor_centavos]]).to eq([nil, nil])
      expect(com_valor.duvidas).not_to include('valor_centavos')
      expect(resultado.campos['valor_centavos']).to eq(225_498)
    end

    it 'cada nome sai em um lugar só: campos com valor, a confirmar ou dúvida' do
      misto = described_class.lido(campos: lidos, a_confirmar: contato.slice('segurado_telefone').merge('valor_centavos' => 225_498),
                                   paginas_total: 2, paginas_enviadas: [1])

      com_valor = misto.campos.compact.keys
      expect((com_valor + misto.a_confirmar + misto.duvidas).sort).to eq(described_class::NOMES.sort)
      expect(misto.duvidas).to eq(%w[ramo_original inicio_vigencia bem corretora segurado_email])
    end

    it 'só aceita a confirmar o contato e o valor; sem achado, e no recusado, não há nada a confirmar' do
      outro = described_class.lido(campos: lidos, a_confirmar: { 'numero' => 'EX-1', 'segurado_email' => nil }, paginas_total: 1,
                                   paginas_enviadas: [1])

      expect([outro.valores_a_confirmar, outro.campos['numero']]).to eq([{}, 'EX-2026.001234'])
      expect([resultado.a_confirmar, described_class.recusado('nao_e_apolice').valores_a_confirmar]).to eq([[], {}])
    end
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
