# Carteira de seguros (E4, #2897): o que os specs da carteira repetem. Os dados são sempre fictícios.
module CarteiraHelpers
  # A conta que tem a carteira: as duas chaves ligadas e corretora de seguros (Carteira::Acesso).
  def conta_com_carteira(**dados)
    create(:account, **dados).tap do |conta|
      Autonomia::Agents::Nicho.atribuir(conta, nicho: 'seguros', perfil: 'corretora')
      conta.enable_features!('relacionamentos_novo', 'carteira_seguros')
    end
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
