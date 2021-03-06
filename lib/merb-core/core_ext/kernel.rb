module Kernel
  # Loads the given string as a gem.
  # An optional second parameter of a version string can be specified and is passed to rubygems.
  # If rubygems cannot find the gem it requires the string as a library.
  
  # Note that this new version tries to load the file via ROOT/gems first before moving off to
  # the system gems (so if you have a lower version of a gem in ROOT/gems, it'll still get loaded)
  def dependency(name, *ver)
    try_framework = Merb.frozen?
    begin
      # If this is a piece of merb, and we're frozen, try to require
      # first, so we can pick it up from framework/, 
      # otherwise try activating the gem
      if name =~ /^merb/ && try_framework
        require name
      else
        Gem.activate(name, true, *ver)
        Merb.logger.info("loading gem '#{name}' from #{__app_file_trace__.first} ...")
      end
    rescue LoadError
      if try_framework
        try_framework = false
        retry
      else
        Merb.logger.info("loading gem '#{name}' from #{__app_file_trace__.first} ...")
        # Failed requiring as a gem, let's try loading with a normal require.
        require name
      end
    end
  end

  # Loads both gem and library dependencies that are passed in as arguments.
  # Each argument can be:
  #   String - single dependency
  #   Hash   - name => version
  #   Array  - string dependencies
  def dependencies(*args)
    args.each do |arg|
      case arg
      when String then dependency(arg)
      when Hash   then arg.each { |r,v| dependency(r, v) }
      when Array  then arg.each { |r|   dependency(r)    }
      end
    end
  end
    
  # Requires the library string passed in.
  # If the library fails to load then it will display a helpful message.
  def requires(library)
    # TODO: Extract messages out into a messages file. This will also be the first step towards internationalization.
    # TODO: adjust this message once logging refactor is complete.
    require(library)
    message = "loading library '#{library}' from #{__app_file_trace__.first} ..."
    Merb.logger.debug(message)
  rescue LoadError
    # TODO: adjust the two messages below to use merb's logger.error/info once logging refactor is complete.
    message = "<e> Could not find '#{library}' as either a library or gem, loaded from #{__app_file_trace__.first}.\n"
    Merb.logger.error(message)
    
    # Print a helpful message
    message =  " <i> Please be sure that if '#{library}': \n"
    message << " <i>   * is a normal ruby library (file), be sure that the path of the library it is present in the $LOAD_PATH via $LOAD_PATH.unshift(\"/path/to/#{library}\") \n"
    message << " <i>   * is included within a gem, be sure that you are specifying the gem as a dependency \n"
    Merb.logger.error(message)
    exit # Missing library/gem must be addressed.
  end
  
  # does a basic require, and prints the message passed as an optional
  # second parameter if an error occurs.
  def rescue_require(sym, message = nil)
    require sym
  rescue LoadError, RuntimeError
    Merb.logger.error(message) if message
  end
  
  # Used in Merb.root/config/init.rb
  # Tells merb which ORM (Object Relational Mapper) you wish to use.
  # Currently merb has plugins to support ActiveRecord, DataMapper, and Sequel.
  #
  # Example
  #   $ sudo gem install merb_datamapper # or merb_activerecord or merb_sequel
  #   use_orm :datamapper # this line goes in dependencies.yml
  #   $ ruby script/generate model MyModel # will use the appropriate generator for your ORM
  def use_orm(orm)
    raise "Don't call use_orm more than once" unless Merb.generator_scope.delete(:merb_default)
    orm_plugin = orm.to_s.match(/^merb_/) ? orm.to_s : "merb_#{orm}"
    Merb.generator_scope.unshift(orm.to_sym) unless Merb.generator_scope.include?(orm.to_sym)
    Kernel.dependency(orm_plugin)
  end
  
  # Used in Merb.root/config/init.rb
  # Tells merb which testing framework to use.
  # Currently merb has plugins to support RSpec and Test::Unit.
  #
  # Example
  #   $ sudo gem install rspec
  #   use_test :rspec # this line goes in dependencies.yml (or use_test :test_unit)
  #   $ ruby script/generate controller MyController # will use the appropriate generator for tests
  def use_test(test_framework)
    raise "use_test only supports :rspec and :test_unit currently" unless 
      [:rspec, :test_unit].include?(test_framework.to_sym)
    Merb.generator_scope.delete(:rspec)
    Merb.generator_scope.delete(:test_unit)
    Merb.generator_scope.push(test_framework.to_sym)
    
    test_plugin = test_framework.to_s.match(/^merb_/) ? test_framework.to_s : "merb_#{test_framework}"
    Kernel.dependency(test_plugin)
  end
  
  # Returns an array with a stack trace of the application's files.
  def __app_file_trace__
    caller.select do |call| 
      call.include?(Merb.root) && !call.include?(Merb.root + "/framework")
    end.map do |call|
      file, line = call.scan(Regexp.new("#{Merb.root}/(.*):(.*)")).first
      "#{file}:#{line}"
    end
  end

  # Gives you back the file, line and method of the caller number i
  #
  # Example
  #   __caller_info__(1) # -> ['/usr/lib/ruby/1.8/irb/workspace.rb', '52', 'irb_binding']
  def __caller_info__(i = 1)
    file, line, meth = caller[i].scan(/(.*?):(\d+):in `(.*?)'/).first
  end

  # Gives you some context around a specific line in a file.
  # the size argument works in both directions + the actual line,
  # size = 2 gives you 5 lines of source, the returned array has the
  # following format.
  #   [
  #     line = [
  #              lineno           = Integer,
  #              line             = String, 
  #              is_searched_line = (lineno == initial_lineno)
  #            ],
  #     ...,
  #     ...
  #   ]
  # Example
  #  __caller_lines__('/usr/lib/ruby/1.8/debug.rb', 122, 2) # ->
  #   [
  #     [ 120, "  def check_suspend",                               false ],
  #     [ 121, "    return if Thread.critical",                     false ],
  #     [ 122, "    while (Thread.critical = true; @suspend_next)", true  ],
  #     [ 123, "      DEBUGGER__.waiting.push Thread.current",      false ],
  #     [ 124, "      @suspend_next = false",                       false ]
  #   ]
  def __caller_lines__(file, line, size = 4)
    return [['Template Error!', "problem while rendering", false]] if file =~ /\(erubis\)/
    lines = File.readlines(file)
    current = line.to_i - 1

    first = current - size
    first = first < 0 ? 0 : first

    last = current + size
    last = last > lines.size ? lines.size : last

    log = lines[first..last]

    area = []

    log.each_with_index do |line, index|
      index = index + first + 1
      area << [index, line.chomp, index == current + 1]
    end

    area
  end
  
  # Requires ruby-prof (<tt>sudo gem install ruby-prof</tt>)
  # Takes a block and profiles the results of running the block 100 times.
  # The resulting profile is written out to Merb.root/log/#{name}.html.
  # <tt>min</tt> specifies the minimum percentage of the total time a method must take for it to be included in the result.
  #
  # Example
  #   __profile__("MyProfile", 5) do
  #     30.times { rand(10)**rand(10) }
  #     puts "Profile run"
  #   end
  # Assuming that the total time taken for #puts calls was less than 5% of the total time to run, #puts won't appear
  # in the profilel report.
  def __profile__(name, min=1)
    require 'ruby-prof' unless defined?(RubyProf)
    return_result = ''
    result = RubyProf.profile do
      100.times{return_result = yield}
    end
    printer = RubyProf::GraphHtmlPrinter.new(result)
    path = File.join(Merb.root, 'log', "#{name}.html")
    File.open(path, 'w') do |file|
     printer.print(file, {:min_percent => min,
                          :print_file => true})
    end
    return_result
  end  
  
  # Extracts an options hash if it is the last item in the args array
  # Used internally in methods that take *args
  #
  # Example

  #   def render(*args,&blk)
  #     opts = extract_options_from_args!(args) || {}
  def extract_options_from_args!(args)
    args.pop if Hash === args.last
  end
  
  # ==== Parameters
  # opts<Hash>:: A hash of options
  #
  # ==== Options
  # *keys<Object>:: A list of objects to type-check
  # *values<Symbol, Class, Array[(Symbol, Class)]>::
  # * If it's a symbol, check whether the object responds to the symbol
  # * If it's a class, check whether it is_a? of the class
  # * If it's an array, check whether the above check is true for any of
  #   the options
  def enforce!(opts = {})
    opts.each do |k,v|
      raise ArgumentError, "#{k.inspect} doesn't quack like #{v.inspect}" unless k.quacks_like?(v)
    end
  end
  
  unless Kernel.respond_to?(:debugger)
    # define debugger method so that code even works if debugger was not
    # requested
    # Drops a not to the logs that Debugger was not available

    def debugger
       Merb.logger.info "\n***** Debugger requested, but was not " + 
                        "available: Start server with --debugger " +
                        "to enable *****\n"
    end
  end
end
