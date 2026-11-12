require 'rails_helper'

# #2858 — regra "QI 70" do Rodrigo (11/11/2026) nas fontes de valor exato: o banco pelo nome, o DDD pelo telefone
# inteiro, a NCM que só manda perguntar o material quando o código ainda não é o da nota, e um texto só sobre a dedução.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
  end

  def pronta(fonte)
    incluir_pronta(fonte, conta: account, agente: agent)
  end

  describe 'Bancos: o codigo pelo nome' do
    let(:lista) { 'https://brasilapi.com.br/api/banks/v1' }
    let(:bancos) do
      [{ ispb: '00000000', name: 'BCO DO BRASIL S.A.', code: 1, fullName: 'Banco do Brasil S.A.' },
       { ispb: '60701190', name: 'ITAÚ UNIBANCO S.A.', code: 341, fullName: 'ITAÚ UNIBANCO S.A.' },
       { ispb: '61182408', name: 'BCO ITAÚ CONSIGNADO S.A.', code: 29, fullName: 'Banco Itaú Consignado S.A.' },
       { ispb: '18236120', name: 'NU PAGAMENTOS - IP', code: 260, fullName: 'NU PAGAMENTOS S.A. - INSTITUIÇÃO DE PAGAMENTO' },
       { ispb: '99999999', name: 'SEM CODIGO', code: nil, fullName: 'Sem código de compensação' }]
    end

    def por_nome(nome)
      executar_pronta(pronta('bancos'), 'consulta' => 'por_nome', 'nome' => nome)
    end

    it '"Qual o codigo do Itau?": sem acento e pelo comeco de palavra; o nome igual vem primeiro' do
      fonte_responde(lista, bancos)

      dados = por_nome('itau')['dados']

      expect(dados['bancos'].pluck('codigo')).to eq(%w[341 029])
      expect(dados['bancos'].first).to include('nome' => 'ITAÚ UNIBANCO S.A.')
    end

    it 'acha tambem pelo nome completo ("Banco do Brasil" e "BCO DO BRASIL")' do
      fonte_responde(lista, bancos)

      expect(por_nome('Banco do Brasil')['dados']['bancos'].pluck('codigo')).to eq(['001'])
    end

    it 'nome comercial que nao e o de registro: nao encontrado, com a orientacao de tentar o nome de registro' do
      fonte_responde(lista, bancos)

      saida = por_nome('Nubank')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('nome de registro', 'Nu Pagamentos')
      expect(por_nome('Nu Pagamentos')['dados']['bancos'].pluck('codigo')).to eq(['260'])
    end

    it 'a lista inteira vai ao cache uma vez so; reserva no STR do Banco Central' do
      cache_em_memoria
      fonte_fora(lista)
      csv = "ISPB,Nome_Reduzido,Número_Código,Participa_da_Compe,Acesso_Principal,Nome_Extenso,Início_da_Operação\n" \
            "60701190,ITAÚ UNIBANCO S.A.,341,Sim,RSFN,ITAÚ UNIBANCO S.A.,1980-01-01\n" \
            "18236120,NU PAGAMENTOS - IP,260,Sim,RSFN,NU PAGAMENTOS S.A. - INSTITUIÇÃO DE PAGAMENTO,2021-01-01\n"
      str = fonte_responde('https://www.bcb.gov.br/content/estabilidadefinanceira/str1/ParticipantesSTR.csv', csv, tipo: 'text/csv')

      expect(por_nome('Itaú')['dados']['bancos'].pluck('codigo')).to eq(['341'])
      expect(por_nome('nu pagamentos')['dados']['bancos'].pluck('codigo')).to eq(['260'])
      expect(str).to have_been_requested.once
    end

    it 'a consulta pelo codigo continua a padrao' do
      fonte_responde('https://brasilapi.com.br/api/banks/v1/341', bancos.second)

      expect(executar_pronta(pronta('bancos'), 'codigo' => '341')['dados']).to include('nome' => 'ITAÚ UNIBANCO S.A.')
    end
  end

  describe 'DDD: o telefone inteiro serve, e so o DDD sai daqui' do
    let(:cidades) { { state: 'MG', cities: %w[UBERLANDIA ARAGUARI] } }

    it '"DDD do 34 99999-0000": fica so com o DDD, e o telefone nunca vai a fonte' do
      pedido = fonte_responde('https://brasilapi.com.br/api/ddd/v1/34', cidades)

      ['34 99999-0000', '(34) 3333-4444', '+55 34 99999-0000', '5534999990000', '34'].each do |telefone|
        expect(executar_pronta(pronta('ddd'), 'ddd' => telefone)['dados']).to include('ddd' => '34', 'uf' => 'MG')
      end
      expect(pedido).to have_been_requested.times(5)
      expect(a_request(:get, /9999|3333/)).not_to have_been_made
    end

    it 'telefone de fora do Brasil ("+1 212 555 0100"): pedido invalido, com a orientacao de que nao e do Brasil' do
      saida = executar_pronta(pronta('ddd'), 'ddd' => '+1 212 555 0100')

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'ddd')
      expect(saida['orientacao']).to include('não é do Brasil')
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
    end

    it 'telefone sem DDD ou de fora do plano: pedido invalido, sem chamar a fonte' do
      expect(executar_pronta(pronta('ddd'), 'ddd' => '99999-0000')['campo']).to eq('ddd')
      expect(executar_pronta(pronta('ddd'), 'ddd' => '20 99999-0000')['campo']).to eq('ddd')
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
    end
  end

  describe 'NCM, consulta codigo: o material so e perguntado antes do codigo da nota' do
    let(:ncm) { Autonomia::FerramentasProntas::Fontes::Ncm }
    let(:item) { { codigo: '7318.15.00', descricao: '-- Outros parafusos', data_inicio: '2022-04-01', data_fim: '9999-12-31' } }

    it 'codigo de 8 digitos: so a descricao, sem mandar perguntar o material' do
      fonte_responde('https://brasilapi.com.br/api/ncm/v1?search=7318', [item])

      dados = executar_pronta(pronta('ncm'), 'consulta' => 'codigo', 'codigo' => '7318.15.00')['dados']

      expect(dados).not_to have_key('observacao')
      expect(ncm::FONTE.consulta('codigo').descricao).not_to include('pergunte')
    end

    # Revisão do #2920: a orientação manda buscar, sem lista de material e sem pergunta (regra do caso comum).
    it 'capitulo ou posicao (2 ou 4 digitos): diz que nao serve na nota e manda buscar' do
      fonte_responde('https://brasilapi.com.br/api/ncm/v1/7318', item.merge(codigo: '73.18', descricao: 'Parafusos'))

      dados = executar_pronta(pronta('ncm'), 'consulta' => 'codigo', 'codigo' => '7318')['dados']

      expect(dados['observacao']).to include('8 dígitos', 'consulta buscar')
      expect(dados['observacao']).not_to include('material', 'Pergunte')
    end
  end

  describe 'um texto so sobre a deducao, no turno real e no Experimente' do
    it 'toda ferramenta pronta leva a regra de deduzir antes de perguntar, antes do "Use quando"' do
      descricao = pronta('fipe').openai_schema[:description]

      expect(descricao).to include(Autonomia::FerramentasProntas::Fonte::DEDUZIR)
      expect(descricao).to end_with('Use quando: o cliente informar o dado')
    end

    it 'a cadeia da FIPE mora na descricao da fonte; o prompt do Experimente nao repete' do
      instrucoes = Autonomia::FerramentasProntas::Experimente::ComModelo::INSTRUCOES
      descricao = Autonomia::FerramentasProntas::Fontes::Fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: nil)[:description]

      expect(descricao).to include('pelo nome')
      expect(instrucoes).not_to include('marcas', 'modelos', 'Código (de marca')
    end
  end
end
