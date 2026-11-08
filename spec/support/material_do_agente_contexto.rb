# #1426 (tema 4b) — montagem comum dos specs das conferências e do autoteste do material: uma conta da Fase 2, um agente
# comum e materiais com texto lido. `material(...)` cria um material já lido e revisado, com os trechos dados.
RSpec.shared_context 'with material do agente' do
  let(:account) { create(:account).tap { |conta| Autonomia::Agents::Fase2.ligar!(conta) } }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', status: :active,
                                     human_card: 'A Bia atende a lanchonete da Bia.')
  end

  # `attrs` muda o que for preciso (status, review_status, metadata, source_type…).
  def material(nome, trechos: ["Texto de #{nome}"], dono: agent, **attrs)
    fonte = Autonomia::Agents::Source.create!(
      { account: dono.account, agent: dono, source_type: 'pdf', reference: nome, status: :ready, review_status: 'accepted',
        reviewed_at: Time.current, review_summary: "Resumo de #{nome}", metadata: {} }.merge(attrs)
    )
    trechos.each_with_index do |texto, indice|
      Autonomia::Agents::KnowledgeEntry.create!(account: dono.account, agent: dono, source: fonte, status: :ready,
                                                chunk_index: indice, content: texto)
    end
    fonte
  end

  def resposta_do_modelo(conteudo)
    { text: conteudo.to_json }
  end

  def credencial_de_teste
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
  end
end
