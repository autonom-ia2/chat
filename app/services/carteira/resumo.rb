# A frase do topo da aba Seguros (E4, #2897): quantos seguros a conta tem, quantos vencem em até 7 dias, quantos estão
# em renovação e, dos que vencem em até 7 dias, quantos já estão em renovação (E5, #2898). `funilEscolhido` diz se a
# conta já escolheu onde ficam as renovações: sem isso a aba convida a escolher. `aggerDisponivel` (E7, #2900) diz se a
# conta pode trazer os seguros pelo Agger (Carteira::Conector.disponivel?), e `aggerLigado`, se a conexão do Agger dela já
# está pronta: com ela, "Trazer do Agger" não pede login nenhum. `aggerPedeLogin`: o Agger recusou o login guardado
# (Carteira::Conector.pede_login?); a tela pede o login de novo e diz isso no lugar do "Ligado". `leituraDePdf` (E6, #2899, decisão
# D4) diz se a conta tem a leitura de PDF liberada: sem ela a tela não mostra nada de leitura (nem o "o que mudou" do
# PDF anexado, nem Trazer por PDFs) e nem chama as rotas, que responderiam `leitura_desligada`.
class Carteira::Resumo
  VENCE_7_EM_RENOVACAO = "#{Carteira::Consulta::EM_RENOVACAO} AND carteira_apolices.fim_vigencia <= :em_7_dias".freeze

  def initialize(account)
    @account = account
  end

  def call
    seguros = Carteira::Consulta.new(@account, {}).contagens
    { total: seguros['todos'], vence7: seguros['vence_7_dias'], vence7EmRenovacao: vence_7_em_renovacao,
      emRenovacao: seguros['em_renovacao'], funilEscolhido: funil_escolhido?, aggerLigado: Carteira::Conector.ligado?(@account),
      aggerDisponivel: Carteira::Conector.disponivel?(@account), aggerPedeLogin: Carteira::Conector.pede_login?(@account),
      leituraDePdf: Carteira::Leitor::Liberado.para?(@account) }
  end

  private

  def funil_escolhido?
    Carteira::RenovacaoConfig.find_by(account_id: @account.id)&.escolhida? || false
  end

  def vence_7_em_renovacao
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id).where(VENCE_7_EM_RENOVACAO, hoje: hoje, em_7_dias: hoje + 7).count
  end
end
