# Cadastro de uma empresa, já validado contra o CNPJ pedido. Imutável: o quadro e as fontes vêm congelados.
#
# qsa guarda todo o quadro em memória, inclusive o menor (is_minor), para a regra do dono explicar por que não há
# decisor. O que se grava é storable_qsa: sem menor, e cada pessoa só com os campos da lista fechada.
Autonomia::Prospecting::Research::Registry::Company = Data.define(
  :cnpj, :legal_name, :trade_name, :registration_status, :registration_state, :city, :legal_nature_code,
  :legal_nature_text, :opened_on, :cnae, :provider, :sources, :qsa, :phones
) do
  # phones: telefones da empresa no cadastro (dígitos E.164, sem fax). O Orth não lê; aqui confirmam a identidade
  # e ficam no perfil (#679, decisão do Rodrigo de 25/09).
  def initialize(sources:, qsa:, phones: [], **attributes)
    super(sources: sources.map { |source| source.dup.freeze }.freeze, qsa: qsa.dup.freeze, phones: phones.dup.freeze, **attributes)
  end

  def failed? = false

  def active? = registration_status == 'ATIVA'

  def storable_qsa
    qsa.reject(&:is_minor).map(&:storable)
  end

  # Colunas de autonomia_prospecting_company_profiles que vêm do cadastro (owners e verified_at são de quem grava).
  def profile_attributes
    {
      'cnpj' => cnpj, 'legal_name' => Autonomia::Prospecting::Research::ProfileAttributes.legal_name(self),
      'trade_name' => trade_name, 'registration_status' => registration_status,
      'registration_state' => registration_state, 'legal_nature_code' => legal_nature_code, 'legal_nature_text' => legal_nature_text,
      'data' => { 'city' => city, 'opened_on' => opened_on&.iso8601, 'cnae' => cnae, 'provider' => provider, 'phones' => phones },
      'qsa' => storable_qsa, 'sources' => sources
    }
  end
end
