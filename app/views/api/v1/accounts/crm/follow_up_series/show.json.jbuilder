json.payload do
  json.partial! 'api/v1/accounts/crm/follow_up_series/series', series: @series
end
