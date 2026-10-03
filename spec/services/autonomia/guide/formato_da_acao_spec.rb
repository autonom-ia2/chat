require 'rails_helper'

# `formato_da_acao` e o que `executar_acao` devolve ao modelo quando o corpo
# não bate com o formato (#900): o modelo consulta antes, e a recusa ensina.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Formato da ação no Guia' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente) do
    Autonomia::Agents::Agent.create!(
      account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
      instruction: 'Guia.', config: { 'with_knowledge' => false }
    )
  end
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }

  def formato(acao, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaFormato.new(agent: agente, params: { 'acao' => acao }, operador: quem).call
  end

  def executar(params)
    Autonomia::Agents::Tools::Native::GuiaExecucao.new(agent: agente, params: params, operador: operador).call
  end

  describe 'formato_da_acao' do
    it 'devolve o formato da ação, com o envelope e os valores aceitos', :aggregate_failures do
      texto = formato('POST custom_roles')

      expect(texto).to eq(Autonomia::Guide::Formatos.resumo_para_o_modelo('POST custom_roles'))
      expect(texto).to include('"custom_role"', 'conversation_manage')
    end

    it 'devolve as ações que existem quando o nome está errado' do
      expect(formato('POST custom_role')).to include('não é uma ação da plataforma', 'POST custom_roles')
    end

    it 'lembra que a ação sem desfazer vai por propor_acao' do
      expect(formato('POST campaigns')).to include('use propor_acao')
    end

    it 'não muda nada na conta nem chama a plataforma' do
      allow(Autonomia::Guide::ChamadaInterna).to receive(:new)

      formato('POST labels')

      expect(Autonomia::Guide::ChamadaInterna).not_to have_received(:new)
    end

    it 'recusa sem saber quem pede' do
      expect(formato('POST labels', quem: nil)).to include('não sei quem está pedindo')
    end

    it 'está no catálogo de ferramentas e na lista do Guia', :aggregate_failures do
      expect(Autonomia::Agents::Tools::Registry.find('formato_da_acao')).to eq(Autonomia::Agents::Tools::Native::GuiaFormato)
      expect(Autonomia::Guide::Seed::FERRAMENTAS).to include('formato_da_acao')
    end
  end

  describe 'executar_acao com o corpo fora do formato' do
    it 'devolve o que estava errado e o formato, sem as ações vizinhas', :aggregate_failures do
      texto = executar('acao' => 'POST labels', 'descricao' => 'Criar a etiqueta vip.',
                       'corpo_json' => { title: 'vip', cor: 'vermelha' }.to_json)

      expect(texto).to include('campo que esta ação não tem: cor', 'Formato de POST labels')
      expect(texto).not_to include('Para isto, o que existe é')
      expect(conta.labels.find_by(title: 'vip')).to be_nil
    end

    it 'junta à recusa da plataforma o que o formato sabe do campo' do
      texto = executar('acao' => 'POST labels', 'descricao' => 'Criar a etiqueta.',
                       'corpo_json' => { title: 'Cliente VIP' }.to_json)

      expect(texto).to include('Não foi feito:', 'O formato diz: title: texto; o registro exige')
    end

    it 'avisa no sucesso do campo que a plataforma pode ter descartado' do
      with_modified_env(CRM_KANBAN_ENABLED: 'true') do
        texto = executar('acao' => 'POST crm/pipelines', 'descricao' => 'Criar o funil.',
                         'corpo_json' => { name: 'Residencial', inventado: 'x' }.to_json)

        expect(texto).to include('Feito.', 'Atenção: não voltaram no registro: inventado')
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
