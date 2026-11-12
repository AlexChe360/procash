class AddBinIinToConnectionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :connection_requests, :bin_iin, :string, limit: 12
    add_check_constraint :connection_requests, "bin_iin IS NULL OR bin_iin ~ '^[0-9]{12}$'", name: "connection_requests_bin_iin_format"
  end
end
