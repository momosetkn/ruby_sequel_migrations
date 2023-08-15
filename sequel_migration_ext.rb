require 'sequel/extensions/migration'

# ライブラリをアップデートしたら例外が発生するようにして
# パッチの消し忘れを防ぐ
raise 'Consider removing this patch' unless Sequel::VERSION == '5.62.0'

module Sequel
  class MigrationReverser < Sequel::BasicObject
    def refresh_schema_migration(_filename)
      false
    end
  end

  class Database
    def refresh_schema_migration(filename)
      query = self[:schema_migrations].where(filename:)
      results = query.to_a
      # branchにあったときのschema_migrationsは削除することで、次回のmigrationでのrefresh_schema_migrationの結果がfalseになるようにする
      query.delete

      results.length > 0
    end
  end
end
