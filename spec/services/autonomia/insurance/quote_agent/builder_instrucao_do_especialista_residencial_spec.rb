require 'rails_helper'

# O MANUAL DO ESPECIALISTA DE RESIDENCIAL NÃO PROMETE O QUE O CÓDIGO NÃO TEM (fase 5 do piloto, chat#323), no molde
# de `builder_instrucao_do_especialista_spec`, que faz o mesmo para auto. Cada frase que depende de uma capacidade
# aponta para o que a sustenta; a frase some, o exemplo reprova; a capacidade some, o exemplo reprova. E o texto é
# assinado por md5: prosa nova escrita com outras palavras passaria pela tabela, e a assinatura obriga a revisá-la.
module ManualDoEspecialistaDeResidencial
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  DADOS = BUILDER::ESPECIALISTAS.find { |e| e[:slug] == 'cotacao_residencial' }.freeze
  ARQUIVO = BUILDER::INSTRUCOES.join(DADOS.fetch(:arquivo))
  # O formulário que o especialista lê: o schema de residencial que o adapter devolve, na cópia do mock.
  SCHEMA = Autonomia::Insurance::Connector::Mock::SCHEMA_RESIDENCIAL

  module_function

  def campo(nome)
    SCHEMA['campos'].find { |c| c['campo'] == nome }
  end

  def obrigatorios
    SCHEMA['campos'].select { |c| c['obrigatorio'] }.pluck('campo')
  end

  PROMESSAS = {
    # O mínimo é o que a conferência cobra, e nada além: o CPF, o número, o tipo e o valor a segurar
    # (adapters#92). O CEP chega pelo segurado, fora do formulário do ramo.
    'Peça só o mínimo. São quatro coisas:' => lambda {
      obrigatorios.sort == %w[configuracoes.imovelNumero configuracoes.imovelTipoResidencia
                              configuracoes.isDanosIncendioRaioExplosao segurado.cpfCnpj].sort
    },
    'consulte-o** com consultar_cep' => lambda {
      BUILDER.ferramentas_do_especialista(DADOS).include?('consultar_cep') &&
        Autonomia::Agents::Tools::Registry.find('consultar_cep') == Autonomia::Agents::Tools::Native::CepLookup
    },
    # A busca por documento nos ramos (adapters#92): o nome é `derivado`, e a conferência do chat2you pergunta só
    # quando a busca não acha (`Veiculo#nome_do_segurado_do_ramo_falta?`).
    'Nome você não pede.' => lambda {
      campo('segurado.nome')['origem'] == 'derivado' &&
        Autonomia::Agents::Tools::Native::InsuranceQuote.private_instance_methods.include?(:nome_do_segurado_do_ramo_falta?)
    },
    'Zona rural e área de risco só se o endereço ou a conversa indicarem.' => lambda {
      %w[configuracoes.zonaRural configuracoes.areaRisco].all? { |nome| campo(nome)&.dig('obrigatorio') == false }
    },
    'O que o seguro protege também não se pergunta.' => lambda {
      campo('configuracoes.imovelObjetoSegurado')['obrigatorio'] == false
    },
    'Nada além dos quatro se pergunta por iniciativa própria' => lambda {
      %w[configuracoes.seguradoProprietario configuracoes.imovelConstrucao configuracoes.imovelPossuiAlarme
         configuracoes.imovelPatrimonioHistorico].all? { |nome| campo(nome)['obrigatorio'] == false }
    },
    'Só prédio não tem roubo.' => -> { campo('configuracoes.isDanosRoubo').present? },
    'Apartamento exige complemento.' => -> { campo('configuracoes.imovelComplemento').present? }
  }.freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:do_ramo) { ManualDoEspecialistaDeResidencial::ARQUIVO.read }
  let(:texto) { described_class.instrucao_do_especialista(ManualDoEspecialistaDeResidencial::DADOS.fetch(:arquivo)) }

  describe 'promessa e capacidade' do
    ManualDoEspecialistaDeResidencial::PROMESSAS.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(do_ramo).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end

    it 'o comparativo e a escolha vêm do bloco comum, como em auto' do
      expect(texto).to include('## K. O comparativo', '## L. Quando o cliente escolhe')
      expect(do_ramo).not_to include('## K.', '## L.')
    end

    it 'não cita ferramenta que não é dele' do
      proprias = described_class.ferramentas_do_especialista(ManualDoEspecialistaDeResidencial::DADOS)
      alheias = Autonomia::Agents::Tools::Registry.slugs - proprias

      expect(alheias.select { |slug| texto.include?(slug) }).to be_empty
    end
  end

  describe 'o texto' do
    it 'não escreve valor em reais, crase, travessão nem variável' do
      expect(do_ramo).not_to include('R$', '`', '—', '–')
      expect(texto).not_to include('$')
    end

    # Escrito em 22/09/2026 (chat#323, fase 5): o manual de auto como molde, com o mínimo de residencial.
    it 'é o texto revisado — mudou? revise PROMESSAS e assine aqui' do
      expect(Digest::MD5.hexdigest(ManualDoEspecialistaDeResidencial::ARQUIVO.binread)).to eq('9541d859130dcc9871977d468cd09e04')
    end
  end
end
