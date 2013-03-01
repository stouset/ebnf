module EBNF
  module LL1
    autoload :Lexer,    "ebnf/ll1/lexer"
    autoload :Parser,   "ebnf/ll1/parser"
    autoload :Scanner,  "ebnf/ll1/scanner"

    # Branch table, represented as a recursive hash.
    # The table is indexed by rule symbol, which in-turn references a hash of terminals (which are the first terminals of the production), which in turn reference the sequence of rules that follow, given that terminal as input
    # @!attribute [r] branch
    # @return [Hash{Symbol => Hash{String, Symbol => Array<Symbol>}}]
    attr_reader :branch

    # First table
    # @!attribute [r] first
    # @return [Hash{Symbol, String => Symbol}]
    attr_reader :first

    # Follow table
    # @!attribute [r] first
    # @return [Hash{Symbol, String => Symbol}]
    attr_reader :follow

    # Terminal table
    # The list of terminals used in the grammar.
    # @!attribute [r] terminals
    # @return [Array<String, Symbol>]
    attr_reader :terminals

    # Start symbol
    # The rule which starts the grammar
    # @!attribute[r] start
    # @return [Symbol]
    attr_reader :start

    ##
    # Create first/follow for each rule using techniques defined for LL(1) parsers.
    #
    # @return [EBNF] self
    # @see http://en.wikipedia.org/wiki/LL_parser#Constructing_an_LL.281.29_parsing_table
    # @param [Symbol] start
    #   Set of symbols which are start rules
    def first_follow(start)
      # Add _eof to follow all start rules
      if @start = start
        start_rule = find_rule(@start)
        raise "No rule found for start symbol #{@start}" unless start_rule
        start_rule.add_follow([:_eof])
        start_rule.start = true
      end

      # Comprehnsion rule, create shorter versions of all non-terminal sequences
      comprehensions = []
      ittr = 0
      depth do
        begin
          comprehensions = []
          ast.select {|r| r.seq? && r.kind == :rule && r.expr.length > 2}.each do |rule|
            new_expr = rule.expr[2..-1].unshift(:seq)
            unless ast.any? {|r| r.expr == new_expr}
              debug("FF.c") {"(#{ittr}) add comprehension rule for #{rule.sym} => #{new_expr.inspect}"}
              new_rule = rule.build(new_expr)
              rule.comp = new_rule
              comprehensions << new_rule
            end
          end
      
          @ast += comprehensions
          progress("FF.c") {"(#{ittr}) comprehensions #{comprehensions.length}"}
          ittr += 1
        end while !comprehensions.empty?

        # Fi(a w' ) = { a } for every terminal a
        # For each rule who's expr's first element of a seq a terminal, or having any element of alt a terminal, add that terminal to the first set for this rule
        each(:rule) do |rule|
          each(:terminal) do |terminal|
            if rule.starts_with?(terminal.sym)
              debug("FF.t") {"(0) add first #{terminal.sym} to #{rule.sym}"}
              rule.add_first([terminal.sym])
            end
          end

          # Add strings to first for strings which are start elements
          start_strs = rule.starts_with?(String)
          if start_strs
            debug("FF.t") {"(0) add firsts #{start_strs.join(", ")} to #{rule.sym}"}
            rule.add_first(start_strs) 
          end
        end

        # # Fi(ε) = { ε }
        # Add _eps as a first of _empty
        find_rule(:_empty).add_first([:_eps])

        # Loop until no more first elements are added
        firsts, follows, ittr = 0, 0, 0
        begin
          firsts, follows = 0, 0
          each(:rule) do |rule|
            each(:rule) do |first_rule|
              next if first_rule == rule || first_rule.first.nil?

              # Fi(A w' ) = Fi(A) for every nonterminal A with ε not in Fi(A)
              # For each rule that starts with another rule having firsts which don't include _eps, add  the firsts of that rule to this rule, unless it already has those terminals in its first
              if rule.starts_with?(first_rule.sym) && !first_rule.first_includes_eps?
                debug("FF.1") {"(#{ittr}) add first #{first_rule.first.inspect} from #{first_rule.sym} to #{rule.sym}"}
                firsts += rule.add_first(first_rule.first)
              end

              # Fi(A w' ) = Fi(A) \ { ε } ∪ Fi(w' ) for every nonterminal A with ε in Fi(A)
              # For each rule starting with eps, add the terminals for the comprehension of this rule
              if rule.seq? &&
                 rule.expr.fetch(1, nil) == first_rule.sym &&
                 first_rule.first_includes_eps? &&
                 (comp = rule.comp)

                debug("FF.2") {"(#{ittr}) add first #{comp.first.inspect} from #{comp.sym} to #{rule.sym}"}
                firsts += rule.add_first(comp.first)
              else
              end
            end

            # Only run these rules if the rule is a sequence having two or more elements, whos first element is also a sequence and first_rule is the comprehension of rule
            if rule.seq? && (comp = rule.comp)
               #if there is a rule of the form Aj → wAiw' , then
               #
              if (ai = find_rule(rule.expr[1])) && ai.kind == :rule && comp.first
                #    * if the terminal a is in Fi(w' ), then add a to Fo(Ai)
                #
                # Add follow terminals based on the first terminals
                # of a comprehension of this rule (having the same
                # sequence other than the first rule in the sequence)
                #
                # @example
                #   rule: (seq a b c)
                #   first_rule: (seq b c)
                #   if first_rule.first == [T]
                #   => a.follow += [T]
                debug("FF.3") {"(#{ittr}) add follow #{comp.first.inspect} from #{comp.sym} to #{ai.sym}"}
                follows += ai.add_follow(comp.first)
              end

              # Follows of a rule are also follows of the comprehension of the rule.
              if rule.follow
                debug("FF.4") {"(#{ittr}) add follow #{rule.follow.inspect} to from #{rule.sym} #{comp.sym}"}
                follows += comp.add_follow(rule.follow)
              end

              #    * if ε is in Fi(w' ), then add Fo(Aj) to Fo(Ai)
              #
              # If the comprehension of a sequence has an _eps first, then the follows of the rule also become the follows of the first member of the rule
              if comp.first && comp.first.include?(:_eps) && rule.first &&
                 (member = find_rule(rule.expr.fetch(1, nil))) &&
                 member.kind == :rule

                debug("FF.5") {"(#{ittr}) add follow #{rule.follow.inspect} from #{rule.sym} to #{member.sym}"}
                follows += member.add_follow(rule.first)
              end
            end

            # Firsts of elements of an alt are firsts of the alt
            if rule.alt?
              rule.expr[1..-1].map {|s| find_rule(s)}.compact.each do |mem|
                debug("FF.6") {"(#{ittr}) add first #{mem.first.inspect} from #{mem.sym} to #{rule.sym}"}
                rule.add_first(mem.first) if mem.first
              end
            end

            # Follows of a rule are also follows of the last production in the rule
            if rule.seq? && rule.follow &&
               (member = find_rule(rule.expr.last)) &&
               member.kind == :rule

              debug("FF.7") {"(#{ittr}) add follow #{rule.follow.inspect} to #{member.sym}"}
              follows += member.add_follow(rule.follow)
            end

            # For alts, anything that follows the rule follows each member of the rule
            if rule.alt? && rule.follow
              rule.expr[1..-1].map {|s| find_rule(s)}.each do |mem|
                if mem && mem.kind == :rule
                  debug("FF.8") {"(#{ittr}) add follow #{rule.first.inspect} to #{mem.sym}"}
                  follows += mem.add_follow(rule.follow)
                end
              end
            end
          end

          progress("first_follow") {"(#{ittr}) firsts #{firsts}, follows #{follows}"}
          ittr += 1
        end while (firsts + follows) > 0
      end
    end

    ##
    # Generate parser tables, {#branch}, {#first}, {#follow}, and {#terminals}
    def build_tables
      progress("build_tables") {
        "Terminals: #{ast.count {|r| r.kind == :terminal}} " +
        "Non-Terminals: #{ast.count {|r| r.kind == :rule}}"
      }

      @first = ast.
        select(&:first).
        inject({}) {|memo, r|
          memo[r.sym] = r.first if r.first
          memo
        }
      @follow = ast.
        select(&:follow).
        inject({}) {|memo, r|
          memo[r.sym] = r.first if r.first
          memo
        }
      @terminals = ast.map do |r|
        (r.first || []) + (r.follow || [])
      end.flatten.uniq
      @terminals = (@terminals - [:_eps, :_eof, :_empty]).sort_by(&:inspect)

      @branch = {}
      @already = []
      @agenda = []
      do_production(@start)
      while !@agenda.empty?
        x = @agenda.shift
        do_production(x)
      end

      if !@errors.empty?
        progress("###### FAILED with #{errors.length} errors.")
        @errors.each {|s| progress("  #{s}")}
        raise "Table creation failed with errors"
      else
        progress("Ok for predictive parsing")
      end 
    end

    # Generate an output table in Ruby format
    # @param [IO, StringIO] io
    # @param [String] name of the table constant
    # @param [String] table
    #   to output, one of {#branch}, {#first}, {#follow}, or {#terminals}
    # @param [Integer] indent = 0
    def outputTable(io, name, table, indent = 0)
      ind0 = '  ' * indent
      ind1 = ind0 + '  '
      ind2 = ind1 + '  '

      if table.is_a?(Hash)
        io.puts "#{ind0}#{name} = {"
        table.keys.sort_by(&:inspect).each do |prod|
          case table[prod]
          when Array
            list = table[prod].map(&:inspect).join(",\n#{ind2}")
            io.puts "#{ind1}#{prod.inspect} => [\n#{ind2}#{list}],"
          when Hash
            io.puts "#{ind1}#{prod.inspect} => {"
            table[prod].keys.sort_by(&:inspect).each do |term|
              list = table[prod][term].map(&:inspect).join(", ")
              io.puts "#{ind2}#{term.inspect} => [#{list}],"
            end
            io.puts "#{ind1}},"
          else
            "Unknown table entry type: #{table[prod].class}"
          end
        end
        io.puts "#{ind0}}.freeze\n"
      else
        io.puts "#{ind0}#{name} = [\n#{ind1}" +
          table.sort_by(&:inspect).map(&:inspect).join(",\n#{ind1}") +
          "\n#{ind0}].freeze\n"
      end
    end

    private
    def do_production(lhs)
      rule = find_rule(lhs)
      if rule.nil? || rule.kind != :rule || rule.sym == :_empty
        progress("prod") {"Skip: #{lhs.inspect}"}
        return
      end
      @already << lhs

      branchDict = {}

      progress("prod") {"Production #{lhs.inspect}"}

      if rule.expr.first == :matches
        debug("prod") {"Rule is regexp: #{rule}"}

        error("No record of what token #{lhs} can start with") unless rule.first
        return
      end

      if rule.alt?
        # Add entries for each alternative, based on the alternative's first/seq
        rule.expr[1..-1].each do |prod|
          prod_rule = find_rule(prod)
          debug("  Alt", prod)
          @agenda << prod unless @already.include?(prod) || @agenda.include?(prod)
          if prod == :_empty
            debug("    empty")
            branchDict[prod] = []
          elsif prod_rule.nil? || prod_rule.first.nil?
            debug("    no first =>", prod)
            branchDict[prod] = [prod]
          else
            prod_rule.first.each do |f|
              if branchDict.has_key?(f)
                error("First/First Conflict: #{f} is also the condition for #{branchDict[f]}")
              end
              debug("   alt") {"[#{f}] => #{prod}"}
              branchDict[f] = [prod]
            end
          end
        end
      else
        error("prod") {"Expected lhs to be alt or seq, was: #{rule}"} unless rule.seq?
        debug("  Seq", rule)
        # Entries for each first element referencing the sequence
        (rule.first || []).each do |f|
          debug("   seq") {"[#{f}] => #{rule.expr[1..-1].inspect}"}
          branchDict[f] = rule.expr[1..-1]
        end
      
        # Add each production to the agenda
        rule.expr[1..-1].each do |prod|
          @agenda << prod unless @already.include?(prod) || @agenda.include?(prod)
        end
      end
  
      # Add follow rules
      (rule.follow || []).each do |f|
        debug("  Follow") {f.inspect}
        branchDict[f] ||= []
      end

      @branch[lhs] = branchDict
    end
  end
end
