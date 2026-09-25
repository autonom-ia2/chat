require 'rails_helper'

# Porte de lib/services/research/company-owner/company-identity-matcher.test.ts do Orth (#679).
RSpec.describe Autonomia::Prospecting::Research::IdentityMatcher do
  let(:place_attributes) do
    { name: 'Alfa Oficina', city: 'Campinas', uf: 'SP', phone: '+55 11 99900-0001', website: 'https://app.alfa-oficina.com.br' }
  end

  def place(**overrides)
    described_class::Place.new(**place_attributes, **overrides)
  end

  def candidate(**overrides)
    described_class::Candidate.new(
      cnpj: '11111111000111', name: 'Alfa Oficina Ltda', city: 'Campinas', uf: 'SP', phone: '+5511999000001',
      domain: 'www.alfa-oficina.com.br', match_score: 0.9, name_similarity: 0.9, **overrides
    )
  end

  def match(place_value, candidates)
    described_class.match(place_value, candidates).to_h
  end

  it 'devolve a decisão canônica completa para o candidato aceito' do
    expect(match(place, [candidate])).to eq(
      decision: :accept, accepted_cnpj: '11111111000111', reason: 'exact_name_plus_phone',
      top_score: 0.9, second_score: nil, name_similarity: 0.9
    )
  end

  it 'iguala telefone nacional BR e E.164 sem reescrever número internacional explícito' do
    expect(match(place(phone: '(11) 99900-0001', website: nil), [candidate(domain: nil)]))
      .to include(decision: :accept, reason: 'exact_name_plus_phone')
    expect(match(place(phone: '+1 (415) 555-2671', website: nil), [candidate(phone: '+14155552671', domain: nil)]))
      .to include(decision: :accept, reason: 'exact_name_plus_phone')
  end

  {
    'conflito de CNPJ' => [{ cnpj_conflict_with: '22222222000122' }, 'cnpj_conflict'],
    'empresa inativa' => [{ status: 'INATIVA' }, 'company_inactive'],
    'matriz no lugar da unidade' => [{ franchise_scope: 'headquarters' }, 'franchise_headquarters_not_unit'],
    'domínio oficial em conflito' => [{ domain: 'alfa-imitacao.com.br' }, 'domain_conflict'],
    'UF incompatível' => [{ uf: 'RJ' }, 'uf_incompatible']
  }.each do |label, (overrides, reason)|
    it "rejeita #{label} quando é o único candidato" do
      expect(match(place, [candidate(**overrides)])).to eq(
        decision: :rejected, accepted_cnpj: nil, reason: reason, top_score: nil, second_score: nil, name_similarity: nil
      )
    end
  end

  it 'não escolhe candidato rejeitado de nota maior no lugar de um válido' do
    result = match(place, [candidate(cnpj: '99999999000199', status: 'INATIVA', match_score: 0.99), candidate(match_score: 0.9)])

    expect(result).to include(decision: :accept, accepted_cnpj: '11111111000111', top_score: 0.9)
  end

  it 'exige cidade e UF mais semelhança de 0,80 quando não há telefone nem domínio' do
    no_primary = place(phone: nil, website: nil)

    expect(match(no_primary, [candidate(phone: nil, domain: nil, name_similarity: 0.79)]))
      .to include(decision: :not_found, reason: 'no_qualified_candidate')
    expect(match(no_primary, [candidate(phone: nil, domain: nil, name_similarity: 0.8)]))
      .to include(decision: :accept, accepted_cnpj: '11111111000111')
  end

  it 'exige cidade e UF mais semelhança de 0,65 quando o telefone é o sinal principal' do
    expect(match(place, [candidate(name: 'Alfa Serviços', name_similarity: 0.64)]))
      .to include(decision: :not_found, reason: 'no_qualified_candidate')
    expect(match(place, [candidate(name: 'Alfa Serviços', name_similarity: 0.65)]))
      .to include(decision: :accept, reason: 'phone_primary_name_065_plus_city_uf')
  end

  it 'compara cidade sem acento, caixa ou espaço extra' do
    expect(match(place(city: '  são   PAULO '), [candidate(city: 'Sao Paulo')])).to include(decision: :accept)
  end

  it 'aceita pelo domínio do site quando não há telefone' do
    expect(match(place(phone: nil), [candidate(phone: nil)])).to include(decision: :accept, reason: 'exact_name_plus_domain')
  end

  it 'devolve ambíguo quando as duas notas qualificadas diferem menos de 0,10' do
    result = match(place, [candidate(match_score: 0.83), candidate(cnpj: '22222222000122', match_score: 0.74)])

    expect(result).to eq(
      decision: :ambiguous, accepted_cnpj: nil, reason: 'top_two_difference_lt_010',
      top_score: 0.83, second_score: 0.74, name_similarity: nil
    )
  end

  it 'usa a ordem do fornecedor como desempate estável só depois da qualificação' do
    result = match(place, [candidate(match_score: 0.9), candidate(cnpj: '22222222000122', match_score: 0.8)])

    expect(result).to include(decision: :accept, accepted_cnpj: '11111111000111')
  end

  it 'sem candidato devolve not_found' do
    expect(match(place, [])).to include(decision: :not_found, reason: 'no_qualified_candidate')
  end
end
