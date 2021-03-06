module PgSync
  class TableList
    include Utils

    attr_reader :args, :opts, :source, :config

    def initialize(args, options, source, config)
      @args = args
      @opts = options
      @source = source
      @config = config
      @groups = config["groups"] || {}
    end

    def group?(group)
      @groups.key?(group)
    end

    def tables
      tables = {}
      sql = args[1]

      groups = to_arr(opts[:groups])
      tables2 = to_arr(opts[:tables])

      if args[0]
        # could be a group, table, or mix
        to_arr(args[0]).each do |tag|
          group, id = tag.split(":", 2)
          if group?(group)
            groups << tag
          else
            tables2 << tag
          end
        end
      end

      groups.each do |tag|
        group, id = tag.split(":", 2)
        raise Error, "Group not found: #{group}" unless group?(group)

        # if id
        #   # TODO show group name and value
        #   log colorize("`pgsync group:value` is deprecated and will have a different function in 0.6.0.", :yellow)
        #   log colorize("Use `pgsync group --var 1=value` instead.", :yellow)
        # end

        @groups[group].each do |table|
          table_sql = nil
          if table.is_a?(Array)
            table, table_sql = table
          end
          add_table(tables, table, id, sql || table_sql)
        end
      end

      tables2.each do |tag|
        table, id = tag.split(":", 2)
        raise Error, "Cannot use parameters with tables" if id
        add_table(tables, table, id, sql)
      end

      if !opts[:groups] && !opts[:tables] && !args[0]
        exclude = to_arr(opts[:exclude])
        exclude = source.fully_resolve_tables(exclude).keys if exclude.any?

        tabs = source.tables
        unless opts[:all_schemas]
          schemas = Set.new(opts[:schemas] ? to_arr(opts[:schemas]) : source.search_path)
          tabs.select! { |t| schemas.include?(t.split(".", 2)[0]) }
        end

        (tabs - exclude).each do |k|
          tables[k] = {}
        end
      end

      source.fully_resolve_tables(tables)
    end

    private

    def to_arr(value)
      if value.is_a?(Array)
        value
      else
        # Split by commas, but don't use commas inside double quotes
        # https://stackoverflow.com/questions/21105360/regex-find-comma-not-inside-quotes
        value.to_s.split(/(?!\B"[^"]*),(?![^"]*"\B)/)
      end
    end

    def add_table(tables, table, id, sql)
      tables2 =
        if table.include?("*")
          regex = Regexp.new('\A' + Regexp.escape(table).gsub('\*','[^\.]*') + '\z')
          source.tables.select { |t| regex.match(t) || regex.match(t.split(".", 2).last) }
        else
          [table]
        end

      tables2.each do |tab|
        tables[tab] = {}
        tables[tab][:sql] = table_sql(sql, id) if sql
      end
    end

    def table_sql(sql, id)
      # vars must match \w
      missing_vars = sql.scan(/{\w+}/).map { |v| v[1..-2] }

      vars = {}

      # legacy
      if id
        vars["id"] = cast(id)
        vars["1"] = cast(id)
      end

      # opts[:var].each do |value|
      #   k, v = value.split("=", 2)
      #   vars[k] = v
      # end

      sql = sql.dup
      vars.each do |k, v|
        # only sub if in var list
        sql.gsub!("{#{k}}", cast(v)) if missing_vars.delete(k)
      end

      raise Error, "Missing variables: #{missing_vars.uniq.join(", ")}" if missing_vars.any?

      sql
    end

    # TODO quote vars in next major version
    def cast(value)
      value.to_s.gsub(/\A\"|\"\z/, '')
    end
  end
end
