class AddReviewStateToCaptainMcpTools < ActiveRecord::Migration[7.2]
  def change
    add_column :captain_mcp_tools, :review_state, :string, null: false, default: 'current'
    # Fork (upgrade 4.20.1, #3120): captain_mcp_servers is created by 20261026062035 in this same release, and no code
    # that runs before it reads the column, so the removal cannot hit a cached attribute.
    safety_assured { remove_column :captain_mcp_servers, :tools_changed_at, :datetime }
  end
end
