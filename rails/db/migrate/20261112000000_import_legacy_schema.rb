class ImportLegacySchema < ActiveRecord::Migration[8.1]
  def up
    Dir[Rails.root.join("db/legacy_migrations/*.up.sql")].sort.each do |path|
      execute File.read(path)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Legacy schema contains merchant data; restore the isolated database backup instead"
  end
end
