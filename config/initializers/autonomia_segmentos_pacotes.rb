# frozen_string_literal: true

# #1550 — camadas do pacote da conta no I18n do Rails, por cima do catálogo base, só dentro de Pacotes.with.
# O backend é o I18n::Backend::Simple (rails-i18n inclui Pluralization; em produção o Rails inclui Fallbacks). Os dois
# entram por include, abaixo deste prepend; o Fallbacks chama lookup a cada idioma da cadeia, e o pacote vale em todos.
module AutonomiaPacotesI18nLookup
  ESTADO = :autonomia_segmentos_camadas

  protected

  # O pacote vem primeiro e, quando tem a chave, poupa a busca no base. Ele só guarda o que no base é folha de texto
  # (Catalogo filtra ao montar o índice; o CI também barra): chave órfã segue ausente, e plural (one/other) ou
  # subárvore do base seguem do base, com o count.
  def lookup(locale, key, scope = [], options = I18n::EMPTY_HASH)
    camadas = ActiveSupport::IsolatedExecutionState[ESTADO]
    if camadas.present?
      achado = Autonomia::Segmentos::Catalogo.procurar(locale, key, scope, options[:separator], camadas)
      return achado if achado
    end
    super
  end
end

I18n::Backend::Simple.prepend(AutonomiaPacotesI18nLookup) unless I18n::Backend::Simple <= AutonomiaPacotesI18nLookup

# Rede de segurança: nenhuma requisição ou job começa ou termina com camadas de outro trabalho na mesma thread.
Rails.application.executor.to_run { ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO) }
Rails.application.executor.to_complete { ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO) }

Rails.application.config.to_prepare do
  unless Api::V1::Accounts::BaseController <= Autonomia::Segmentos::PacoteDaRequisicao
    Api::V1::Accounts::BaseController.prepend(Autonomia::Segmentos::PacoteDaRequisicao)
  end
  ApplicationMailer.prepend(Autonomia::Segmentos::PacoteDoEmail) unless ApplicationMailer <= Autonomia::Segmentos::PacoteDoEmail
end
