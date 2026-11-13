# frozen_string_literal: false

begin
  require 'psych'
rescue LoadError
  case RUBY_ENGINE
  when 'jruby'
    warn "The Psych YAML extension failed to load.\n" \
      "Check your env for conflicting versions of SnakeYAML\n" \
      "See https://github.com/jruby/jruby/wiki/FAQs#why-does-the-psych-yaml-extension-fail-to-load-in-my-environment",
         uplevel: 1
  else
    warn "It seems your ruby installation is missing psych (for YAML output).\n" \
      "To eliminate this warning, please install libyaml and reinstall your ruby.\n",
         uplevel: 1
  end
  raise
end

YAML = Psych # :nodoc:

# YAML Ain't Markup Language
#
# This module provides a Ruby interface for data serialization in YAML format.
#
# The YAML module is an alias of Psych, the YAML engine for Ruby.
#
# == Usage
#
# Working with YAML can be very simple, for example:
#
#     require 'yaml'
#     # Parse a YAML string
#     YAML.load("--- foo") #=> "foo"
#
#     # Emit some YAML
#     YAML.dump("foo")     # => "--- foo\n...\n"
#     { :a => 'b'}.to_yaml  # => "---\n:a: b\n"
#
# As the implementation is provided by the Psych library, detailed documentation
# can be found in that library's docs (also part of standard library).
#
# == Security
#
# +YAML.load+ and +YAML.safe_load+ deserialize through +Psych.safe_load+.
# The primitive classes are permitted. +YAML.load+ also permits +Symbol+.
# Aliases are rejected unless <tt>aliases: true</tt> is passed.
#
# +YAML.unsafe_load+ and +YAML.unsafe_load_file+ build arbitrary Ruby
# objects. Do not pass untrusted data to them.
#
# On the safe loader, a +permitted_classes+ entry whose +_load+ runs code
# runs that code, and <tt>aliases: true</tt> allows shared and recursive
# structures. See doc/security/security.rdoc.
#
# == History
#
# Syck was the original YAML implementation in Ruby's standard library
# developed by why the lucky stiff.
#
# You can still use Syck, if you prefer, for parsing and emitting YAML, but you
# must install the 'syck' gem now in order to use it.
#
# In older Ruby versions, ie. <= 1.9, Syck is still provided, however it was
# completely removed with the release of Ruby 2.0.0.
#
# == More info
#
# For more advanced details on the implementation see Psych, and also check out
# http://yaml.org for spec details and other helpful information.
#
# Psych is maintained by Aaron Patterson on github: https://github.com/ruby/psych
#
# Syck can also be found on github: https://github.com/ruby/syck
module YAML
  # The version of YAML wrapper
  LOADER_VERSION = "0.4.0"
end
