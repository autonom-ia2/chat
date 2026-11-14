# "Trazer minha lista" com seguros (E4, #2897): o seguro da linha que já está na carteira de um jeito que o gravador
# único (Carteira::Guardar) recusaria. A leitura aponta a linha como problema antes, com o que fazer, em vez de a
# gravação falhar calada:
# - `seguro_de_outra_pessoa`: a apólice (a mesma seguradora, o mesmo número, o mesmo termo de vigência) está guardada
#   em nome de outro contato. A pessoa da linha é a do contato quando tem o mesmo telefone (com ou sem o nono dígito) ou
#   o mesmo e-mail, a regra de quem grava a linha. Nada é mesclado nem muda de dono;
# - `seguro_termo_ambiguo`: há mais de um termo guardado com esse número e as datas da linha não dizem qual é o dela
#   (Carteira::Termo). O sistema não adivinha.
# As duas não têm conserto na tela: a pessoa arruma a planilha e envia de novo, ou deixa a linha de fora.
#
# A linha cuja apólice está CANCELADA na carteira não é problema: ela entra, e o seguro continua cancelado e não muda.
# `marcar` devolve quantas são, para a conferência poder dizer.
#
# A leitura olha a carteira como ela está agora. Se ela mudar até o "Trazer", o gravador recusa e a linha falha na
# gravação (Carteira::Trazer::SeguroDaLinha). Só lê; nada daqui vai para o log.
class Carteira::Trazer::JaNaCarteira
  DE_OUTRA_PESSOA = 'seguro_de_outra_pessoa'.freeze
  TERMO_AMBIGUO = 'seguro_termo_ambiguo'.freeze
  LOTE = 1000
  GUARDADO = [:seguradora_chave, :numero_chave, :inicio_vigencia, :fim_vigencia, :cancelado_em,
              'contacts.phone_number', Arel.sql('LOWER(contacts.email)')].freeze

  # colunas: Carteira::Trazer::ColunasDeSeguro.
  def initialize(account, colunas)
    @account = account
    @colunas = colunas
    @telefones = CampaignImports::ContactMatcher.new(account)
  end

  # linhas: as do validador ({ extra_values:, errors:, normalized_phone:, email: }), mexidas no lugar. Só olha as boas.
  # Devolve quantas linhas boas são de apólice cancelada na carteira.
  def marcar(linhas)
    lidas = linhas.select { |linha| linha[:errors].empty? }.map { |linha| [linha, ler(linha)] }
    guardadas = guardadas_de(lidas.filter_map { |_linha, lido| lido.atributos[:numero_chave] }.uniq)
    lidas.count { |linha, lido| cancelada?(linha, lido, guardadas.fetch(lido.chave, [])) }
  end

  private

  def ler(linha)
    Carteira::Trazer::SeguroLido.call(@colunas.valores(linha[:extra_values]))
  end

  # Aponta a linha que o gravador recusaria. Verdadeiro só para a linha boa de apólice cancelada.
  def cancelada?(linha, lido, guardadas)
    achada = Carteira::Termo.escolher(guardadas, lido.atributos)
    return false if achada.nil?
    return apontar(linha, TERMO_AMBIGUO) if achada == Carteira::Termo::AMBIGUO
    return apontar(linha, DE_OUTRA_PESSOA) unless da_pessoa?(achada, linha)

    achada[:cancelado_em].present?
  end

  def apontar(linha, motivo)
    linha[:errors] << motivo
    false
  end

  def da_pessoa?(guardada, linha)
    telefone = linha[:normalized_phone]
    (telefone.present? && @telefones.candidates(telefone).include?(guardada[:telefone])) ||
      (linha[:email].present? && linha[:email].downcase == guardada[:email])
  end

  # { [seguradora_chave, numero_chave] => [{ inicio_vigencia:, fim_vigencia:, cancelado_em:, telefone:, email: }] }
  def guardadas_de(numeros)
    numeros.each_slice(LOTE).with_object({}) do |lote, por_chave|
      Carteira::Apolice.where(account_id: @account.id, numero_chave: lote).joins(:contact).order(:id).pluck(*GUARDADO).each do |linha|
        seguradora, numero, comeca, termina, cancelado_em, telefone, email = linha
        guardada = { inicio_vigencia: comeca, fim_vigencia: termina, cancelado_em: cancelado_em, telefone: telefone, email: email }
        (por_chave[[seguradora, numero]] ||= []) << guardada
      end
    end
  end
end
