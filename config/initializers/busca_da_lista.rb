# frozen_string_literal: true

# #2211 — a busca da lista de conversas entra no SearchService por prepend (tipo 'Lista'); os outros tipos não mudam.
Rails.application.config.to_prepare do
  SearchService.prepend(SearchService::BuscaDaLista) unless SearchService <= SearchService::BuscaDaLista
end
