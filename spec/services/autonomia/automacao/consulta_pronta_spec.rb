require 'rails_helper'

# #2934 (decisão do Rodrigo, 12/11): as consultas prontas do "buscar em outro sistema" rodam pela Execucao das
# Ferramentas prontas dos agentes, e voltam os dados com o rótulo pronto, já em texto para a pessoa.
RSpec.describe Autonomia::Automacao::ConsultaPronta do
  include FerramentasProntasHelper

  let(:account) { create(:account) }
  let(:prontas) { Autonomia::Automacao::ConsultasProntas }
  let(:viacep) { 'https://viacep.com.br/ws/01310100/json/' }
  let(:endereco) { { cep: '01310-100', logradouro: 'Avenida Paulista', bairro: 'Bela Vista', localidade: 'São Paulo', uf: 'SP' } }

  def buscar(id, entradas) = described_class.new(account, prontas.buscar(id), entradas).buscar

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
  end

  it 'a Busca de CEP volta cada dado pelo caminho, e gasta o limite do dia da conta naquela fonte', :aggregate_failures do
    fonte_responde(viacep, endereco)

    resposta = buscar('cep', 'cep' => '01310-100')

    expect(resposta).to be_ok
    expect(resposta.dados).to eq('logradouro' => 'Avenida Paulista', 'bairro' => 'Bela Vista', 'cidade' => 'São Paulo', 'uf' => 'SP',
                                 'cep' => '01310-100')
    expect(Autonomia::FerramentasProntas::Uso.find_by!(account_id: account.id, fonte: 'cep').consultas).to eq(1)
  end

  it 'o valor do carro sai em reais e o mês da tabela no formato daqui' do
    texto = described_class::Formato
    expect(texto.texto(56_043.0, :dinheiro)).to eq('R$ 56.043,00')
    expect(texto.texto('2026-11', :mes)).to eq('11/2026')
    expect(texto.texto('1966-08-01', :data)).to eq('01/08/1966')
    expect(texto.texto(false, :sim_ou_nao)).to eq(I18n.t('autonomia.automacao.consultas_prontas.nao'))
    expect(texto.texto(['São Paulo', 'Campinas'], :lista)).to eq('São Paulo, Campinas')
  end

  it 'conferir CPF não sai do servidor e diz sim ou não' do
    ligar_consultas(account)

    resposta = buscar('cpf', 'cpf' => '111.111.111-11')

    expect(resposta.dados).to eq('valido' => I18n.t('autonomia.automacao.consultas_prontas.nao'))
  end

  it 'a entrada vazia não busca nada', :aggregate_failures do
    resposta = buscar('cep', 'cep' => ' ')

    expect(resposta.motivo).to eq('consulta_pronta_sem_dado')
    expect(a_request(:get, /viacep/)).not_to have_been_made
  end

  it 'o CEP que não existe e o fora do formato viram o motivo que a pessoa lê', :aggregate_failures do
    fonte_responde(viacep, { erro: true })
    stub_request(:get, %r{awesomeapi.com.br/json/01310100}).to_return(status: 404, body: '{}')

    expect(buscar('cep', 'cep' => '01310100').motivo).to eq('consulta_pronta_nao_achou')
    expect(buscar('cep', 'cep' => '123').motivo).to eq('consulta_pronta_dado_invalido')
  end

  it 'sem a flag das prontas ou com a fonte cortada, não busca e diz o que falta', :aggregate_failures do
    account.disable_features!(Autonomia::FerramentasProntas::FLAG)
    expect(buscar('cep', 'cep' => '01310100').motivo).to eq('consulta_pronta_desligada')

    ligar_prontas(account)
    Autonomia::FerramentasProntas::Acesso.create!(account: account, fonte: 'cep').cortar!('teste')
    expect(buscar('cep', 'cep' => '01310100').motivo).to eq('consulta_pronta_pausada')
    expect(a_request(:get, /viacep/)).not_to have_been_made
  end

  describe Autonomia::Automacao::ConsultasProntas do
    it 'a consulta que a conta não pode usar aparece com o que falta, nunca some', :aggregate_failures do
      tela = described_class.para_tela(account)

      expect(tela.pluck(:id)).to eq(%w[cep cnpj fipe cpf])
      expect(tela.find { |consulta| consulta[:id] == 'cep' }).to include(disponivel: true, falta: nil, limite_do_dia: 500)
      cpf = tela.find { |consulta| consulta[:id] == 'cpf' }
      expect(cpf).to include(disponivel: false, falta: I18n.t('autonomia.automacao.consultas_prontas.falta.desligada'))
      expect(cpf[:dados].pluck(:rotulo)).to all(be_present)
    end

    it 'cada consulta é uma consulta grátis das Ferramentas prontas, com os rótulos em pt_BR e en', :aggregate_failures do
      idiomas = %i[pt_BR en]
      described_class::TODAS.each do |pronta|
        fonte = described_class.fonte(pronta)
        expect(fonte).to be_present
        expect(fonte).not_to be_premium
        expect(fonte.consulta(pronta.consulta)).to be_present
        idiomas.each do |idioma|
          I18n.with_locale(idioma) do
            expect(I18n.exists?("autonomia.automacao.consultas_prontas.#{pronta.id}.nome")).to be(true)
            pronta.caminhos.each { |caminho| expect(described_class.rotulo_do_dado(pronta, caminho)).not_to include('translation missing') }
          end
        end
      end
    end
  end
end
