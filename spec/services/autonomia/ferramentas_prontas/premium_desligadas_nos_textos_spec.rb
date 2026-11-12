require 'rails_helper'

# #2946 (revisor do #2949): religar uma consulta não é só tirar a linha de `Premium::DESLIGADAS_NA_FONTE`. O código volta
# sozinho; os textos escritos à mão, não. Este spec falha enquanto a lista e os textos não baterem:
#   - a vitrine em pt_BR e en (`AGENTS.VITRINE.FERRAMENTAS.<CARD>`): o `CONSULTAS` cita cada consulta ligada, e nenhum
#     texto do card cita a desligada;
#   - o artigo 11.14 da Central: o aviso "Sumiu uma consulta do cartão Premium" cita cada desligada e some com a lista
#     vazia.
# O "Responde N tipos de pergunta" vem do servidor (`premium.consultas`) e acompanha a lista sozinho.
# `termos`: como cada dataset aparece no texto, em pt_BR e em en (nil: o card de uma consulta só, sem `CONSULTAS`).
# Dataset novo no Premium entra aqui com os termos dele.
RSpec.describe Autonomia::FerramentasProntas::Premium do
  let(:termos) do
    {
      'ondemand_pgfn_company' => ['dívida com a União', 'federal debt'],
      'ondemand_cert_labor_debt_absence_company' => %w[trabalhista labor],
      'ondemand_fgts_company' => %w[FGTS FGTS],
      'ondemand_cnj_negative_certificate_company' => %w[improbidade misconduct],
      'ondemand_cadin_company' => %w[CADIN CADIN],
      'processes' => %w[processos lawsuits],
      'kyc' => %w[sanções sanctions],
      'company_evolution' => %w[crescimento growth],
      'economic_group_relationships' => ['grupo de empresas', 'group of companies'],
      'civil_construction_data' => ['obras', 'construction works'],
      'ondemand_rf_status_person' => ['situação do CPF', 'CPF status'],
      'basic_data' => ['nascimento', 'birth date'],
      'class_organization' => %w[conselho council],
      'license_plates' => [nil, nil],
      'address_risk' => ['área de risco', 'risk area'],
      'criminal_statistics_data' => %w[crimes crimes],
      'partner_rede_vistorias_address' => %w[vistoria inspection],
      'sicar_property_data' => ['Cadastro Ambiental Rural', 'Rural Environmental Registry'],
      'ondemand_ibama_embargados_company' => %w[IBAMA IBAMA],
      'phones_extended' => %w[telefone phone],
      'emails_extended' => %w[e-mail email],
      'companies_statistics' => ['empresas na região', 'companies in the region']
    }
  end
  let(:idiomas) { { 'pt_BR' => 0, 'en' => 1 } }
  let(:aviso) { '- **"Sumiu uma consulta do cartão Premium."**' }

  def textos_do_card(idioma, chave)
    caminho = Rails.root.join("app/javascript/dashboard/i18n/locale/#{idioma}/agents.json")
    JSON.parse(File.read(caminho)).dig('AGENTS', 'VITRINE', 'FERRAMENTAS', chave.upcase)
  end

  def aviso_do_artigo
    artigo = Rails.root.glob('lib/central_de_ajuda/11/11.14-*.md').sole.read
    inicio = artigo.index(aviso)
    return nil if inicio.nil?

    fim = artigo.index("\n- **", inicio + aviso.length) || artigo.length
    artigo[inicio...fim].tr("\n", ' ').squeeze(' ')
  end

  it 'todo dataset Premium tem os termos dele aqui' do
    expect(todas_as_consultas_premium.map { |consulta| consulta.dataset.nome }).to match_array(termos.keys)
  end

  it 'a vitrine em pt_BR e en cita cada consulta ligada e não cita nenhuma desligada' do
    modulos_premium.each do |modulo|
      chave = modulo::FONTE.chave
      idiomas.each do |idioma, posicao|
        textos = textos_do_card(idioma, chave)
        tudo = textos.values.join(' ')
        modulo::CONSULTAS.each do |consulta|
          termo = termos.fetch(consulta.dataset.nome)[posicao]
          next if termo.nil?

          if consulta.desligada?
            expect(tudo).not_to include(termo), "#{idioma} #{chave}: cita a desligada #{consulta.dataset.nome} (#{termo})"
          else
            expect(textos['CONSULTAS']).to include(termo), "#{idioma} #{chave}.CONSULTAS: falta a ligada #{consulta.dataset.nome} (#{termo})"
          end
        end
      end
    end
  end

  it 'o artigo 11.14 avisa cada consulta desligada, e o aviso some com a lista vazia' do
    trecho = aviso_do_artigo
    if described_class::DESLIGADAS_NA_FONTE.empty?
      expect(trecho).to be_nil
    else
      expect(trecho).to be_present
      described_class::DESLIGADAS_NA_FONTE.each do |dataset|
        expect(trecho).to include(termos.fetch(dataset).first), "11.14: o aviso não cita #{dataset}"
      end
    end
  end

  it 'o selo de perguntas do card acompanha a lista' do
    conta = create(:account)
    cards = Autonomia::FerramentasProntas::Catalogo.premium

    contagem = described_class.para_tela(conta, cards).transform_values { |tela| tela['consultas'] }

    expect(contagem).to eq(cards.to_h { |card| [card.chave, consultas_do_card(card.chave).count { |consulta| !consulta.desligada? }] })
  end
end
