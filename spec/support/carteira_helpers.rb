# Carteira de seguros (E4, #2897): o que os specs da carteira repetem. Os dados são sempre fictícios.
module CarteiraHelpers
  # A conta que tem a carteira: corretora de seguros (Carteira::Acesso; sem chave desde a E9, #2902).
  def conta_com_carteira(**dados)
    create(:account, **dados).tap { |conta| com_a_carteira!(conta) }
  end

  # A conta passa a ser corretora de seguros, e ganha a carteira.
  def com_a_carteira!(conta)
    Autonomia::Agents::Nicho.atribuir(conta, nicho: 'seguros', perfil: 'corretora')
    conta.save!
    conta
  end

  # A conta sai do nicho corretora (vai para o geral), e fica sem a carteira: é o que fecha a carteira desde a E9.
  def sem_a_carteira!(conta)
    Autonomia::Agents::Nicho.atribuir(conta, nicho: 'geral', perfil: nil)
    conta.save!
    conta
  end

  # Uma apólice da pessoa, na conta dela. A seguradora e o número levam a forma de comparação certa, como quem grava.
  def criar_apolice(pessoa, **campos)
    chaves = {}
    chaves[:seguradora_chave] = Carteira::Chave.seguradora(campos[:seguradora]) if campos.key?(:seguradora)
    chaves[:numero_chave] = Carteira::Chave.numero(campos[:numero]).presence if campos.key?(:numero)
    create(:carteira_apolice, account: pessoa.account, contact: pessoa, **chaves, **campos)
  end

  def guardar_pdf_na(apolice, nome: 'apolice-exemplo.pdf')
    apolice.pdf.attach(io: StringIO.new('%PDF-1.4 exemplo'), filename: nome, content_type: 'application/pdf', identify: false)
    apolice
  end

  # A conta escolhe onde ficam as renovações (E5, #2898): um funil novo com a etapa dele. Devolve os ajustes.
  def escolher_funil_de_renovacao(conta, user:, nome: 'Renovação', **ajustes)
    funil, etapa = create_crm_pipeline(account: conta, user: user, name: nome)
    create(:carteira_renovacao_config, account: conta, pipeline: funil, stage: etapa, **ajustes)
  end

  # O card de renovação do seguro, criado como a rotina cria.
  def por_em_renovacao(apolice, ajustes)
    Carteira::Renovacao::CriarCard.new(apolice.account, ajustes).call(apolice)
    apolice.reload.crm_card
  end

  # Quantas consultas o bloco fez no banco, fora as de esquema e de transação.
  def consultas_da_carteira(&)
    feitas = 0
    contar = ->(*, dados) { feitas += 1 unless dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name]) }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    feitas
  end
end

RSpec.configure do |config|
  config.include CarteiraHelpers
end
