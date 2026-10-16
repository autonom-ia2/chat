json.fase2 @retrato[:fase2]
json.sem_robo @retrato[:sem_robo]
json.pessoas @retrato[:pessoas]
json.agentes @retrato[:agentes]
json.com_ia @retrato[:com_ia]
json.origem @retrato[:origem]
if @assignee
  json.assignee do
    json.partial! 'api/v1/models/agent', formats: [:json], resource: @assignee
  end
end
