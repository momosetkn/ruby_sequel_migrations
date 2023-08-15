top_level = self

using Module.new {
  refine(top_level.singleton_class) do
    def selected_branch(base_path, branch)
      branch_dir = branch ? "branch/#{branch}/" : ''

      loop do
        puts "On branch #{branch || 'main'}"
        [
          'Back to top',
          'Migrate',
          'Merge',
          'Create migration'
        ].each.with_index { |menu, index| puts " #{index}) #{menu}" }
        select_index = STDIN.gets.to_i

        case select_index
        when 0
          break
        when 1
          print 'Please press enter to continue(optionally input revision):'
          revision = STDIN.gets.strip
          migrate(branch_dir, revision)
        when 2
          unless branch
            warn 'Cant merge! Because this is main branch!'
            next
          end
          merge(base_path, branch_dir)
        when 3
          print 'Input migration name:'
          migration_name = STDIN.gets.strip
          create_migration(base_path, branch_dir, migration_name)
        end
      end
    end

    def migrate(branch_dir, revision)
      require 'sequel'
      require 'sequel/extensions/migration'

      puts "Begin migrate"
      Sequel.connect("#{ENV.fetch('DATABASE_URL', nil)}",
                     encoding: "#{InnoscouterServer::Persistence::DBOptions::CLIENT_CHARSET}",
                     logger: Logger.new(STDOUT)) do |db|
        options = {
          allow_missing_migration_files: ALLOW_MISSING_FILES
        }
        options = options.merge(target: revision.to_i) if revision && !revision.empty?
        Sequel::Migrator.run(db, File.expand_path("../../../../../db/migrations#{branch_dir}", __FILE__),
                             options)
      end
      puts 'Migrated'
    end

    def merge(base_path, branch_dir)
      filepath_regex_pattern = %r{^(?<dire_path>.*/)?(?<filename>(?<migration_index>\d+)(?<remaining>[^/]+))$}

      # 既存のマイグレーションファイルの最大値を取得して、それより大きい値をマイグレーションファイルとして生成する
      max_migration_index = Dir.glob("#{base_path}*.rb").filter_map do |f|
        File.file?(f) && filepath_regex_pattern.match(f)&.[](:migration_index)&.to_i
      end.max || 0
      timestamp = [generate_timestamp, max_migration_index + 1000].max / 1000 * 1000 # 複数mergeした際、数字の最後が00,10, 20, 30, 40, 50となるようにする
      search_glob = "#{base_path}#{branch_dir}*.rb"
      Dir.glob(search_glob).each do |f|
        result = filepath_regex_pattern.match(f)
        dire_path = result[:dire_path]
        filename = result[:filename]
        new_file_name = "#{timestamp}#{result[:remaining]}"
        `mv #{dire_path + filename} #{base_path + new_file_name}`
        timestamp += 10
        puts("Merged!\n#{dire_path + filename} -> #{base_path + new_file_name}")
      end
      `rm -rf #{base_path}#{branch_dir}` if Dir.glob(search_glob).empty?
    end

    def create_migration(base_path, branch_dir, migration_name)
      migration_name = migration_name&.strip
      migration_name = 'migration' if migration_name.empty?

      timestamp = generate_timestamp
      filename = "#{timestamp}_#{migration_name}.rb"
      filepath = "#{base_path}#{branch_dir}#{filename}"
      file_body = %(Sequel.migration do
  change do
    # 自動生成した後にファイル名を変更しないでください。マージ前のファイル名とここの値が一致しないと、マイグレーションを二重適用してしまい、意味をなさないためです。
    next if refresh_schema_migration('#{filename}')

  end
end)
      `echo "#{file_body}" > #{filepath}`
    end

    def generate_timestamp
      Time.now.strftime('%Y%m%d%H%M%S').to_i
    end
  end
}

namespace :db do
  desc ''
  task :migrate_cli => :environment do |_task, args|
    base_dir = "db/migrations"

    FIRST_MENU = [
      'Quit',
      'Create branch',
      'Switch to main branch menu'
    ]

    loop do
      branch_arr = Dir.glob("db/migrations/branch/*").filter_map do |f|
        if File.directory? f
          %r{(?:.*/)?(.+)}.match(f)[1]
        end
      end

      puts 'Select branch'
      [FIRST_MENU, branch_arr.map { |branch| "Switch to #{branch} branch menu" }].flatten
                                                                              .each.with_index { |menu, index| puts " #{index}) #{menu}" }
      select_index = STDIN.gets.to_i

      case select_index
      when 0
        puts 'bye'
        break
      when 1
        print 'Input branch name:'
        branch_name = STDIN.gets.strip
        `mkdir #{base_dir}branch/#{branch_name}`
        selected_branch(base_dir, branch_name)
      when 2
        selected_branch(base_dir, nil)
      else
        selected_branch(base_dir, branch_arr[select_index - FIRST_MENU.length])
      end
    end
  end
end
