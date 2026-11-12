# A CONSULTA DO EXPERIMENTE PREMIUM (#2858, F7), em segundo plano (`ExperimentePagoJob`, revisor 12/11). O clique já
# passou pela conferência das grátis (`Experimente`); aqui a consulta roda pelo caminho do agente
# (`FerramentasProntas.executor_para`, a `Premium::Execucao`), com o texto livre entendido pela IA da conta
# (`ComModelo`), e a resposta leva o contador novo do card.
#
# - `uma_consulta`: o clique vale UMA consulta que chegou à BigDataCorp ou ao cache do dia;
# - `pode_cobrar`: a consulta acima das grátis só vai à fatura com o clique no preço (`confirmou_preco`). A conferência
#   do clique e a consulta não andam juntas: na corrida, a 21ª sem o clique fica sem cobrança (`Cobranca.registrar!`);
# - `em_andamento`: a linha da telemetria nasce antes da chamada, e o varredor fecha a que sobrar
#   (`Premium::FecharEmAndamentoJob`).
# A flag pode ter sido desligada entre o clique e o job: sem ela, nada roda.
class Autonomia::FerramentasProntas::Experimente::Pago
  def self.contador(account, fonte)
    Autonomia::FerramentasProntas::Premium.para_tela(account, [fonte]).fetch(fonte.chave)
  end

  def initialize(account:, fonte:, valor:, confirmou_preco: false)
    @account = account
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(fonte)
    @valor = valor.to_s.strip.first(Autonomia::FerramentasProntas::Experimente::MAX_VALOR)
    @confirmou_preco = confirmou_preco == true
  end

  # -> { 'situacao', 'dados'?, 'mais_provavel'?, 'premium' }
  def call
    return { 'situacao' => 'desligada' } unless @fonte&.premium? && Autonomia::FerramentasProntas.na_vitrine?(@account, @fonte)

    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @account.id, fonte: @fonte.chave)
    resultado = Autonomia::FerramentasProntas::Experimente::ComModelo.new(
      account: @account, fonte: @fonte, valor: @valor, uma_consulta: true, pode_cobrar: @confirmou_preco, em_andamento: true
    ).call
    resultado.merge('premium' => self.class.contador(@account, @fonte))
  end
end
