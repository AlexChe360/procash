class CreateAcquiringRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :acquiring_requests, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :merchant_id, null: false
      t.uuid :outlet_id, null: false
      t.uuid :requested_by, null: false
      t.uuid :reviewed_by
      t.uuid :acquiring_connection_id
      t.string :provider, null: false, limit: 50
      t.string :status, null: false, default: "pending", limit: 20
      t.text :review_note
      t.datetime :reviewed_at
      t.timestamps
    end
    add_foreign_key :acquiring_requests, :merchants
    add_foreign_key :acquiring_requests, :merchant_outlets, column: [:outlet_id, :merchant_id], primary_key: [:id, :merchant_id]
    add_foreign_key :acquiring_requests, :users, column: :requested_by
    add_foreign_key :acquiring_requests, :users, column: :reviewed_by
    add_foreign_key :acquiring_requests, :acquiring_connections
    add_index :acquiring_requests, [:outlet_id, :provider], unique: true, where: "status IN ('pending', 'in_review', 'approved')", name: "acquiring_one_open_request"
    add_check_constraint :acquiring_requests, "status IN ('pending', 'in_review', 'approved', 'rejected')", name: "acquiring_request_status"
  end
end
